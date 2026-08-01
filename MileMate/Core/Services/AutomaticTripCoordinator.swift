@preconcurrency import CoreLocation
import Foundation
import Observation

enum AutomaticTrackingSettings {
    static let enabledKey = "automaticTrackingEnabled"
    static let minimumDistanceKey = "automaticMinimumTripDistance"
    static let defaultMinimumDistance = 0.30

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var minimumDistance: Double {
        let value = UserDefaults.standard.double(forKey: minimumDistanceKey)
        return value > 0 ? value : defaultMinimumDistance
    }
}

@MainActor
@Observable
final class AutomaticTripCoordinator: TripReviewCoordinating {
    enum State: Equatable {
        case disabled
        case idle
        case detecting
        case tracking
        case reviewing
        case permissionRequired
        case failed(String)
    }

    private struct PendingTripEnvelope: Codable {
        let trip: Trip
    }

    private let locationService: any AutomaticLocationService
    private let motionService: any MotionActivityService
    private let repository: any MileageRepository
    private let notificationService: any TripNotificationScheduling
    private let isManualTrackingActive: @MainActor () -> Bool
    private let stopInterval: TimeInterval
    private var processor = LocationSampleProcessor()
    private var automotiveConfirmed = false
    private var candidateStartedAt: Date?
    private var highestObservedSpeed = 0.0
    private var elapsedTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var detectionTimeoutTask: Task<Void, Never>?
    private var requestedAlwaysAuthorization = false

    private(set) var state: State = .disabled
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var distanceMeters = 0.0
    var pendingTrip: Trip?

    private static let pendingTripKey = "automaticPendingTrip"
    private static let confirmationDistanceMeters = 80.0
    private static let minimumDrivingSpeed = 4.0

    init(
        locationService: any AutomaticLocationService,
        motionService: any MotionActivityService,
        repository: any MileageRepository,
        notificationService: any TripNotificationScheduling,
        stopInterval: TimeInterval = 180,
        isManualTrackingActive: @escaping @MainActor () -> Bool
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.repository = repository
        self.notificationService = notificationService
        self.stopInterval = stopInterval
        self.isManualTrackingActive = isManualTrackingActive

        locationService.eventHandler = { [weak self] event in
            self?.handleLocation(event)
        }
        motionService.eventHandler = { [weak self] activity in
            self?.handleMotion(activity)
        }
        restorePendingTrip()
    }

    var distanceMiles: Double {
        distanceMeters / 1_609.344
    }

    var currentDeduction: Double {
        MileageDeductionService.deduction(miles: distanceMiles, classification: .business)
    }

    var currentRoute: [TripCoordinate] {
        processor.acceptedSamples.map {
            TripCoordinate(latitude: $0.latitude, longitude: $0.longitude, timestamp: $0.timestamp)
        }
    }

    var locationAuthorizationStatus: CLAuthorizationStatus {
        locationService.authorizationStatus
    }

    var motionPermissionStatus: MotionPermissionStatus {
        motionService.permissionStatus
    }

    func startIfEnabled() {
        guard AutomaticTrackingSettings.isEnabled else {
            state = .disabled
            return
        }
        guard state != .detecting, state != .tracking else { return }

        requestLocationAuthorizationIfNeeded()

        if pendingTrip != nil {
            state = .reviewing
        } else if locationService.authorizationStatus == CLAuthorizationStatus.authorizedAlways {
            locationService.startLowPowerMonitoring()
            startMotionMonitoring()
            state = .idle
        }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled, state == .tracking || state == .reviewing {
            UserDefaults.standard.set(true, forKey: AutomaticTrackingSettings.enabledKey)
            return
        }

        UserDefaults.standard.set(enabled, forKey: AutomaticTrackingSettings.enabledKey)
        if enabled {
            startIfEnabled()
        } else {
            stopDetection()
            pendingTrip = nil
            clearPersistedPendingTrip()
            state = .disabled
        }
    }

    func savePendingTrip(
        classification: Trip.Classification,
        purpose: String,
        notes: String,
        vehicle: VehicleSnapshot? = nil,
        classificationSource: Trip.ClassificationSource = .user,
        appliedRuleID: UUID? = nil
    ) async throws {
        guard var trip = pendingTrip else { return }
        trip.classification = classification
        trip.purpose = purpose
        trip.notes = notes
        trip.vehicle = vehicle
        trip.classificationSource = classificationSource
        trip.appliedRuleID = appliedRuleID
        trip.updatedAt = .now
        try await repository.save(trip)
        notificationService.cancelNotifications(for: trip.id)
        NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
        pendingTrip = nil
        clearPersistedPendingTrip()
        resetToIdle()
    }

    func discardPendingTrip() {
        if let tripID = pendingTrip?.id {
            notificationService.cancelNotifications(for: tripID)
        }
        pendingTrip = nil
        clearPersistedPendingTrip()
        resetToIdle()
    }

    private func requestLocationAuthorizationIfNeeded() {
        switch locationService.authorizationStatus {
        case CLAuthorizationStatus.notDetermined:
            locationService.requestWhenInUseAuthorization()
        case CLAuthorizationStatus.authorizedWhenInUse:
            requestedAlwaysAuthorization = true
            locationService.requestAlwaysAuthorization()
        case CLAuthorizationStatus.authorizedAlways:
            locationService.startLowPowerMonitoring()
            if pendingTrip == nil { state = .idle }
        case CLAuthorizationStatus.denied, CLAuthorizationStatus.restricted:
            state = .permissionRequired
        @unknown default:
            state = .permissionRequired
        }
    }

    private func handleLocation(_ event: LocationServiceEvent) {
        switch event {
        case .authorizationChanged(let status):
            switch status {
            case CLAuthorizationStatus.authorizedAlways:
                locationService.startLowPowerMonitoring()
                if pendingTrip == nil {
                    startMotionMonitoring()
                    state = .idle
                }
            case CLAuthorizationStatus.authorizedWhenInUse where !requestedAlwaysAuthorization:
                requestedAlwaysAuthorization = true
                locationService.requestAlwaysAuthorization()
            case CLAuthorizationStatus.denied, CLAuthorizationStatus.restricted:
                state = .permissionRequired
            default:
                break
            }

        case .locations(let samples):
            guard AutomaticTrackingSettings.isEnabled,
                  !isManualTrackingActive(),
                  state == .detecting || state == .tracking else {
                return
            }
            process(samples)

        case .failed(let message):
            guard state == .detecting || state == .tracking else { return }
            state = .failed(message)
            stopPreciseSession()
            locationService.startLowPowerMonitoring()
        }
    }

    private func startMotionMonitoring() {
        motionService.startUpdates()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self,
                  AutomaticTrackingSettings.isEnabled,
                  self.pendingTrip == nil else { return }
            switch self.motionService.permissionStatus {
            case MotionPermissionStatus.denied,
                 MotionPermissionStatus.restricted,
                 MotionPermissionStatus.unavailable:
                self.state = .permissionRequired
            case MotionPermissionStatus.notDetermined,
                 MotionPermissionStatus.authorized:
                break
            }
        }
    }

    private func handleMotion(_ activity: MotionActivitySample) {
        guard AutomaticTrackingSettings.isEnabled,
              pendingTrip == nil,
              !isManualTrackingActive() else {
            return
        }

        if activity.kind == .automotive, activity.confidence == .high {
            automotiveConfirmed = true
            cancelStopCountdown()
            if state == .idle {
                beginDetecting()
            } else if case .failed = state {
                beginDetecting()
            }
            return
        }

        guard activity.confidence != .low else { return }
        switch activity.kind {
        case .walking, .running, .cycling:
            if state == .detecting {
                resetToIdle()
            } else if state == .tracking {
                scheduleStopCountdown()
            }
        case .stationary:
            if state == .tracking {
                scheduleStopCountdown()
            } else if state == .detecting {
                resetToIdle()
            }
        case .automotive, .unknown:
            break
        }
    }

    private func beginDetecting() {
        guard locationService.authorizationStatus == CLAuthorizationStatus.authorizedAlways else {
            state = .permissionRequired
            return
        }
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        highestObservedSpeed = 0
        state = .detecting
        locationService.stopLowPowerMonitoring()
        locationService.startPreciseTracking()
        detectionTimeoutTask?.cancel()
        detectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self, self.state == .detecting else { return }
            self.resetToIdle()
        }
    }

    private func process(_ samples: [LocationSample]) {
        for sample in samples {
            let reportsStationarySpeed = sample.speed >= 0 && sample.speed < 1.5
            if sample.speed >= 0 {
                highestObservedSpeed = max(highestObservedSpeed, sample.speed)
                if state == .tracking {
                    reportsStationarySpeed ? scheduleStopCountdown() : cancelStopCountdown()
                }
            }

            if state == .tracking, reportsStationarySpeed {
                continue
            }
            guard processor.process(sample) else { continue }
            candidateStartedAt = candidateStartedAt ?? sample.timestamp
            distanceMeters = processor.distanceMeters
            if let firstSample = processor.acceptedSamples.first {
                let duration = sample.timestamp.timeIntervalSince(firstSample.timestamp)
                if duration > 0 {
                    highestObservedSpeed = max(highestObservedSpeed, distanceMeters / duration)
                }
            }

            if state == .detecting,
               automotiveConfirmed,
               distanceMeters >= Self.confirmationDistanceMeters,
               highestObservedSpeed >= Self.minimumDrivingSpeed {
                beginTracking()
            }
        }
    }

    private func beginTracking() {
        detectionTimeoutTask?.cancel()
        detectionTimeoutTask = nil
        state = .tracking
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let startedAt = self.candidateStartedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func scheduleStopCountdown() {
        guard state == .tracking, stopTask == nil else { return }
        stopTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.stopInterval))
            guard !Task.isCancelled, self.state == .tracking else { return }
            self.finishAutomaticTrip()
        }
    }

    private func cancelStopCountdown() {
        stopTask?.cancel()
        stopTask = nil
    }

    private func finishAutomaticTrip() {
        guard state == .tracking, let startedAt = candidateStartedAt else { return }
        let route = currentRoute
        let miles = distanceMiles
        stopPreciseSession()

        guard miles >= AutomaticTrackingSettings.minimumDistance else {
            resetToIdle()
            return
        }

        let trip = Trip(
            id: UUID(),
            startedAt: startedAt,
            endedAt: .now,
            originName: "Unknown location",
            destinationName: "Unknown location",
            distanceMiles: miles,
            classification: .unclassified,
            purpose: "",
            startCoordinate: route.first,
            endCoordinate: route.last,
            route: route
        )
        Task { [weak self] in
            guard let self else { return }
            var assignedTrip = trip
            async let fetchedVehicles = self.repository.fetchVehicles()
            async let fetchedPlaces = self.repository.fetchFrequentPlaces()
            async let fetchedRules = self.repository.fetchClassificationRules()
            let vehicles = (try? await fetchedVehicles) ?? []
            assignedTrip = VehicleAssignmentService.assigningDefault(
                to: assignedTrip,
                vehicles: vehicles
            )
            if UserDefaults.standard.bool(
                forKey: ClassificationSettings.automaticRulesEnabledKey
            ) {
                let places = (try? await fetchedPlaces) ?? []
                let rules = (try? await fetchedRules) ?? []
                if let rule = SmartClassificationService.matchingRule(
                    for: assignedTrip,
                    places: places,
                    rules: rules
                ) {
                    let classifiedTrip = SmartClassificationService.applying(
                        rule,
                        to: assignedTrip
                    )
                    do {
                        try await self.repository.save(classifiedTrip)
                        NotificationCenter.default.post(
                            name: .mileageTripsDidChange,
                            object: classifiedTrip.id
                        )
                        self.resetToIdle()
                        return
                    } catch {
                        // Fall through to review so a persistence failure never loses the trip.
                    }
                }
            }
            self.completeAutomaticTrip(assignedTrip)
        }
    }

    private func completeAutomaticTrip(_ trip: Trip) {
        guard persistPendingTrip(trip) else {
            resetToIdle()
            return
        }
        pendingTrip = trip
        state = .reviewing
        Task { [notificationService] in
            await notificationService.scheduleTripCompletion(for: trip)
        }
        reverseGeocodePendingTrip()
    }

    private func stopDetection() {
        motionService.stopUpdates()
        locationService.stopPreciseTracking()
        locationService.stopLowPowerMonitoring()
        stopPreciseSession()
    }

    private func stopPreciseSession() {
        locationService.stopPreciseTracking()
        elapsedTask?.cancel()
        elapsedTask = nil
        detectionTimeoutTask?.cancel()
        detectionTimeoutTask = nil
        cancelStopCountdown()
        automotiveConfirmed = false
    }

    private func resetToIdle() {
        stopPreciseSession()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        highestObservedSpeed = 0
        if AutomaticTrackingSettings.isEnabled {
            locationService.startLowPowerMonitoring()
            state = .idle
        } else {
            state = .disabled
        }
    }

    @discardableResult
    private func persistPendingTrip(_ trip: Trip) -> Bool {
        guard let data = try? JSONEncoder().encode(PendingTripEnvelope(trip: trip)) else {
            return false
        }
        UserDefaults.standard.set(data, forKey: Self.pendingTripKey)
        return UserDefaults.standard.data(forKey: Self.pendingTripKey) == data
    }

    private func restorePendingTrip() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingTripKey),
              let envelope = try? JSONDecoder().decode(PendingTripEnvelope.self, from: data) else {
            return
        }
        pendingTrip = envelope.trip
        state = .reviewing
    }

    private func clearPersistedPendingTrip() {
        UserDefaults.standard.removeObject(forKey: Self.pendingTripKey)
    }

    private func reverseGeocodePendingTrip() {
        guard let trip = pendingTrip else { return }
        Task {
            let startName = await Self.locationName(for: trip.startCoordinate)
            let endName = await Self.locationName(for: trip.endCoordinate)
            guard var updated = pendingTrip, updated.id == trip.id else { return }
            updated.originName = startName
            updated.destinationName = endName
            pendingTrip = updated
            persistPendingTrip(updated)
        }
    }

    private static func locationName(for coordinate: TripCoordinate?) async -> String {
        guard let coordinate else { return "Unknown location" }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return "Unknown location" }
            let name = [placemark.name, placemark.locality]
                .compactMap { $0 }
                .reduce(into: []) { result, value in
                    if !result.contains(value) { result.append(value) }
                }
                .joined(separator: ", ")
            return name.isEmpty ? "Unknown location" : name
        } catch {
            return "Unknown location"
        }
    }
}

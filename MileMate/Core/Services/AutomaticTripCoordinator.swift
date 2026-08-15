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

    private struct ActiveTripEnvelope: Codable {
        let startedAt: Date
        let tripStartedAt: Date?
        let samples: [LocationSample]
        let distanceMeters: Double
        let automotiveConfirmed: Bool
        let highestObservedSpeed: Double
        let isTracking: Bool
        let candidateStopStartedAt: Date?
        let motionStopEvidence: Bool?
        let lowSpeedStopEvidence: Bool?
    }

    private let locationService: any AutomaticLocationService
    private let motionService: any MotionActivityService
    private let repository: any MileageRepository
    private let notificationService: any TripNotificationScheduling
    private let isManualTrackingActive: @MainActor () -> Bool
    private let stopInterval: TimeInterval
    private let detectionTimeout: TimeInterval
    private var processor = LocationSampleProcessor()
    private var automotiveConfirmed = false
    private var detectionStartedAt: Date?
    private var candidateStartedAt: Date?
    private var highestObservedSpeed = 0.0
    private var elapsedTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var detectionTimeoutTask: Task<Void, Never>?
    private var requestedAlwaysAuthorization = false
    private var legacyPendingMigrationStarted = false
    private var candidateStopStartedAt: Date?
    private var motionStopEvidence = false
    private var lowSpeedStopEvidence = false
    private var pendingLowPowerSamples: [LocationSample] = []

    private(set) var state: State = .disabled
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var distanceMeters = 0.0
    var pendingTrip: Trip?

    private static let pendingTripKey = "automaticPendingTrip"
    private static let activeTripKey = "automaticActiveTrip"
    private static let confirmationDistanceMeters = 80.0
    private static let minimumDrivingSpeed = 4.0

    init(
        locationService: any AutomaticLocationService,
        motionService: any MotionActivityService,
        repository: any MileageRepository,
        notificationService: any TripNotificationScheduling,
        stopInterval: TimeInterval = 180,
        detectionTimeout: TimeInterval = 180,
        isManualTrackingActive: @escaping @MainActor () -> Bool
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.repository = repository
        self.notificationService = notificationService
        self.stopInterval = stopInterval
        self.detectionTimeout = detectionTimeout
        self.isManualTrackingActive = isManualTrackingActive

        locationService.eventHandler = { [weak self] event in
            self?.handleLocation(event)
        }
        motionService.eventHandler = { [weak self] activity in
            self?.handleMotion(activity)
        }
        restorePendingTrip()
        restoreActiveTrip()
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

    var backgroundCapabilityAvailable: Bool {
        locationService.backgroundCapabilityAvailable
    }

    var trackingReadiness: AutomaticTrackingReadiness {
        AutomaticTrackingReadiness.evaluate(
            location: locationService.authorizationStatus,
            motion: motionService.permissionStatus,
            backgroundCapabilityAvailable: locationService.backgroundCapabilityAvailable,
            significantLocationMonitoringAvailable: locationService.significantLocationMonitoringAvailable,
            motionActivityMonitoringAvailable: motionService.activityMonitoringAvailable
        )
    }

    var readinessSnapshot: AutomaticTrackingReadinessSnapshot {
        AutomaticTrackingReadinessSnapshot(
            locationAuthorization: locationService.authorizationStatus,
            motionAuthorization: motionService.permissionStatus,
            backgroundCapabilityAvailable: locationService.backgroundCapabilityAvailable,
            significantLocationMonitoringAvailable: locationService.significantLocationMonitoringAvailable,
            motionActivityMonitoringAvailable: motionService.activityMonitoringAvailable,
            automaticTrackingEnabled: AutomaticTrackingSettings.isEnabled,
            result: trackingReadiness
        )
    }

    func startIfEnabled() {
        TrackingDiagnostics.log("automatic tracking startup requested; enabled=\(AutomaticTrackingSettings.isEnabled)")
        TrackingDiagnostics.log(readinessSnapshot.diagnosticDescription)
        migrateLegacyPendingTripIfNeeded()
        guard AutomaticTrackingSettings.isEnabled else {
            state = .disabled
            TrackingDiagnostics.log("automatic tracking disabled; detector not started")
            return
        }
        guard state != .detecting, state != .tracking else { return }

        requestLocationAuthorizationIfNeeded()

        if locationService.authorizationStatus == CLAuthorizationStatus.authorizedAlways {
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
        let existing = (try? await repository.fetchTrips()) ?? []
        if existing.contains(where: { $0.id == trip.id }) {
            try await repository.update(trip)
        } else {
            try await repository.save(trip)
        }
        notificationService.cancelNotifications(for: trip.id)
        await notificationService.reconcileReviewReminder()
        NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
        pendingTrip = nil
        clearPersistedPendingTrip()
        resetToIdle()
    }

    func discardPendingTrip() {
        if let trip = pendingTrip {
            let tripID = trip.id
            notificationService.cancelNotifications(for: tripID)
            Task { [repository, notificationService] in
                try? await repository.delete(trip)
                await notificationService.reconcileReviewReminder()
                NotificationCenter.default.post(name: .mileageTripsDidChange, object: tripID)
            }
        }
        pendingTrip = nil
        clearPersistedPendingTrip()
        resetToIdle()
    }

    func prepareForLocalDataDeletion() {
        stopDetection()
        pendingTrip = nil
        clearPersistedPendingTrip()
        clearPersistedActiveTrip()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        detectionStartedAt = nil
        candidateStopStartedAt = nil
        pendingLowPowerSamples.removeAll()
        state = .disabled
    }

    func appDidEnterBackground() {
        TrackingDiagnostics.log("app entered background; automatic detector state=\(state)")
        persistActiveTrip()
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
            state = .idle
        case CLAuthorizationStatus.denied, CLAuthorizationStatus.restricted:
            state = .permissionRequired
        @unknown default:
            state = .permissionRequired
        }
    }

    private func handleLocation(_ event: LocationServiceEvent) {
        switch event {
        case .authorizationChanged(let status):
            TrackingDiagnostics.log("location authorization changed: \(status.rawValue)")
            switch status {
            case CLAuthorizationStatus.authorizedAlways:
                locationService.startLowPowerMonitoring()
                startMotionMonitoring()
                state = .idle
            case CLAuthorizationStatus.authorizedWhenInUse where !requestedAlwaysAuthorization:
                requestedAlwaysAuthorization = true
                locationService.requestAlwaysAuthorization()
            case CLAuthorizationStatus.denied, CLAuthorizationStatus.restricted:
                state = .permissionRequired
            default:
                break
            }

        case .locations(let samples):
            guard AutomaticTrackingSettings.isEnabled else {
                TrackingDiagnostics.log("location wake ignored because automatic tracking is disabled")
                return
            }
            guard !isManualTrackingActive() else {
                TrackingDiagnostics.log("location wake ignored because manual tracking is active")
                return
            }
            if state == .idle {
                pendingLowPowerSamples = Array(
                    (pendingLowPowerSamples + samples).suffix(4)
                )
                TrackingDiagnostics.log(
                    "low-power location wake buffered while awaiting automotive motion evidence; sampleCount=\(samples.count)"
                )
                return
            }
            guard state == .detecting || state == .tracking else {
                TrackingDiagnostics.log(
                    "low-power location wake received while state=\(state); sampleCount=\(samples.count); awaiting automotive motion evidence"
                )
                return
            }
            process(samples)
            persistActiveTrip()

        case .failed(let message):
            guard state == .detecting || state == .tracking else { return }
            TrackingDiagnostics.log("automatic location service failed while \(state): \(message)")
            state = .failed(message)
            stopPreciseSession()
            locationService.startLowPowerMonitoring()
        }
    }

    private func startMotionMonitoring() {
        motionService.startUpdates()
        TrackingDiagnostics.log(
            "motion monitoring requested; authorization=\(motionService.permissionStatus); available=\(motionService.activityMonitoringAvailable)"
        )
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self,
                  AutomaticTrackingSettings.isEnabled,
                  !self.isManualTrackingActive() else { return }
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
              !isManualTrackingActive() else {
            return
        }

        TrackingDiagnostics.log(
            "motion event received; kind=\(activity.kind.rawValue); confidence=\(activity.confidence)"
        )

        if activity.kind == .automotive, activity.confidence != .low {
            automotiveConfirmed = true
            TrackingDiagnostics.log("automotive movement accepted as detection evidence")
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
                TrackingDiagnostics.log("detection canceled by non-automotive motion evidence: \(activity.kind.rawValue)")
                resetToIdle()
            } else if state == .tracking {
                scheduleStopCountdown(motionEvidence: true)
            }
        case .stationary:
            if state == .tracking {
                scheduleStopCountdown(motionEvidence: true)
            } else if state == .detecting {
                TrackingDiagnostics.log("stationary event observed during GPS confirmation; detector remains active")
            }
        case .automotive, .unknown:
            break
        }
    }

    private func beginDetecting() {
        guard trackingReadiness == .ready else {
            state = .permissionRequired
            TrackingDiagnostics.log("detection could not initialize; readiness=\(trackingReadiness.diagnosticReason)")
            return
        }
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        detectionStartedAt = .now
        candidateStartedAt = nil
        highestObservedSpeed = 0
        state = .detecting
        TrackingDiagnostics.log(
            "automatic detector entered detecting; timeout=\(Int(detectionTimeout)) seconds"
        )
        locationService.stopLowPowerMonitoring()
        guard locationService.startPreciseTracking() else {
            state = .permissionRequired
            TrackingDiagnostics.log("detection could not initialize; precise location tracking failed to start")
            locationService.startLowPowerMonitoring()
            return
        }
        let bufferedSamples = pendingLowPowerSamples
        pendingLowPowerSamples.removeAll()
        if !bufferedSamples.isEmpty {
            TrackingDiagnostics.log(
                "processing \(bufferedSamples.count) buffered low-power samples after automotive evidence"
            )
            process(bufferedSamples)
        }
        persistActiveTrip()
        guard state == .detecting else { return }
        detectionTimeoutTask?.cancel()
        let timeout = detectionTimeout
        detectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, self.state == .detecting else { return }
            TrackingDiagnostics.log(
                "detection timed out; reason=\(self.detectionConfirmationBlockers); acceptedSamples=\(self.processor.acceptedSamples.count); movementMeters=\(Int(self.distanceMeters)); highestSpeedMetersPerSecond=\(self.highestObservedSpeed.formatted(.number.precision(.fractionLength(1))))"
            )
            self.resetToIdle()
        }
    }

    private func process(_ samples: [LocationSample]) {
        var rejectionCounts: [String: Int] = [:]
        for sample in samples {
            let reportsStationarySpeed = sample.speed >= 0 && sample.speed < 1.5
            if state == .tracking, sample.speed >= 0 {
                reportsStationarySpeed
                    ? scheduleStopCountdown(lowSpeedEvidence: true)
                    : cancelStopCountdown()
            }

            if state == .tracking, reportsStationarySpeed {
                continue
            }
            let processingResult = processor.processWithResult(sample)
            guard processingResult == .accepted else {
                let reason = diagnosticName(for: processingResult)
                rejectionCounts[reason, default: 0] += 1
                continue
            }
            if sample.speed >= 0 {
                highestObservedSpeed = max(highestObservedSpeed, sample.speed)
            }
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
        TrackingDiagnostics.log(
            "location batch processed; received=\(samples.count); acceptedTotal=\(processor.acceptedSamples.count); movementMeters=\(Int(distanceMeters)); highestSpeedMetersPerSecond=\(highestObservedSpeed.formatted(.number.precision(.fractionLength(1)))); rejected=\(rejectionCounts)"
        )
    }

    private func beginTracking() {
        detectionTimeoutTask?.cancel()
        detectionTimeoutTask = nil
        state = .tracking
        TrackingDiagnostics.log(
            "automatic tracking confirmed; acceptedSamples=\(processor.acceptedSamples.count); movementMeters=\(Int(distanceMeters)); highestSpeedMetersPerSecond=\(highestObservedSpeed.formatted(.number.precision(.fractionLength(1))))"
        )
        TripFeedback.started()
        persistActiveTrip()
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let startedAt = self.candidateStartedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func scheduleStopCountdown(
        motionEvidence: Bool = false,
        lowSpeedEvidence: Bool = false
    ) {
        guard state == .tracking else { return }
        self.motionStopEvidence = self.motionStopEvidence || motionEvidence
        self.lowSpeedStopEvidence = self.lowSpeedStopEvidence || lowSpeedEvidence
        candidateStopStartedAt = candidateStopStartedAt ?? .now
        TrackingDiagnostics.log(
            "candidate stop active; motionEvidence=\(self.motionStopEvidence); lowSpeedEvidence=\(self.lowSpeedStopEvidence)"
        )
        persistActiveTrip()
        guard stopTask == nil else { return }
        let elapsed = Date().timeIntervalSince(candidateStopStartedAt ?? .now)
        let remaining = max(stopInterval - elapsed, 0)
        stopTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, self.state == .tracking else { return }
            if !(self.motionStopEvidence && self.lowSpeedStopEvidence) {
                let grace = min(TimeInterval(60), max(self.stopInterval / 3, 0.01))
                try? await Task.sleep(for: .seconds(grace))
                guard !Task.isCancelled, self.state == .tracking else { return }
            }
            self.finishAutomaticTrip()
        }
    }

    private func cancelStopCountdown() {
        let hadCandidateStop = candidateStopStartedAt != nil
        stopTask?.cancel()
        stopTask = nil
        candidateStopStartedAt = nil
        motionStopEvidence = false
        lowSpeedStopEvidence = false
        if hadCandidateStop {
            TrackingDiagnostics.log("candidate stop canceled because driving evidence resumed")
        }
        if state == .tracking { persistActiveTrip() }
    }

    private func finishAutomaticTrip() {
        guard state == .tracking, let startedAt = candidateStartedAt else { return }
        let route = currentRoute
        let miles = distanceMiles
        stopPreciseSession()
        clearPersistedActiveTrip()

        guard miles >= AutomaticTrackingSettings.minimumDistance else {
            TrackingDiagnostics.log(
                "automatic trip rejected; reason=below configured minimum; miles=\(miles.formatted(.number.precision(.fractionLength(2)))); minimum=\(AutomaticTrackingSettings.minimumDistance.formatted(.number.precision(.fractionLength(2))))"
            )
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
        resetToIdle()
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
            let automaticClassificationEnabled = UserDefaults.standard.bool(
                forKey: ClassificationSettings.automaticRulesEnabledKey
            )
            if automaticClassificationEnabled {
                let places = (try? await fetchedPlaces) ?? []
                let rules = (try? await fetchedRules) ?? []
                if let rule = SmartClassificationService.matchingRule(
                    for: assignedTrip,
                    places: places,
                    rules: rules,
                    automaticClassificationEnabled: automaticClassificationEnabled
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
                        await self.notificationService.scheduleTripCompletion(for: classifiedTrip)
                        TrackingDiagnostics.log("automatic trip persisted successfully with approved classification rule")
                        self.reverseGeocodeStoredTrip(classifiedTrip)
                        return
                    } catch {
                        // Fall through to review so a persistence failure never loses the trip.
                    }
                }
            }
            do {
                try await self.repository.save(assignedTrip)
                NotificationCenter.default.post(
                    name: .mileageTripsDidChange,
                    object: assignedTrip.id
                )
                self.completeAutomaticTrip(assignedTrip)
                TrackingDiagnostics.log("automatic trip persisted successfully for review")
                self.reverseGeocodeStoredTrip(assignedTrip)
            } catch {
                TrackingDiagnostics.log("automatic trip could not be persisted")
            }
        }
    }

    private func completeAutomaticTrip(_ trip: Trip) {
        TripFeedback.completed()
        TrackingDiagnostics.log("automatic trip ended")
        Task { [notificationService] in
            await notificationService.scheduleTripCompletion(for: trip)
        }
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
        clearPersistedActiveTrip()
        stopPreciseSession()
        clearPersistedActiveTrip()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        detectionStartedAt = nil
        pendingLowPowerSamples.removeAll()
        highestObservedSpeed = 0
        if AutomaticTrackingSettings.isEnabled {
            locationService.startLowPowerMonitoring()
            state = .idle
        } else {
            state = .disabled
        }
    }

    private func persistActiveTrip() {
        guard state == .detecting || state == .tracking,
              let startedAt = detectionStartedAt ?? candidateStartedAt ?? processor.acceptedSamples.first?.timestamp else {
            return
        }
        let envelope = ActiveTripEnvelope(
            startedAt: startedAt,
            tripStartedAt: candidateStartedAt,
            samples: processor.acceptedSamples,
            distanceMeters: distanceMeters,
            automotiveConfirmed: automotiveConfirmed,
            highestObservedSpeed: highestObservedSpeed,
            isTracking: state == .tracking,
            candidateStopStartedAt: candidateStopStartedAt,
            motionStopEvidence: motionStopEvidence,
            lowSpeedStopEvidence: lowSpeedStopEvidence
        )
        if let data = try? JSONEncoder().encode(envelope) {
            UserDefaults.standard.set(data, forKey: Self.activeTripKey)
        }
    }

    private func restoreActiveTrip() {
        guard AutomaticTrackingSettings.isEnabled,
              let data = UserDefaults.standard.data(forKey: Self.activeTripKey),
              let envelope = try? JSONDecoder().decode(ActiveTripEnvelope.self, from: data) else {
            return
        }
        guard trackingReadiness == .ready else {
            state = .permissionRequired
            return
        }
        detectionStartedAt = envelope.startedAt
        candidateStartedAt = envelope.tripStartedAt ?? envelope.samples.first?.timestamp
        processor.restore(samples: envelope.samples, distanceMeters: envelope.distanceMeters)
        distanceMeters = envelope.distanceMeters
        automotiveConfirmed = envelope.automotiveConfirmed
        highestObservedSpeed = envelope.highestObservedSpeed
        candidateStopStartedAt = envelope.candidateStopStartedAt
        motionStopEvidence = envelope.motionStopEvidence ?? false
        lowSpeedStopEvidence = envelope.lowSpeedStopEvidence ?? false
        elapsedTime = Date().timeIntervalSince(candidateStartedAt ?? envelope.startedAt)
        guard locationService.startPreciseTracking() else {
            state = .permissionRequired
            return
        }
        locationService.stopLowPowerMonitoring()
        state = envelope.isTracking ? .tracking : .detecting
        startMotionMonitoring()
        if envelope.isTracking {
            startElapsedTimer()
            if candidateStopStartedAt != nil {
                scheduleStopCountdown(
                    motionEvidence: motionStopEvidence,
                    lowSpeedEvidence: lowSpeedStopEvidence
                )
            }
        }
        if !envelope.isTracking {
            detectionTimeoutTask?.cancel()
            let elapsed = Date().timeIntervalSince(envelope.startedAt)
            let remaining = max(detectionTimeout - elapsed, 0)
            detectionTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(remaining))
                guard let self, self.state == .detecting else { return }
                TrackingDiagnostics.log("restored detection timed out before driving confirmation")
                self.resetToIdle()
            }
        }
        TrackingDiagnostics.log("active automatic trip state restored")
    }

    private func diagnosticName(for result: LocationSampleProcessor.Result) -> String {
        switch result {
        case .accepted: "accepted"
        case .rejectedInvalidAccuracy: "invalidAccuracy"
        case .rejectedStale: "stale"
        case .rejectedNonIncreasingTime: "nonIncreasingTime"
        case .rejectedInsufficientMovement: "insufficientMovement"
        case .rejectedImplausibleSpeed: "implausibleSpeed"
        }
    }

    private var detectionConfirmationBlockers: String {
        var blockers: [String] = []
        if !automotiveConfirmed { blockers.append("automotive motion not confirmed") }
        if processor.acceptedSamples.isEmpty { blockers.append("no usable GPS samples") }
        if distanceMeters < Self.confirmationDistanceMeters {
            blockers.append("movement below 80 meters")
        }
        if highestObservedSpeed < Self.minimumDrivingSpeed {
            blockers.append("observed speed below 4 meters per second")
        }
        return blockers.isEmpty ? "confirmation did not complete" : blockers.joined(separator: "; ")
    }

    private func clearPersistedActiveTrip() {
        UserDefaults.standard.removeObject(forKey: Self.activeTripKey)
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let startedAt = self.candidateStartedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
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

    private func migrateLegacyPendingTripIfNeeded() {
        guard !legacyPendingMigrationStarted, let trip = pendingTrip else { return }
        legacyPendingMigrationStarted = true
        Task { [weak self, repository, notificationService] in
            let existing = (try? await repository.fetchTrips()) ?? []
            if !existing.contains(where: { $0.id == trip.id }) {
                try? await repository.save(trip)
            }
            self?.clearPersistedPendingTrip()
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
            await notificationService.reconcileReviewReminder()
        }
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
            try? await repository.update(updated)
        }
    }

    private func reverseGeocodeStoredTrip(_ trip: Trip) {
        Task { [repository] in
            async let startName = Self.locationName(for: trip.startCoordinate)
            async let endName = Self.locationName(for: trip.endCoordinate)
            var updated = trip
            updated.originName = await startName
            updated.destinationName = await endName
            updated.updatedAt = .now
            try? await repository.update(updated)
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: updated.id)
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

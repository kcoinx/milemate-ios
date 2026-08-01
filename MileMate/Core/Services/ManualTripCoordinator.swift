@preconcurrency import CoreLocation
import Foundation
import Observation

@MainActor
protocol TripReviewCoordinating: AnyObject, Observable {
    var pendingTrip: Trip? { get }
    func savePendingTrip(
        classification: Trip.Classification,
        purpose: String,
        notes: String,
        vehicle: VehicleSnapshot?,
        classificationSource: Trip.ClassificationSource,
        appliedRuleID: UUID?
    ) async throws
    func discardPendingTrip()
}

@MainActor
@Observable
final class ManualTripCoordinator: TripReviewCoordinating {
    enum State: Equatable {
        case ready
        case requestingPermission
        case tracking
        case reviewing
        case permissionDenied
        case failed(String)
    }

    private let locationService: any LocationService
    private let repository: any MileageRepository
    private var processor = LocationSampleProcessor()
    private var elapsedTask: Task<Void, Never>?
    private var geocodeTask: Task<Void, Never>?
    private var startedAt: Date?
    private var lastGeocodedAt: Date?
    private var pendingStart = false

    private(set) var state: State = .ready
    private(set) var distanceMeters = 0.0
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var currentLocationLabel: String?
    var pendingTrip: Trip?

    init(locationService: any LocationService, repository: any MileageRepository) {
        self.locationService = locationService
        self.repository = repository
        self.locationService.eventHandler = { [weak self] event in
            self?.handle(event)
        }
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

    func startTrip() {
        guard state != .tracking else { return }
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginTracking()
        case .notDetermined:
            pendingStart = true
            state = .requestingPermission
            locationService.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .failed("Location permission is unavailable.")
        }
    }

    func stopTrip() {
        guard state == .tracking, let startedAt else { return }
        stopLocationUpdates()
        let endedAt = Date()
        let route = processor.acceptedSamples.map {
            TripCoordinate(latitude: $0.latitude, longitude: $0.longitude, timestamp: $0.timestamp)
        }

        pendingTrip = Trip(
            id: UUID(),
            startedAt: startedAt,
            endedAt: endedAt,
            originName: "Unknown location",
            destinationName: "Unknown location",
            distanceMiles: distanceMiles,
            classification: .unclassified,
            purpose: "",
            startCoordinate: route.first,
            endCoordinate: route.last,
            route: route
        )
        state = .reviewing
        assignDefaultVehicleToPendingTrip()
        reverseGeocodePendingTrip()
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
        NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
        pendingTrip = nil
        resetSession()
    }

    func discardPendingTrip() {
        pendingTrip = nil
        stopLocationUpdates()
        resetSession()
    }

    func appDidEnterBackground() {
        if state == .tracking {
            stopTrip()
        }
    }

    private func beginTracking() {
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        currentLocationLabel = nil
        lastGeocodedAt = nil
        startedAt = .now
        state = .tracking
        locationService.startUpdatingLocation()
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func handle(_ event: LocationServiceEvent) {
        switch event {
        case .authorizationChanged(let status):
            if pendingStart && (status == .authorizedAlways || status == .authorizedWhenInUse) {
                pendingStart = false
                beginTracking()
            } else if status == .denied || status == .restricted {
                pendingStart = false
                state = .permissionDenied
            }
        case .locations(let samples):
            guard state == .tracking else { return }
            for sample in samples where processor.process(sample) {
                distanceMeters = processor.distanceMeters
                updateCurrentLocationContext(using: sample)
            }
        case .failed(let message):
            guard state == .tracking else { return }
            stopLocationUpdates()
            state = .failed(message)
        }
    }

    private func stopLocationUpdates() {
        locationService.stopUpdatingLocation()
        elapsedTask?.cancel()
        elapsedTask = nil
        geocodeTask?.cancel()
        geocodeTask = nil
        pendingStart = false
    }

    private func resetSession() {
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        currentLocationLabel = nil
        lastGeocodedAt = nil
        startedAt = nil
        state = .ready
    }

    private func updateCurrentLocationContext(using sample: LocationSample) {
        let now = Date()
        guard lastGeocodedAt.map({ now.timeIntervalSince($0) >= 20 }) ?? true else { return }
        lastGeocodedAt = now
        geocodeTask?.cancel()

        geocodeTask = Task { [weak self] in
            let coordinate = TripCoordinate(
                latitude: sample.latitude,
                longitude: sample.longitude,
                timestamp: sample.timestamp
            )
            let label = await Self.areaName(for: coordinate)
            guard !Task.isCancelled, let self, self.state == .tracking else { return }
            self.currentLocationLabel = label
        }
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
        }
    }

    private func assignDefaultVehicleToPendingTrip() {
        guard let tripID = pendingTrip?.id else { return }
        Task {
            let vehicles = (try? await repository.fetchVehicles()) ?? []
            guard let current = pendingTrip, current.id == tripID else { return }
            pendingTrip = VehicleAssignmentService.assigningDefault(
                to: current,
                vehicles: vehicles
            )
        }
    }

    private static func locationName(for coordinate: TripCoordinate?) async -> String {
        guard let coordinate else { return "Unknown location" }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return "Unknown location" }
            return [placemark.name, placemark.locality]
                .compactMap { $0 }
                .uniqued()
                .joined(separator: ", ")
                .nilIfEmpty ?? "Unknown location"
        } catch {
            return "Unknown location"
        }
    }

    private static func areaName(for coordinate: TripCoordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return [placemark.locality, placemark.administrativeArea]
                .compactMap { $0 }
                .uniqued()
                .joined(separator: ", ")
                .nilIfEmpty
        } catch {
            return nil
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

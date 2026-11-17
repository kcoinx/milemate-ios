@preconcurrency import CoreLocation
import Foundation
import Observation
import UIKit

enum AutomaticTrackingSettings {
    static let enabledKey = "automaticTrackingEnabled"
    static let minimumDistanceKey = "automaticMinimumTripDistance"
    static let tripEndDelayKey = "automaticTripEndDelay"
    static let defaultMinimumDistance = 0.30
    static let defaultTripEndDelay: TimeInterval = 600
    static let supportedTripEndDelays: [TimeInterval] = [300, 600, 1_200]

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var minimumDistance: Double {
        let value = UserDefaults.standard.double(forKey: minimumDistanceKey)
        return value > 0 ? value : defaultMinimumDistance
    }

    static var tripEndDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: tripEndDelayKey)
        return supportedTripEndDelays.contains(value) ? value : defaultTripEndDelay
    }
}

enum AutomaticDrivingConfirmation {
    static func qualifies(
        distanceMeters: Double,
        highestObservedSpeed: Double,
        acceptedSampleCount: Int,
        automotiveConfidence: MotionConfidence?
    ) -> Bool {
        let standardDrivingConfirmed = distanceMeters >= 80 && highestObservedSpeed >= 4
        let slowDrivingConfirmed =
            automotiveConfidence == .high &&
            acceptedSampleCount >= 3 &&
            distanceMeters >= 160 &&
            highestObservedSpeed >= 1.5
        return standardDrivingConfirmed || slowDrivingConfirmed
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
        let ownerScopeIdentifier: String?
    }

    private struct ActiveTripEnvelope: Codable {
        let tripID: UUID?
        let startedAt: Date
        let tripStartedAt: Date?
        let samples: [LocationSample]
        let distanceMeters: Double
        let automotiveConfirmed: Bool
        let automotiveConfidence: MotionConfidence?
        let highestObservedSpeed: Double
        let isTracking: Bool
        let lastCredibleDrivingActivityAt: Date?
        let candidateStopStartedAt: Date?
        let motionStopEvidence: Bool?
        let lowSpeedStopEvidence: Bool?
        let ownerScopeIdentifier: String?
    }

    private let locationService: any AutomaticLocationService
    private let motionService: any MotionActivityService
    private let repository: any MileageRepository
    private let notificationService: any TripNotificationScheduling
    private let canStartNewTrip: @MainActor () -> Bool
    private let tripDidSave: @MainActor (Trip) -> Void
    private let isManualTrackingActive: @MainActor () -> Bool
    private let dataScopeProvider: LocalDataScopeProvider?
    private let backgroundRefreshStatusProvider: @MainActor () -> UIBackgroundRefreshStatus
    private let stopIntervalOverride: TimeInterval?
    private let detectionTimeout: TimeInterval
    private var processor = LocationSampleProcessor()
    private var automotiveConfirmed = false
    private var automotiveConfidence: MotionConfidence?
    private var detectionStartedAt: Date?
    private var candidateStartedAt: Date?
    private var highestObservedSpeed = 0.0
    private var elapsedTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var detectionTimeoutTask: Task<Void, Never>?
    private var requestedAlwaysAuthorization = false
    private var legacyPendingMigrationStarted = false
    private var candidateStopStartedAt: Date?
    private var lastCredibleDrivingActivityAt: Date?
    private var motionStopEvidence = false
    private var lowSpeedStopEvidence = false
    private var pendingLowPowerSamples: [LocationSample] = []
    private var activeOwnerScopeIdentifier: String?
    private var pendingOwnerScopeIdentifier: String?
    private var activeTripID: UUID?
    private(set) var isFinalizingTrip = false

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
        canStartNewTrip: @escaping @MainActor () -> Bool = { true },
        tripDidSave: @escaping @MainActor (Trip) -> Void = { _ in },
        dataScopeProvider: LocalDataScopeProvider? = nil,
        backgroundRefreshStatusProvider: @escaping @MainActor () -> UIBackgroundRefreshStatus = {
            UIApplication.shared.backgroundRefreshStatus
        },
        stopInterval: TimeInterval? = nil,
        detectionTimeout: TimeInterval = 180,
        isManualTrackingActive: @escaping @MainActor () -> Bool
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.repository = repository
        self.notificationService = notificationService
        self.canStartNewTrip = canStartNewTrip
        self.tripDidSave = tripDidSave
        self.dataScopeProvider = dataScopeProvider
        self.backgroundRefreshStatusProvider = backgroundRefreshStatusProvider
        self.stopIntervalOverride = stopInterval
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

    var preciseLocationAvailable: Bool {
        locationService.preciseLocationAvailable
    }

    var backgroundRefreshStatus: UIBackgroundRefreshStatus {
        backgroundRefreshStatusProvider()
    }

    var backgroundRefreshUnavailable: Bool {
        backgroundRefreshStatus != .available
    }

    var hasProtectedTripState: Bool {
        activeOwnerScopeIdentifier != nil ||
            pendingOwnerScopeIdentifier != nil ||
            pendingTrip != nil ||
            isFinalizingTrip
    }

    var trackingReadiness: AutomaticTrackingReadiness {
        AutomaticTrackingReadiness.evaluate(
            location: locationService.authorizationStatus,
            preciseLocationAvailable: locationService.preciseLocationAvailable,
            motion: motionService.permissionStatus,
            backgroundCapabilityAvailable: locationService.backgroundCapabilityAvailable,
            significantLocationMonitoringAvailable: locationService.significantLocationMonitoringAvailable,
            motionActivityMonitoringAvailable: motionService.activityMonitoringAvailable
        )
    }

    var readinessSnapshot: AutomaticTrackingReadinessSnapshot {
        AutomaticTrackingReadinessSnapshot(
            locationAuthorization: locationService.authorizationStatus,
            preciseLocationAvailable: locationService.preciseLocationAvailable,
            motionAuthorization: motionService.permissionStatus,
            backgroundCapabilityAvailable: locationService.backgroundCapabilityAvailable,
            significantLocationMonitoringAvailable: locationService.significantLocationMonitoringAvailable,
            motionActivityMonitoringAvailable: motionService.activityMonitoringAvailable,
            automaticTrackingEnabled: AutomaticTrackingSettings.isEnabled,
            result: trackingReadiness
        )
    }

    private var stopInterval: TimeInterval {
        stopIntervalOverride ?? AutomaticTrackingSettings.tripEndDelay
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
        guard dataScopeProvider?.current != nil else {
            stopDetection()
            state = .disabled
            TrackingDiagnostics.log("automatic tracking waiting for an active guest or account scope")
            return
        }
        if state == .tracking || isFinalizingTrip { return }
        if pendingTrip != nil {
            state = .reviewing
            return
        }
        requestLocationAuthorizationIfNeeded()
        let passiveMonitoringArmed = armPassiveMonitoringIfPossible()
        if !passiveMonitoringArmed, trackingReadiness != .ready {
            state = .permissionRequired
        }
        guard state != .detecting else { return }
        if !canStartNewTrip(), state != .permissionRequired {
            state = .idle
        }
    }

    /// Recreates the battery-efficient wake path without granting permission to
    /// begin or persist a trip. Eligibility remains enforced by motion/location
    /// callbacks and again before tracking is confirmed.
    @discardableResult
    func armPassiveMonitoringIfPossible() -> Bool {
        guard AutomaticTrackingSettings.isEnabled,
              dataScopeProvider?.current != nil else {
            return false
        }
        guard locationService.authorizationStatus == .authorizedAlways,
              locationService.backgroundCapabilityAvailable,
              locationService.significantLocationMonitoringAvailable,
              motionService.activityMonitoringAvailable else {
            return false
        }
        switch motionService.permissionStatus {
        case .denied, .restricted, .unavailable:
            return false
        case .notDetermined, .authorized:
            break
        }
        locationService.startLowPowerMonitoring()
        startMotionMonitoring()
        switch state {
        case .disabled, .permissionRequired, .failed:
            state = trackingReadiness == .ready ? .idle : .permissionRequired
        case .idle, .detecting, .tracking, .reviewing:
            break
        }
        return true
    }

    func handleLocationBackgroundLaunch() {
        TrackingDiagnostics.log("location-triggered background launch received")
        startIfEnabled()
    }

    func handleSessionScopeChange() {
        guard !hasProtectedTripState else { return }
        pendingLowPowerSamples.removeAll()
        if dataScopeProvider?.current == nil {
            stopDetection()
            state = .disabled
            return
        }
        startIfEnabled()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled, hasProtectedTripState {
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
        guard pendingOwnerScopeIdentifier == dataScopeProvider?.current?.identifier else {
            throw LocalDataScopeError.noActiveAccount
        }
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
        tripDidSave(trip)
        notificationService.cancelNotifications(for: trip.id)
        await notificationService.reconcileReviewReminder()
        NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
        pendingTrip = nil
        pendingOwnerScopeIdentifier = nil
        clearPersistedPendingTrip()
        resetToIdle()
    }

    func discardPendingTrip() {
        if let trip = pendingTrip {
            let tripID = trip.id
            let ownerScopeIdentifier = pendingOwnerScopeIdentifier
            notificationService.cancelNotifications(for: tripID)
            Task { [repository, notificationService, dataScopeProvider] in
                guard dataScopeProvider?.current?.identifier == ownerScopeIdentifier else { return }
                try? await repository.delete(trip)
                await notificationService.reconcileReviewReminder()
                NotificationCenter.default.post(name: .mileageTripsDidChange, object: tripID)
            }
        }
        pendingTrip = nil
        pendingOwnerScopeIdentifier = nil
        clearPersistedPendingTrip()
        resetToIdle()
    }

    /// Safely converts the active automatic trip into the existing review flow.
    /// This is intentionally available even when automatic finalization is waiting
    /// for an inactivity deadline, so a user is never trapped in an active trip.
    func endActiveTripForReview() {
        guard stageActiveTripForReview(
            endedAt: lastCredibleDrivingActivityAt ?? .now,
            failureMessage: "MileMate couldn't prepare this trip for review. Your active trip remains saved for recovery."
        ) else { return }
        TrackingDiagnostics.log("automatic trip ended by user and preserved for review")
        reverseGeocodePendingTrip()
    }

    func prepareForLocalDataDeletion() {
        stopDetection()
        pendingTrip = nil
        pendingOwnerScopeIdentifier = nil
        activeOwnerScopeIdentifier = nil
        activeTripID = nil
        isFinalizingTrip = false
        clearPersistedPendingTrip()
        clearPersistedActiveTrip()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        detectionStartedAt = nil
        candidateStopStartedAt = nil
        lastCredibleDrivingActivityAt = nil
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
            _ = armPassiveMonitoringIfPossible()
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
            if status != CLAuthorizationStatus.authorizedAlways,
               state == .tracking {
                interruptActiveTripForPermissionLoss()
                return
            }
            if status != CLAuthorizationStatus.authorizedAlways,
               state == .detecting {
                cancelDetectionForPermissionLoss()
                return
            }
            if pendingTrip != nil {
                state = .reviewing
                return
            }
            switch status {
            case CLAuthorizationStatus.authorizedAlways:
                _ = armPassiveMonitoringIfPossible()
            case CLAuthorizationStatus.authorizedWhenInUse where !requestedAlwaysAuthorization:
                requestedAlwaysAuthorization = true
                locationService.requestAlwaysAuthorization()
            case CLAuthorizationStatus.denied, CLAuthorizationStatus.restricted:
                state = .permissionRequired
            default:
                break
            }

        case .locations(let samples):
            guard !isFinalizingTrip else { return }
            guard AutomaticTrackingSettings.isEnabled else {
                TrackingDiagnostics.log("location wake ignored because automatic tracking is disabled")
                return
            }
            guard !isManualTrackingActive() else {
                TrackingDiagnostics.log("location wake ignored because manual tracking is active")
                return
            }
            guard canStartNewTrip() || state == .tracking else {
                TrackingDiagnostics.log("automatic location wake ignored because the guest trip limit is complete")
                if state == .detecting { resetToIdle() }
                return
            }
            if state == .idle {
                pendingLowPowerSamples = Array(
                    (pendingLowPowerSamples + samples).suffix(4)
                )
                TrackingDiagnostics.log(
                    "low-power location wake buffered while awaiting automotive motion evidence; sampleCount=\(samples.count)"
                )
                startMotionMonitoring()
                motionService.refreshRecentActivity(since: .now.addingTimeInterval(-300))
                TrackingDiagnostics.log("motion monitoring re-armed after low-power location wake")
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
            guard trackingReadiness == .ready else {
                state = .permissionRequired
                return
            }
            // Core Location failures can be transient during background execution.
            // Preserve the active detector/trip and re-arm the low-power wake path
            // instead of discarding the in-memory route until the app is reopened.
            locationService.startLowPowerMonitoring()
            startMotionMonitoring()
            motionService.refreshRecentActivity(since: .now.addingTimeInterval(-300))
            TrackingDiagnostics.log("automatic detector preserved after transient location interruption")
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
              !isManualTrackingActive(),
              !isFinalizingTrip else {
            return
        }
        guard canStartNewTrip() || state == .tracking else {
            if state == .detecting { resetToIdle() }
            return
        }

        TrackingDiagnostics.log(
            "motion event received; kind=\(activity.kind.rawValue); confidence=\(activity.confidence)"
        )

        if activity.kind == .automotive, activity.confidence != .low {
            automotiveConfirmed = true
            if automotiveConfidence == nil ||
                activity.confidence.rawValue > (automotiveConfidence?.rawValue ?? 0) {
                automotiveConfidence = activity.confidence
            }
            TrackingDiagnostics.log("automotive movement accepted as detection evidence")
            if state != .tracking {
                cancelStopCountdown()
            }
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
        guard let ownerScopeIdentifier = dataScopeProvider?.current?.identifier else {
            state = .failed("Choose a MileMate account or guest session before tracking a trip.")
            return
        }
        activeOwnerScopeIdentifier = ownerScopeIdentifier
        activeTripID = UUID()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        detectionStartedAt = .now
        candidateStartedAt = nil
        lastCredibleDrivingActivityAt = nil
        highestObservedSpeed = 0
        state = .detecting
        TrackingDiagnostics.log(
            "automatic detector entered detecting; timeout=\(Int(detectionTimeout)) seconds"
        )
        locationService.stopLowPowerMonitoring()
        guard locationService.startPreciseTracking() else {
            activeOwnerScopeIdentifier = nil
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
            let reportsUnknownSpeed = sample.speed < 0
            if state == .tracking, reportsStationarySpeed || reportsUnknownSpeed {
                scheduleStopCountdown(lowSpeedEvidence: true)
                rejectionCounts[reportsUnknownSpeed ? "unknownSpeedWhileTracking" : "stationarySpeed", default: 0] += 1
                continue
            }
            if state == .tracking,
               candidateStopStartedAt != nil,
               sample.speed < Self.minimumDrivingSpeed {
                scheduleStopCountdown(lowSpeedEvidence: true)
                rejectionCounts["belowCredibleDrivingSpeed", default: 0] += 1
                continue
            }
            let processingResult = processor.processWithResult(sample)
            guard processingResult == .accepted else {
                if state == .tracking, reportsStationarySpeed {
                    scheduleStopCountdown(lowSpeedEvidence: true)
                }
                let reason = diagnosticName(for: processingResult)
                rejectionCounts[reason, default: 0] += 1
                continue
            }
            if state == .tracking {
                recordCredibleDrivingActivity(at: sample.timestamp)
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
               AutomaticDrivingConfirmation.qualifies(
                   distanceMeters: distanceMeters,
                   highestObservedSpeed: highestObservedSpeed,
                   acceptedSampleCount: processor.acceptedSamples.count,
                   automotiveConfidence: automotiveConfidence
               ) {
                beginTracking()
            }
        }
        TrackingDiagnostics.log(
            "location batch processed; received=\(samples.count); acceptedTotal=\(processor.acceptedSamples.count); movementMeters=\(Int(distanceMeters)); highestSpeedMetersPerSecond=\(highestObservedSpeed.formatted(.number.precision(.fractionLength(1)))); rejected=\(rejectionCounts)"
        )
    }

    private func beginTracking() {
        guard canStartNewTrip() else {
            resetToIdle()
            return
        }
        detectionTimeoutTask?.cancel()
        detectionTimeoutTask = nil
        state = .tracking
        lastCredibleDrivingActivityAt = processor.acceptedSamples.last?.timestamp ?? .now
        TrackingDiagnostics.log(
            "automatic tracking confirmed; acceptedSamples=\(processor.acceptedSamples.count); movementMeters=\(Int(distanceMeters)); highestSpeedMetersPerSecond=\(highestObservedSpeed.formatted(.number.precision(.fractionLength(1))))"
        )
        TripFeedback.started()
        persistActiveTrip()
        scheduleInactivityDeadline()
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
        scheduleInactivityDeadline()
    }

    private func recordCredibleDrivingActivity(at timestamp: Date) {
        lastCredibleDrivingActivityAt = max(lastCredibleDrivingActivityAt ?? timestamp, timestamp)
        cancelStopCountdown(rescheduleInactivityDeadline: false)
        persistActiveTrip()
        scheduleInactivityDeadline()
    }

    private func scheduleInactivityDeadline() {
        guard state == .tracking else { return }
        stopTask?.cancel()
        let lastActivity = lastCredibleDrivingActivityAt
            ?? processor.acceptedSamples.last?.timestamp
            ?? candidateStartedAt
            ?? .now
        lastCredibleDrivingActivityAt = lastActivity
        let remaining = max(stopInterval - Date().timeIntervalSince(lastActivity), 0)
        stopTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, self.state == .tracking else { return }
            self.finishAutomaticTrip()
        }
    }

    private func cancelStopCountdown(rescheduleInactivityDeadline: Bool = true) {
        let hadCandidateStop = candidateStopStartedAt != nil
        stopTask?.cancel()
        stopTask = nil
        candidateStopStartedAt = nil
        motionStopEvidence = false
        lowSpeedStopEvidence = false
        if hadCandidateStop {
            TrackingDiagnostics.log("candidate stop canceled because driving evidence resumed")
        }
        if state == .tracking {
            persistActiveTrip()
            if rescheduleInactivityDeadline {
                scheduleInactivityDeadline()
            }
        }
    }

    private func finishAutomaticTrip() {
        guard state == .tracking, let startedAt = candidateStartedAt else { return }
        guard let ownerScopeIdentifier = activeOwnerScopeIdentifier else { return }
        let route = currentRoute
        let miles = distanceMiles
        let stoppedAt = candidateStopStartedAt ?? lastCredibleDrivingActivityAt ?? .now
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
            id: activeTripID ?? UUID(),
            startedAt: startedAt,
            endedAt: max(stoppedAt, startedAt),
            originName: "Unknown location",
            destinationName: "Unknown location",
            distanceMiles: miles,
            classification: .unclassified,
            purpose: "",
            startCoordinate: route.first,
            endCoordinate: route.last,
            route: route
        )
        if persistPendingTrip(trip, ownerScopeIdentifier: ownerScopeIdentifier) {
            TrackingDiagnostics.log("completed automatic trip staged for crash-safe persistence")
        } else {
            TrackingDiagnostics.log("completed automatic trip could not be staged for recovery")
        }
        isFinalizingTrip = true
        resetToIdle(preservingOwner: true)
        Task { [weak self] in
            guard let self else { return }
            guard self.dataScopeProvider?.current?.identifier == ownerScopeIdentifier else {
                self.quarantinePendingTripAfterScopeMismatch()
                return
            }
            var assignedTrip = trip
            async let fetchedVehicles = self.repository.fetchVehicles()
            async let fetchedPlaces = self.repository.fetchFrequentPlaces()
            async let fetchedRules = self.repository.fetchClassificationRules()
            let vehicles = (try? await fetchedVehicles) ?? []
            guard self.dataScopeProvider?.current?.identifier == ownerScopeIdentifier else {
                self.quarantinePendingTripAfterScopeMismatch()
                return
            }
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
                        guard self.dataScopeProvider?.current?.identifier == ownerScopeIdentifier else {
                            self.quarantinePendingTripAfterScopeMismatch()
                            return
                        }
                        try await self.repository.save(classifiedTrip)
                        self.tripDidSave(classifiedTrip)
                        NotificationCenter.default.post(
                            name: .mileageTripsDidChange,
                            object: classifiedTrip.id
                        )
                        self.clearPersistedPendingTrip()
                        self.pendingOwnerScopeIdentifier = nil
                        self.isFinalizingTrip = false
                        await self.notificationService.scheduleTripCompletion(for: classifiedTrip)
                        TrackingDiagnostics.log("automatic trip persisted successfully with approved classification rule")
                        self.resetToIdle()
                        self.reverseGeocodeStoredTrip(
                            classifiedTrip,
                            ownerScopeIdentifier: ownerScopeIdentifier
                        )
                        return
                    } catch {
                        // Fall through to review so a persistence failure never loses the trip.
                    }
                }
            }
            guard self.dataScopeProvider?.current?.identifier == ownerScopeIdentifier else {
                self.quarantinePendingTripAfterScopeMismatch()
                return
            }
            do {
                try await self.repository.save(assignedTrip)
                NotificationCenter.default.post(
                    name: .mileageTripsDidChange,
                    object: assignedTrip.id
                )
                self.clearPersistedPendingTrip()
                self.pendingOwnerScopeIdentifier = nil
                self.isFinalizingTrip = false
                self.completeAutomaticTrip(assignedTrip)
                self.resetToIdle()
                TrackingDiagnostics.log("automatic trip persisted successfully for review")
                self.reverseGeocodeStoredTrip(
                    assignedTrip,
                    ownerScopeIdentifier: ownerScopeIdentifier
                )
            } catch {
                TrackingDiagnostics.log("automatic trip could not be persisted")
                self.pendingTrip = assignedTrip
                self.pendingOwnerScopeIdentifier = ownerScopeIdentifier
                self.persistPendingTrip(assignedTrip, ownerScopeIdentifier: ownerScopeIdentifier)
                self.isFinalizingTrip = false
                self.state = .reviewing
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
        cancelStopCountdown(rescheduleInactivityDeadline: false)
        automotiveConfirmed = false
        automotiveConfidence = nil
    }

    private func resetToIdle(preservingOwner: Bool = false) {
        clearPersistedActiveTrip()
        stopPreciseSession()
        clearPersistedActiveTrip()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        lastCredibleDrivingActivityAt = nil
        detectionStartedAt = nil
        pendingLowPowerSamples.removeAll()
        highestObservedSpeed = 0
        if !preservingOwner {
            activeOwnerScopeIdentifier = nil
            activeTripID = nil
        }
        if AutomaticTrackingSettings.isEnabled {
            state = armPassiveMonitoringIfPossible() ? .idle : .permissionRequired
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
            tripID: activeTripID,
            startedAt: startedAt,
            tripStartedAt: candidateStartedAt,
            samples: processor.acceptedSamples,
            distanceMeters: distanceMeters,
            automotiveConfirmed: automotiveConfirmed,
            automotiveConfidence: automotiveConfidence,
            highestObservedSpeed: highestObservedSpeed,
            isTracking: state == .tracking,
            lastCredibleDrivingActivityAt: lastCredibleDrivingActivityAt,
            candidateStopStartedAt: candidateStopStartedAt,
            motionStopEvidence: motionStopEvidence,
            lowSpeedStopEvidence: lowSpeedStopEvidence,
            ownerScopeIdentifier: activeOwnerScopeIdentifier
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
        guard let ownerScopeIdentifier = envelope.ownerScopeIdentifier,
              ownerScopeIdentifier == dataScopeProvider?.current?.identifier else {
            RecoverySnapshotQuarantine.preserve(data, from: Self.activeTripKey)
            return
        }
        activeOwnerScopeIdentifier = ownerScopeIdentifier
        activeTripID = envelope.tripID ?? UUID()
        guard trackingReadiness == .ready else {
            state = .permissionRequired
            return
        }
        detectionStartedAt = envelope.startedAt
        candidateStartedAt = envelope.tripStartedAt ?? envelope.samples.first?.timestamp
        processor.restore(samples: envelope.samples, distanceMeters: envelope.distanceMeters)
        distanceMeters = envelope.distanceMeters
        automotiveConfirmed = envelope.automotiveConfirmed
        automotiveConfidence = envelope.automotiveConfidence
        highestObservedSpeed = envelope.highestObservedSpeed
        candidateStopStartedAt = envelope.candidateStopStartedAt
        lastCredibleDrivingActivityAt = envelope.lastCredibleDrivingActivityAt
            ?? envelope.candidateStopStartedAt
            ?? envelope.samples.last?.timestamp
            ?? envelope.tripStartedAt
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
            scheduleInactivityDeadline()
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
    private func persistPendingTrip(_ trip: Trip, ownerScopeIdentifier: String) -> Bool {
        guard let data = try? JSONEncoder().encode(
            PendingTripEnvelope(trip: trip, ownerScopeIdentifier: ownerScopeIdentifier)
        ) else {
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
        guard let ownerScopeIdentifier = envelope.ownerScopeIdentifier,
              ownerScopeIdentifier == dataScopeProvider?.current?.identifier else {
            RecoverySnapshotQuarantine.preserve(data, from: Self.pendingTripKey)
            return
        }
        pendingTrip = envelope.trip
        pendingOwnerScopeIdentifier = ownerScopeIdentifier
        state = .reviewing
    }

    private func migrateLegacyPendingTripIfNeeded() {
        guard !legacyPendingMigrationStarted, let trip = pendingTrip else { return }
        legacyPendingMigrationStarted = true
        Task { [weak self, repository, notificationService] in
            guard self?.dataScopeProvider?.current?.identifier == self?.pendingOwnerScopeIdentifier else {
                return
            }
            let existing = (try? await repository.fetchTrips()) ?? []
            if !existing.contains(where: { $0.id == trip.id }) {
                try? await repository.save(trip)
            }
            guard self?.dataScopeProvider?.current?.identifier == self?.pendingOwnerScopeIdentifier else { return }
            self?.clearPersistedPendingTrip()
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
            await notificationService.reconcileReviewReminder()
        }
    }

    private func clearPersistedPendingTrip() {
        UserDefaults.standard.removeObject(forKey: Self.pendingTripKey)
    }

    private func interruptActiveTripForPermissionLoss() {
        guard stageActiveTripForReview(
            endedAt: .now,
            failureMessage: "Location permission changed. Your active trip remains saved for recovery."
        ) else { return }
        TrackingDiagnostics.log("automatic trip interrupted by location permission change and preserved for review")
        reverseGeocodePendingTrip()
    }

    @discardableResult
    private func stageActiveTripForReview(endedAt: Date, failureMessage: String) -> Bool {
        guard state == .tracking,
              let startedAt = candidateStartedAt,
              let ownerScopeIdentifier = activeOwnerScopeIdentifier else {
            return false
        }
        let route = currentRoute
        let trip = Trip(
            id: activeTripID ?? UUID(),
            startedAt: startedAt,
            endedAt: max(endedAt, startedAt),
            originName: "Unknown location",
            destinationName: "Unknown location",
            distanceMiles: distanceMiles,
            classification: .unclassified,
            purpose: "",
            startCoordinate: route.first,
            endCoordinate: route.last,
            route: route
        )
        guard persistPendingTrip(trip, ownerScopeIdentifier: ownerScopeIdentifier) else {
            stopDetection()
            state = .failed(failureMessage)
            return false
        }
        pendingTrip = trip
        pendingOwnerScopeIdentifier = ownerScopeIdentifier
        stopDetection()
        clearPersistedActiveTrip()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        lastCredibleDrivingActivityAt = nil
        detectionStartedAt = nil
        activeOwnerScopeIdentifier = nil
        activeTripID = nil
        state = .reviewing
        return true
    }

    private func cancelDetectionForPermissionLoss() {
        stopDetection()
        clearPersistedActiveTrip()
        processor.reset()
        distanceMeters = 0
        elapsedTime = 0
        candidateStartedAt = nil
        lastCredibleDrivingActivityAt = nil
        detectionStartedAt = nil
        activeOwnerScopeIdentifier = nil
        activeTripID = nil
        pendingLowPowerSamples.removeAll()
        state = .permissionRequired
        TrackingDiagnostics.log("unconfirmed automatic detection canceled after location permission change")
    }

    private func quarantinePendingTripAfterScopeMismatch() {
        if let data = UserDefaults.standard.data(forKey: Self.pendingTripKey) {
            RecoverySnapshotQuarantine.preserve(data, from: Self.pendingTripKey)
        }
        pendingTrip = nil
        pendingOwnerScopeIdentifier = nil
        activeOwnerScopeIdentifier = nil
        activeTripID = nil
        lastCredibleDrivingActivityAt = nil
        isFinalizingTrip = false
        state = AutomaticTrackingSettings.isEnabled ? .idle : .disabled
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
            guard let ownerScopeIdentifier = pendingOwnerScopeIdentifier,
                  dataScopeProvider?.current?.identifier == ownerScopeIdentifier else { return }
            persistPendingTrip(updated, ownerScopeIdentifier: ownerScopeIdentifier)
            try? await repository.update(updated)
        }
    }

    private func reverseGeocodeStoredTrip(_ trip: Trip, ownerScopeIdentifier: String) {
        Task { [repository, dataScopeProvider] in
            async let startName = Self.locationName(for: trip.startCoordinate)
            async let endName = Self.locationName(for: trip.endCoordinate)
            var updated = trip
            updated.originName = await startName
            updated.destinationName = await endName
            updated.updatedAt = .now
            guard dataScopeProvider?.current?.identifier == ownerScopeIdentifier else { return }
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

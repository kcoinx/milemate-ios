import CoreLocation
import UIKit
import XCTest
@testable import MileMate

@MainActor
final class AutomaticTripCoordinatorTests: XCTestCase {
    private let enabledKey = AutomaticTrackingSettings.enabledKey
    private let minimumDistanceKey = AutomaticTrackingSettings.minimumDistanceKey
    private let pendingTripKey = "automaticPendingTrip"

    func testPassiveMonitoringArmsWhileTripEligibilityIsPendingWithoutStartingTrip() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(canStartNewTrip: { false })

        coordinator.startIfEnabled()

        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertTrue(motion.isUpdating)
        motion.send(activity(.automotive, confidence: .high))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testLocationBackgroundLaunchRearmsPassiveMonitoringWithoutDuplicateRegistration() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(canStartNewTrip: { false })

        coordinator.handleLocationBackgroundLaunch()
        coordinator.handleLocationBackgroundLaunch()

        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertTrue(motion.isUpdating)
        XCTAssertEqual(location.lowPowerStartCount, 1)
        XCTAssertEqual(motion.startUpdatesCount, 1)
    }

    func testSessionScopeChangeStopsAndRearmsPassiveMonitoring() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let scopeProvider = LocalDataScopeProvider()
        let (coordinator, location, motion) = makeCoordinator(scopeProvider: scopeProvider)

        coordinator.startIfEnabled()
        XCTAssertFalse(location.isLowPowerMonitoring)

        scopeProvider.setCurrent(.authenticated(userID: "replacement-account"))
        coordinator.handleSessionScopeChange()
        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertTrue(motion.isUpdating)

        scopeProvider.setCurrent(nil)
        coordinator.handleSessionScopeChange()
        XCTAssertFalse(location.isLowPowerMonitoring)
        XCTAssertFalse(motion.isUpdating)
        XCTAssertEqual(coordinator.state, .disabled)
    }

    func testBackgroundRefreshUnavailableIsReportedWithoutBlockingForegroundMonitoring() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, _) = makeCoordinator(
            backgroundRefreshStatusProvider: { .denied }
        )

        coordinator.startIfEnabled()

        XCTAssertTrue(coordinator.backgroundRefreshUnavailable)
        XCTAssertTrue(location.isLowPowerMonitoring)
    }

    func testMediumOrHighConfidenceAutomotiveActivityStartsResilientDetection() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, _, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.walking, confidence: .high))
        XCTAssertEqual(coordinator.state, .idle)

        motion.send(activity(.automotive, confidence: .medium))
        XCTAssertEqual(coordinator.state, .detecting)
    }

    func testUnconfirmedDetectionCanSwitchBackToManualAndRestartAutomaticMode() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        XCTAssertEqual(coordinator.state, .detecting)
        XCTAssertFalse(coordinator.hasProtectedTripState)
        coordinator.appDidEnterBackground()

        coordinator.setEnabled(false)

        XCTAssertEqual(coordinator.state, .disabled)
        XCTAssertFalse(location.isPreciseTracking)
        XCTAssertFalse(location.isLowPowerMonitoring)
        XCTAssertFalse(motion.isUpdating)
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticActiveTrip"))

        coordinator.setEnabled(true)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertTrue(motion.isUpdating)
        XCTAssertFalse(coordinator.hasProtectedTripState)

        for _ in 0..<2 {
            motion.send(activity(.automotive, confidence: .medium))
            XCTAssertEqual(coordinator.state, .detecting)
            XCTAssertFalse(coordinator.hasProtectedTripState)
            coordinator.setEnabled(false)
            XCTAssertEqual(coordinator.state, .disabled)
            coordinator.setEnabled(true)
            XCTAssertEqual(coordinator.state, .idle)
        }
    }

    func testRestoredUnconfirmedDetectionCanSwitchToManual() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let scope = testScopeProvider()
        let (original, _, motion) = makeCoordinator(scopeProvider: scope)
        defer { original.prepareForLocalDataDeletion() }
        original.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        XCTAssertEqual(original.state, .detecting)

        let restored = makeCoordinator(scopeProvider: scope).0
        defer { restored.prepareForLocalDataDeletion() }
        XCTAssertEqual(restored.state, .detecting)
        XCTAssertFalse(restored.hasProtectedTripState)

        restored.setEnabled(false)

        XCTAssertEqual(restored.state, .disabled)
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
    }

    func testConfirmedAutomaticTripStillBlocksModeChange() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(coordinator.state, .tracking)
        XCTAssertTrue(coordinator.hasProtectedTripState)

        coordinator.setEnabled(false)

        XCTAssertEqual(coordinator.state, .tracking)
        XCTAssertTrue(AutomaticTrackingSettings.isEnabled)
        XCTAssertTrue(coordinator.hasProtectedTripState)
    }

    func testAccountScopeChangeCancelsUnconfirmedDetectionBeforeRearming() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let scope = testScopeProvider(userID: "first-account")
        let (coordinator, location, motion) = makeCoordinator(scopeProvider: scope)
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        XCTAssertEqual(coordinator.state, .detecting)

        scope.setCurrent(.authenticated(userID: "second-account"))
        coordinator.handleSessionScopeChange()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(location.isPreciseTracking)
        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertTrue(motion.isUpdating)
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
        XCTAssertFalse(coordinator.hasProtectedTripState)
    }

    func testForegroundDetectionToleratesDelayedFirstUsableGPSSample() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        location.send([
            LocationSample(
                latitude: 37.7749,
                longitude: -122.4194,
                horizontalAccuracy: 250,
                timestamp: .now,
                speed: 10
            )
        ])
        XCTAssertEqual(coordinator.state, .detecting)

        location.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(coordinator.state, .tracking)
    }

    func testLocationWakeBeforeDelayedAutomotiveEventIsNotLost() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }
        motion.recentActivity = activity(.automotive, confidence: .medium)

        coordinator.startIfEnabled()
        location.send(drivingSamples(latitudeDelta: 0.005))

        XCTAssertEqual(coordinator.state, .tracking)
        XCTAssertEqual(motion.recentActivityRefreshCount, 1)
    }

    func testSlowDrivingRequiresStrongAutomotiveAndSustainedMovement() {
        XCTAssertTrue(
            AutomaticDrivingConfirmation.qualifies(
                distanceMeters: 180,
                highestObservedSpeed: 2.2,
                acceptedSampleCount: 4,
                automotiveConfidence: .high
            )
        )
        XCTAssertFalse(
            AutomaticDrivingConfirmation.qualifies(
                distanceMeters: 180,
                highestObservedSpeed: 2.2,
                acceptedSampleCount: 4,
                automotiveConfidence: .medium
            )
        )
        XCTAssertFalse(
            AutomaticDrivingConfirmation.qualifies(
                distanceMeters: 70,
                highestObservedSpeed: 2.2,
                acceptedSampleCount: 4,
                automotiveConfidence: .high
            )
        )
    }

    func testCyclingEvidenceCancelsUnconfirmedDrive() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, _, motion) = makeCoordinator()

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        XCTAssertEqual(coordinator.state, .detecting)

        motion.send(activity(.cycling, confidence: .high))
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testTripEndPreferenceDefaultsToTenMinutesAndSupportsExpectedChoices() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AutomaticTrackingSettings.tripEndDelayKey)
        defer {
            if let original {
                defaults.set(original, forKey: AutomaticTrackingSettings.tripEndDelayKey)
            } else {
                defaults.removeObject(forKey: AutomaticTrackingSettings.tripEndDelayKey)
            }
        }

        defaults.removeObject(forKey: AutomaticTrackingSettings.tripEndDelayKey)
        XCTAssertEqual(AutomaticTrackingSettings.tripEndDelay, 600)
        for delay in AutomaticTrackingSettings.supportedTripEndDelays {
            defaults.set(delay, forKey: AutomaticTrackingSettings.tripEndDelayKey)
            XCTAssertEqual(AutomaticTrackingSettings.tripEndDelay, delay)
        }
        defaults.set(42, forKey: AutomaticTrackingSettings.tripEndDelayKey)
        XCTAssertEqual(AutomaticTrackingSettings.tripEndDelay, 600)
    }

    func testStationaryMotionDuringGPSWarmupDoesNotCancelDetection() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, _, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        motion.send(activity(.stationary, confidence: .high))

        XCTAssertEqual(coordinator.state, .detecting)
    }

    func testLowConfidenceAutomotiveAndFalseMovementDoNotStartTrip() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .low))
        location.send(drivingSamples(latitudeDelta: 0.005))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testInsufficientMovementDoesNotConfirmTracking() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.0005))

        XCTAssertEqual(coordinator.state, .detecting)
    }

    func testInsufficientSpeedDoesNotConfirmTracking() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }
        let now = Date()

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send([
            LocationSample(
                latitude: 37.7749,
                longitude: -122.4194,
                horizontalAccuracy: 8,
                timestamp: now.addingTimeInterval(-14),
                speed: 2
            ),
            LocationSample(
                latitude: 37.77571,
                longitude: -122.4194,
                horizontalAccuracy: 8,
                timestamp: now.addingTimeInterval(14),
                speed: 2
            )
        ])

        XCTAssertGreaterThan(coordinator.distanceMeters, 80)
        XCTAssertEqual(coordinator.state, .detecting)
    }

    func testDetectionTimeoutReturnsToBatteryEfficientIdle() async {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(detectionTimeout: 0.01)

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        let didReturnToIdle = await waitUntil {
            coordinator.state == .idle
        }

        XCTAssertTrue(didReturnToIdle)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testBackgroundAndLockedTransitionPreserveDetectingAndTrackingState() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        coordinator.appDidEnterBackground()

        XCTAssertEqual(coordinator.state, .detecting)

        location.send(drivingSamples(latitudeDelta: 0.005))
        coordinator.appDidEnterBackground()

        XCTAssertEqual(coordinator.state, .tracking)
    }

    func testTransientBackgroundLocationInterruptionPreservesActiveTripAndRearmsDetection() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(coordinator.state, .tracking)

        location.sendFailure()

        XCTAssertEqual(coordinator.state, .tracking)
        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertTrue(motion.isUpdating)
        XCTAssertEqual(motion.recentActivityRefreshCount, 1)
    }

    func testDetectingAndActiveTrackingRestoreAfterCoordinatorRecreation() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let detectingScope = testScopeProvider()
        let (detecting, _, detectingMotion) = makeCoordinator(scopeProvider: detectingScope)
        defer { detecting.prepareForLocalDataDeletion() }
        detecting.startIfEnabled()
        detectingMotion.send(activity(.automotive, confidence: .medium))

        let (restoredDetecting, _, _) = makeCoordinator(scopeProvider: detectingScope)
        defer { restoredDetecting.prepareForLocalDataDeletion() }
        XCTAssertEqual(restoredDetecting.state, .detecting)

        clearAutomaticTrackingState()
        enableAutomaticTracking()
        let trackingScope = testScopeProvider()
        let (tracking, trackingLocation, trackingMotion) = makeCoordinator(scopeProvider: trackingScope)
        defer { tracking.prepareForLocalDataDeletion() }
        tracking.startIfEnabled()
        trackingMotion.send(activity(.automotive, confidence: .medium))
        trackingLocation.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(tracking.state, .tracking)

        let (restoredTracking, _, _) = makeCoordinator(scopeProvider: trackingScope)
        defer { restoredTracking.prepareForLocalDataDeletion() }
        XCTAssertEqual(restoredTracking.state, .tracking)
    }

    func testActiveTripIsQuarantinedForDifferentOwner() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let originalScope = testScopeProvider(userID: "original-owner")
        let (tracking, location, motion) = makeCoordinator(scopeProvider: originalScope)
        defer { tracking.prepareForLocalDataDeletion() }
        tracking.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        location.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(tracking.state, .tracking)

        let otherScope = testScopeProvider(userID: "different-owner")
        let (restored, _, _) = makeCoordinator(scopeProvider: otherScope)

        XCTAssertNotEqual(restored.state, .tracking)
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
        XCTAssertTrue(hasQuarantinedSnapshot(for: "automaticActiveTrip"))
    }

    func testLegacyOwnerlessActiveTripIsQuarantined() throws {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let scope = testScopeProvider()
        let (tracking, location, motion) = makeCoordinator(scopeProvider: scope)
        tracking.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        location.send(drivingSamples(latitudeDelta: 0.005))
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "ownerScopeIdentifier")
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: object), forKey: "automaticActiveTrip")

        let (restored, _, _) = makeCoordinator(scopeProvider: scope)

        XCTAssertNotEqual(restored.state, .tracking)
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
        XCTAssertTrue(hasQuarantinedSnapshot(for: "automaticActiveTrip"))
    }

    func testPendingTripIsQuarantinedForDifferentOwner() throws {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let tripData = try JSONEncoder().encode(MockData.trips[0])
        let tripObject = try XCTUnwrap(JSONSerialization.jsonObject(with: tripData))
        let envelope: [String: Any] = [
            "trip": tripObject,
            "ownerScopeIdentifier": LocalDataScope.authenticated(userID: "pending-original").identifier
        ]
        UserDefaults.standard.set(
            try JSONSerialization.data(withJSONObject: envelope),
            forKey: "automaticPendingTrip"
        )

        let (restored, _, _) = makeCoordinator(
            scopeProvider: testScopeProvider(userID: "pending-other")
        )

        XCTAssertNil(restored.pendingTrip)
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticPendingTrip"))
        XCTAssertTrue(hasQuarantinedSnapshot(for: "automaticPendingTrip"))
    }

    func testPendingTripRestoresOnlyForItsOriginalOwner() throws {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let ownerScope = LocalDataScope.authenticated(userID: "pending-owner")
        let trip = MockData.trips[0]
        let tripData = try JSONEncoder().encode(trip)
        let tripObject = try XCTUnwrap(JSONSerialization.jsonObject(with: tripData))
        let envelope: [String: Any] = [
            "trip": tripObject,
            "ownerScopeIdentifier": ownerScope.identifier
        ]
        UserDefaults.standard.set(
            try JSONSerialization.data(withJSONObject: envelope),
            forKey: "automaticPendingTrip"
        )

        let (restored, _, _) = makeCoordinator(
            scopeProvider: LocalDataScopeProvider(scope: ownerScope)
        )

        XCTAssertEqual(restored.state, .reviewing)
        XCTAssertEqual(restored.pendingTrip?.id, trip.id)
        XCTAssertFalse(hasQuarantinedSnapshot(for: "automaticPendingTrip"))
    }

    func testPermissionErrorDoesNotHideProtectedAutomaticTrip() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        location.send(drivingSamples(latitudeDelta: 0.005))

        location.authorizationStatus = .denied
        location.eventHandler?(.authorizationChanged(.denied))

        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertNotNil(coordinator.pendingTrip)
        XCTAssertTrue(coordinator.hasProtectedTripState)
    }

    func testAutomaticTripInterruptedWhenAlwaysChangesToWhileUsing() {
        assertAutomaticTripInterruption(for: .authorizedWhenInUse)
    }

    func testAutomaticTripInterruptedWhenLocationIsDenied() {
        assertAutomaticTripInterruption(for: .denied)
    }

    func testAutomaticTripInterruptedWhenLocationIsRestricted() {
        assertAutomaticTripInterruption(for: .restricted)
    }

    func testPermissionRestorationDoesNotResumeOrDuplicateInterruptedAutomaticTrip() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let scope = testScopeProvider()
        let (coordinator, location, motion) = makeCoordinator(scopeProvider: scope)
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        location.authorizationStatus = .denied
        location.eventHandler?(.authorizationChanged(.denied))
        let pendingID = coordinator.pendingTrip?.id

        location.authorizationStatus = .authorizedAlways
        location.eventHandler?(.authorizationChanged(.authorizedAlways))
        coordinator.startIfEnabled()

        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertEqual(coordinator.pendingTrip?.id, pendingID)
        XCTAssertFalse(location.isPreciseTracking)
        XCTAssertTrue(coordinator.hasProtectedTripState)
    }

    func testDetectionOnlyPermissionLossDoesNotCreateTrip() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        XCTAssertEqual(coordinator.state, .detecting)

        location.authorizationStatus = .denied
        location.eventHandler?(.authorizationChanged(.denied))

        XCTAssertEqual(coordinator.state, .permissionRequired)
        XCTAssertNil(coordinator.pendingTrip)
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
        XCTAssertFalse(coordinator.hasProtectedTripState)
    }

    func testDoesNotDetectWhileManualTrackingIsActive() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let location = MockAutomaticLocationService()
        let motion = MockMotionActivityService()
        let coordinator = AutomaticTripCoordinator(
            locationService: location,
            motionService: motion,
            repository: MockMileageRepository(),
            notificationService: MockTripNotificationService(),
            dataScopeProvider: testScopeProvider(),
            isManualTrackingActive: { true }
        )

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testInvalidLocationAuthorizationFailsDetectionSafely() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()
        location.authorizationStatus = .authorizedWhenInUse

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))

        XCTAssertEqual(coordinator.state, .permissionRequired)
        XCTAssertEqual(coordinator.trackingReadiness, .locationPermissionRequired)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testTrackingReadinessRequiresAlwaysMotionAndCapability() {
        XCTAssertEqual(
            AutomaticTrackingReadiness.evaluate(
                location: .authorizedAlways,
                motion: .authorized,
                backgroundCapabilityAvailable: true
            ),
            .ready
        )
        XCTAssertEqual(
            AutomaticTrackingReadiness.evaluate(
                location: .authorizedAlways,
                motion: .authorized,
                backgroundCapabilityAvailable: false
            ),
            .backgroundCapabilityUnavailable
        )
        XCTAssertEqual(
            AutomaticTrackingReadiness.evaluate(
                location: .authorizedWhenInUse,
                motion: .authorized,
                backgroundCapabilityAvailable: true
            ),
            .locationPermissionRequired
        )
        XCTAssertEqual(
            AutomaticTrackingReadiness.evaluate(
                location: .authorizedAlways,
                preciseLocationAvailable: false,
                motion: .authorized,
                backgroundCapabilityAvailable: true
            ),
            .preciseLocationRequired
        )
        XCTAssertEqual(
            AutomaticTrackingReadiness.evaluate(
                location: .authorizedAlways,
                motion: .denied,
                backgroundCapabilityAvailable: true
            ),
            .motionPermissionRequired
        )
    }

    func testBackgroundCapabilityAcceptsGeneratedPlistRepresentations() {
        XCTAssertTrue(BackgroundLocationCapability.containsLocationMode(["location"]))
        XCTAssertTrue(BackgroundLocationCapability.containsLocationMode(["location"] as [Any]))
        XCTAssertTrue(BackgroundLocationCapability.containsLocationMode("location"))
        XCTAssertFalse(BackgroundLocationCapability.containsLocationMode(["fetch"]))
        XCTAssertFalse(BackgroundLocationCapability.containsLocationMode(nil))
    }

    func testBuiltHostContainsBackgroundLocationMode() {
        XCTAssertTrue(
            BackgroundLocationCapability.isAvailable,
            "The built MileMate host must contain UIBackgroundModes.location"
        )
    }

    func testUnavailableDetectionServiceHasExactFailureReason() {
        let readiness = AutomaticTrackingReadiness.evaluate(
            location: .authorizedAlways,
            motion: .authorized,
            backgroundCapabilityAvailable: true,
            significantLocationMonitoringAvailable: false,
            motionActivityMonitoringAvailable: true
        )

        XCTAssertEqual(readiness, .detectionServicesUnavailable)
        XCTAssertTrue(readiness.diagnosticReason.contains("detection service is unavailable"))
    }

    func testMissingBackgroundCapabilityPreventsPreciseAutomaticTracking() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let location = MockAutomaticLocationService()
        location.backgroundCapabilityAvailable = false
        let motion = MockMotionActivityService()
        let coordinator = AutomaticTripCoordinator(
            locationService: location,
            motionService: motion,
            repository: MockMileageRepository(),
            notificationService: MockTripNotificationService(),
            dataScopeProvider: testScopeProvider(),
            isManualTrackingActive: { false }
        )

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))

        XCTAssertEqual(coordinator.trackingReadiness, .backgroundCapabilityUnavailable)
        XCTAssertEqual(coordinator.state, .permissionRequired)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testTrackingModeSelectionReflectsPersistedPreferenceWithoutChangingTabs() {
        XCTAssertEqual(
            TrackingModeSelection(automaticTrackingEnabled: false),
            .manual
        )
        XCTAssertEqual(
            TrackingModeSelection(automaticTrackingEnabled: true),
            .automatic
        )
        let (coordinator, _, _) = makeCoordinator()
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )
        router.selectedTab = .settings
        _ = TrackingModeSelection(automaticTrackingEnabled: false)
        XCTAssertEqual(router.selectedTab, .settings)
    }

    func testPermissionCTAIsUserActionableOnly() {
        XCTAssertEqual(
            TrackingPermissionAction(readiness: .locationPermissionRequired)?.title,
            "Review Location"
        )
        XCTAssertEqual(
            TrackingPermissionAction(readiness: .motionPermissionRequired)?.title,
            "Review Motion & Fitness"
        )
        XCTAssertEqual(
            TrackingPermissionAction(readiness: .preciseLocationRequired)?.title,
            "Review Location"
        )
        XCTAssertNil(TrackingPermissionAction(readiness: .ready))
        XCTAssertNil(TrackingPermissionAction(readiness: .backgroundCapabilityUnavailable))
        XCTAssertNil(TrackingPermissionAction(readiness: .detectionServicesUnavailable))
    }

    func testReadyStartupEntersBatteryEfficientIdleMonitoring() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator()

        coordinator.startIfEnabled()

        XCTAssertEqual(coordinator.trackingReadiness, .ready)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(location.isLowPowerMonitoring)
        XCTAssertTrue(motion.isUpdating)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testReadinessDiagnosticReportsExactInputsWithoutLocationData() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, _, _) = makeCoordinator()
        let diagnostic = coordinator.readinessSnapshot.diagnosticDescription

        XCTAssertTrue(diagnostic.contains("Location Authorization: authorizedAlways"))
        XCTAssertTrue(diagnostic.contains("Motion Authorization: authorized"))
        XCTAssertTrue(diagnostic.contains("Background Location Capability: available"))
        XCTAssertTrue(diagnostic.contains("Significant Change Monitoring: available"))
        XCTAssertTrue(diagnostic.contains("Motion Activity Monitoring: available"))
        XCTAssertTrue(diagnostic.contains("Result: ready"))
        XCTAssertFalse(diagnostic.contains("latitude"))
        XCTAssertFalse(diagnostic.contains("longitude"))
    }

    func testRollingDetectionDiagnosticsExplainStateWithoutPrivateLocationData() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        TrackingDiagnostics.resetHistory()
        let (coordinator, location, motion) = makeCoordinator()

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .medium))
        location.send(drivingSamples(latitudeDelta: 0.005))
        let history = TrackingDiagnostics.recentHistory.joined(separator: "\n")

        XCTAssertTrue(history.contains("automatic detector entered detecting"))
        XCTAssertTrue(history.contains("location batch processed"))
        XCTAssertTrue(history.contains("automatic tracking confirmed"))
        XCTAssertFalse(history.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(history.localizedCaseInsensitiveContains("longitude"))
        XCTAssertFalse(history.localizedCaseInsensitiveContains("address"))
        XCTAssertLessThanOrEqual(TrackingDiagnostics.recentHistory.count, 120)
    }

    func testShortAutomaticTripIsDiscarded() async {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(stopInterval: 0.01)

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.001))
        XCTAssertEqual(coordinator.state, .tracking)

        motion.send(activity(.stationary, confidence: .high))
        let didFinish = await waitUntil {
            coordinator.state == .idle && !coordinator.hasProtectedTripState
        }

        XCTAssertTrue(didFinish)
        XCTAssertNil(coordinator.pendingTrip)
    }

    func testQualifyingAutomaticTripReturnsToIdleForFutureDetection() async {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(stopInterval: 0.01)

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(coordinator.state, .tracking)

        motion.send(activity(.stationary, confidence: .high))
        let didFinish = await waitUntil {
            coordinator.state == .idle && !coordinator.hasProtectedTripState
        }

        XCTAssertTrue(didFinish)
        XCTAssertNil(coordinator.pendingTrip)
    }

    func testTrackingExpiresWithoutFurtherLocationOrMotionCallbacks() async {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(stopInterval: 0.02)

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(coordinator.state, .tracking)

        let didExpire = await waitUntil {
            coordinator.state == .idle && !coordinator.hasProtectedTripState
        }
        XCTAssertTrue(didExpire)
        XCTAssertFalse(coordinator.hasProtectedTripState)
    }

    func testRestoredTrackingUsesPersistedDrivingActivityDeadline() async throws {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let scope = testScopeProvider()
        let (coordinator, location, motion) = makeCoordinator(
            stopInterval: 0.2,
            scopeProvider: scope
        )
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        envelope["lastCredibleDrivingActivityAt"] = Date(timeIntervalSinceNow: -60).timeIntervalSinceReferenceDate
        let restoredEnvelope = try JSONSerialization.data(withJSONObject: envelope)
        coordinator.prepareForLocalDataDeletion()
        UserDefaults.standard.set(restoredEnvelope, forKey: "automaticActiveTrip")

        let restored = makeCoordinator(stopInterval: 0.2, scopeProvider: scope).0

        let restoredTripExpired = await waitUntil {
            restored.state == .idle && !restored.hasProtectedTripState
        }
        XCTAssertTrue(restoredTripExpired)
        XCTAssertFalse(restored.hasProtectedTripState)
    }

    func testStationaryAndUnknownSpeedSamplesDoNotAddMileageOrExtendTrip() async {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(stopInterval: 0.04)
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        let distance = coordinator.distanceMeters
        let now = Date()

        location.send([
            LocationSample(
                latitude: 37.785,
                longitude: -122.4194,
                horizontalAccuracy: 8,
                timestamp: now.addingTimeInterval(0.01),
                speed: -1
            ),
            LocationSample(
                latitude: 37.786,
                longitude: -122.4194,
                horizontalAccuracy: 8,
                timestamp: now.addingTimeInterval(0.02),
                speed: 0.4
            )
        ])

        XCTAssertEqual(coordinator.distanceMeters, distance, accuracy: 0.001)
        let didExpire = await waitUntil {
            coordinator.state == .idle && !coordinator.hasProtectedTripState
        }
        XCTAssertTrue(didExpire)
    }

    func testEndAndReviewPreservesTripAndReleasesProtectionAfterDiscard() {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let scope = testScopeProvider(userID: "end-review-owner")
        let (coordinator, location, motion) = makeCoordinator(scopeProvider: scope)
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        let route = coordinator.currentRoute
        let distance = coordinator.distanceMiles

        coordinator.endActiveTripForReview()

        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertEqual(coordinator.pendingTrip?.route, route)
        XCTAssertEqual(coordinator.pendingTrip?.distanceMiles ?? -1, distance, accuracy: 0.000_001)
        XCTAssertTrue(coordinator.hasProtectedTripState)

        let restored = makeCoordinator(scopeProvider: scope).0
        XCTAssertEqual(restored.pendingTrip?.id, coordinator.pendingTrip?.id)
        restored.discardPendingTrip()
        XCTAssertFalse(restored.hasProtectedTripState)
        XCTAssertEqual(restored.state, .idle)
    }

    func testCredibleDrivingResetsInactivityDeadline() async {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(stopInterval: 0.1)
        defer { coordinator.prepareForLocalDataDeletion() }

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        let distanceBeforeResuming = coordinator.distanceMeters
        motion.send(activity(.stationary, confidence: .high))
        let resumedAt = Date().addingTimeInterval(2)
        location.send([
            LocationSample(
                latitude: 37.77995,
                longitude: -122.4194,
                horizontalAccuracy: 8,
                timestamp: resumedAt,
                speed: 12
            )
        ])

        XCTAssertGreaterThan(coordinator.distanceMeters, distanceBeforeResuming)

        // The original 100 ms deadline has passed, while the accepted sample's
        // new deadline remains well in the future. This wide margin avoids a
        // simulator scheduling race while still proving that driving reset it.
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(coordinator.state, .tracking)
    }

    func testReviewPermissionsRouteOpensSettings() {
        let (coordinator, _, _) = makeCoordinator()
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )

        router.showTrackingPermissions()

        XCTAssertEqual(router.selectedTab, .settings)
    }

    func testRecentTripRoutesThroughTripsStackAndFallsBackWhenMissing() async {
        let (coordinator, _, _) = makeCoordinator()
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )
        let expected = MockData.trips[0]

        await router.showTripDetails(tripID: expected.id)
        XCTAssertEqual(router.selectedTab, .trips)
        XCTAssertEqual(router.requestedTrip?.id, expected.id)

        await router.showTripDetails(tripID: UUID())
        XCTAssertEqual(router.selectedTab, .trips)
        XCTAssertNil(router.requestedTrip)
    }

    func testClosingRoutedTripDetailsLeavesTripsSelected() async {
        let (coordinator, _, _) = makeCoordinator()
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )

        await router.showTripDetails(tripID: MockData.trips[0].id)
        router.requestedTrip = nil

        XCTAssertEqual(router.selectedTab, .trips)
        XCTAssertNil(router.requestedTrip)
    }

    func testDirectTripsNavigationStateRemainsUnchanged() {
        let (coordinator, _, _) = makeCoordinator()
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )
        router.selectedTab = .trips

        // Trips-list NavigationLinks use their own Trip value in the same stack;
        // external requested-trip state remains reserved for cross-tab routing.
        XCTAssertEqual(router.selectedTab, .trips)
        XCTAssertNil(router.requestedTrip)
    }

    private func makeCoordinator(
        stopInterval: TimeInterval = 180,
        detectionTimeout: TimeInterval = 180,
        scopeProvider: LocalDataScopeProvider? = nil,
        canStartNewTrip: @escaping @MainActor () -> Bool = { true },
        backgroundRefreshStatusProvider: @escaping @MainActor () -> UIBackgroundRefreshStatus = {
            .available
        }
    ) -> (
        AutomaticTripCoordinator,
        MockAutomaticLocationService,
        MockMotionActivityService
    ) {
        let location = MockAutomaticLocationService()
        let motion = MockMotionActivityService()
        let scopeProvider = scopeProvider ?? testScopeProvider()
        let coordinator = AutomaticTripCoordinator(
            locationService: location,
            motionService: motion,
            repository: MockMileageRepository(),
            notificationService: MockTripNotificationService(),
            canStartNewTrip: canStartNewTrip,
            dataScopeProvider: scopeProvider,
            backgroundRefreshStatusProvider: backgroundRefreshStatusProvider,
            stopInterval: stopInterval,
            detectionTimeout: detectionTimeout,
            isManualTrackingActive: { false }
        )
        return (coordinator, location, motion)
    }

    private func enableAutomaticTracking(minimumDistance: Double = 0.30) {
        UserDefaults.standard.set(true, forKey: enabledKey)
        UserDefaults.standard.set(minimumDistance, forKey: minimumDistanceKey)
        UserDefaults.standard.removeObject(forKey: pendingTripKey)
        UserDefaults.standard.removeObject(forKey: "automaticActiveTrip")
    }

    private func clearAutomaticTrackingState() {
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: minimumDistanceKey)
        UserDefaults.standard.removeObject(forKey: pendingTripKey)
        UserDefaults.standard.removeObject(forKey: "automaticActiveTrip")
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix(RecoverySnapshotQuarantine.keyPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func testScopeProvider(userID: String = UUID().uuidString) -> LocalDataScopeProvider {
        LocalDataScopeProvider(scope: .authenticated(userID: userID))
    }

    private func hasQuarantinedSnapshot(for sourceKey: String) -> Bool {
        UserDefaults.standard.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(RecoverySnapshotQuarantine.keyPrefix + sourceKey + ".")
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func assertAutomaticTripInterruption(
        for status: CLAuthorizationStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let scope = testScopeProvider()
        let (coordinator, location, motion) = makeCoordinator(scopeProvider: scope)
        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        let route = coordinator.currentRoute
        let distance = coordinator.distanceMiles

        location.authorizationStatus = status
        location.eventHandler?(.authorizationChanged(status))

        let pending = coordinator.pendingTrip
        XCTAssertEqual(coordinator.state, .reviewing, file: file, line: line)
        XCTAssertEqual(pending?.route.count, route.count, file: file, line: line)
        XCTAssertEqual(pending?.distanceMiles ?? -1, distance, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(pending?.startedAt, route.first?.timestamp, file: file, line: line)
        XCTAssertFalse(location.isPreciseTracking, file: file, line: line)
        XCTAssertTrue(coordinator.hasProtectedTripState, file: file, line: line)

        let restored = makeCoordinator(scopeProvider: scope).0
        XCTAssertEqual(restored.state, .reviewing, file: file, line: line)
        XCTAssertEqual(restored.pendingTrip?.id, pending?.id, file: file, line: line)
        XCTAssertEqual(restored.pendingTrip?.route.count, route.count, file: file, line: line)
    }

    private func activity(
        _ kind: MotionKind,
        confidence: MotionConfidence
    ) -> MotionActivitySample {
        MotionActivitySample(kind: kind, confidence: confidence, timestamp: .now)
    }

    private func drivingSamples(latitudeDelta: Double) -> [LocationSample] {
        let now = Date()
        return [
            LocationSample(
                latitude: 37.7749,
                longitude: -122.4194,
                horizontalAccuracy: 8,
                timestamp: now.addingTimeInterval(-10),
                speed: 12
            ),
            LocationSample(
                latitude: 37.7749 + latitudeDelta,
                longitude: -122.4194,
                horizontalAccuracy: 8,
                timestamp: now,
                speed: 12
            )
        ]
    }
}

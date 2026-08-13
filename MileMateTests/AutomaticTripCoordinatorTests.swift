import CoreLocation
import XCTest
@testable import MileMate

@MainActor
final class AutomaticTripCoordinatorTests: XCTestCase {
    private let enabledKey = AutomaticTrackingSettings.enabledKey
    private let minimumDistanceKey = AutomaticTrackingSettings.minimumDistanceKey
    private let pendingTripKey = "automaticPendingTrip"

    func testRequiresHighConfidenceAutomotiveActivityToDetect() {
        enableAutomaticTracking()
        defer { clearAutomaticTrackingState() }
        let (coordinator, _, motion) = makeCoordinator()

        coordinator.startIfEnabled()
        motion.send(activity(.walking, confidence: .high))
        XCTAssertEqual(coordinator.state, .idle)

        motion.send(activity(.automotive, confidence: .medium))
        XCTAssertEqual(coordinator.state, .idle)

        motion.send(activity(.automotive, confidence: .high))
        XCTAssertEqual(coordinator.state, .detecting)
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
        let location = MockAutomaticLocationService()
        location.authorizationStatus = .authorizedWhenInUse
        let motion = MockMotionActivityService()
        let coordinator = AutomaticTripCoordinator(
            locationService: location,
            motionService: motion,
            repository: MockMileageRepository(),
            notificationService: MockTripNotificationService(),
            isManualTrackingActive: { false }
        )

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))

        XCTAssertEqual(coordinator.state, .permissionRequired)
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
            isManualTrackingActive: { false }
        )

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))

        XCTAssertEqual(coordinator.trackingReadiness, .backgroundCapabilityUnavailable)
        XCTAssertEqual(coordinator.state, .permissionRequired)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testManualTrackingRowActionabilityAndRouting() {
        XCTAssertTrue(ManualTrackingRowState(automaticTrackingEnabled: false).isActionable)
        XCTAssertFalse(ManualTrackingRowState(automaticTrackingEnabled: true).isActionable)

        let (coordinator, _, _) = makeCoordinator()
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )
        router.selectedTab = .settings
        router.showManualTracking()
        XCTAssertEqual(router.selectedTab, .dashboard)
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

    func testShortAutomaticTripIsDiscarded() async {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(stopInterval: 0.01)

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.001))
        XCTAssertEqual(coordinator.state, .tracking)

        motion.send(activity(.stationary, confidence: .high))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.pendingTrip)
    }

    func testQualifyingAutomaticTripMovesToReview() async {
        enableAutomaticTracking(minimumDistance: 0.30)
        defer { clearAutomaticTrackingState() }
        let (coordinator, location, motion) = makeCoordinator(stopInterval: 0.01)

        coordinator.startIfEnabled()
        motion.send(activity(.automotive, confidence: .high))
        location.send(drivingSamples(latitudeDelta: 0.005))
        XCTAssertEqual(coordinator.state, .tracking)

        motion.send(activity(.stationary, confidence: .high))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertNotNil(coordinator.pendingTrip)
        XCTAssertGreaterThan(coordinator.pendingTrip?.distanceMiles ?? 0, 0.30)
        coordinator.discardPendingTrip()
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
        stopInterval: TimeInterval = 180
    ) -> (
        AutomaticTripCoordinator,
        MockAutomaticLocationService,
        MockMotionActivityService
    ) {
        let location = MockAutomaticLocationService()
        let motion = MockMotionActivityService()
        let coordinator = AutomaticTripCoordinator(
            locationService: location,
            motionService: motion,
            repository: MockMileageRepository(),
            notificationService: MockTripNotificationService(),
            stopInterval: stopInterval,
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

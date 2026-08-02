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
    }

    private func clearAutomaticTrackingState() {
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: minimumDistanceKey)
        UserDefaults.standard.removeObject(forKey: pendingTripKey)
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

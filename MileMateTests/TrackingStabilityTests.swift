import CoreLocation
import MapKit
import XCTest
@testable import MileMate

@MainActor
final class TrackingStabilityTests: XCTestCase {
    func testManualTripSurvivesBackgroundAndRestoresWithoutCompleting() {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        defer { UserDefaults.standard.removeObject(forKey: "manualActiveTrip") }
        let location = StabilityLocationService()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository()
        )
        coordinator.startTrip()
        location.send(samples())
        coordinator.appDidEnterBackground()

        XCTAssertEqual(coordinator.state, .tracking)
        XCTAssertTrue(location.isUpdating)
        XCTAssertNil(coordinator.pendingTrip)

        let restoredLocation = StabilityLocationService()
        let restored = ManualTripCoordinator(
            locationService: restoredLocation,
            repository: MockMileageRepository()
        )
        XCTAssertEqual(restored.state, .tracking)
        XCTAssertTrue(restoredLocation.isUpdating)
        XCTAssertNil(restored.pendingTrip)
        XCTAssertGreaterThan(restored.distanceMeters, 0)
    }

    func testRouteRegionUsesStoredEndpointsAndNoRouteRemainsEmpty() {
        let start = TripCoordinate(latitude: 37.77, longitude: -122.42, timestamp: .now)
        let end = TripCoordinate(latitude: 37.79, longitude: -122.39, timestamp: .now)
        let points = RouteMapRegionCalculator.displayCoordinates(
            route: [], start: start, end: end
        )

        XCTAssertEqual(points.count, 2)
        let rect = RouteMapRegionCalculator.mapRect(for: points)
        XCTAssertTrue(rect.contains(MKMapPoint(points[0])))
        XCTAssertTrue(rect.contains(MKMapPoint(points[1])))
        XCTAssertTrue(RouteMapRegionCalculator.displayCoordinates(
            route: [], start: nil, end: nil
        ).isEmpty)
    }

    func testFeedbackPreferenceDoesNotAffectTrackingState() {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        UserDefaults.standard.set(false, forKey: TripFeedbackSettings.enabledKey)
        defer {
            UserDefaults.standard.removeObject(forKey: TripFeedbackSettings.enabledKey)
            UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        }
        let coordinator = ManualTripCoordinator(
            locationService: StabilityLocationService(),
            repository: MockMileageRepository()
        )

        coordinator.startTrip()

        XCTAssertEqual(coordinator.state, .tracking)
    }

    func testLongRunningReminderHasSessionCooldownAndCancelsAtTripEnd() async {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        defer { UserDefaults.standard.removeObject(forKey: "manualActiveTrip") }
        let notifications = MockTripNotificationService()
        let coordinator = ManualTripCoordinator(
            locationService: StabilityLocationService(),
            repository: MockMileageRepository(),
            notificationService: notifications,
            reminderEligibilityDuration: 0,
            inactivityReminderDelay: 0.02,
            safeguardCheckInterval: 0.01
        )
        coordinator.startTrip()

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(notifications.longRunningReminderCount, 1)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(notifications.longRunningReminderCount, 1)

        coordinator.stopTrip()
        XCTAssertTrue(notifications.longRunningReminderCancelled)
    }

    private func samples() -> [LocationSample] {
        let now = Date()
        return [
            LocationSample(latitude: 37.77, longitude: -122.42, horizontalAccuracy: 5,
                           timestamp: now.addingTimeInterval(-5), speed: 10),
            LocationSample(latitude: 37.771, longitude: -122.42, horizontalAccuracy: 5,
                           timestamp: now, speed: 10)
        ]
    }
}

@MainActor
private final class StabilityLocationService: LocationService {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var eventHandler: ((LocationServiceEvent) -> Void)?
    private(set) var isUpdating = false

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() -> Bool {
        isUpdating = true
        return true
    }
    func stopUpdatingLocation() { isUpdating = false }
    func send(_ samples: [LocationSample]) { eventHandler?(.locations(samples)) }
}

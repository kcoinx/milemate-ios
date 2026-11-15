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
        let scopeProvider = testScopeProvider()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: scopeProvider
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
            repository: MockMileageRepository(),
            dataScopeProvider: scopeProvider
        )
        XCTAssertEqual(restored.state, .tracking)
        XCTAssertTrue(restoredLocation.isUpdating)
        XCTAssertNil(restored.pendingTrip)
        XCTAssertGreaterThan(restored.distanceMeters, 0)
    }

    func testManualActiveTripIsQuarantinedForDifferentOwner() {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        defer { clearRecoveryState() }
        let originalScope = testScopeProvider(userID: "manual-original")
        let location = StabilityLocationService()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: originalScope
        )
        coordinator.startTrip()
        location.send(samples())

        let restored = ManualTripCoordinator(
            locationService: StabilityLocationService(),
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider(userID: "manual-other")
        )

        XCTAssertNotEqual(restored.state, .tracking)
        XCTAssertNil(UserDefaults.standard.data(forKey: "manualActiveTrip"))
        XCTAssertTrue(hasQuarantinedSnapshot(for: "manualActiveTrip"))
    }

    func testLegacyOwnerlessManualActiveTripIsQuarantined() throws {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        defer { clearRecoveryState() }
        let scope = testScopeProvider()
        let location = StabilityLocationService()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: scope
        )
        coordinator.startTrip()
        location.send(samples())
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "manualActiveTrip"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "ownerScopeIdentifier")
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: object), forKey: "manualActiveTrip")

        let restored = ManualTripCoordinator(
            locationService: StabilityLocationService(),
            repository: MockMileageRepository(),
            dataScopeProvider: scope
        )

        XCTAssertNotEqual(restored.state, .tracking)
        XCTAssertNil(UserDefaults.standard.data(forKey: "manualActiveTrip"))
        XCTAssertTrue(hasQuarantinedSnapshot(for: "manualActiveTrip"))
    }

    func testPermissionErrorDoesNotHideProtectedManualTrip() {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        defer { clearRecoveryState() }
        let location = StabilityLocationService()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider()
        )
        coordinator.startTrip()

        location.changeAuthorization(to: .denied)

        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertTrue(coordinator.hasProtectedTripState)
    }

    func testManualTripInterruptedWhenAlwaysChangesToWhileUsing() {
        assertManualTripInterruption(for: .authorizedWhenInUse)
    }

    func testManualTripInterruptedWhenLocationIsDenied() {
        assertManualTripInterruption(for: .denied)
    }

    func testManualTripInterruptedWhenLocationIsRestricted() {
        assertManualTripInterruption(for: .restricted)
    }

    func testPermissionRestorationDoesNotResumeInterruptedManualTrip() {
        clearRecoveryState()
        defer { clearRecoveryState() }
        let location = StabilityLocationService()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider()
        )
        coordinator.startTrip()
        location.send(samples())
        location.changeAuthorization(to: .denied)
        let pendingID = coordinator.pendingTrip?.id

        location.changeAuthorization(to: .authorizedAlways)
        coordinator.startTrip()

        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertEqual(coordinator.pendingTrip?.id, pendingID)
        XCTAssertFalse(location.isUpdating)
        XCTAssertTrue(coordinator.hasProtectedTripState)
    }

    func testManualPermissionRestorationReturnsToReadyWithoutStartingTrip() {
        clearRecoveryState()
        defer { clearRecoveryState() }
        let location = StabilityLocationService()
        location.authorizationStatus = .denied
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider()
        )
        coordinator.startTrip()
        XCTAssertEqual(coordinator.state, .permissionDenied)

        location.changeAuthorization(to: .authorizedAlways)

        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertFalse(location.isUpdating)
        XCTAssertNil(coordinator.pendingTrip)
    }

    func testManualPendingReviewIsQuarantinedForDifferentOwner() {
        clearRecoveryState()
        defer { clearRecoveryState() }
        let location = StabilityLocationService()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider(userID: "manual-pending-original")
        )
        coordinator.startTrip()
        location.send(samples())
        location.changeAuthorization(to: .denied)
        XCTAssertNotNil(coordinator.pendingTrip)

        let restored = ManualTripCoordinator(
            locationService: StabilityLocationService(),
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider(userID: "manual-pending-other")
        )

        XCTAssertNil(restored.pendingTrip)
        XCTAssertTrue(hasQuarantinedSnapshot(for: "manualPendingTrip"))
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
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider()
        )

        coordinator.startTrip()

        XCTAssertEqual(coordinator.state, .tracking)
    }

    func testManualTripContinuesWithLimitedBackgroundReadiness() {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        defer { UserDefaults.standard.removeObject(forKey: "manualActiveTrip") }
        let location = StabilityLocationService()
        location.backgroundCapabilityAvailable = false
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: testScopeProvider()
        )

        coordinator.startTrip()
        coordinator.appDidEnterBackground()

        XCTAssertEqual(coordinator.state, .tracking)
        XCTAssertFalse(coordinator.backgroundRecordingAvailable)
        XCTAssertTrue(location.isUpdating)
        XCTAssertNil(coordinator.pendingTrip)
    }

    func testLongRunningReminderHasSessionCooldownAndCancelsAtTripEnd() async {
        clearRecoveryState()
        defer { clearRecoveryState() }
        let notifications = MockTripNotificationService()
        let coordinator = ManualTripCoordinator(
            locationService: StabilityLocationService(),
            repository: MockMileageRepository(),
            notificationService: notifications,
            dataScopeProvider: testScopeProvider(),
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

    private func testScopeProvider(userID: String = UUID().uuidString) -> LocalDataScopeProvider {
        LocalDataScopeProvider(scope: .authenticated(userID: userID))
    }

    private func hasQuarantinedSnapshot(for sourceKey: String) -> Bool {
        UserDefaults.standard.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(RecoverySnapshotQuarantine.keyPrefix + sourceKey + ".")
        }
    }

    private func clearRecoveryState() {
        UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
        UserDefaults.standard.removeObject(forKey: "manualPendingTrip")
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix(RecoverySnapshotQuarantine.keyPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func assertManualTripInterruption(
        for status: CLAuthorizationStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        clearRecoveryState()
        defer { clearRecoveryState() }
        let scope = testScopeProvider()
        let location = StabilityLocationService()
        let coordinator = ManualTripCoordinator(
            locationService: location,
            repository: MockMileageRepository(),
            dataScopeProvider: scope
        )
        let earliestStart = Date()
        coordinator.startTrip()
        let latestStart = Date()
        location.send(samples())
        let route = coordinator.currentRoute
        let distance = coordinator.distanceMiles

        location.changeAuthorization(to: status)

        let pending = coordinator.pendingTrip
        XCTAssertEqual(coordinator.state, .reviewing, file: file, line: line)
        XCTAssertEqual(pending?.route.count, route.count, file: file, line: line)
        XCTAssertEqual(pending?.distanceMiles ?? -1, distance, accuracy: 0.000_001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(pending?.startedAt ?? .distantPast, earliestStart, file: file, line: line)
        XCTAssertLessThanOrEqual(pending?.startedAt ?? .distantFuture, latestStart, file: file, line: line)
        XCTAssertFalse(location.isUpdating, file: file, line: line)
        XCTAssertTrue(coordinator.hasProtectedTripState, file: file, line: line)

        let restoredLocation = StabilityLocationService()
        restoredLocation.authorizationStatus = status
        let restored = ManualTripCoordinator(
            locationService: restoredLocation,
            repository: MockMileageRepository(),
            dataScopeProvider: scope
        )
        XCTAssertEqual(restored.state, .reviewing, file: file, line: line)
        XCTAssertEqual(restored.pendingTrip?.id, pending?.id, file: file, line: line)
        XCTAssertEqual(restored.pendingTrip?.startedAt, pending?.startedAt, file: file, line: line)
        XCTAssertEqual(restored.pendingTrip?.route.count, route.count, file: file, line: line)
        XCTAssertFalse(restoredLocation.isUpdating, file: file, line: line)
    }
}

@MainActor
private final class StabilityLocationService: LocationService {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var backgroundCapabilityAvailable = true
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
    func changeAuthorization(to status: CLAuthorizationStatus) {
        authorizationStatus = status
        eventHandler?(.authorizationChanged(status))
    }
}

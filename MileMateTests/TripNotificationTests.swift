import Foundation
import XCTest
@testable import MileMate

@MainActor
final class TripNotificationTests: XCTestCase {
    private let enabledKey = AutomaticTrackingSettings.enabledKey
    private let minimumDistanceKey = AutomaticTrackingSettings.minimumDistanceKey
    private let pendingTripKey = "automaticPendingTrip"

    func testQualifyingAutomaticTripSchedulesOneNotification() async {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)

        await completeQualifyingTrip(coordinator, location: location, motion: motion)

        XCTAssertEqual(notifications.scheduledTripIDs.count, 1)
        XCTAssertTrue(notifications.pendingWasPersistedWhenScheduled)
        coordinator.startIfEnabled()
        XCTAssertEqual(notifications.scheduledTripIDs.count, 1)
        coordinator.discardPendingTrip()
    }

    func testShortTripSchedulesNoNotification() async {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)

        coordinator.startIfEnabled()
        motion.send(sample(.automotive))
        location.send(drivingSamples(latitudeDelta: 0.001))
        motion.send(sample(.stationary))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(notifications.scheduledTripIDs.isEmpty)
        XCTAssertNil(coordinator.pendingTrip)
    }

    func testReviewingTripCancelsReminder() async throws {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)
        await completeQualifyingTrip(coordinator, location: location, motion: motion)
        let tripID = try XCTUnwrap(coordinator.pendingTrip?.id)

        try await coordinator.savePendingTrip(
            classification: .business,
            purpose: "Client meeting",
            notes: ""
        )

        XCTAssertTrue(notifications.cancelledTripIDs.contains(tripID))
    }

    func testDiscardingTripCancelsReminder() async throws {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)
        await completeQualifyingTrip(coordinator, location: location, motion: motion)
        let tripID = try XCTUnwrap(coordinator.pendingTrip?.id)

        coordinator.discardPendingTrip()

        XCTAssertTrue(notifications.cancelledTripIDs.contains(tripID))
    }

    func testNotificationTapRoutesToCorrectPendingTrip() async throws {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)
        await completeQualifyingTrip(coordinator, location: location, motion: motion)
        let tripID = try XCTUnwrap(coordinator.pendingTrip?.id)
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )

        await router.handleNotificationTap(tripID: tripID)

        XCTAssertEqual(router.selectedTab, AppTab.dashboard)
        XCTAssertNil(router.requestedTrip)
        coordinator.discardPendingTrip()
    }

    func testDeniedNotificationPermissionDoesNotBreakTracking() async {
        defer { clearState() }
        let notifications = MockTripNotificationService(authorizationStatus: .denied)
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)

        await completeQualifyingTrip(coordinator, location: location, motion: motion)

        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertNotNil(coordinator.pendingTrip)
        XCTAssertTrue(notifications.scheduledTripIDs.isEmpty)
        coordinator.discardPendingTrip()
    }

    private func makeCoordinator(
        notifications: MockTripNotificationService
    ) -> (
        AutomaticTripCoordinator,
        MockAutomaticLocationService,
        MockMotionActivityService
    ) {
        UserDefaults.standard.set(true, forKey: enabledKey)
        UserDefaults.standard.set(0.30, forKey: minimumDistanceKey)
        UserDefaults.standard.removeObject(forKey: pendingTripKey)
        let location = MockAutomaticLocationService()
        let motion = MockMotionActivityService()
        let coordinator = AutomaticTripCoordinator(
            locationService: location,
            motionService: motion,
            repository: MockMileageRepository(),
            notificationService: notifications,
            stopInterval: 0.01,
            isManualTrackingActive: { false }
        )
        return (coordinator, location, motion)
    }

    private func clearState() {
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: minimumDistanceKey)
        UserDefaults.standard.removeObject(forKey: pendingTripKey)
    }

    private func completeQualifyingTrip(
        _ coordinator: AutomaticTripCoordinator,
        location: MockAutomaticLocationService,
        motion: MockMotionActivityService
    ) async {
        coordinator.startIfEnabled()
        motion.send(sample(.automotive))
        location.send(drivingSamples(latitudeDelta: 0.005))
        motion.send(sample(.stationary))
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func sample(_ kind: MotionKind) -> MotionActivitySample {
        MotionActivitySample(kind: kind, confidence: .high, timestamp: .now)
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

@MainActor
final class MockTripNotificationService: TripNotificationScheduling {
    private(set) var authorizationStatus: NotificationPermissionStatus
    private(set) var scheduledTripIDs: [UUID] = []
    private(set) var cancelledTripIDs: Set<UUID> = []
    private(set) var pendingWasPersistedWhenScheduled = false

    init(authorizationStatus: NotificationPermissionStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
    }

    func refreshAuthorizationStatus() async {}

    func requestAuthorization() async {
        if authorizationStatus == .notDetermined {
            authorizationStatus = .authorized
        }
    }

    func scheduleTripCompletion(for trip: Trip) async {
        guard authorizationStatus != .denied,
              !scheduledTripIDs.contains(trip.id) else {
            return
        }
        pendingWasPersistedWhenScheduled =
            UserDefaults.standard.data(forKey: "automaticPendingTrip") != nil
        scheduledTripIDs.append(trip.id)
    }

    func cancelNotifications(for tripID: UUID) {
        cancelledTripIDs.insert(tripID)
    }

    func cancelCompletionNotifications() {}
    func cancelReminderNotifications() {}
    func cancelAllTripNotifications() {}
}

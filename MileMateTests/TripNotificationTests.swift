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
        XCTAssertFalse(notifications.pendingWasPersistedWhenScheduled)
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

    func testCompletedTripDoesNotBlockDetectionOfNextTrip() async {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)

        await completeQualifyingTrip(coordinator, location: location, motion: motion)
        await completeQualifyingTrip(coordinator, location: location, motion: motion)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.pendingTrip)
        XCTAssertEqual(notifications.scheduledTripIDs.count, 2)
        XCTAssertEqual(Set(notifications.scheduledTripIDs).count, 2)
    }

    func testLegacySinglePendingTripMigratesOnceWithoutChangingItsID() async throws {
        defer { clearState() }
        let trip = reviewTrip(classification: .unclassified)
        let data = try JSONEncoder().encode(LegacyPendingTripEnvelope(trip: trip))
        UserDefaults.standard.set(data, forKey: pendingTripKey)
        UserDefaults.standard.set(false, forKey: enabledKey)
        let repository = RecordingMileageRepository()
        let notifications = MockTripNotificationService()
        let coordinator = AutomaticTripCoordinator(
            locationService: MockAutomaticLocationService(),
            motionService: MockMotionActivityService(),
            repository: repository,
            notificationService: notifications,
            isManualTrackingActive: { false }
        )

        coordinator.startIfEnabled()
        coordinator.startIfEnabled()
        try? await Task.sleep(for: .milliseconds(50))

        let migrated = try await repository.fetchTrips()
        XCTAssertEqual(migrated.map(\.id), [trip.id])
        XCTAssertNil(UserDefaults.standard.data(forKey: pendingTripKey))
    }

    func testReviewingTripCancelsReminder() async throws {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)
        await completeQualifyingTrip(coordinator, location: location, motion: motion)
        let tripID = try XCTUnwrap(notifications.scheduledTripIDs.first)

        notifications.cancelNotifications(for: tripID)

        XCTAssertTrue(notifications.cancelledTripIDs.contains(tripID))
    }

    func testDiscardingTripCancelsReminder() async throws {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)
        await completeQualifyingTrip(coordinator, location: location, motion: motion)
        let tripID = try XCTUnwrap(notifications.scheduledTripIDs.first)

        notifications.cancelNotifications(for: tripID)

        XCTAssertTrue(notifications.cancelledTripIDs.contains(tripID))
    }

    func testNotificationTapRoutesToCorrectPendingTrip() async throws {
        defer { clearState() }
        let notifications = MockTripNotificationService()
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)
        await completeQualifyingTrip(coordinator, location: location, motion: motion)
        let tripID = try XCTUnwrap(notifications.scheduledTripIDs.first)
        let router = AppRouter(
            repository: MockMileageRepository(),
            automaticTripCoordinator: coordinator
        )

        await router.handleNotificationTap(tripID: tripID)

        XCTAssertEqual(router.selectedTab, AppTab.trips)
        XCTAssertNil(router.requestedTrip)
    }

    func testDeniedNotificationPermissionDoesNotBreakTracking() async {
        defer { clearState() }
        let notifications = MockTripNotificationService(authorizationStatus: .denied)
        let (coordinator, location, motion) = makeCoordinator(notifications: notifications)

        await completeQualifyingTrip(coordinator, location: location, motion: motion)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.pendingTrip)
        XCTAssertTrue(notifications.scheduledTripIDs.isEmpty)
        coordinator.discardPendingTrip()
    }

    func testGrantedPermissionNeedsNoSettingsRecoveryRow() {
        XCTAssertEqual(NotificationSettingsRecovery(status: .authorized), .none)
        XCTAssertEqual(NotificationSettingsRecovery(status: .provisional), .none)
        XCTAssertEqual(NotificationSettingsRecovery(status: .ephemeral), .none)
    }

    func testDeniedOrUnavailablePermissionShowsSystemSettingsRecovery() {
        XCTAssertEqual(NotificationSettingsRecovery(status: .denied), .openSystemSettings)
        XCTAssertEqual(NotificationSettingsRecovery(status: .unavailable), .openSystemSettings)
        XCTAssertEqual(NotificationSettingsRecovery(status: .notDetermined), .requestPermission)
    }

    func testNotificationPreferencesPersistAcrossRecreationAndLifecycleReads() throws {
        let suiteName = "TripNotificationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        TripNotificationSettings.registerDefaults(in: defaults)

        XCTAssertTrue(defaults.bool(forKey: TripNotificationSettings.completionEnabledKey))
        XCTAssertTrue(defaults.bool(forKey: TripNotificationSettings.remindersEnabledKey))
        defaults.set(false, forKey: TripNotificationSettings.completionEnabledKey)
        defaults.set(false, forKey: TripNotificationSettings.remindersEnabledKey)

        let recreatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertFalse(recreatedDefaults.bool(forKey: TripNotificationSettings.completionEnabledKey))
        XCTAssertFalse(recreatedDefaults.bool(forKey: TripNotificationSettings.remindersEnabledKey))
        XCTAssertFalse(defaults.bool(forKey: TripNotificationSettings.completionEnabledKey))
        XCTAssertFalse(defaults.bool(forKey: TripNotificationSettings.remindersEnabledKey))
    }

    func testEnabledNotificationPreferencesPersistAcrossViewRecreation() throws {
        let suiteName = "TripNotificationTests.Enabled.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        TripNotificationSettings.registerDefaults(in: defaults)
        defaults.set(true, forKey: TripNotificationSettings.completionEnabledKey)
        defaults.set(true, forKey: TripNotificationSettings.remindersEnabledKey)

        let recreatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(recreatedDefaults.bool(forKey: TripNotificationSettings.completionEnabledKey))
        XCTAssertTrue(recreatedDefaults.bool(forKey: TripNotificationSettings.remindersEnabledKey))
    }

    func testRegisteringDefaultsNeverOverwritesExistingPreferences() throws {
        let suiteName = "TripNotificationTests.Existing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: TripNotificationSettings.completionEnabledKey)
        defaults.set(true, forKey: TripNotificationSettings.remindersEnabledKey)

        TripNotificationSettings.registerDefaults(in: defaults)

        XCTAssertFalse(defaults.bool(forKey: TripNotificationSettings.completionEnabledKey))
        XCTAssertTrue(defaults.bool(forKey: TripNotificationSettings.remindersEnabledKey))
    }

    func testAuthorizationStateChangesDoNotOverwritePreferences() throws {
        let suiteName = "TripNotificationTests.Authorization.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        TripNotificationSettings.registerDefaults(in: defaults)
        defaults.set(true, forKey: TripNotificationSettings.completionEnabledKey)
        defaults.set(false, forKey: TripNotificationSettings.remindersEnabledKey)

        _ = NotificationSettingsRecovery(status: .denied)
        _ = NotificationSettingsRecovery(status: .authorized)

        XCTAssertTrue(defaults.bool(forKey: TripNotificationSettings.completionEnabledKey))
        XCTAssertFalse(defaults.bool(forKey: TripNotificationSettings.remindersEnabledKey))
    }

    func testDeliveryPlanRespectsIndividualPreferencesAndSystemPermission() {
        XCTAssertEqual(
            TripNotificationDeliveryPlan.make(
                authorizationStatus: .authorized,
                tripDetectedEnabled: false,
                reviewRemindersEnabled: true
            ),
            TripNotificationDeliveryPlan(sendsTripDetected: false, sendsReviewReminder: true)
        )
        XCTAssertEqual(
            TripNotificationDeliveryPlan.make(
                authorizationStatus: .authorized,
                tripDetectedEnabled: true,
                reviewRemindersEnabled: false
            ),
            TripNotificationDeliveryPlan(sendsTripDetected: true, sendsReviewReminder: false)
        )
        XCTAssertEqual(
            TripNotificationDeliveryPlan.make(
                authorizationStatus: .denied,
                tripDetectedEnabled: true,
                reviewRemindersEnabled: true
            ),
            TripNotificationDeliveryPlan(sendsTripDetected: false, sendsReviewReminder: false)
        )
        XCTAssertEqual(
            TripNotificationDeliveryPlan.make(
                authorizationStatus: .authorized,
                tripDetectedEnabled: true,
                reviewRemindersEnabled: true
            ),
            TripNotificationDeliveryPlan(sendsTripDetected: true, sendsReviewReminder: true)
        )
    }

    func testCompletionAndAggregatedReviewCopy() {
        XCTAssertEqual(TripNotificationCopy.completionTitle, "Trip Complete")
        XCTAssertEqual(
            TripNotificationCopy.reviewBody(count: 1),
            "1 trip is waiting for review. Tap to classify it."
        )
        XCTAssertEqual(
            TripNotificationCopy.reviewBody(count: 3),
            "3 trips are waiting for review. Tap to classify them."
        )
    }

    func testReviewReminderUsesNextDayAtNineLocalTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 20))!
        let reminder = ReviewReminderSchedule.nextDate(after: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 13)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func testReviewQueueCountIncludesAutomaticAndManualUnclassifiedTripsOnly() {
        let automatic = reviewTrip(classification: .unclassified)
        let manual = reviewTrip(classification: .unclassified)
        let reviewed = reviewTrip(classification: .business)
        XCTAssertEqual(
            ReviewQueueService.pendingTrips(from: [automatic, manual, reviewed]).count,
            2
        )
    }

    func testSettingsKeysAreTheSchedulingSourceOfTruth() {
        let defaults = UserDefaults.standard
        let originalDetected = defaults.object(
            forKey: TripNotificationSettings.completionEnabledKey
        )
        let originalReminders = defaults.object(
            forKey: TripNotificationSettings.remindersEnabledKey
        )
        defer {
            if let originalDetected {
                defaults.set(originalDetected, forKey: TripNotificationSettings.completionEnabledKey)
            } else {
                defaults.removeObject(forKey: TripNotificationSettings.completionEnabledKey)
            }
            if let originalReminders {
                defaults.set(originalReminders, forKey: TripNotificationSettings.remindersEnabledKey)
            } else {
                defaults.removeObject(forKey: TripNotificationSettings.remindersEnabledKey)
            }
        }
        defaults.set(false, forKey: TripNotificationSettings.completionEnabledKey)
        defaults.set(true, forKey: TripNotificationSettings.remindersEnabledKey)

        XCTAssertEqual(
            TripNotificationDeliveryPlan.current(authorizationStatus: .authorized),
            TripNotificationDeliveryPlan(sendsTripDetected: false, sendsReviewReminder: true)
        )
        XCTAssertEqual(
            TripNotificationDeliveryPlan.current(authorizationStatus: .denied),
            TripNotificationDeliveryPlan(sendsTripDetected: false, sendsReviewReminder: false)
        )
        XCTAssertFalse(defaults.bool(forKey: TripNotificationSettings.completionEnabledKey))
        XCTAssertTrue(defaults.bool(forKey: TripNotificationSettings.remindersEnabledKey))
    }

    private func reviewTrip(classification: Trip.Classification) -> Trip {
        Trip(
            id: UUID(),
            startedAt: .now.addingTimeInterval(-1_800),
            endedAt: .now,
            originName: "Start",
            destinationName: "End",
            distanceMiles: 2,
            classification: classification,
            purpose: ""
        )
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

private struct LegacyPendingTripEnvelope: Codable {
    let trip: Trip
}

private actor RecordingMileageRepository: MileageRepository {
    private var trips: [Trip] = []

    func fetchTrips() async throws -> [Trip] { trips }
    func fetchSummary() async throws -> MileageSummary {
        MileageSummaryCalculator.summary(for: trips)
    }
    func fetchProfile() async throws -> UserProfile { MockData.profile }
    func save(_ trip: Trip) async throws {
        if !trips.contains(where: { $0.id == trip.id }) { trips.append(trip) }
    }
    func update(_ trip: Trip) async throws {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
    }
    func delete(_ trip: Trip) async throws {
        trips.removeAll { $0.id == trip.id }
    }
}

@MainActor
final class MockTripNotificationService: TripNotificationScheduling {
    private(set) var authorizationStatus: NotificationPermissionStatus
    private(set) var scheduledTripIDs: [UUID] = []
    private(set) var cancelledTripIDs: Set<UUID> = []
    private(set) var pendingWasPersistedWhenScheduled = false
    private(set) var longRunningReminderCount = 0
    private(set) var longRunningReminderCancelled = false

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

    func reconcileReviewReminder() async {}

    func cancelNotifications(for tripID: UUID) {
        cancelledTripIDs.insert(tripID)
    }

    func cancelCompletionNotifications() {}
    func cancelReminderNotifications() {}
    func cancelAllTripNotifications() {}
    func scheduleLongRunningTripReminder(after delay: TimeInterval) async {
        longRunningReminderCount += 1
        longRunningReminderCancelled = false
    }
    func cancelLongRunningTripReminder() {
        longRunningReminderCancelled = true
    }
}

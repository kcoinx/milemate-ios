import Foundation
import XCTest
@testable import MileMate

@MainActor
final class ClassificationVehicleTests: XCTestCase {
    func testReviewQueueOrdersOldestUnclassifiedTripFirst() {
        let newest = trip(startedAt: .now, classification: .unclassified)
        let oldest = trip(
            startedAt: .now.addingTimeInterval(-3_600),
            classification: .unclassified
        )
        let classified = trip(
            startedAt: .now.addingTimeInterval(-7_200),
            classification: .business
        )

        let queue = ReviewQueueService.pendingTrips(from: [newest, classified, oldest])

        XCTAssertEqual(queue.map(\.id), [oldest.id, newest.id])
    }

    func testSuggestionRequiresThreeConsistentRouteConfirmations() {
        let places = routePlaces()
        let target = routeTrip(places: places, classification: .unclassified)
        let two = (0..<2).map { _ in routeTrip(places: places, classification: .business) }
        let three = two + [routeTrip(places: places, classification: .business)]

        XCTAssertNil(
            SmartClassificationService.suggestion(for: target, history: two, places: places)
        )
        XCTAssertEqual(
            SmartClassificationService.suggestion(
                for: target,
                history: three,
                places: places
            )?.classification,
            .business
        )
    }

    func testApprovedRuleMatchesOnlyItsConfirmedRoute() {
        let places = routePlaces()
        let trip = routeTrip(places: places, classification: .unclassified)
        let rule = ClassificationRule(
            startPlaceID: places[0].id,
            startLabel: places[0].label,
            endPlaceID: places[1].id,
            endLabel: places[1].label,
            classification: .business
        )

        XCTAssertEqual(
            SmartClassificationService.matchingRule(
                for: trip,
                places: places,
                rules: [rule]
            )?.id,
            rule.id
        )
    }

    func testDisabledRuleDoesNotAutomaticallyMatch() {
        let places = routePlaces()
        let trip = routeTrip(places: places, classification: .unclassified)
        let rule = ClassificationRule(
            startPlaceID: places[0].id,
            startLabel: places[0].label,
            endPlaceID: places[1].id,
            endLabel: places[1].label,
            classification: .business,
            isEnabled: false
        )

        XCTAssertNil(
            SmartClassificationService.matchingRule(
                for: trip,
                places: places,
                rules: [rule]
            )
        )
    }

    func testApprovedRuleApplicationAndUserOverrideAreExplainable() {
        let places = routePlaces()
        let original = routeTrip(places: places, classification: .unclassified)
        let rule = ClassificationRule(
            startPlaceID: places[0].id,
            startLabel: places[0].label,
            endPlaceID: places[1].id,
            endLabel: places[1].label,
            classification: .business
        )

        let automatic = SmartClassificationService.applying(rule, to: original)
        let overridden = SmartClassificationService.overriding(
            automatic,
            with: .personal
        )

        XCTAssertEqual(automatic.classificationSource, .approvedRule)
        XCTAssertEqual(automatic.appliedRuleID, rule.id)
        XCTAssertEqual(overridden.classification, .personal)
        XCTAssertEqual(overridden.classificationSource, .user)
        XCTAssertNil(overridden.appliedRuleID)
    }

    func testFrequentPlaceMatchesCoordinatesWithinRadius() {
        let place = FrequentPlace(
            label: "Work",
            latitude: 37.7749,
            longitude: -122.4194,
            radiusMeters: 150
        )
        let nearby = TripCoordinate(
            latitude: 37.7755,
            longitude: -122.4194,
            timestamp: .now
        )
        let farAway = TripCoordinate(
            latitude: 37.7849,
            longitude: -122.4194,
            timestamp: .now
        )

        XCTAssertTrue(place.contains(nearby))
        XCTAssertFalse(place.contains(farAway))
    }

    func testDefaultVehicleSelectionAndSingleDefaultPolicy() {
        let first = Vehicle(nickname: "Car")
        let second = Vehicle(nickname: "Work Van", isDefault: true)

        XCTAssertEqual(
            VehicleAssignmentService.defaultVehicle(in: [first, second])?.id,
            second.id
        )
        let normalized = VehicleAssignmentService.enforcingSingleDefault(
            first.id,
            in: [first, second]
        )
        XCTAssertEqual(normalized.filter(\.isDefault).map(\.id), [first.id])
    }

    func testNewAndExistingTripReceiveDefaultVehicleSnapshot() {
        let vehicle = Vehicle(nickname: "Camry", isDefault: true)
        let existingTrip = trip(startedAt: .now, classification: .business)

        let migrated = VehicleAssignmentService.assigningDefault(
            to: existingTrip,
            vehicles: [vehicle]
        )

        XCTAssertEqual(migrated.vehicle, vehicle.snapshot)
    }

    func testLegacyTripJSONDecodesWithoutVehicleOrRuleMetadata() throws {
        struct LegacyTrip: Encodable {
            let id = UUID()
            let startedAt = Date()
            let endedAt = Date().addingTimeInterval(600)
            let originName = "Start"
            let destinationName = "End"
            let distanceMiles = 4.2
            let classification = Trip.Classification.business
            let purpose = ""
            let notes = ""
            let startCoordinate: TripCoordinate? = nil
            let endCoordinate: TripCoordinate? = nil
            let route: [TripCoordinate] = []
            let createdAt = Date()
            let updatedAt = Date()
        }

        let data = try JSONEncoder().encode(LegacyTrip())
        let decoded = try JSONDecoder().decode(Trip.self, from: data)

        XCTAssertNil(decoded.vehicle)
        XCTAssertNil(decoded.appliedRuleID)
    }

    func testVehicleReassignmentPreservesOtherTrips() {
        let oldVehicle = Vehicle(nickname: "Old")
        let replacement = Vehicle(nickname: "New")
        var linked = trip(startedAt: .now, classification: .business)
        linked.vehicle = oldVehicle.snapshot
        let unlinked = trip(startedAt: .now, classification: .personal)

        let trips = VehicleAssignmentService.reassigning(
            trips: [linked, unlinked],
            from: oldVehicle.id,
            to: replacement
        )

        XCTAssertEqual(trips[0].vehicle, replacement.snapshot)
        XCTAssertNil(trips[1].vehicle)
    }

    func testVehicleFilteredReportTotals() {
        let car = Vehicle(nickname: "Car")
        let van = Vehicle(nickname: "Van")
        var carTrip = trip(startedAt: .now, classification: .business, miles: 12)
        carTrip.vehicle = car.snapshot
        var vanTrip = trip(startedAt: .now, classification: .business, miles: 8)
        vanTrip.vehicle = van.snapshot

        let summary = MileageSummaryCalculator.summary(
            for: [carTrip, vanTrip].filter { $0.vehicle?.id == car.id }
        )

        XCTAssertEqual(summary.businessMiles, 12, accuracy: 0.001)
    }

    func testQueueClassificationUpdatesPendingCountAndCancelsReminder() async {
        let pending = trip(startedAt: .now, classification: .unclassified)
        let repository = QueueTestRepository(trips: [pending])
        let notifications = QueueNotificationService()
        let viewModel = ReviewQueueViewModel(
            repository: repository,
            notificationService: notifications
        )
        await viewModel.load()

        await viewModel.classify(.business)

        XCTAssertEqual(viewModel.pendingCount, 0)
        XCTAssertTrue(notifications.cancelledTripIDs.contains(pending.id))
        let saved = await repository.currentTrips()
        XCTAssertEqual(saved.first?.classification, .business)
    }

    private func trip(
        startedAt: Date,
        classification: Trip.Classification,
        miles: Double = 5
    ) -> Trip {
        Trip(
            id: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            originName: "Start",
            destinationName: "End",
            distanceMiles: miles,
            classification: classification,
            purpose: ""
        )
    }

    private func routePlaces() -> [FrequentPlace] {
        [
            FrequentPlace(label: "Home", latitude: 37.7749, longitude: -122.4194),
            FrequentPlace(label: "Client Office", latitude: 37.7849, longitude: -122.4094)
        ]
    }

    private func routeTrip(
        places: [FrequentPlace],
        classification: Trip.Classification
    ) -> Trip {
        Trip(
            id: UUID(),
            startedAt: .now,
            endedAt: .now.addingTimeInterval(900),
            originName: "Private address",
            destinationName: "Private address",
            distanceMiles: 7,
            classification: classification,
            purpose: "",
            startCoordinate: TripCoordinate(
                latitude: places[0].latitude,
                longitude: places[0].longitude,
                timestamp: .now
            ),
            endCoordinate: TripCoordinate(
                latitude: places[1].latitude,
                longitude: places[1].longitude,
                timestamp: .now
            )
        )
    }
}

private actor QueueTestRepository: MileageRepository {
    private var trips: [Trip]

    init(trips: [Trip]) {
        self.trips = trips
    }

    func currentTrips() -> [Trip] { trips }
    func fetchTrips() async throws -> [Trip] { trips }
    func fetchSummary() async throws -> MileageSummary {
        MileageSummaryCalculator.summary(for: trips)
    }
    func fetchProfile() async throws -> UserProfile { MockData.profile }
    func save(_ trip: Trip) async throws { trips.append(trip) }
    func update(_ trip: Trip) async throws {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
    }
    func delete(_ trip: Trip) async throws {
        trips.removeAll { $0.id == trip.id }
    }
}

@MainActor
private final class QueueNotificationService: TripNotificationScheduling {
    var authorizationStatus = NotificationPermissionStatus.authorized
    private(set) var cancelledTripIDs: Set<UUID> = []

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async {}
    func scheduleTripCompletion(for trip: Trip) async {}
    func reconcileReviewReminder() async {}
    func cancelNotifications(for tripID: UUID) { cancelledTripIDs.insert(tripID) }
    func cancelCompletionNotifications() {}
    func cancelReminderNotifications() {}
    func cancelAllTripNotifications() {}
    func scheduleLongRunningTripReminder(after delay: TimeInterval) async {}
    func cancelLongRunningTripReminder() {}
}

import CoreLocation
import Foundation
import XCTest
@testable import MileMate

@MainActor
final class SettingsCompletionTests: XCTestCase {
    func testCurrentAndPreviousTaxYearsUseQualifyingBusinessTrips() async {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: .now)
        let previousYear = currentYear - 1
        let currentBusiness = trip(year: currentYear, miles: 10, classification: .business)
        let currentPersonal = trip(year: currentYear, miles: 40, classification: .personal)
        let previousBusiness = trip(year: previousYear, miles: 7, classification: .business)
        let datesBefore = [currentBusiness.startedAt, currentPersonal.startedAt, previousBusiness.startedAt]
        let repository = SettingsTestRepository(
            trips: [currentBusiness, currentPersonal, previousBusiness]
        )
        let viewModel = AnnualSummaryViewModel(
            repository: repository,
            initialYear: currentYear,
            vehicleID: nil
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.summary.businessMiles, 10, accuracy: 0.001)
        XCTAssertEqual(viewModel.summary.businessTrips, 1)
        XCTAssertEqual(
            viewModel.summary.estimatedDeduction,
            MileageDeductionService.deduction(
                miles: 10,
                classification: .business,
                rate: MileageSettings.mileageRate
            ),
            accuracy: 0.001
        )

        viewModel.selectedYear = previousYear
        XCTAssertEqual(viewModel.summary.businessMiles, 7, accuracy: 0.001)
        XCTAssertEqual(viewModel.summary.businessTrips, 1)
        let datesAfter = try? await repository.fetchTrips().map { trip in
            trip.startedAt
        }
        XCTAssertEqual(datesAfter, datesBefore)
    }

    func testAutomaticClassificationReportsZeroEnabledRules() async {
        let repository = SettingsTestRepository()
        let viewModel = SettingsViewModel(repository: repository)
        await viewModel.loadFrequentPlaces()
        XCTAssertEqual(viewModel.classificationRuleCount, 0)

        let first = FrequentPlace(label: "Home", latitude: 1, longitude: 1)
        let second = FrequentPlace(label: "Office", latitude: 2, longitude: 2)
        let rule = ClassificationRule(
            startPlaceID: first.id,
            startLabel: first.label,
            endPlaceID: second.id,
            endLabel: second.label,
            classification: .business
        )
        try? await repository.saveFrequentPlace(first)
        try? await repository.saveFrequentPlace(second)
        try? await repository.saveClassificationRule(rule)
        await viewModel.loadFrequentPlaces()
        XCTAssertEqual(viewModel.classificationRuleCount, 1)
    }

    func testDeletionConfirmationRequiresTwoDeliberateStages() {
        var state = DataDeletionConfirmationState.none
        state = .warning
        XCTAssertNotEqual(state, .final)
        state = .none
        XCTAssertEqual(state, .none)
        state = .warning
        state = .final
        XCTAssertEqual(state, .final)
    }

    func testCancelingDeletionPreservesStoredData() async throws {
        let saved = trip(
            year: Calendar.current.component(.year, from: .now),
            miles: 5,
            classification: .business
        )
        let repository = SettingsTestRepository(trips: [saved])
        var state = DataDeletionConfirmationState.warning
        state = .none

        let trips = try await repository.fetchTrips()
        XCTAssertEqual(state, .none)
        XCTAssertEqual(trips.map(\.id), [saved.id])
    }

    func testConfirmedDeletionRemovesOwnedDataButNotPermissions() async throws {
        let route = [
            TripCoordinate(latitude: 1, longitude: 2, timestamp: .now),
            TripCoordinate(latitude: 1.1, longitude: 2.1, timestamp: .now)
        ]
        var savedTrip = trip(
            year: Calendar.current.component(.year, from: .now),
            miles: 4,
            classification: .unclassified
        )
        savedTrip.route = route
        let place = FrequentPlace(label: "Home", latitude: 1, longitude: 2)
        let secondPlace = FrequentPlace(label: "Office", latitude: 2, longitude: 3)
        let repository = SettingsTestRepository(
            trips: [savedTrip],
            vehicles: [Vehicle(nickname: "Work Car", isDefault: true)],
            places: [place, secondPlace],
            rules: [
                ClassificationRule(
                    startPlaceID: place.id,
                    startLabel: place.label,
                    endPlaceID: secondPlace.id,
                    endLabel: secondPlace.label,
                    classification: .business
                )
            ]
        )
        let notifications = MockTripNotificationService()
        let manualLocation = MockLocationService()
        let manual = ManualTripCoordinator(
            locationService: manualLocation,
            repository: repository,
            notificationService: notifications
        )
        let automaticLocation = MockAutomaticLocationService()
        let motion = MockMotionActivityService()
        let automatic = AutomaticTripCoordinator(
            locationService: automaticLocation,
            motionService: motion,
            repository: repository,
            notificationService: notifications,
            isManualTrackingActive: { false }
        )
        let suiteName = "SettingsCompletionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AutomaticTrackingSettings.enabledKey)
        defaults.set(44.0, forKey: MileageSettings.taxRateKey)
        UserDefaults.standard.set(Data([1, 2, 3]), forKey: "manualActiveTrip")
        UserDefaults.standard.set(Data([1, 2, 3]), forKey: "automaticActiveTrip")
        UserDefaults.standard.set(Data([1, 2, 3]), forKey: "automaticPendingTrip")
        defer {
            UserDefaults.standard.removeObject(forKey: "manualActiveTrip")
            UserDefaults.standard.removeObject(forKey: "automaticActiveTrip")
            UserDefaults.standard.removeObject(forKey: "automaticPendingTrip")
        }
        let locationPermissionBefore = automaticLocation.authorizationStatus
        let motionPermissionBefore = motion.permissionStatus
        let service = LocalDataDeletionService(
            repository: repository,
            manualCoordinator: manual,
            automaticCoordinator: automatic,
            notificationService: notifications,
            defaults: defaults
        )

        try await service.deleteAllData()

        let remainingTrips = try await repository.fetchTrips()
        let remainingVehicles = try await repository.fetchVehicles()
        let remainingPlaces = try await repository.fetchFrequentPlaces()
        let remainingRules = try await repository.fetchClassificationRules()
        XCTAssertTrue(remainingTrips.isEmpty)
        XCTAssertTrue(remainingVehicles.isEmpty)
        XCTAssertTrue(remainingPlaces.isEmpty)
        XCTAssertTrue(remainingRules.isEmpty)
        XCTAssertEqual(notifications.cancelAllCount, 1)
        XCTAssertNil(UserDefaults.standard.data(forKey: "manualActiveTrip"))
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticActiveTrip"))
        XCTAssertNil(UserDefaults.standard.data(forKey: "automaticPendingTrip"))
        XCTAssertEqual(
            MileageSettings.estimatedTaxPercentage(in: defaults),
            MileageSettings.defaultTaxRate
        )
        XCTAssertEqual(automaticLocation.authorizationStatus, locationPermissionBefore)
        XCTAssertEqual(motion.permissionStatus, motionPermissionBefore)
    }

    func testVersionBuildAndFeedbackDiagnosticsAreSafe() {
        let dictionary: [String: Any] = [
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "34"
        ]
        XCTAssertEqual(AppBuildInformation.version(from: dictionary), "1.2")
        XCTAssertEqual(AppBuildInformation.build(from: dictionary), "34")
        let feedback = FeedbackContent.message(
            version: "1.2",
            build: "34",
            systemVersion: "26.0"
        )
        XCTAssertTrue(feedback.contains("MileMate Feedback"))
        XCTAssertFalse(feedback.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(feedback.localizedCaseInsensitiveContains("longitude"))
        XCTAssertFalse(feedback.localizedCaseInsensitiveContains("route"))
        XCTAssertFalse(feedback.localizedCaseInsensitiveContains("address"))
    }

    private func trip(
        year: Int,
        miles: Double,
        classification: Trip.Classification
    ) -> Trip {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: 6, day: 15, hour: 10)
        )!
        return Trip(
            id: UUID(),
            startedAt: date,
            endedAt: date.addingTimeInterval(1_800),
            originName: "Start",
            destinationName: "End",
            distanceMiles: miles,
            classification: classification,
            purpose: ""
        )
    }
}

private actor SettingsTestRepository: MileageRepository {
    private var trips: [Trip]
    private var vehicles: [Vehicle]
    private var places: [FrequentPlace]
    private var rules: [ClassificationRule]

    init(
        trips: [Trip] = [],
        vehicles: [Vehicle] = [],
        places: [FrequentPlace] = [],
        rules: [ClassificationRule] = []
    ) {
        self.trips = trips
        self.vehicles = vehicles
        self.places = places
        self.rules = rules
    }

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
    func delete(_ trip: Trip) async throws { trips.removeAll { $0.id == trip.id } }
    func fetchVehicles() async throws -> [Vehicle] { vehicles }
    func saveVehicle(_ vehicle: Vehicle) async throws { vehicles.append(vehicle) }
    func deleteVehicle(id: UUID, reassignTo vehicle: Vehicle?) async throws {
        vehicles.removeAll { $0.id == id }
    }
    func fetchFrequentPlaces() async throws -> [FrequentPlace] { places }
    func saveFrequentPlace(_ place: FrequentPlace) async throws { places.append(place) }
    func deleteFrequentPlace(id: UUID) async throws { places.removeAll { $0.id == id } }
    func fetchClassificationRules() async throws -> [ClassificationRule] { rules }
    func saveClassificationRule(_ rule: ClassificationRule) async throws { rules.append(rule) }
    func deleteClassificationRule(id: UUID) async throws { rules.removeAll { $0.id == id } }
    func deleteAllLocalData() async throws {
        trips.removeAll()
        vehicles.removeAll()
        places.removeAll()
        rules.removeAll()
    }
}

import Foundation
import SwiftData
import XCTest
@testable import MileMate

@MainActor
final class AccountSessionTests: XCTestCase {
    func testFirstLaunchRequiresWelcomeAndReturningGuestDoesNot() {
        let store = InMemoryAccountStore()
        let repository = AccountTestRepository()
        let firstLaunch = AccountSessionController(
            repository: repository,
            secureStore: store,
            authenticationService: AccountTestAuthenticationService()
        )
        XCTAssertTrue(firstLaunch.requiresWelcome)

        firstLaunch.continueAsGuest()
        XCTAssertFalse(firstLaunch.requiresWelcome)
        XCTAssertEqual(firstLaunch.remainingGuestTrips, 10)

        let returningGuest = AccountSessionController(
            repository: repository,
            secureStore: store,
            authenticationService: AccountTestAuthenticationService()
        )
        XCTAssertFalse(returningGuest.requiresWelcome)
        XCTAssertEqual(returningGuest.guest?.guestID, firstLaunch.guest?.guestID)
    }

    func testGuestCountsUniqueSavedTripsAndBlocksTripEleven() {
        let controller = makeController()
        controller.continueAsGuest()
        let trips = (0..<10).map { index in testTrip(id: UUID(), minutesAgo: index) }

        for trip in trips { controller.recordSavedTrip(trip) }
        controller.recordSavedTrip(trips[0])

        XCTAssertEqual(controller.guest?.completedTripCount, 10)
        XCTAssertEqual(controller.remainingGuestTrips, 0)
        XCTAssertFalse(controller.requestTrackingAccess())
        XCTAssertTrue(controller.presentsUpgrade)
    }

    func testGuestTrialPersistsAcrossControllerRecreation() {
        let store = InMemoryAccountStore()
        let repository = AccountTestRepository()
        let first = makeController(repository: repository, store: store)
        first.continueAsGuest()
        first.recordSavedTrip(testTrip())

        let restored = makeController(repository: repository, store: store)

        XCTAssertEqual(restored.guest?.completedTripCount, 1)
        XCTAssertEqual(restored.remainingGuestTrips, 9)
    }

    func testRepositoryReconciliationAddsSavedTripsWithoutDuplicates() async {
        let trips = [testTrip(), testTrip(), testTrip()]
        let repository = AccountTestRepository(trips: trips)
        let controller = makeController(repository: repository)
        controller.continueAsGuest()

        await controller.reconcileGuestTrial()
        controller.recordSavedTrip(trips[0])

        XCTAssertEqual(controller.guest?.completedTripCount, 3)
        XCTAssertEqual(controller.remainingGuestTrips, 7)
    }

    func testGuestUpgradePreservesTripsAndRestoresAuthenticatedSession() async throws {
        let trip = testTrip()
        let repository = AccountTestRepository(trips: [trip])
        let store = InMemoryAccountStore()
        let controller = makeController(repository: repository, store: store)
        controller.continueAsGuest()
        await controller.authenticateWithApple(token: "verified-token", rawNonce: "nonce", displayName: "Taylor")

        XCTAssertTrue(controller.isAuthenticated)
        let upgradedTrips = try await repository.fetchTrips()
        XCTAssertEqual(upgradedTrips.map { $0.id }, [trip.id])

        let restored = makeController(repository: repository, store: store)
        XCTAssertTrue(restored.isAuthenticated)
        XCTAssertEqual(restored.account?.provider, .apple)
    }

    func testGoogleSignInStoresProviderAndRestoresSession() async {
        let store = InMemoryAccountStore()
        let repository = AccountTestRepository()
        let controller = makeController(repository: repository, store: store)
        controller.continueAsGuest()

        await controller.authenticateWithGoogle()

        XCTAssertEqual(controller.account?.provider, .google)
        let restored = makeController(repository: repository, store: store)
        XCTAssertEqual(restored.account?.provider, .google)
    }

    func testLogOutReturnsToWelcomeAndPreservesGuestProgressAcrossRelaunch() async {
        let store = InMemoryAccountStore()
        let repository = AccountTestRepository()
        let controller = makeController(repository: repository, store: store)
        controller.continueAsGuest()
        controller.recordSavedTrip(testTrip())
        await controller.authenticateWithApple(token: "verified-token", rawNonce: "nonce", displayName: nil)

        controller.logOut()

        XCTAssertTrue(controller.requiresWelcome)
        let relaunched = makeController(repository: repository, store: store)
        XCTAssertTrue(relaunched.requiresWelcome)
        relaunched.continueAsGuest()
        XCTAssertEqual(relaunched.guest?.completedTripCount, 1)
    }

    func testAccountDeletionReturnsToWelcomeAndPreservesLocalTripHistory() async throws {
        let trip = testTrip()
        let repository = AccountTestRepository(trips: [trip])
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        await controller.authenticateWithApple(token: "verified-token", rawNonce: "nonce", displayName: nil)

        await controller.deleteAccount()

        XCTAssertFalse(controller.isAuthenticated)
        XCTAssertTrue(controller.requiresWelcome)
        let remainingTrips = try await repository.fetchTrips()
        XCTAssertEqual(remainingTrips.map { $0.id }, [trip.id])
    }

    func testManualAndAutomaticTrackingDoNotStartTripEleven() {
        let repository = AccountTestRepository()
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        for _ in 0..<10 { controller.recordSavedTrip(testTrip()) }

        let manualLocation = MockLocationService()
        manualLocation.authorizationStatus = .authorizedAlways
        let manual = ManualTripCoordinator(
            locationService: manualLocation,
            repository: repository,
            canStartNewTrip: { controller.requestTrackingAccess() }
        )
        manual.startTrip()
        XCTAssertEqual(manual.state, .ready)
        XCTAssertFalse(manualLocation.isUpdating)

        let enabledKey = AutomaticTrackingSettings.enabledKey
        let originalEnabled = UserDefaults.standard.object(forKey: enabledKey)
        defer {
            if let originalEnabled {
                UserDefaults.standard.set(originalEnabled, forKey: enabledKey)
            } else {
                UserDefaults.standard.removeObject(forKey: enabledKey)
            }
        }
        UserDefaults.standard.set(true, forKey: enabledKey)
        let automaticLocation = MockAutomaticLocationService()
        let automatic = AutomaticTripCoordinator(
            locationService: automaticLocation,
            motionService: MockMotionActivityService(),
            repository: repository,
            notificationService: AccountTestNotificationService(),
            canStartNewTrip: { controller.requestTrackingAccess() },
            isManualTrackingActive: { false }
        )
        automatic.startIfEnabled()
        XCTAssertEqual(automatic.state, .idle)
        XCTAssertFalse(automaticLocation.isPreciseTracking)
        XCTAssertFalse(automaticLocation.isLowPowerMonitoring)
    }

    func testDifferentAuthenticatedAccountsSeeOnlyTheirOwnTrips() async throws {
        let (repository, scopeProvider, _) = try makeSwiftDataRepository()
        let firstTrip = testTrip()
        let secondTrip = testTrip()

        scopeProvider.setCurrent(.authenticated(userID: "google-user-one"))
        try await repository.save(firstTrip)

        scopeProvider.setCurrent(.authenticated(userID: "google-user-two"))
        let secondAccountBeforeSave = try await repository.fetchTrips()
        XCTAssertTrue(secondAccountBeforeSave.isEmpty)
        try await repository.save(secondTrip)
        let secondAccountTrips = try await repository.fetchTrips()
        XCTAssertEqual(secondAccountTrips.map { $0.id }, [secondTrip.id])

        scopeProvider.setCurrent(.authenticated(userID: "google-user-one"))
        let firstAccountTrips = try await repository.fetchTrips()
        XCTAssertEqual(firstAccountTrips.map { $0.id }, [firstTrip.id])
    }

    func testGuestSessionsAreIsolatedFromAccountsAndOtherGuests() async throws {
        let (repository, scopeProvider, _) = try makeSwiftDataRepository()
        let firstGuestID = UUID()
        let secondGuestID = UUID()
        let guestTrip = testTrip()

        scopeProvider.setCurrent(.guest(id: firstGuestID))
        try await repository.save(guestTrip)

        scopeProvider.setCurrent(.guest(id: secondGuestID))
        let secondGuestTrips = try await repository.fetchTrips()
        XCTAssertTrue(secondGuestTrips.isEmpty)

        scopeProvider.setCurrent(.authenticated(userID: "signed-in-user"))
        let accountTrips = try await repository.fetchTrips()
        XCTAssertTrue(accountTrips.isEmpty)

        scopeProvider.setCurrent(.guest(id: firstGuestID))
        let firstGuestTrips = try await repository.fetchTrips()
        XCTAssertEqual(firstGuestTrips.map { $0.id }, [guestTrip.id])
    }

    func testGuestUpgradeMigratesOnlyThatGuestData() async throws {
        let (repository, scopeProvider, _) = try makeSwiftDataRepository()
        let upgradingGuest = LocalDataScope.guest(id: UUID())
        let otherGuest = LocalDataScope.guest(id: UUID())
        let account = LocalDataScope.authenticated(userID: "upgraded-user")
        let upgradingTrip = testTrip()
        let otherTrip = testTrip()

        scopeProvider.setCurrent(upgradingGuest)
        try await repository.save(upgradingTrip)
        scopeProvider.setCurrent(otherGuest)
        try await repository.save(otherTrip)

        try await repository.migrateLocalData(from: upgradingGuest, to: account)
        scopeProvider.setCurrent(account)
        let accountTrips = try await repository.fetchTrips()
        XCTAssertEqual(accountTrips.map { $0.id }, [upgradingTrip.id])

        scopeProvider.setCurrent(otherGuest)
        let otherGuestTrips = try await repository.fetchTrips()
        XCTAssertEqual(otherGuestTrips.map { $0.id }, [otherTrip.id])
    }

    func testLegacyTripsWithoutKnownOwnerRemainUnassigned() async throws {
        let (repository, scopeProvider, container) = try makeSwiftDataRepository()
        let legacyTrip = testTrip()
        container.mainContext.insert(StoredTrip(trip: legacyTrip))
        try container.mainContext.save()

        scopeProvider.setCurrent(.authenticated(userID: "new-user"))
        let accountTrips = try await repository.fetchTrips()
        XCTAssertTrue(accountTrips.isEmpty)

        scopeProvider.setCurrent(.guest(id: UUID()))
        let guestTrips = try await repository.fetchTrips()
        XCTAssertTrue(guestTrips.isEmpty)
    }

    private func makeSwiftDataRepository() throws -> (
        SwiftDataMileageRepository,
        LocalDataScopeProvider,
        ModelContainer
    ) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StoredTrip.self,
            StoredVehicle.self,
            StoredFrequentPlace.self,
            StoredClassificationRule.self,
            configurations: configuration
        )
        let repository = SwiftDataMileageRepository(modelContainer: container)
        return (repository, repository.scopeProvider, container)
    }

    private func makeController(
        repository: AccountTestRepository = AccountTestRepository(),
        store: InMemoryAccountStore = InMemoryAccountStore()
    ) -> AccountSessionController {
        AccountSessionController(
            repository: repository,
            secureStore: store,
            authenticationService: AccountTestAuthenticationService()
        )
    }

    private func testTrip(id: UUID = UUID(), minutesAgo: Int = 0) -> Trip {
        let end = Date.now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
        return Trip(
            id: id,
            startedAt: end.addingTimeInterval(-600),
            endedAt: end,
            originName: "Start",
            destinationName: "End",
            distanceMiles: 4,
            classification: .business,
            purpose: "Client Meeting"
        )
    }
}

private struct AccountTestAuthenticationService: AuthenticationServicing {
    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        displayName: String?
    ) async throws -> AuthenticatedAccount {
        AuthenticatedAccount(
            userID: "test-user",
            provider: .apple,
            displayName: displayName,
            email: "driver@example.com",
            idToken: identityToken,
            refreshToken: "refresh-token",
            tokenExpiration: .now.addingTimeInterval(3_600),
            migratedGuestID: nil
        )
    }

    @MainActor
    func signInWithGoogle() async throws -> AuthenticatedAccount {
        AuthenticatedAccount(
            userID: "google-user",
            provider: .google,
            displayName: "Google Driver",
            email: "driver@example.com",
            idToken: "id-token",
            refreshToken: "refresh-token",
            tokenExpiration: .now.addingTimeInterval(3_600),
            migratedGuestID: nil
        )
    }

    func deleteAccount(_ account: AuthenticatedAccount) async throws {}
}

private actor AccountTestRepository: MileageRepository {
    private var trips: [Trip]

    init(trips: [Trip] = []) { self.trips = trips }
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
    func delete(_ trip: Trip) async throws { trips.removeAll { $0.id == trip.id } }
}

@MainActor
private final class AccountTestNotificationService: TripNotificationScheduling {
    var authorizationStatus: NotificationPermissionStatus = .authorized
    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async {}
    func scheduleTripCompletion(for trip: Trip) async {}
    func reconcileReviewReminder() async {}
    func cancelNotifications(for tripID: UUID) {}
    func cancelCompletionNotifications() {}
    func cancelReminderNotifications() {}
    func cancelAllTripNotifications() {}
    func scheduleLongRunningTripReminder(after delay: TimeInterval) async {}
    func cancelLongRunningTripReminder() {}
}

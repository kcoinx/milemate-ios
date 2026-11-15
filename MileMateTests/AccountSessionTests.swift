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

    func testScheduledAndExplicitReconciliationAreCoalescedAndFullyAwaited() async {
        let repository = AccountTestRepository(trips: [testTrip()])
        let controller = makeController(repository: repository)
        controller.continueAsGuest()

        XCTAssertTrue(controller.isReconcilingGuestTrial)
        await controller.reconcileGuestTrial()

        let fetchCallCount = await repository.fetchTripsCallCount()
        XCTAssertFalse(controller.isReconcilingGuestTrial)
        XCTAssertEqual(fetchCallCount, 1)
        XCTAssertEqual(controller.remainingGuestTrips, 9)
    }

    func testUnreviewedAutomaticTripsDoNotConsumeGuestTrial() async {
        let unreviewedTrips = (0..<10).map { index in
            testTrip(
                id: UUID(),
                minutesAgo: index,
                classification: .unclassified
            )
        }
        let repository = AccountTestRepository(trips: unreviewedTrips)
        let controller = makeController(repository: repository)
        controller.continueAsGuest()

        for trip in unreviewedTrips {
            controller.recordSavedTrip(trip)
        }
        await controller.reconcileGuestTrial()

        XCTAssertEqual(controller.guest?.completedTripCount, 0)
        XCTAssertEqual(controller.remainingGuestTrips, 10)
        XCTAssertFalse(controller.requiresGuestUpgrade)
        XCTAssertTrue(controller.requestTrackingAccess())
    }

    func testReviewQueueClassificationImmediatelyConsumesOneFreeTrip() async {
        let pending = testTrip(classification: .unclassified)
        let repository = AccountTestRepository(trips: [pending])
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        let viewModel = ReviewQueueViewModel(
            repository: repository,
            notificationService: AccountTestNotificationService(),
            tripDidSave: { controller.recordSavedTrip($0) }
        )
        await viewModel.load()

        await viewModel.classify(.business)

        XCTAssertEqual(controller.remainingGuestTrips, 9)
        XCTAssertEqual(controller.guest?.completedTripCount, 1)
    }

    func testRepeatedClassificationEditsCountTripOnlyOnce() async {
        let pending = testTrip(classification: .unclassified)
        let repository = AccountTestRepository(trips: [pending])
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        let viewModel = TripsViewModel(
            repository: repository,
            tripDidSave: { controller.recordSavedTrip($0) }
        )
        await viewModel.load()

        await viewModel.classify(pending, as: .business)
        let businessTrip = viewModel.trips[0]
        await viewModel.classify(businessTrip, as: .personal)
        let personalTrip = viewModel.trips[0]
        await viewModel.classify(personalTrip, as: .unclassified)
        let unclassifiedTrip = viewModel.trips[0]
        await viewModel.classify(unclassifiedTrip, as: .business)

        XCTAssertEqual(controller.guest?.completedTripCount, 1)
        XCTAssertEqual(controller.remainingGuestTrips, 9)
    }

    func testFailedClassificationSaveDoesNotConsumeFreeTrip() async throws {
        let pending = testTrip(classification: .unclassified)
        let repository = AccountTestRepository(trips: [pending], updateShouldFail: true)
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        let viewModel = ReviewQueueViewModel(
            repository: repository,
            notificationService: AccountTestNotificationService(),
            tripDidSave: { controller.recordSavedTrip($0) }
        )
        await viewModel.load()

        await viewModel.classify(.business)

        XCTAssertEqual(controller.guest?.completedTripCount, 0)
        XCTAssertEqual(controller.remainingGuestTrips, 10)
        let persistedTrips = try await repository.fetchTrips()
        XCTAssertEqual(persistedTrips.first?.classification, .unclassified)
    }

    func testReviewingTenthTripImmediatelyBlocksTripEleven() async {
        let pending = testTrip(classification: .unclassified)
        let repository = AccountTestRepository(trips: [pending])
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        for _ in 0..<9 { controller.recordSavedTrip(testTrip()) }
        let viewModel = ReviewQueueViewModel(
            repository: repository,
            notificationService: AccountTestNotificationService(),
            tripDidSave: { controller.recordSavedTrip($0) }
        )
        await viewModel.load()

        await viewModel.classify(.personal)

        XCTAssertEqual(controller.remainingGuestTrips, 0)
        XCTAssertFalse(controller.requestTrackingAccess())
        XCTAssertTrue(controller.presentsUpgrade)
    }

    func testReconciliationRepairsPreviouslyCountedUnreviewedTrips() async {
        let store = InMemoryAccountStore()
        let tripIDs = (0..<10).map { _ in UUID() }
        let repository = AccountTestRepository(
            trips: tripIDs.map { id in
                testTrip(id: id, classification: .unclassified)
            }
        )
        let controller = makeController(repository: repository, store: store)
        controller.continueAsGuest()

        for id in tripIDs {
            controller.recordSavedTrip(testTrip(id: id))
        }
        XCTAssertTrue(controller.requiresGuestUpgrade)

        await controller.reconcileGuestTrial()

        XCTAssertEqual(controller.guest?.completedTripCount, 0)
        XCTAssertFalse(controller.requiresGuestUpgrade)
    }

    func testReconciliationDoesNotAutomaticallyPresentPaywall() async {
        let trips = (0..<10).map { index in
            testTrip(id: UUID(), minutesAgo: index)
        }
        let controller = makeController(repository: AccountTestRepository(trips: trips))
        controller.continueAsGuest()

        await controller.reconcileGuestTrial()

        XCTAssertTrue(controller.requiresGuestUpgrade)
        XCTAssertFalse(controller.presentsUpgrade)
        XCTAssertFalse(controller.requestTrackingAccess())
        XCTAssertTrue(controller.presentsUpgrade)
    }

    func testDismissedPaywallStaysDismissedDuringReconciliation() async {
        let trips = (0..<10).map { index in
            testTrip(id: UUID(), minutesAgo: index)
        }
        let controller = makeController(repository: AccountTestRepository(trips: trips))
        controller.continueAsGuest()
        await controller.reconcileGuestTrial()
        XCTAssertFalse(controller.requestTrackingAccess())
        XCTAssertTrue(controller.presentsUpgrade)

        controller.presentsUpgrade = false
        await controller.reconcileGuestTrial()

        XCTAssertFalse(controller.presentsUpgrade)
        XCTAssertTrue(controller.requiresGuestUpgrade)
        XCTAssertEqual(controller.remainingGuestTrips, 0)
    }

    func testSigningInDoesNotResetExhaustedTrial() async {
        let trips = (0..<10).map { _ in testTrip() }
        let controller = makeController(
            repository: AccountTestRepository(trips: trips)
        )
        controller.continueAsGuest()
        for trip in trips {
            controller.recordSavedTrip(trip)
        }

        XCTAssertTrue(controller.requiresGuestUpgrade)
        XCTAssertFalse(controller.requiresWelcome)
        XCTAssertFalse(controller.requestTrackingAccess())
        XCTAssertTrue(controller.requiresGuestUpgrade)

        await controller.authenticateWithGoogle()

        await controller.reconcileGuestTrial()

        XCTAssertTrue(controller.requiresGuestUpgrade)
        XCTAssertFalse(controller.requiresWelcome)
        XCTAssertTrue(controller.isAuthenticated)
        XCTAssertEqual(controller.remainingGuestTrips, 0)
        XCTAssertFalse(controller.presentsUpgrade)
        XCTAssertFalse(controller.requestTrackingAccess())
    }

    func testTrialAllowanceSurvivesLogoutAndGuestReturn() async {
        let store = InMemoryAccountStore()
        let trips = (0..<4).map { _ in testTrip() }
        let controller = makeController(
            repository: AccountTestRepository(trips: trips),
            store: store
        )
        controller.continueAsGuest()
        for trip in trips { controller.recordSavedTrip(trip) }
        await controller.authenticateWithGoogle()

        controller.logOut()
        controller.continueAsGuest()

        XCTAssertEqual(controller.remainingGuestTrips, 6)
    }

    func testVerifiedProEntitlementBypassesExhaustedTrial() {
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(proEntitlement: entitlement)
        controller.continueAsGuest()
        for _ in 0..<10 { controller.recordSavedTrip(testTrip()) }

        XCTAssertEqual(controller.remainingGuestTrips, 0)
        XCTAssertFalse(controller.requiresGuestUpgrade)
        XCTAssertTrue(controller.requestTrackingAccess())
    }

    func testSignedInUserReceivesSameTenTripAllowance() async {
        let controller = makeController()
        await controller.authenticateWithGoogle()

        for _ in 0..<10 { controller.recordSavedTrip(testTrip()) }

        XCTAssertTrue(controller.isAuthenticated)
        XCTAssertEqual(controller.remainingGuestTrips, 0)
        XCTAssertFalse(controller.requestTrackingAccess())
    }

    func testExpiredProEntitlementRestoresFreeTripGateWithoutDeletingProgress() async {
        let trips = (0..<10).map { _ in testTrip() }
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(
            repository: AccountTestRepository(trips: trips),
            proEntitlement: entitlement
        )
        controller.continueAsGuest()
        for trip in trips { controller.recordSavedTrip(trip) }
        XCTAssertTrue(controller.requestTrackingAccess())

        entitlement.hasProAccess = false

        XCTAssertEqual(controller.remainingGuestTrips, 0)
        XCTAssertFalse(controller.requestTrackingAccess())
        await waitForGuestReconciliation(controller)
        XCTAssertTrue(controller.presentsUpgrade)
    }

    func testTrackingRequestDuringReconciliationPresentsUpgradeOnceWhenTrialIsExhausted() async {
        let trips = (0..<10).map { _ in testTrip() }
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(
            repository: AccountTestRepository(trips: trips),
            proEntitlement: entitlement
        )
        controller.continueAsGuest()
        for trip in trips { controller.recordSavedTrip(trip) }
        entitlement.hasProAccess = false

        XCTAssertTrue(controller.isReconcilingGuestTrial)
        XCTAssertFalse(controller.requestTrackingAccess())
        XCTAssertFalse(controller.presentsUpgrade)

        await waitForGuestReconciliation(controller)

        XCTAssertTrue(controller.presentsUpgrade)
        controller.presentsUpgrade = false
        await controller.reconcileGuestTrial()
        XCTAssertFalse(controller.presentsUpgrade)
    }

    func testDismissalClearsARequestStillPendingDuringReconciliation() async {
        let trips = (0..<10).map { _ in testTrip() }
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(
            repository: AccountTestRepository(trips: trips),
            proEntitlement: entitlement
        )
        controller.continueAsGuest()
        for trip in trips { controller.recordSavedTrip(trip) }
        entitlement.hasProAccess = false

        XCTAssertFalse(controller.requestTrackingAccess())
        controller.presentsUpgrade = true
        controller.presentsUpgrade = false
        await controller.reconcileGuestTrial()

        XCTAssertFalse(controller.presentsUpgrade)
    }

    func testTrackingRequestDuringReconciliationDoesNotPresentUpgradeWhenTripsAreRestored() async {
        let tripIDs = (0..<10).map { _ in UUID() }
        let repository = AccountTestRepository(
            trips: tripIDs.map { id in
                testTrip(id: id, classification: .unclassified)
            }
        )
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(repository: repository, proEntitlement: entitlement)
        controller.continueAsGuest()
        for id in tripIDs {
            controller.recordSavedTrip(testTrip(id: id))
        }
        entitlement.hasProAccess = false

        XCTAssertFalse(controller.requestTrackingAccess())
        await waitForGuestReconciliation(controller)

        XCTAssertEqual(controller.remainingGuestTrips, 10)
        XCTAssertFalse(controller.presentsUpgrade)
        XCTAssertTrue(controller.requestTrackingAccess())
    }

    func testActiveProCanTrackDuringReconciliationWithoutPresentingUpgrade() async {
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(proEntitlement: entitlement)
        controller.continueAsGuest()

        XCTAssertTrue(controller.requestTrackingAccess())
        XCTAssertFalse(controller.presentsUpgrade)
        await waitForGuestReconciliation(controller)

        XCTAssertFalse(controller.presentsUpgrade)
        XCTAssertTrue(controller.requestTrackingAccess())
    }

    func testAccountSessionChangeClearsPendingTrackingRequest() async {
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(proEntitlement: entitlement)
        controller.continueAsGuest()
        for _ in 0..<10 { controller.recordSavedTrip(testTrip()) }
        entitlement.hasProAccess = false

        XCTAssertFalse(controller.requestTrackingAccess())
        controller.logOut()
        await Task.yield()

        XCTAssertTrue(controller.requiresWelcome)
        XCTAssertFalse(controller.presentsUpgrade)

        controller.continueAsGuest()
        await waitForGuestReconciliation(controller)
        XCTAssertFalse(controller.presentsUpgrade)
    }

    func testAuthenticationChangeClearsPendingTrackingRequest() async {
        let trips = (0..<10).map { _ in testTrip() }
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(
            repository: AccountTestRepository(trips: trips),
            proEntitlement: entitlement
        )
        controller.continueAsGuest()
        for trip in trips { controller.recordSavedTrip(trip) }
        entitlement.hasProAccess = false

        XCTAssertFalse(controller.requestTrackingAccess())
        await controller.authenticateWithGoogle()
        await controller.reconcileGuestTrial()

        XCTAssertTrue(controller.isAuthenticated)
        XCTAssertFalse(controller.presentsUpgrade)
        XCTAssertEqual(controller.remainingGuestTrips, 0)
    }

    func testReconciliationFailureClearsPendingTrackingRequest() async {
        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let controller = makeController(
            repository: AccountTestRepository(fetchShouldFail: true),
            proEntitlement: entitlement
        )
        controller.continueAsGuest()
        for _ in 0..<10 { controller.recordSavedTrip(testTrip()) }
        entitlement.hasProAccess = false

        XCTAssertFalse(controller.requestTrackingAccess())
        await waitForGuestReconciliation(controller)

        XCTAssertFalse(controller.presentsUpgrade)
        await controller.reconcileGuestTrial()
        XCTAssertFalse(controller.presentsUpgrade)
    }

    func testMissingStoreKitProductConfigurationRemainsSafelyFree() async {
        let purchaseManager = PurchaseManager(configuration: nil)

        await purchaseManager.prepare()

        XCTAssertTrue(purchaseManager.isEntitlementReady)
        XCTAssertFalse(purchaseManager.hasProAccess)
        XCTAssertNil(purchaseManager.monthlyProduct)
        XCTAssertNil(purchaseManager.lifetimeProduct)
        XCTAssertNotNil(purchaseManager.errorMessage)
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

    func testSessionTransitionGuardBlocksLogoutAndSignIn() async {
        let controller = makeController()
        controller.continueAsGuest()
        let guestID = controller.guest?.guestID
        controller.configureSessionTransitionGuard { false }

        controller.logOut()

        XCTAssertFalse(controller.requiresWelcome)
        XCTAssertEqual(controller.guest?.guestID, guestID)
        XCTAssertNotNil(controller.authenticationError)

        await controller.authenticateWithGoogle()

        XCTAssertFalse(controller.isAuthenticated)
        XCTAssertEqual(controller.guest?.guestID, guestID)
        XCTAssertNotNil(controller.authenticationError)
    }

    func testSessionTransitionGuardBlocksAccountDeletion() async {
        let repository = AccountTestRepository(trips: [testTrip()])
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        await controller.authenticateWithGoogle()
        controller.configureSessionTransitionGuard { false }

        await controller.deleteAccount()

        let remainingTrips = try? await repository.fetchTrips()
        XCTAssertTrue(controller.isAuthenticated)
        XCTAssertNotNil(controller.authenticationError)
        XCTAssertEqual(remainingTrips?.count, 1)
    }

    func testAccountDeletionReturnsToWelcomeAndDeletesOwnedLocalTripHistory() async throws {
        let trip = testTrip()
        let repository = AccountTestRepository(trips: [trip])
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        await controller.authenticateWithApple(token: "verified-token", rawNonce: "nonce", displayName: nil)

        await controller.deleteAccount()

        XCTAssertFalse(controller.isAuthenticated)
        XCTAssertTrue(controller.requiresWelcome)
        let remainingTrips = try await repository.fetchTrips()
        XCTAssertTrue(remainingTrips.isEmpty)
    }

    func testRemoteAccountDeletionFailurePreservesSessionAndLocalData() async throws {
        let trip = testTrip()
        let repository = AccountTestRepository(trips: [trip])
        let controller = AccountSessionController(
            repository: repository,
            secureStore: InMemoryAccountStore(),
            authenticationService: AccountTestAuthenticationService(deleteShouldFail: true)
        )
        controller.continueAsGuest()
        await controller.authenticateWithApple(token: "verified-token", rawNonce: "nonce", displayName: nil)

        await controller.deleteAccount()

        XCTAssertTrue(controller.isAuthenticated)
        XCTAssertNotNil(controller.authenticationError)
        let remainingTrips = try await repository.fetchTrips()
        XCTAssertEqual(remainingTrips.map { $0.id }, [trip.id])
    }

    func testLocalCleanupFailureAfterRemoteDeletionReturnsToWelcomeSafely() async throws {
        let repository = AccountTestRepository(trips: [testTrip()], deleteAllShouldFail: true)
        let controller = makeController(repository: repository)
        controller.continueAsGuest()
        await controller.authenticateWithApple(token: "verified-token", rawNonce: "nonce", displayName: nil)

        await controller.deleteAccount()

        XCTAssertTrue(controller.requiresWelcome)
        XCTAssertNotNil(controller.authenticationError)
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
        XCTAssertTrue(controller.presentsUpgrade)
        controller.presentsUpgrade = false

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
            canStartNewTrip: { controller.canStartAutomaticTracking },
            isManualTrackingActive: { false }
        )
        automatic.startIfEnabled()
        XCTAssertEqual(automatic.state, .idle)
        XCTAssertFalse(automaticLocation.isPreciseTracking)
        XCTAssertFalse(automaticLocation.isLowPowerMonitoring)
        XCTAssertFalse(controller.presentsUpgrade)
    }

    func testDismissedPaywallStaysDismissedAcrossAutomaticStartupAndCallbacks() async {
        let controller = makeController()
        controller.continueAsGuest()
        await controller.reconcileGuestTrial()
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
        let location = MockAutomaticLocationService()
        let motion = MockMotionActivityService()
        let automatic = AutomaticTripCoordinator(
            locationService: location,
            motionService: motion,
            repository: AccountTestRepository(),
            notificationService: AccountTestNotificationService(),
            canStartNewTrip: { controller.canStartAutomaticTracking },
            isManualTrackingActive: { false }
        )
        automatic.startIfEnabled()
        XCTAssertTrue(location.isLowPowerMonitoring)

        for _ in 0..<10 { controller.recordSavedTrip(testTrip()) }
        XCTAssertTrue(controller.presentsUpgrade)
        controller.presentsUpgrade = false

        automatic.startIfEnabled()
        location.send([])
        motion.send(
            MotionActivitySample(
                kind: .automotive,
                confidence: .high,
                timestamp: .now
            )
        )

        XCTAssertFalse(controller.presentsUpgrade)
        XCTAssertEqual(automatic.state, .idle)
        XCTAssertFalse(location.isPreciseTracking)
    }

    func testReconciliationAndLifecycleAutomaticStartupRemainSilentWhenExhausted() async {
        let trips = (0..<10).map { _ in testTrip() }
        let controller = makeController(repository: AccountTestRepository(trips: trips))
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
        let automatic = AutomaticTripCoordinator(
            locationService: MockAutomaticLocationService(),
            motionService: MockMotionActivityService(),
            repository: AccountTestRepository(),
            notificationService: AccountTestNotificationService(),
            canStartNewTrip: { controller.canStartAutomaticTracking },
            isManualTrackingActive: { false }
        )
        controller.continueAsGuest()
        automatic.startIfEnabled()

        await controller.reconcileGuestTrial()
        automatic.startIfEnabled()
        XCTAssertEqual(controller.remainingGuestTrips, 0)
        XCTAssertFalse(controller.presentsUpgrade)

        XCTAssertFalse(controller.canStartAutomaticTracking)
        XCTAssertFalse(controller.presentsUpgrade)
    }

    func testAutomaticEligibilityAllowsFreeTripsAndVerifiedProWithoutPresentation() async {
        let freeController = makeController()
        freeController.continueAsGuest()
        await freeController.reconcileGuestTrial()
        XCTAssertTrue(freeController.canStartAutomaticTracking)
        XCTAssertFalse(freeController.presentsUpgrade)

        let entitlement = AccountTestProEntitlement(hasProAccess: true)
        let proController = makeController(proEntitlement: entitlement)
        proController.continueAsGuest()
        for _ in 0..<10 { proController.recordSavedTrip(testTrip()) }
        XCTAssertTrue(proController.canStartAutomaticTracking)
        XCTAssertFalse(proController.presentsUpgrade)
    }

    func testUnavailableStoreKitProductsDoNotCauseAutomaticPaywallLoop() async {
        let purchaseManager = PurchaseManager(configuration: nil)
        await purchaseManager.prepare()
        let controller = AccountSessionController(
            repository: AccountTestRepository(),
            secureStore: InMemoryAccountStore(),
            authenticationService: AccountTestAuthenticationService(),
            proEntitlementProvider: purchaseManager
        )
        controller.continueAsGuest()
        await controller.reconcileGuestTrial()
        for _ in 0..<10 { controller.recordSavedTrip(testTrip()) }
        XCTAssertTrue(controller.presentsUpgrade)
        controller.presentsUpgrade = false

        XCTAssertFalse(controller.canStartAutomaticTracking)
        XCTAssertFalse(controller.presentsUpgrade)
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

    func testDeletingOneScopeDoesNotDeleteAnotherAccountOrGuest() async throws {
        let (repository, scopeProvider, _) = try makeSwiftDataRepository()
        let firstAccount = LocalDataScope.authenticated(userID: "first-account")
        let secondAccount = LocalDataScope.authenticated(userID: "second-account")
        let guest = LocalDataScope.guest(id: UUID())
        let firstTrip = testTrip()
        let secondTrip = testTrip()
        let guestTrip = testTrip()

        scopeProvider.setCurrent(firstAccount)
        try await repository.save(firstTrip)
        scopeProvider.setCurrent(secondAccount)
        try await repository.save(secondTrip)
        scopeProvider.setCurrent(guest)
        try await repository.save(guestTrip)

        scopeProvider.setCurrent(firstAccount)
        try await repository.deleteAllLocalData()
        let firstAccountTrips = try await repository.fetchTrips()
        XCTAssertTrue(firstAccountTrips.isEmpty)

        scopeProvider.setCurrent(secondAccount)
        let secondAccountTrips = try await repository.fetchTrips()
        XCTAssertEqual(secondAccountTrips.map { $0.id }, [secondTrip.id])

        scopeProvider.setCurrent(guest)
        let guestTrips = try await repository.fetchTrips()
        XCTAssertEqual(guestTrips.map { $0.id }, [guestTrip.id])
    }

    func testProductionAppleDeletionRequiresSecureRevocationService() async {
        let service = FirebaseAuthenticationService(configuration: nil)
        let account = AuthenticatedAccount(
            userID: "apple-user",
            provider: .apple,
            displayName: nil,
            email: nil,
            idToken: "token",
            refreshToken: "refresh",
            tokenExpiration: .now.addingTimeInterval(3_600),
            migratedGuestID: nil
        )

        do {
            try await service.deleteAccount(account)
            XCTFail("Apple deletion must not be reported as complete without token revocation.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Apple token revocation"))
        }
    }

    func testAppleFirebasePostBodyIncludesProviderIdentityTokenAndRawNonce() {
        let body = FirebaseAuthenticationService.identityProviderPostBody(
            providerID: "apple.com",
            idToken: "header.payload+signature",
            nonce: "raw nonce/value"
        )

        XCTAssertEqual(
            body,
            "id_token=header.payload%2Bsignature&providerId=apple.com&nonce=raw%20nonce%2Fvalue"
        )
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
        store: InMemoryAccountStore = InMemoryAccountStore(),
        proEntitlement: AccountTestProEntitlement = AccountTestProEntitlement()
    ) -> AccountSessionController {
        AccountSessionController(
            repository: repository,
            secureStore: store,
            authenticationService: AccountTestAuthenticationService(),
            proEntitlementProvider: proEntitlement
        )
    }

    private func waitForGuestReconciliation(_ controller: AccountSessionController) async {
        for _ in 0..<100 where controller.isReconcilingGuestTrial {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertFalse(controller.isReconcilingGuestTrial)
    }

    private func testTrip(
        id: UUID = UUID(),
        minutesAgo: Int = 0,
        classification: Trip.Classification = .business
    ) -> Trip {
        let end = Date.now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
        return Trip(
            id: id,
            startedAt: end.addingTimeInterval(-600),
            endedAt: end,
            originName: "Start",
            destinationName: "End",
            distanceMiles: 4,
            classification: classification,
            purpose: "Client Meeting"
        )
    }
}

@MainActor
private final class AccountTestProEntitlement: ProEntitlementProviding {
    var hasProAccess: Bool
    var isEntitlementReady = true

    init(hasProAccess: Bool = false) {
        self.hasProAccess = hasProAccess
    }
}

private struct AccountTestAuthenticationService: AuthenticationServicing {
    var deleteShouldFail = false
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

    func deleteAccount(_ account: AuthenticatedAccount) async throws {
        if deleteShouldFail {
            throw AuthenticationError.provider("Network unavailable")
        }
    }
}

private actor AccountTestRepository: MileageRepository {
    private var trips: [Trip]
    private let deleteAllShouldFail: Bool
    private let updateShouldFail: Bool
    private let fetchShouldFail: Bool
    private var fetchCallCount = 0

    init(
        trips: [Trip] = [],
        deleteAllShouldFail: Bool = false,
        updateShouldFail: Bool = false,
        fetchShouldFail: Bool = false
    ) {
        self.trips = trips
        self.deleteAllShouldFail = deleteAllShouldFail
        self.updateShouldFail = updateShouldFail
        self.fetchShouldFail = fetchShouldFail
    }
    func fetchTrips() async throws -> [Trip] {
        fetchCallCount += 1
        if fetchShouldFail {
            throw AuthenticationError.provider("Fetch failed")
        }
        return trips
    }
    func fetchTripsCallCount() -> Int { fetchCallCount }
    func fetchSummary() async throws -> MileageSummary {
        MileageSummaryCalculator.summary(for: trips)
    }
    func fetchProfile() async throws -> UserProfile { MockData.profile }
    func save(_ trip: Trip) async throws {
        if !trips.contains(where: { $0.id == trip.id }) { trips.append(trip) }
    }
    func update(_ trip: Trip) async throws {
        if updateShouldFail {
            throw AuthenticationError.provider("Update failed")
        }
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
    }
    func delete(_ trip: Trip) async throws { trips.removeAll { $0.id == trip.id } }
    func deleteAllLocalData() async throws {
        if deleteAllShouldFail {
            throw AuthenticationError.provider("Local storage unavailable")
        }
        trips.removeAll()
    }
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

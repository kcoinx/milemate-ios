import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security

@MainActor
@Observable
final class AccountSessionController {
    private enum Key {
        static let guest = "account.guestTrial.v1"
        static let authenticated = "account.authenticated.v1"
        static let loggedOut = "account.loggedOut.v1"
    }

    private let secureStore: any SecureAccountStoring
    private let authenticationService: any AuthenticationServicing
    private let repository: any MileageRepository
    private let dataScopeProvider: LocalDataScopeProvider
    private let proEntitlementProvider: any ProEntitlementProviding
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var currentAppleNonce: String?
    private var trialRecord: GuestTrialRecord
    private var pendingTrackingAccessRequest = false
    private var sessionGeneration = 0
    private var reconciliationTask: Task<Void, Never>?
    private var reconciliationID: UUID?
    private var sessionTransitionAllowed: @MainActor () -> Bool = { true }

    private(set) var state: AccountAccessState
    private(set) var isAuthenticating = false
    private(set) var isReconcilingGuestTrial = false
    var authenticationError: String?
    var presentsUpgrade = false {
        didSet {
            if !presentsUpgrade {
                pendingTrackingAccessRequest = false
            }
        }
    }
    var presentsDeletionConfirmation = false

    init(
        repository: any MileageRepository,
        dataScopeProvider: LocalDataScopeProvider = LocalDataScopeProvider(),
        secureStore: any SecureAccountStoring = KeychainAccountStore(),
        authenticationService: any AuthenticationServicing = FirebaseAuthenticationService(),
        proEntitlementProvider: any ProEntitlementProviding = FreeProEntitlementProvider()
    ) {
        self.repository = repository
        self.dataScopeProvider = dataScopeProvider
        self.secureStore = secureStore
        self.authenticationService = authenticationService
        self.proEntitlementProvider = proEntitlementProvider
        let decoder = JSONDecoder()
        let storedTrial: GuestTrialRecord?
        if let data = try? secureStore.data(for: Key.guest),
           let decodedTrial = try? decoder.decode(GuestTrialRecord.self, from: data) {
            storedTrial = decodedTrial
        } else {
            storedTrial = nil
        }
        trialRecord = storedTrial ?? GuestTrialRecord(guestID: UUID(), countedTripIDs: [])
        if let data = try? secureStore.data(for: Key.authenticated),
           let account = try? decoder.decode(AuthenticatedAccount.self, from: data) {
            state = .authenticated(account)
        } else if (try? secureStore.data(for: Key.loggedOut)) != nil {
            state = .firstLaunch
        } else if storedTrial != nil {
            state = .guest(storedTrial ?? GuestTrialRecord(guestID: UUID(), countedTripIDs: []))
        } else {
            state = .firstLaunch
        }
        dataScopeProvider.setCurrent(Self.localDataScope(for: state))
        if case .firstLaunch = state {} else { scheduleGuestReconciliation() }
    }

    var requiresWelcome: Bool {
        if case .firstLaunch = state { return true }
        return false
    }

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var account: AuthenticatedAccount? {
        guard case .authenticated(let account) = state else { return nil }
        return account
    }

    var guest: GuestTrialRecord? {
        guard case .guest = state else { return nil }
        return trialRecord
    }

    var remainingGuestTrips: Int { trialRecord.remainingTripCount }

    var requiresGuestUpgrade: Bool {
        guard !requiresWelcome,
              proEntitlementProvider.isEntitlementReady,
              !proEntitlementProvider.hasProAccess else { return false }
        return !trialRecord.canRecordAnotherTrip
    }

    var canStartAutomaticTracking: Bool {
        guard !requiresWelcome,
              !isAuthenticating,
              proEntitlementProvider.isEntitlementReady else {
            return false
        }
        if proEntitlementProvider.hasProAccess { return true }
        guard !isReconcilingGuestTrial else { return false }
        return trialRecord.canRecordAnotherTrip
    }

    @discardableResult
    func requestTrackingAccess() -> Bool {
        guard !requiresWelcome, !isAuthenticating else { return false }
        if proEntitlementProvider.isEntitlementReady,
           proEntitlementProvider.hasProAccess {
            return true
        }
        if isReconcilingGuestTrial {
            pendingTrackingAccessRequest = true
            return false
        }
        guard proEntitlementProvider.isEntitlementReady else { return false }
        if trialRecord.canRecordAnotherTrip { return true }
        presentsUpgrade = true
        return false
    }

    func continueAsGuest() {
        guard validateSessionTransition() else { return }
        invalidatePendingAccessAndReconciliation()
        try? secureStore.remove(Key.loggedOut)
        state = .guest(trialRecord)
        dataScopeProvider.setCurrent(.guest(id: trialRecord.guestID))
        persistGuest(trialRecord)
        authenticationError = nil
        scheduleGuestReconciliation()
    }

    func configureSessionTransitionGuard(_ isAllowed: @escaping @MainActor () -> Bool) {
        sessionTransitionAllowed = isAllowed
    }

    func recordSavedTrip(_ trip: Trip) {
        guard !requiresWelcome else { return }
        guard GuestTrialRecord.countsTowardTrial(trip) else { return }
        let inserted = trialRecord.countedTripIDs.insert(trip.id).inserted
        guard inserted else { return }
        synchronizeGuestState()
        persistGuest(trialRecord)
        if !trialRecord.canRecordAnotherTrip, !proEntitlementProvider.hasProAccess {
            presentsUpgrade = true
        }
    }

    func reconcileGuestTrial() async {
        let task = reconciliationTask ?? startGuestReconciliation()
        await task.value
    }

    private func performGuestReconciliation(
        reconciliationID: UUID,
        generationAtStart: Int,
        scopeAtStart: LocalDataScope?
    ) async {
        var completedSuccessfully = false
        defer {
            finishGuestReconciliation(
                reconciliationID: reconciliationID,
                generationAtStart: generationAtStart,
                scopeAtStart: scopeAtStart,
                completedSuccessfully: completedSuccessfully
            )
        }
        guard let scopeAtStart else { return }
        guard !Task.isCancelled else { return }
        guard let trips = try? await repository.fetchTrips() else { return }
        guard !Task.isCancelled,
              sessionGeneration == generationAtStart,
              dataScopeProvider.current == scopeAtStart else { return }
        completedSuccessfully = true
        let savedIDs = Set(trips.map { trip in trip.id })
        let qualifyingIDs = Set(
            trips.compactMap { trip in
                GuestTrialRecord.countsTowardTrial(trip) ? trip.id : nil
            }
        )
        var reconciledIDs = trialRecord.countedTripIDs
        reconciledIDs.subtract(savedIDs.subtracting(qualifyingIDs))
        reconciledIDs.formUnion(qualifyingIDs)
        guard reconciledIDs != trialRecord.countedTripIDs else { return }
        trialRecord.countedTripIDs = reconciledIDs
        synchronizeGuestState()
        persistGuest(trialRecord)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            currentAppleNonce = nil
            if let authorizationError = error as? ASAuthorizationError {
                guard authorizationError.code != .canceled else { return }
                authenticationError = Self.appleAuthorizationErrorMessage(authorizationError)
            } else {
                authenticationError = error.localizedDescription
            }
        case .success(let authorization):
            let nonce = currentAppleNonce
            currentAppleNonce = nil
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce else {
                authenticationError = AuthenticationError.invalidCredential.localizedDescription
                return
            }
            let displayName = PersonNameComponentsFormatter().string(from: credential.fullName ?? .init())
            Task { await authenticateWithApple(token: token, rawNonce: nonce, displayName: displayName) }
        }
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func authenticateWithApple(token: String, rawNonce: String, displayName: String?) async {
        await authenticate {
            try await authenticationService.signInWithApple(
                identityToken: token,
                rawNonce: rawNonce,
                displayName: displayName?.isEmpty == false ? displayName : nil
            )
        }
    }

    func authenticateWithGoogle() async {
        await authenticate { try await authenticationService.signInWithGoogle() }
    }

    func logOut() {
        guard validateSessionTransition() else { return }
        clearAuthenticatedSession()
        authenticationError = nil
    }

    private func clearAuthenticatedSession() {
        invalidatePendingAccessAndReconciliation()
        try? secureStore.remove(Key.authenticated)
        try? secureStore.set(Data([1]), for: Key.loggedOut)
        presentsUpgrade = false
        state = .firstLaunch
        dataScopeProvider.setCurrent(nil)
    }

    func deleteAccount() async {
        guard let account else { return }
        guard validateSessionTransition() else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let expectedScope = LocalDataScope.authenticated(userID: account.userID)
            guard dataScopeProvider.current == expectedScope else {
                throw AuthenticationError.provider(
                    "MileMate could not verify the local account boundary. No account or mileage data was deleted."
                )
            }
            try await authenticationService.deleteAccount(account)
            var cleanupError: Error?
            do {
                try await repository.deleteAllLocalData()
            } catch {
                cleanupError = error
            }
            clearAuthenticatedSession()
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: nil)
            NotificationCenter.default.post(name: .mileageVehiclesDidChange, object: nil)
            NotificationCenter.default.post(name: .mileageClassificationDataDidChange, object: nil)
            if cleanupError != nil {
                authenticationError = "Your account was deleted, but some isolated local data could not be removed. It remains inaccessible to other accounts."
            }
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    private func authenticate(
        operation: () async throws -> AuthenticatedAccount
    ) async {
        guard !isAuthenticating else { return }
        guard validateSessionTransition() else { return }
        invalidatePendingAccessAndReconciliation()
        isAuthenticating = true
        authenticationError = nil
        defer { isAuthenticating = false }
        do {
            var account = try await operation()
            let guestAtSignIn = guest
            account.migratedGuestID = guestAtSignIn?.guestID
            let accountScope = LocalDataScope.authenticated(userID: account.userID)
            if let guestAtSignIn {
                try await repository.migrateLocalData(
                    from: .guest(id: guestAtSignIn.guestID),
                    to: accountScope
                )
            }
            try secureStore.set(try encoder.encode(account), for: Key.authenticated)
            try? secureStore.remove(Key.loggedOut)
            state = .authenticated(account)
            dataScopeProvider.setCurrent(accountScope)
            presentsUpgrade = false
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: nil)
            NotificationCenter.default.post(name: .mileageVehiclesDidChange, object: nil)
            NotificationCenter.default.post(name: .mileageClassificationDataDidChange, object: nil)
            scheduleGuestReconciliation()
        } catch let error as AuthenticationError where error == .canceled {
            return
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    private func persistGuest(_ guest: GuestTrialRecord) {
        guard let data = try? encoder.encode(guest) else { return }
        try? secureStore.set(data, for: Key.guest)
    }

    private func synchronizeGuestState() {
        if case .guest = state {
            state = .guest(trialRecord)
        }
    }

    private func scheduleGuestReconciliation() {
        guard reconciliationTask == nil else { return }
        _ = startGuestReconciliation()
    }

    @discardableResult
    private func startGuestReconciliation() -> Task<Void, Never> {
        let reconciliationID = UUID()
        let generationAtStart = sessionGeneration
        let scopeAtStart = dataScopeProvider.current
        self.reconciliationID = reconciliationID
        isReconcilingGuestTrial = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performGuestReconciliation(
                reconciliationID: reconciliationID,
                generationAtStart: generationAtStart,
                scopeAtStart: scopeAtStart
            )
        }
        reconciliationTask = task
        return task
    }

    private func finishGuestReconciliation(
        reconciliationID: UUID,
        generationAtStart: Int,
        scopeAtStart: LocalDataScope?,
        completedSuccessfully: Bool
    ) {
        guard self.reconciliationID == reconciliationID else { return }
        reconciliationTask = nil
        self.reconciliationID = nil
        isReconcilingGuestTrial = false
        guard sessionGeneration == generationAtStart,
              dataScopeProvider.current == scopeAtStart else {
            pendingTrackingAccessRequest = false
            return
        }
        if completedSuccessfully {
            resolvePendingTrackingAccessRequest()
        } else {
            pendingTrackingAccessRequest = false
        }
    }

    private func resolvePendingTrackingAccessRequest() {
        guard pendingTrackingAccessRequest else { return }
        pendingTrackingAccessRequest = false
        guard !requiresWelcome,
              proEntitlementProvider.isEntitlementReady,
              !proEntitlementProvider.hasProAccess,
              !trialRecord.canRecordAnotherTrip else {
            return
        }
        presentsUpgrade = true
    }

    private func invalidatePendingAccessAndReconciliation() {
        sessionGeneration += 1
        pendingTrackingAccessRequest = false
        reconciliationTask?.cancel()
        reconciliationTask = nil
        reconciliationID = nil
        isReconcilingGuestTrial = false
    }

    private func validateSessionTransition() -> Bool {
        guard sessionTransitionAllowed() else {
            authenticationError = "Finish or discard the current trip before changing accounts. Your active trip remains safely available."
            return false
        }
        return true
    }

    private static func localDataScope(for state: AccountAccessState) -> LocalDataScope? {
        switch state {
        case .firstLaunch:
            nil
        case .guest(let guest):
            .guest(id: guest.guestID)
        case .authenticated(let account):
            .authenticated(userID: account.userID)
        }
    }

    private static func randomNonce() -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        for byte in bytes { result.append(characters[Int(byte) % characters.count]) }
        return result
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }

    private static func appleAuthorizationErrorMessage(_ error: ASAuthorizationError) -> String {
        switch error.code {
        case .failed:
            "Apple Sign-In failed. Please try again."
        case .invalidResponse:
            "Apple Sign-In returned an invalid response. Please try again."
        case .notHandled:
            "Apple Sign-In could not be handled. Verify that Sign in with Apple is enabled for this app target and App ID."
        case .notInteractive:
            "Apple Sign-In requires an interactive Apple Account session. Please try again."
        default:
            "Apple Sign-In could not be completed (error \(error.code.rawValue)). Verify the Apple Account and Sign in with Apple capability, then try again."
        }
    }
}

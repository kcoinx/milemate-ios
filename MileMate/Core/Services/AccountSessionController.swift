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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var currentAppleNonce: String?

    private(set) var state: AccountAccessState
    private(set) var isAuthenticating = false
    private(set) var isReconcilingGuestTrial = false
    var authenticationError: String?
    var presentsUpgrade = false
    var presentsDeletionConfirmation = false

    init(
        repository: any MileageRepository,
        dataScopeProvider: LocalDataScopeProvider = LocalDataScopeProvider(),
        secureStore: any SecureAccountStoring = KeychainAccountStore(),
        authenticationService: any AuthenticationServicing = FirebaseAuthenticationService()
    ) {
        self.repository = repository
        self.dataScopeProvider = dataScopeProvider
        self.secureStore = secureStore
        self.authenticationService = authenticationService
        let decoder = JSONDecoder()
        if let data = try? secureStore.data(for: Key.authenticated),
           let account = try? decoder.decode(AuthenticatedAccount.self, from: data) {
            state = .authenticated(account)
        } else if (try? secureStore.data(for: Key.loggedOut)) != nil {
            state = .firstLaunch
        } else if let data = try? secureStore.data(for: Key.guest),
                  let guest = try? decoder.decode(GuestTrialRecord.self, from: data) {
            state = .guest(guest)
        } else {
            state = .firstLaunch
        }
        dataScopeProvider.setCurrent(Self.localDataScope(for: state))
        if case .guest = state { scheduleGuestReconciliation() }
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
        guard case .guest(let guest) = state else { return nil }
        return guest
    }

    var remainingGuestTrips: Int { guest?.remainingTripCount ?? GuestTrialRecord.tripLimit }

    @discardableResult
    func requestTrackingAccess() -> Bool {
        switch state {
        case .authenticated:
            return true
        case .guest(let guest):
            if isReconcilingGuestTrial { return false }
            if guest.canRecordAnotherTrip { return true }
            presentsUpgrade = true
            return false
        case .firstLaunch:
            return false
        }
    }

    func continueAsGuest() {
        try? secureStore.remove(Key.loggedOut)
        let guest: GuestTrialRecord
        if let existing = self.guest {
            guest = existing
        } else if let data = try? secureStore.data(for: Key.guest),
                  let stored = try? decoder.decode(GuestTrialRecord.self, from: data) {
            guest = stored
        } else {
            guest = GuestTrialRecord(guestID: UUID(), countedTripIDs: [])
        }
        state = .guest(guest)
        dataScopeProvider.setCurrent(.guest(id: guest.guestID))
        persistGuest(guest)
        scheduleGuestReconciliation()
    }

    func recordSavedTrip(_ trip: Trip) {
        guard case .guest(var guest) = state else { return }
        let inserted = guest.countedTripIDs.insert(trip.id).inserted
        guard inserted else { return }
        state = .guest(guest)
        persistGuest(guest)
        if !guest.canRecordAnotherTrip { presentsUpgrade = true }
    }

    func reconcileGuestTrial() async {
        isReconcilingGuestTrial = true
        defer { isReconcilingGuestTrial = false }
        guard case .guest(let guestAtStart) = state else { return }
        let trips = (try? await repository.fetchTrips()) ?? []
        guard case .guest(var guest) = state,
              guest.guestID == guestAtStart.guestID else {
            return
        }
        let savedIDs = Set(trips.map { trip in trip.id })
        let reconciledIDs = guest.countedTripIDs.union(savedIDs)
        guard reconciledIDs != guest.countedTripIDs else { return }
        guest.countedTripIDs = reconciledIDs
        state = .guest(guest)
        persistGuest(guest)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            currentAppleNonce = nil
            if (error as? ASAuthorizationError)?.code != .canceled {
                authenticationError = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentAppleNonce else {
                authenticationError = AuthenticationError.invalidCredential.localizedDescription
                return
            }
            currentAppleNonce = nil
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
        clearAuthenticatedSession()
        authenticationError = nil
    }

    private func clearAuthenticatedSession() {
        try? secureStore.remove(Key.authenticated)
        try? secureStore.set(Data([1]), for: Key.loggedOut)
        presentsUpgrade = false
        state = .firstLaunch
        dataScopeProvider.setCurrent(nil)
    }

    func deleteAccount() async {
        guard let account else { return }
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

    private func scheduleGuestReconciliation() {
        isReconcilingGuestTrial = true
        Task { await reconcileGuestTrial() }
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
}

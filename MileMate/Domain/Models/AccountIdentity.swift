import Foundation

enum AuthenticationProvider: String, Codable, Sendable {
    case apple = "Apple"
    case google = "Google"
}

struct AuthenticatedAccount: Codable, Equatable, Sendable {
    let userID: String
    let provider: AuthenticationProvider
    var displayName: String?
    var email: String?
    var idToken: String
    var refreshToken: String
    var tokenExpiration: Date
    var migratedGuestID: UUID?
}

struct GuestTrialRecord: Codable, Equatable, Sendable {
    static let tripLimit = 10

    let guestID: UUID
    var countedTripIDs: Set<UUID>

    var completedTripCount: Int { countedTripIDs.count }
    var remainingTripCount: Int { max(Self.tripLimit - completedTripCount, 0) }
    var canRecordAnotherTrip: Bool { completedTripCount < Self.tripLimit }

    static func countsTowardTrial(_ trip: Trip) -> Bool {
        trip.classification != .unclassified
    }
}

enum AccountAccessState: Equatable, Sendable {
    case firstLaunch
    case guest(GuestTrialRecord)
    case authenticated(AuthenticatedAccount)
}

enum AuthenticationError: LocalizedError, Equatable {
    case configurationRequired(String)
    case invalidCredential
    case canceled
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .configurationRequired(let message): message
        case .invalidCredential: "The identity provider did not return a valid credential."
        case .canceled: "Sign in was canceled."
        case .provider(let message): message
        }
    }
}

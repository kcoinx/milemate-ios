import Foundation

protocol MileageRepository: Sendable {
    func fetchTrips() async throws -> [Trip]
    func fetchSummary() async throws -> MileageSummary
    func fetchProfile() async throws -> UserProfile
}


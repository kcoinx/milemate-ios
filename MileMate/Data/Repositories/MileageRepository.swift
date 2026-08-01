import Foundation

protocol MileageRepository: Sendable {
    func fetchTrips() async throws -> [Trip]
    func fetchSummary() async throws -> MileageSummary
    func fetchProfile() async throws -> UserProfile
    func save(_ trip: Trip) async throws
    func update(_ trip: Trip) async throws
    func delete(_ trip: Trip) async throws
}

extension Notification.Name {
    static let mileageTripsDidChange = Notification.Name("MileMate.mileageTripsDidChange")
}

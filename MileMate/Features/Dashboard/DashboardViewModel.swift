import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let repository: any MileageRepository
    private(set) var summary = MockData.summary
    private(set) var recentTrips = Array(MockData.trips.prefix(3))
    private(set) var profile = MockData.profile

    init(repository: any MileageRepository = MockMileageRepository()) {
        self.repository = repository
    }

    func load() async {
        do {
            async let summary = repository.fetchSummary()
            async let trips = repository.fetchTrips()
            async let profile = repository.fetchProfile()
            self.summary = try await summary
            let fetchedTrips = try await trips
            self.recentTrips = Array(fetchedTrips.prefix(3))
            self.profile = try await profile
        } catch {
            // Retain cached values. A production repository can surface recoverable errors here.
        }
    }
}

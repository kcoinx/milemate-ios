import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let repository: any MileageRepository
    private(set) var summary = MileageSummary.empty
    private(set) var recentTrips: [Trip] = []
    private(set) var allTrips: [Trip] = []
    private(set) var profile = MockData.profile

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            async let summary = repository.fetchSummary()
            async let trips = repository.fetchTrips()
            async let profile = repository.fetchProfile()
            self.summary = try await summary
            let fetchedTrips = try await trips
            self.allTrips = fetchedTrips
            self.recentTrips = Array(fetchedTrips.prefix(3))
            self.profile = try await profile
        } catch {
            // Retain cached values. A production repository can surface recoverable errors here.
        }
    }

    var todayBusinessMiles: Double {
        allTrips
            .filter { $0.classification == .business && Calendar.current.isDateInToday($0.startedAt) }
            .reduce(0) { $0 + $1.distanceMiles }
    }

    var weeklyTrips: [Trip] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return allTrips.filter { interval.contains($0.startedAt) }
    }

    var weeklyBusinessMiles: Double {
        weeklyTrips.filter { $0.classification == .business }.reduce(0) { $0 + $1.distanceMiles }
    }

    var weeklyDeduction: Double {
        weeklyTrips.reduce(0) { $0 + $1.estimatedDeduction }
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class InsightsViewModel {
    private let repository: any MileageRepository
    private(set) var trips: [Trip] = []

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    func load() async {
        trips = (try? await repository.fetchTrips()) ?? []
    }

    var hasMeaningfulData: Bool {
        trips.count >= 2 && trips.reduce(0) { $0 + $1.distanceMiles } >= 0.2
    }

    var weekTrips: [Trip] {
        trips(in: Calendar.current.dateInterval(of: .weekOfYear, for: .now))
    }

    var previousWeekTrips: [Trip] {
        guard let thisWeek = Calendar.current.dateInterval(of: .weekOfYear, for: .now),
              let start = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start) else {
            return []
        }
        return trips(in: Calendar.current.dateInterval(of: .weekOfYear, for: start))
    }

    var weeklyBusinessMiles: Double {
        businessMiles(in: weekTrips)
    }

    var weekChangePercentage: Double? {
        let previous = businessMiles(in: previousWeekTrips)
        guard previous > 0 else { return nil }
        return (weeklyBusinessMiles - previous) / previous * 100
    }

    var businessPercentage: Double {
        percentage(for: .business)
    }

    var personalPercentage: Double {
        percentage(for: .personal)
    }

    var longestTrip: Trip? {
        trips.max { $0.distanceMiles < $1.distanceMiles }
    }

    var averageDailyMiles: Double {
        let days = Set(trips.map { Calendar.current.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }
        return trips.reduce(0) { $0 + $1.distanceMiles } / Double(days.count)
    }

    var mostDrivenDay: String {
        let grouped = Dictionary(grouping: trips) {
            $0.startedAt.formatted(.dateTime.weekday(.wide))
        }
        return grouped.max { left, right in
            left.value.reduce(0) { total, trip in total + trip.distanceMiles } <
            right.value.reduce(0) { total, trip in total + trip.distanceMiles }
        }?.key ?? "Not enough data"
    }

    var mostVisitedDestination: (name: String, count: Int)? {
        let grouped = Dictionary(grouping: trips, by: \.destinationName)
        guard let result = grouped.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return (result.key, result.value.count)
    }

    var monthlyBusinessMiles: Double {
        businessMiles(in: trips(in: Calendar.current.dateInterval(of: .month, for: .now)))
    }

    private func trips(in interval: DateInterval?) -> [Trip] {
        guard let interval else { return [] }
        return trips.filter { interval.contains($0.startedAt) }
    }

    private func businessMiles(in trips: [Trip]) -> Double {
        trips.filter { $0.classification == .business }.reduce(0) { $0 + $1.distanceMiles }
    }

    private func percentage(for classification: Trip.Classification) -> Double {
        let classified = trips.filter { $0.classification != .unclassified }
        guard !classified.isEmpty else { return 0 }
        return Double(classified.filter { $0.classification == classification }.count) / Double(classified.count)
    }
}

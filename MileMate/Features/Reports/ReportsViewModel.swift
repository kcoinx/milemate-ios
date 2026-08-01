import Foundation
import Observation

@MainActor
@Observable
final class ReportsViewModel {
    struct WeeklyMileage: Identifiable {
        let weekStart: Date
        let miles: Double

        var id: Date { weekStart }
    }

    struct VehicleMileage: Identifiable {
        let vehicle: String
        let miles: Double

        var id: String { vehicle }
    }

    enum Period: String, CaseIterable {
        case month = "Month"
        case quarter = "Quarter"
        case year = "Year"
    }

    private let repository: any MileageRepository
    private(set) var trips: [Trip] = []
    private(set) var vehicles: [Vehicle] = []
    var period: Period = .month
    var selectedVehicleID: UUID?

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    var summary: MileageSummary {
        MileageSummaryCalculator.summary(for: filteredTrips)
    }

    var weeklyMileage: [WeeklyMileage] {
        let calendar = Calendar.current
        let businessTrips = filteredTrips.filter { $0.classification == .business }
        let grouped = Dictionary(grouping: businessTrips) {
            calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start
                ?? calendar.startOfDay(for: $0.startedAt)
        }
        return grouped.map { weekStart, trips in
            WeeklyMileage(
                weekStart: weekStart,
                miles: trips.reduce(0) { $0 + $1.distanceMiles }
            )
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    func load() async {
        async let fetchedTrips = repository.fetchTrips()
        async let fetchedVehicles = repository.fetchVehicles()
        trips = (try? await fetchedTrips) ?? []
        vehicles = (try? await fetchedVehicles) ?? []
    }

    var vehicleBreakdown: [VehicleMileage] {
        let business = trips.filter {
            selectedInterval.contains($0.startedAt) && $0.classification == .business
        }
        let grouped = Dictionary(grouping: business) { $0.vehicle?.nickname ?? "No vehicle assigned" }
        return grouped.map { name, trips in
            VehicleMileage(
                vehicle: name,
                miles: trips.reduce(0) { $0 + $1.distanceMiles }
            )
        }
        .sorted { $0.miles > $1.miles }
    }

    private var filteredTrips: [Trip] {
        trips.filter {
            selectedInterval.contains($0.startedAt) &&
            (selectedVehicleID == nil || $0.vehicle?.id == selectedVehicleID)
        }
    }

    private var selectedInterval: DateInterval {
        let calendar = Calendar.current
        switch period {
        case .month:
            return calendar.dateInterval(of: .month, for: .now) ?? fallbackInterval
        case .quarter:
            let month = calendar.component(.month, from: .now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: .now)
            components.month = quarterStartMonth
            let start = calendar.date(from: components) ?? .now
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? .now
            return DateInterval(start: start, end: end)
        case .year:
            return calendar.dateInterval(of: .year, for: .now) ?? fallbackInterval
        }
    }

    private var fallbackInterval: DateInterval {
        DateInterval(start: .distantPast, end: .distantFuture)
    }
}

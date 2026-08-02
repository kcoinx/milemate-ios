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
    private(set) var places: [FrequentPlace] = []
    private(set) var profile: UserProfile?
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
        async let fetchedPlaces = repository.fetchFrequentPlaces()
        async let fetchedProfile = repository.fetchProfile()
        trips = (try? await fetchedTrips) ?? []
        vehicles = (try? await fetchedVehicles) ?? []
        places = (try? await fetchedPlaces) ?? []
        profile = try? await fetchedProfile
    }

    func prepareReportData(generatedAt: Date = .now) throws -> MileageReportData {
        try MileageReportPreparationService.prepare(
            trips: trips,
            places: places,
            profile: profile,
            selection: reportSelection,
            generatedAt: generatedAt
        )
    }

    func preparePDFReport(generatedAt: Date = .now) throws -> MileageReportData {
        try prepareReportData(generatedAt: generatedAt)
    }

    var selectedTaxYear: Int {
        Calendar.current.component(.year, from: selectedInterval.start)
    }

    var vehicleBreakdown: [VehicleMileage] {
        let business = MileageReportPreparationService.filteredTrips(
            trips,
            interval: selectedInterval,
            vehicleID: nil,
            classifications: [.business]
        )
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
        MileageReportPreparationService.filteredTrips(
            trips,
            interval: selectedInterval,
            vehicleID: selectedVehicleID,
            classifications: Set(Trip.Classification.allCases)
        )
    }

    var selectedInterval: DateInterval {
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

    var reportSelection: MileageReportSelection {
        let calendar = Calendar.current
        let reportType: MileageReportType
        switch period {
        case .month:
            reportType = .monthly
        case .quarter:
            reportType = .quarterly
        case .year:
            reportType = .annual
        }
        let inclusiveEnd = selectedInterval.end.addingTimeInterval(-1)
        let periodLabel = selectedInterval.start.formatted(
            .dateTime.month(.wide).day().year()
        ) + " - " + inclusiveEnd.formatted(.dateTime.month(.wide).day().year())
        let selectedVehicle = vehicles.first { $0.id == selectedVehicleID }
        let vehicleLabel: String
        if let selectedVehicle {
            vehicleLabel = selectedVehicle.detail.isEmpty
                ? selectedVehicle.nickname
                : "\(selectedVehicle.nickname) - \(selectedVehicle.detail)"
        } else {
            vehicleLabel = "All Vehicles"
        }
        return MileageReportSelection(
            type: reportType,
            interval: selectedInterval,
            periodLabel: periodLabel,
            taxYear: calendar.component(.year, from: selectedInterval.start),
            vehicleID: selectedVehicleID,
            vehicleLabel: vehicleLabel,
            mileageRate: MileageSettings.mileageRate
        )
    }
}

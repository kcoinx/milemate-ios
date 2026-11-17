import Foundation
import Observation

struct ReportRangeSummary: Equatable, Sendable {
    let businessMiles: Double
    let personalMiles: Double
    let unclassifiedMiles: Double
    let totalMiles: Double
    let estimatedDeduction: Double
    let estimatedTaxSavings: Double
}

enum ReportRangeSummaryCalculator {
    static func summary(
        trips: [Trip],
        interval: DateInterval,
        vehicleID: UUID?,
        defaults: UserDefaults = .standard,
        taxPercentage: Double? = nil
    ) -> ReportRangeSummary {
        let selectedTrips = MileageReportPreparationService.filteredTrips(
            trips,
            interval: interval,
            vehicleID: vehicleID,
            classifications: Set(Trip.Classification.allCases)
        )
        let miles: (Trip.Classification) -> Double = { classification in
            selectedTrips
                .filter { trip in trip.classification == classification }
                .reduce(0) { total, trip in total + max(trip.distanceMiles, 0) }
        }
        let businessMiles = miles(.business)
        let personalMiles = miles(.personal)
        let unclassifiedMiles = miles(.unclassified)
        let deduction = selectedTrips
            .filter { trip in
                MileageReportPreparationService.isQualifyingBusinessTrip(trip)
            }
            .reduce(0) { total, trip in
                total + MileageDeductionService.deduction(
                    miles: trip.distanceMiles,
                    classification: trip.classification,
                    rate: MileageSettings.mileageRate(
                        for: trip.startedAt,
                        defaults: defaults
                    )
                )
            }
        let configuredTaxPercentage = taxPercentage
            ?? MileageSettings.estimatedTaxPercentage(in: defaults)

        return ReportRangeSummary(
            businessMiles: businessMiles,
            personalMiles: personalMiles,
            unclassifiedMiles: unclassifiedMiles,
            totalMiles: businessMiles + personalMiles + unclassifiedMiles,
            estimatedDeduction: deduction,
            estimatedTaxSavings: MileageDeductionService.estimatedTaxSavings(
                deduction: deduction,
                taxPercentage: configuredTaxPercentage
            )
        )
    }
}

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
        case custom = "Custom"
    }

    private let repository: any MileageRepository
    private let accountDisplayName: String?
    private(set) var trips: [Trip] = []
    private(set) var vehicles: [Vehicle] = []
    private(set) var places: [FrequentPlace] = []
    private(set) var profile: UserProfile?
    var period: Period = .month
    var selectedVehicleID: UUID?
    var customStartDate: Date = Calendar.current.startOfDay(for: .now)
    var customEndDate: Date = Calendar.current.startOfDay(for: .now)

    init(
        repository: any MileageRepository,
        accountDisplayName: String? = nil
    ) {
        self.repository = repository
        self.accountDisplayName = accountDisplayName
    }

    var summary: MileageSummary {
        MileageReportPreparationService.reportingSummary(
            trips: trips,
            interval: selectedInterval,
            vehicleID: selectedVehicleID
        )
    }

    var rangeSummary: ReportRangeSummary {
        ReportRangeSummaryCalculator.summary(
            trips: trips,
            interval: selectedInterval,
            vehicleID: selectedVehicleID
        )
    }

    var estimatedTaxRateDescription: String {
        MileageSettings.estimatedTaxPercentage.formatted(
            .number.precision(.fractionLength(0...1))
        ) + "%"
    }

    var mileageRateDescription: String {
        var rates = Set(
            qualifyingBusinessTrips.map { trip in
                MileageSettings.mileageRate(for: trip.startedAt)
            }
        )
        if rates.isEmpty {
            rates.insert(MileageSettings.mileageRate(for: selectedInterval.start))
            rates.insert(
                MileageSettings.mileageRate(
                    for: selectedInterval.end.addingTimeInterval(-1)
                )
            )
        }
        return rates.sorted().map {
            $0.formatted(.currency(code: "USD"))
        }
        .joined(separator: " – ") + " / mile"
    }

    var weeklyMileage: [WeeklyMileage] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: qualifyingBusinessTrips) {
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

    func businessWeek(containing date: Date) -> DateInterval? {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(
            of: .weekOfYear,
            for: date
        ) else {
            return nil
        }
        let clippedStart = max(interval.start, selectedInterval.start)
        let clippedEnd = min(interval.end, selectedInterval.end)
        guard clippedStart < clippedEnd else { return nil }
        let clippedInterval = DateInterval(start: clippedStart, end: clippedEnd)
        let hasTrips = qualifyingBusinessTrips.contains { trip in
            clippedInterval.contains(trip.startedAt)
        }
        return hasTrips ? clippedInterval : nil
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
        if let accountDisplayName {
            profile?.firstName = accountDisplayName.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
            )
            profile?.occupation = ""
        }
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
        let business = MileageReportPreparationService.qualifyingBusinessTrips(
            trips,
            interval: selectedInterval,
            vehicleID: nil
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

    private var qualifyingBusinessTrips: [Trip] {
        MileageReportPreparationService.qualifyingBusinessTrips(
            trips,
            interval: selectedInterval,
            vehicleID: selectedVehicleID
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
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let inclusiveEnd = calendar.startOfDay(for: customEndDate)
            let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd)
                ?? inclusiveEnd.addingTimeInterval(86_400)
            return DateInterval(start: min(start, inclusiveEnd), end: end)
        }
    }

    func setCustomStartDate(_ date: Date) {
        customStartDate = date
        if date > customEndDate {
            customEndDate = date
        }
    }

    func setCustomEndDate(_ date: Date) {
        customEndDate = date
        if date < customStartDate {
            customStartDate = date
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
        case .custom:
            reportType = .custom
        }
        let inclusiveEnd = selectedInterval.end.addingTimeInterval(-1)
        let periodLabel = selectedInterval.start.formatted(
            .dateTime.month(.wide).day().year()
        ) + " – " + inclusiveEnd.formatted(.dateTime.month(.wide).day().year())
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
            mileageRate: MileageSettings.mileageRate(for: selectedInterval.start),
            usesConfiguredMileageRateSchedule: true
        )
    }
}

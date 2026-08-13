import CoreGraphics
import Foundation

enum MileageReportType: String, Sendable {
    case monthly = "Monthly Report"
    case quarterly = "Quarterly Report"
    case annual = "Annual Report"
    case custom = "Custom Report"
}

struct MileageReportSelection: Sendable {
    let type: MileageReportType
    let interval: DateInterval
    let periodLabel: String
    let taxYear: Int
    let vehicleID: UUID?
    let vehicleLabel: String
    let mileageRate: Double
}

struct MileageReportTrip: Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let start: String
    let end: String
    let distanceMiles: Double
    let purpose: String
    let notes: String
    let vehicle: String

    var date: Date { startedAt }
    var durationMinutes: Double {
        max(
            endedAt.timeIntervalSince(startedAt),
            TimeInterval(0)
        ) / TimeInterval(60)
    }
}

struct MileageReportData: Sendable {
    let reportID: String
    let generatedAt: Date
    let selection: MileageReportSelection
    let userName: String?
    let professionalTitle: String?
    let trips: [MileageReportTrip]
    let businessMiles: Double
    let estimatedDeduction: Double
    let fileName: String

    var businessTripCount: Int { trips.count }
}

enum MileageReportPreparationError: LocalizedError, Equatable {
    case noBusinessTrips

    var errorDescription: String? {
        switch self {
        case .noBusinessTrips:
            "Add or classify at least one Business trip in the selected period before exporting."
        }
    }
}

enum MileageReportPreparationService {
    static func prepare(
        trips: [Trip],
        places: [FrequentPlace],
        profile: UserProfile?,
        selection: MileageReportSelection,
        generatedAt: Date = .now,
        reportToken: String = String(UUID().uuidString.prefix(4))
    ) throws -> MileageReportData {
        let businessTrips = qualifyingBusinessTrips(
            trips,
            interval: selection.interval,
            vehicleID: selection.vehicleID
        )

        guard !businessTrips.isEmpty else {
            throw MileageReportPreparationError.noBusinessTrips
        }

        let rows = businessTrips.map { trip in
            let matched = SmartClassificationService.matchingPlaces(
                for: trip,
                places: places
            )
            return MileageReportTrip(
                id: trip.id,
                startedAt: trip.startedAt,
                endedAt: trip.endedAt,
                start: matched.start?.label ?? trip.originName,
                end: matched.end?.label ?? trip.destinationName,
                distanceMiles: trip.distanceMiles,
                purpose: trip.purpose,
                notes: trip.notes,
                vehicle: vehicleLabel(for: trip.vehicle)
            )
        }
        let miles = rows.reduce(0) { $0 + $1.distanceMiles }
        let deduction = rows.reduce(0) {
            $0 + MileageDeductionService.deduction(
                miles: $1.distanceMiles,
                classification: .business,
                rate: selection.mileageRate
            )
        }

        return MileageReportData(
            reportID: reportID(
                year: selection.taxYear,
                type: selection.type,
                interval: selection.interval,
                token: reportToken
            ),
            generatedAt: generatedAt,
            selection: selection,
            userName: profile?.firstName.nilIfBlank,
            professionalTitle: profile?.occupation.nilIfBlank,
            trips: rows,
            businessMiles: miles,
            estimatedDeduction: deduction,
            fileName: fileName(for: selection)
        )
    }

    static func reportID(
        year: Int,
        type: MileageReportType,
        interval: DateInterval,
        token: String
    ) -> String {
        let period: String
        switch type {
        case .monthly:
            period = String(format: "%02d", Calendar.current.component(.month, from: interval.start))
        case .quarterly:
            let month = Calendar.current.component(.month, from: interval.start)
            period = "Q\((month - 1) / 3 + 1)"
        case .annual:
            period = "YR"
        case .custom:
            let formatter = DateFormatter()
            formatter.calendar = Calendar.current
            formatter.dateFormat = "yyyyMMdd"
            let inclusiveEnd = interval.end.addingTimeInterval(-1)
            period = "\(formatter.string(from: interval.start))-\(formatter.string(from: inclusiveEnd))"
        }
        return "MM-\(year)-\(period)-\(sanitizedToken(token))"
    }

    static func fileName(for selection: MileageReportSelection) -> String {
        let period: String
        switch selection.type {
        case .monthly:
            period = selection.interval.start.formatted(.dateTime.month(.wide).year())
        case .quarterly:
            let month = Calendar.current.component(.month, from: selection.interval.start)
            period = "Q\((month - 1) / 3 + 1)-\(selection.taxYear)"
        case .annual:
            period = "\(selection.taxYear)"
        case .custom:
            period = selection.periodLabel
        }
        let vehicle = selection.vehicleID == nil
            ? ""
            : "-\(safeFileComponent(selection.vehicleLabel))"
        return "MileMate-\(safeFileComponent(period))\(vehicle)-Mileage-Report.pdf"
    }

    static func csvFileName(for selection: MileageReportSelection) -> String {
        let period = filePeriod(for: selection)
        let vehicle = selection.vehicleID == nil
            ? ""
            : "-\(safeFileComponent(selection.vehicleLabel))"
        return "MileMate-\(safeFileComponent(period))\(vehicle)-Business-Mileage.csv"
    }

    static func irsFileName(for selection: MileageReportSelection) -> String {
        let period = filePeriod(for: selection)
        let vehicle = selection.vehicleID == nil
            ? ""
            : "-\(safeFileComponent(selection.vehicleLabel))"
        return "MileMate-\(safeFileComponent(period))\(vehicle)-IRS-Mileage-Report.pdf"
    }

    static func filteredTrips(
        _ trips: [Trip],
        interval: DateInterval,
        vehicleID: UUID?,
        classifications: Set<Trip.Classification>
    ) -> [Trip] {
        trips
            .filter { trip in
                classifications.contains(trip.classification) &&
                interval.contains(trip.startedAt) &&
                (vehicleID == nil || trip.vehicle?.id == vehicleID)
            }
            .sorted { first, second in
                first.startedAt < second.startedAt
            }
    }

    static func isQualifyingBusinessTrip(_ trip: Trip) -> Bool {
        trip.classification == .business && trip.distanceMiles > 0
    }

    static func qualifyingBusinessTrips(
        _ trips: [Trip],
        interval: DateInterval,
        vehicleID: UUID?
    ) -> [Trip] {
        filteredTrips(
            trips,
            interval: interval,
            vehicleID: vehicleID,
            classifications: [.business]
        )
        .filter { trip in
            isQualifyingBusinessTrip(trip)
        }
    }

    static func reportingSummary(
        trips: [Trip],
        interval: DateInterval,
        vehicleID: UUID?,
        mileageRate: Double
    ) -> MileageSummary {
        MileageSummaryCalculator.summary(
            for: qualifyingBusinessTrips(
                trips,
                interval: interval,
                vehicleID: vehicleID
            ),
            mileageRate: mileageRate
        )
    }

    static func annualSummary(
        trips: [Trip],
        year: Int,
        vehicleID: UUID?,
        mileageRate: Double,
        calendar: Calendar = .current
    ) -> AnnualMileageSummary {
        let interval = annualInterval(year: year, calendar: calendar)
        let business = qualifyingBusinessTrips(
            trips,
            interval: interval,
            vehicleID: vehicleID
        )
        let personal = filteredTrips(
            trips,
            interval: interval,
            vehicleID: vehicleID,
            classifications: [.personal]
        )
        let monthly = (1...12).map { month in
            let miles = business
                .filter { trip in
                    calendar.component(.month, from: trip.startedAt) == month
                }
                .reduce(0) { result, trip in
                    result + trip.distanceMiles
                }
            return AnnualMonthlyMileage(
                month: month,
                label: calendar.shortMonthSymbols[month - 1],
                miles: miles
            )
        }
        let vehicleGroups = Dictionary(grouping: business) { trip in
            vehicleLabel(for: trip.vehicle)
        }
        let vehicleBreakdown = vehicleGroups.map { label, vehicleTrips in
            AnnualVehicleMileage(
                vehicle: label,
                miles: vehicleTrips.reduce(0) { result, trip in
                    result + trip.distanceMiles
                },
                trips: vehicleTrips.count
            )
        }
        .sorted { first, second in
            if first.miles == second.miles {
                return first.vehicle < second.vehicle
            }
            return first.miles > second.miles
        }
        let businessMiles = business.reduce(0) { result, trip in
            result + trip.distanceMiles
        }
        let personalMiles = personal.reduce(0) { result, trip in
            result + trip.distanceMiles
        }
        let deduction = business.reduce(0) { result, trip in
            result + MileageDeductionService.deduction(
                miles: trip.distanceMiles,
                classification: .business,
                rate: mileageRate
            )
        }
        let mostActiveMonth = monthly
            .filter { item in item.miles > 0 }
            .max { first, second in first.miles < second.miles }

        return AnnualMileageSummary(
            taxYear: year,
            businessMiles: businessMiles,
            businessTrips: business.count,
            estimatedDeduction: deduction,
            mileageRate: mileageRate,
            averageBusinessTripDistance: business.isEmpty
                ? 0
                : businessMiles / Double(business.count),
            mostActiveMonth: mostActiveMonth?.label,
            primaryVehicle: vehicleBreakdown.first?.vehicle,
            monthlyMileage: monthly,
            vehicleBreakdown: vehicleBreakdown,
            personalMiles: personalMiles
        )
    }

    private static func vehicleLabel(for snapshot: VehicleSnapshot?) -> String {
        guard let snapshot else { return "No vehicle assigned" }
        if !snapshot.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshot.nickname
        }
        let detail = [
            snapshot.year.map { String($0) },
            snapshot.make.nilIfBlank,
            snapshot.model.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        return detail.isEmpty ? "Vehicle" : detail
    }

    private static func sanitizedToken(_ token: String) -> String {
        let value = token.uppercased().filter { character in
            character.isLetter || character.isNumber
        }
        return String(value.prefix(8)).nilIfBlank ?? "REPORT"
    }

    private static func safeFileComponent(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func filePeriod(for selection: MileageReportSelection) -> String {
        switch selection.type {
        case .monthly:
            return selection.interval.start.formatted(.dateTime.month(.wide).year())
        case .quarterly:
            let month = Calendar.current.component(.month, from: selection.interval.start)
            return "Q\((month - 1) / 3 + 1)-\(selection.taxYear)"
        case .annual:
            return "\(selection.taxYear)"
        case .custom:
            return selection.periodLabel
        }
    }

    private static func annualInterval(year: Int, calendar: Calendar) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            ?? .distantPast
        let end = calendar.date(byAdding: .year, value: 1, to: start)
            ?? .distantFuture
        return DateInterval(start: start, end: end)
    }
}

struct AnnualMonthlyMileage: Identifiable, Sendable, Equatable {
    let month: Int
    let label: String
    let miles: Double

    var id: Int { month }
}

struct AnnualVehicleMileage: Identifiable, Sendable, Equatable {
    let vehicle: String
    let miles: Double
    let trips: Int

    var id: String { vehicle }
}

struct AnnualMileageSummary: Sendable, Equatable {
    let taxYear: Int
    let businessMiles: Double
    let businessTrips: Int
    let estimatedDeduction: Double
    let mileageRate: Double
    let averageBusinessTripDistance: Double
    let mostActiveMonth: String?
    let primaryVehicle: String?
    let monthlyMileage: [AnnualMonthlyMileage]
    let vehicleBreakdown: [AnnualVehicleMileage]
    let personalMiles: Double
}

struct MileageReportPagePlan: Equatable {
    let rowIndices: [Int]
    let includesRecordSummary: Bool
}

enum MileageReportPaginator {
    static func pages(
        rowHeights: [CGFloat],
        firstPageCapacity: CGFloat,
        subsequentPageCapacity: CGFloat,
        recordSummaryHeight: CGFloat
    ) -> [MileageReportPagePlan] {
        guard !rowHeights.isEmpty else {
            return [MileageReportPagePlan(rowIndices: [], includesRecordSummary: true)]
        }
        var pages: [MileageReportPagePlan] = []
        var currentRows: [Int] = []
        var remaining = firstPageCapacity

        for (index, height) in rowHeights.enumerated() {
            if !currentRows.isEmpty, height > remaining {
                pages.append(
                    MileageReportPagePlan(
                        rowIndices: currentRows,
                        includesRecordSummary: false
                    )
                )
                currentRows = []
                remaining = subsequentPageCapacity
            }
            currentRows.append(index)
            remaining -= min(height, subsequentPageCapacity)
        }

        if !currentRows.isEmpty {
            pages.append(
                MileageReportPagePlan(
                    rowIndices: currentRows,
                    includesRecordSummary: false
                )
            )
        }

        if remaining >= recordSummaryHeight, let last = pages.indices.last {
            pages[last] = MileageReportPagePlan(
                rowIndices: pages[last].rowIndices,
                includesRecordSummary: true
            )
        } else {
            pages.append(
                MileageReportPagePlan(
                    rowIndices: [],
                    includesRecordSummary: true
                )
            )
        }
        return pages
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

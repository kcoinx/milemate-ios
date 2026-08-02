import CoreGraphics
import Foundation

enum MileageReportType: String, Sendable {
    case monthly = "Monthly Report"
    case quarterly = "Quarterly Report"
    case annual = "Annual Report"
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
    let date: Date
    let start: String
    let end: String
    let distanceMiles: Double
    let purpose: String
    let vehicle: String
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
        let businessTrips = trips
            .filter {
                $0.classification == .business &&
                selection.interval.contains($0.startedAt) &&
                (selection.vehicleID == nil || $0.vehicle?.id == selection.vehicleID)
            }
            .sorted { $0.startedAt < $1.startedAt }

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
                date: trip.startedAt,
                start: matched.start?.label ?? trip.originName,
                end: matched.end?.label ?? trip.destinationName,
                distanceMiles: trip.distanceMiles,
                purpose: trip.purpose,
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
        }
        let vehicle = selection.vehicleID == nil
            ? ""
            : "-\(safeFileComponent(selection.vehicleLabel))"
        return "MileMate-\(safeFileComponent(period))\(vehicle)-Mileage-Report.pdf"
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
        let value = token.uppercased().filter(\.isLetterOrNumber)
        return String(value.prefix(8)).nilIfBlank ?? "REPORT"
    }

    private static func safeFileComponent(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
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

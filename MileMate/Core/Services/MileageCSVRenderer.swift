import Foundation

enum MileageCSVRenderer {
    enum RendererError: LocalizedError {
        case unableToCreateReport

        var errorDescription: String? {
            "MileMate could not generate the CSV file. Please try again."
        }
    }

    static func render(_ report: MileageReportData) throws -> URL {
        let fileName = MileageReportPreparationService.csvFileName(
            for: report.selection
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName, isDirectory: false)
        let csv = csvString(for: report)

        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            throw RendererError.unableToCreateReport
        }
    }

    static func csvString(for report: MileageReportData) -> String {
        let headers = [
            "Date",
            "Start Time",
            "End Time",
            "Start Location",
            "End Location",
            "Distance Miles",
            "Duration Minutes",
            "Classification",
            "Trip Purpose",
            "Vehicle",
            "Mileage Rate",
            "Estimated Deduction",
            "Notes"
        ]
        var lines = [
            headers.map { header in
                escape(header)
            }
            .joined(separator: ",")
        ]
        let dateFormatter = makeDateFormatter()
        let timeFormatter = makeTimeFormatter()

        for trip in report.trips {
            let deduction = MileageDeductionService.deduction(
                miles: trip.distanceMiles,
                classification: .business,
                rate: report.selection.mileageRate
            )
            let values = [
                dateFormatter.string(from: trip.startedAt),
                timeFormatter.string(from: trip.startedAt),
                timeFormatter.string(from: trip.endedAt),
                trip.start,
                trip.end,
                decimal(trip.distanceMiles, fractionDigits: 3),
                decimal(trip.durationMinutes, fractionDigits: 1),
                Trip.Classification.business.rawValue,
                trip.purpose,
                trip.vehicle,
                decimal(report.selection.mileageRate, fractionDigits: 3),
                decimal(deduction, fractionDigits: 2),
                trip.notes
            ]
            lines.append(
                values.map { value in
                    escape(value)
                }
                .joined(separator: ",")
            )
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ value: String) -> String {
        guard value.contains(",") ||
                value.contains("\"") ||
                value.contains("\n") ||
                value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func decimal(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func makeTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }
}

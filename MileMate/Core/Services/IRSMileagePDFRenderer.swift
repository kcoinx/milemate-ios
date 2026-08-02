import CoreGraphics
import Foundation
import UIKit

@MainActor
final class IRSMileagePDFRenderer {
    enum RendererError: LocalizedError {
        case unableToCreateReport

        var errorDescription: String? {
            "MileMate could not generate the IRS Mileage Report. Please try again."
        }
    }

    private let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let margin: CGFloat = 38
    private let footerTop: CGFloat = 746
    private let accent = UIColor(red: 0.04, green: 0.42, blue: 0.28, alpha: 1)
    private let text = UIColor(white: 0.10, alpha: 1)
    private let secondary = UIColor(white: 0.38, alpha: 1)
    private let rule = UIColor(white: 0.78, alpha: 1)

    func render(_ report: MileageReportData) throws -> URL {
        let fileName = MileageReportPreparationService.irsFileName(
            for: report.selection
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName, isDirectory: false)
        try? FileManager.default.removeItem(at: url)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "MileMate IRS Mileage Report",
            kCGPDFContextAuthor as String: "MileMate",
            kCGPDFContextCreator as String: "MileMate"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let heights = report.trips.map { trip in
            rowHeight(trip)
        }
        let pages = MileageReportPaginator.pages(
            rowHeights: heights,
            firstPageCapacity: CGFloat(400),
            subsequentPageCapacity: CGFloat(640),
            recordSummaryHeight: CGFloat(95)
        )

        do {
            try renderer.writePDF(to: url) { context in
                for (pageIndex, page) in pages.enumerated() {
                    context.beginPage()
                    var y = pageIndex == 0
                        ? drawFirstPageHeader(report)
                        : drawContinuationHeader(report)
                    if !page.rowIndices.isEmpty {
                        y = drawTableHeader(at: y)
                        for rowIndex in page.rowIndices {
                            y = drawRow(
                                report.trips[rowIndex],
                                at: y,
                                height: heights[rowIndex]
                            )
                        }
                    }
                    if page.includesRecordSummary {
                        drawDisclaimer(at: y + CGFloat(16))
                    }
                    drawFooter(page: pageIndex + 1, totalPages: pages.count)
                }
            }
            return url
        } catch {
            throw RendererError.unableToCreateReport
        }
    }

    private func drawFirstPageHeader(_ report: MileageReportData) -> CGFloat {
        drawText(
            "MileMate",
            rect: CGRect(x: margin, y: 34, width: 180, height: 22),
            font: .systemFont(ofSize: 16, weight: .bold),
            color: accent
        )
        drawText(
            "IRS Mileage Report",
            rect: CGRect(x: margin, y: 61, width: 300, height: 28),
            font: .systemFont(ofSize: 20, weight: .bold),
            color: text
        )
        drawText(
            report.selection.type.rawValue,
            rect: CGRect(x: 390, y: 38, width: 184, height: 18),
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: text,
            alignment: .right
        )
        drawText(
            report.selection.periodLabel,
            rect: CGRect(x: 330, y: 62, width: 244, height: 28),
            font: .systemFont(ofSize: 9),
            color: secondary,
            alignment: .right
        )
        drawRule(at: 101, color: accent, height: 1.5)

        let generated = report.generatedAt.formatted(
            .dateTime.month(.wide).day().year().hour().minute()
        )
        var identity: [String] = []
        if let userName = report.userName { identity.append(userName) }
        if let title = report.professionalTitle { identity.append(title) }
        var details: [String] = []
        if !identity.isEmpty {
            details.append("Prepared for: " + identity.joined(separator: ", "))
        }
        details.append(contentsOf: [
            "Vehicle: \(report.selection.vehicleLabel)",
            "Report ID: \(report.reportID)",
            "Generated: \(generated)"
        ])
        drawText(
            details.joined(separator: "\n"),
            rect: CGRect(x: margin, y: 116, width: 536, height: 66),
            font: .systemFont(ofSize: 9),
            color: text
        )

        drawRule(at: 192, color: rule, height: 0.5)
        let metrics = [
            ("Total Business Miles", report.businessMiles.milesFormatted),
            ("Total Business Trips", "\(report.businessTripCount)"),
            (
                "Mileage Rate",
                report.selection.mileageRate.formatted(.currency(code: "USD")) + " / mile"
            ),
            ("Estimated Deduction", report.estimatedDeduction.currencyFormatted)
        ]
        for (index, metric) in metrics.enumerated() {
            let column = index % 2
            let row = index / 2
            let x = margin + CGFloat(column) * CGFloat(268)
            let y = CGFloat(207 + row * 43)
            drawText(
                metric.0.uppercased(),
                rect: CGRect(x: x, y: y, width: 250, height: 12),
                font: .systemFont(ofSize: 7, weight: .semibold),
                color: secondary
            )
            drawText(
                metric.1,
                rect: CGRect(x: x, y: y + 14, width: 250, height: 21),
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: text
            )
        }
        drawRule(at: 292, color: rule, height: 0.5)
        return CGFloat(307)
    }

    private func drawContinuationHeader(_ report: MileageReportData) -> CGFloat {
        drawText(
            "MileMate  |  IRS Mileage Report",
            rect: CGRect(x: margin, y: 33, width: 300, height: 18),
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: accent
        )
        drawText(
            report.selection.periodLabel,
            rect: CGRect(x: 330, y: 33, width: 244, height: 18),
            font: .systemFont(ofSize: 8),
            color: secondary,
            alignment: .right
        )
        drawRule(at: 58, color: rule, height: 0.5)
        return CGFloat(70)
    }

    private func drawTableHeader(at y: CGFloat) -> CGFloat {
        UIColor(white: 0.94, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: 536, height: 24)).fill()
        let headings = ["DATE", "START LOCATION", "END LOCATION", "DISTANCE", "PURPOSE", "VEHICLE"]
        for (index, heading) in headings.enumerated() {
            let column = columns[index]
            drawText(
                heading,
                rect: CGRect(x: column.x, y: y + 7, width: column.width, height: 12),
                font: .systemFont(ofSize: 6.7, weight: .bold),
                color: secondary
            )
        }
        return y + CGFloat(24)
    }

    private func drawRow(
        _ trip: MileageReportTrip,
        at y: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        let values = rowValues(trip)
        for (index, value) in values.enumerated() {
            let column = columns[index]
            drawText(
                value,
                rect: CGRect(
                    x: column.x,
                    y: y + CGFloat(7),
                    width: column.width,
                    height: height - CGFloat(12)
                ),
                font: .systemFont(ofSize: 7.8),
                color: text
            )
        }
        drawRule(at: y + height - CGFloat(1), color: rule, height: 0.5)
        return y + height
    }

    private func rowHeight(_ trip: MileageReportTrip) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 7.8)
        let heights = zip(rowValues(trip), columns).map { pair in
            let (value, column) = pair
            return textHeight(value, width: column.width, font: font)
        }
        let contentHeight = heights.max() ?? CGFloat(16)
        return max(CGFloat(30), ceil(contentHeight) + CGFloat(14))
    }

    private func rowValues(_ trip: MileageReportTrip) -> [String] {
        [
            trip.startedAt.formatted(.dateTime.month(.abbreviated).day().year()),
            trip.start,
            trip.end,
            trip.distanceMiles.milesFormatted,
            trip.purpose.isEmpty ? "Not specified" : trip.purpose,
            trip.vehicle
        ]
    }

    private func drawDisclaimer(at y: CGFloat) {
        drawRule(at: y, color: accent, height: 1)
        drawText(
            "This report is intended to assist with mileage recordkeeping. Users are responsible for maintaining records that satisfy applicable tax requirements.",
            rect: CGRect(x: margin, y: y + 14, width: 536, height: 44),
            font: .italicSystemFont(ofSize: 8),
            color: secondary
        )
    }

    private func drawFooter(page: Int, totalPages: Int) {
        drawRule(at: footerTop, color: rule, height: 0.5)
        drawText(
            "Generated by MileMate",
            rect: CGRect(x: margin, y: footerTop + 10, width: 250, height: 15),
            font: .systemFont(ofSize: 8),
            color: secondary
        )
        drawText(
            "Page \(page) of \(totalPages)",
            rect: CGRect(x: 370, y: footerTop + 10, width: 204, height: 15),
            font: .systemFont(ofSize: 8),
            color: secondary,
            alignment: .right
        )
    }

    private var columns: [(x: CGFloat, width: CGFloat)] {
        let widths: [CGFloat] = [60, 116, 116, 58, 98, 88]
        var x = margin
        return widths.map { width in
            defer { x += width }
            return (x, width - CGFloat(6))
        }
    }

    private func drawRule(at y: CGFloat, color: UIColor, height: CGFloat) {
        color.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: 536, height: height)).fill()
    }

    private func drawText(
        _ value: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (value as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private func textHeight(_ value: String, width: CGFloat, font: UIFont) -> CGFloat {
        (value as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    }
}

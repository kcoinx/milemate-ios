import CoreGraphics
import Foundation
import UIKit

@MainActor
final class MileagePDFRenderer {
    enum RendererError: LocalizedError {
        case unableToCreateReport

        var errorDescription: String? {
            "MileMate could not generate the PDF. Please try again."
        }
    }

    private let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let margin: CGFloat = 42
    private let footerTop: CGFloat = 746
    private let emerald = UIColor(red: 0.04, green: 0.48, blue: 0.31, alpha: 1)
    private let darkText = UIColor(white: 0.12, alpha: 1)
    private let secondaryText = UIColor(white: 0.36, alpha: 1)
    private let divider = UIColor(white: 0.84, alpha: 1)

    func render(_ report: MileageReportData) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(report.fileName, isDirectory: false)
        try? FileManager.default.removeItem(at: url)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "MileMate Professional Mileage Report",
            kCGPDFContextAuthor as String: "MileMate",
            kCGPDFContextCreator as String: "MileMate"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let rowHeights = report.trips.map { trip in
            rowHeight(trip)
        }
        let plans = MileageReportPaginator.pages(
            rowHeights: rowHeights,
            firstPageCapacity: 360,
            subsequentPageCapacity: 625,
            recordSummaryHeight: 140
        )

        do {
            try renderer.writePDF(to: url) { context in
                for (pageIndex, plan) in plans.enumerated() {
                    context.beginPage()
                    var y = pageIndex == 0
                        ? drawReportHeader(report)
                        : drawContinuationHeader(report)

                    if !plan.rowIndices.isEmpty {
                        y = drawTableHeader(at: y)
                        for rowIndex in plan.rowIndices {
                            y = drawRow(
                                report.trips[rowIndex],
                                at: y,
                                height: rowHeights[rowIndex]
                            )
                        }
                    }
                    if plan.includesRecordSummary {
                        drawRecordSummary(report, at: y + 18)
                    }
                    drawFooter(page: pageIndex + 1, totalPages: plans.count)
                }
            }
            return url
        } catch {
            throw RendererError.unableToCreateReport
        }
    }

    private func drawReportHeader(_ report: MileageReportData) -> CGFloat {
        var y = margin
        drawText(
            "MileMate",
            rect: CGRect(x: margin, y: y, width: 200, height: 28),
            font: .systemFont(ofSize: 20, weight: .bold),
            color: emerald
        )
        drawText(
            "Professional Mileage Report",
            rect: CGRect(x: margin, y: y + 29, width: 350, height: 25),
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: darkText
        )
        drawText(
            report.selection.type.rawValue,
            rect: CGRect(x: 410, y: y, width: 160, height: 20),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: darkText,
            alignment: .right
        )
        drawText(
            report.selection.periodLabel,
            rect: CGRect(x: 340, y: y + 23, width: 230, height: 34),
            font: .systemFont(ofSize: 10),
            color: secondaryText,
            alignment: .right
        )
        y += 72
        drawRule(at: y, color: emerald, height: 2)
        y += 18

        let generated = report.generatedAt.formatted(
            .dateTime.month(.wide).day().year().hour().minute()
        )
        drawText(
            "Report ID: \(report.reportID)\nGenerated: \(generated)",
            rect: CGRect(x: margin, y: y, width: 275, height: 36),
            font: .systemFont(ofSize: 9),
            color: secondaryText
        )
        var preparedLines: [String] = []
        if let userName = report.userName { preparedLines.append(userName) }
        if let title = report.professionalTitle { preparedLines.append(title) }
        drawText(
            preparedLines.isEmpty ? "" : "Prepared for\n" + preparedLines.joined(separator: "\n"),
            rect: CGRect(x: 330, y: y - 5, width: 240, height: 52),
            font: .systemFont(ofSize: 9),
            color: darkText,
            alignment: .right
        )
        y += 55

        drawText(
            "Vehicle",
            rect: CGRect(x: margin, y: y, width: 80, height: 16),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: secondaryText
        )
        drawText(
            report.selection.vehicleLabel,
            rect: CGRect(x: margin + 82, y: y, width: 448, height: 16),
            font: .systemFont(ofSize: 10, weight: .medium),
            color: darkText
        )
        y += 28

        let boxWidth = (pageRect.width - margin * 2 - 24) / 4
        let summaries = [
            ("BUSINESS MILES", report.businessMiles.milesFormatted),
            ("BUSINESS TRIPS", "\(report.businessTripCount)"),
            (
                "IRS MILEAGE RATE",
                report.selection.mileageRate.formatted(.currency(code: "USD")) + " / mi"
            ),
            ("EST. DEDUCTION", report.estimatedDeduction.currencyFormatted)
        ]
        for (index, summary) in summaries.enumerated() {
            let x = margin + CGFloat(index) * (boxWidth + 8)
            UIColor(white: 0.96, alpha: 1).setFill()
            UIBezierPath(
                roundedRect: CGRect(x: x, y: y, width: boxWidth, height: 54),
                cornerRadius: 5
            ).fill()
            drawText(
                summary.0,
                rect: CGRect(x: x + 8, y: y + 8, width: boxWidth - 16, height: 12),
                font: .systemFont(ofSize: 7, weight: .semibold),
                color: secondaryText
            )
            drawText(
                summary.1,
                rect: CGRect(x: x + 8, y: y + 24, width: boxWidth - 16, height: 22),
                font: .systemFont(ofSize: 13, weight: .bold),
                color: index == 0 ? emerald : darkText
            )
        }
        return y + 72
    }

    private func drawContinuationHeader(_ report: MileageReportData) -> CGFloat {
        drawText(
            "MileMate  |  Mileage Report",
            rect: CGRect(x: margin, y: 34, width: 300, height: 18),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: emerald
        )
        drawText(
            report.selection.periodLabel,
            rect: CGRect(x: 330, y: 34, width: 240, height: 18),
            font: .systemFont(ofSize: 9),
            color: secondaryText,
            alignment: .right
        )
        drawRule(at: 58, color: divider, height: 1)
        return 70
    }

    private func drawTableHeader(at y: CGFloat) -> CGFloat {
        UIColor(white: 0.93, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: 528, height: 24)).fill()
        let titles = ["DATE", "START", "END", "DISTANCE", "PURPOSE", "VEHICLE"]
        for (index, title) in titles.enumerated() {
            let column = columns[index]
            drawText(
                title,
                rect: CGRect(x: column.x, y: y + 7, width: column.width, height: 12),
                font: .systemFont(ofSize: 7, weight: .bold),
                color: secondaryText
            )
        }
        return y + 24
    }

    private func drawRow(
        _ trip: MileageReportTrip,
        at y: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        let values = [
            trip.date.formatted(.dateTime.month(.abbreviated).day().year()),
            trip.start,
            trip.end,
            trip.distanceMiles.milesFormatted,
            trip.purpose.isEmpty ? "Not specified" : trip.purpose,
            trip.vehicle
        ]
        for (index, value) in values.enumerated() {
            let column = columns[index]
            drawText(
                value,
                rect: CGRect(x: column.x, y: y + 7, width: column.width, height: height - 12),
                font: .systemFont(ofSize: 8),
                color: darkText
            )
        }
        drawRule(at: y + height - 1, color: divider, height: 0.5)
        return y + height
    }

    private func rowHeight(_ trip: MileageReportTrip) -> CGFloat {
        let values = [
            trip.date.formatted(.dateTime.month(.abbreviated).day().year()),
            trip.start,
            trip.end,
            trip.distanceMiles.milesFormatted,
            trip.purpose.isEmpty ? "Not specified" : trip.purpose,
            trip.vehicle
        ]
        let font = UIFont.systemFont(ofSize: 8)
        let contentHeight = zip(values, columns).map { pair in
            let (value, column) = pair
            textHeight(value, width: column.width, font: font)
        }.max() ?? CGFloat(16)
        return max(CGFloat(30), ceil(contentHeight) + CGFloat(14))
    }

    private func drawRecordSummary(_ report: MileageReportData, at y: CGFloat) {
        drawRule(at: y, color: emerald, height: 1.5)
        drawText(
            "Record Summary",
            rect: CGRect(x: margin, y: y + 14, width: 200, height: 20),
            font: .systemFont(ofSize: 13, weight: .bold),
            color: darkText
        )
        drawText(
            "This report was generated from mileage records stored in MileMate.\nGenerated on: \(report.generatedAt.formatted(.dateTime.month(.wide).day().year().hour().minute()))",
            rect: CGRect(x: margin, y: y + 39, width: 528, height: 34),
            font: .systemFont(ofSize: 9),
            color: darkText
        )
        drawText(
            "This report is intended to assist with mileage recordkeeping. Users are responsible for maintaining records that satisfy applicable tax requirements.",
            rect: CGRect(x: margin, y: y + 82, width: 528, height: 34),
            font: .italicSystemFont(ofSize: 8),
            color: secondaryText
        )
    }

    private func drawFooter(page: Int, totalPages: Int) {
        drawRule(at: footerTop, color: divider, height: 0.5)
        drawText(
            "Generated by MileMate",
            rect: CGRect(x: margin, y: footerTop + 10, width: 250, height: 16),
            font: .systemFont(ofSize: 8),
            color: secondaryText
        )
        drawText(
            "Page \(page) of \(totalPages)",
            rect: CGRect(x: 350, y: footerTop + 10, width: 220, height: 16),
            font: .systemFont(ofSize: 8),
            color: secondaryText,
            alignment: .right
        )
    }

    private var columns: [(x: CGFloat, width: CGFloat)] {
        let widths: [CGFloat] = [60, 104, 104, 54, 108, 98]
        var x = margin
        return widths.map { width in
            defer { x += width }
            return (x, width - 6)
        }
    }

    private func drawRule(at y: CGFloat, color: UIColor, height: CGFloat) {
        color.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: 528, height: height)).fill()
    }

    private func drawText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
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

    private func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    }
}

import CoreGraphics
import Foundation
import XCTest
@testable import MileMate

final class MileageReportExportTests: XCTestCase {
    func testPreparationIncludesBusinessTripsOnly() throws {
        let selection = selection()
        let business = trip(classification: .business, miles: 12)
        let personal = trip(classification: .personal, miles: 20)
        let unclassified = trip(classification: .unclassified, miles: 30)

        let report = try MileageReportPreparationService.prepare(
            trips: [personal, business, unclassified],
            places: [],
            profile: nil,
            selection: selection,
            reportToken: "TEST"
        )

        XCTAssertEqual(
            report.trips.map { trip in trip.id },
            [business.id]
        )
        XCTAssertEqual(report.businessMiles, 12, accuracy: 0.001)
    }

    func testPreparationRespectsPeriodAndVehicleFilters() throws {
        let includedVehicle = Vehicle(nickname: "Work Van")
        let otherVehicle = Vehicle(nickname: "Car")
        let interval = dateInterval()
        var included = trip(
            date: interval.start.addingTimeInterval(3_600),
            classification: .business,
            miles: 8
        )
        included.vehicle = includedVehicle.snapshot
        var wrongVehicle = trip(
            date: interval.start.addingTimeInterval(7_200),
            classification: .business,
            miles: 10
        )
        wrongVehicle.vehicle = otherVehicle.snapshot
        var outsidePeriod = trip(
            date: interval.end.addingTimeInterval(60),
            classification: .business,
            miles: 15
        )
        outsidePeriod.vehicle = includedVehicle.snapshot

        let report = try MileageReportPreparationService.prepare(
            trips: [outsidePeriod, wrongVehicle, included],
            places: [],
            profile: nil,
            selection: selection(
                interval: interval,
                vehicleID: includedVehicle.id,
                vehicleLabel: includedVehicle.nickname
            ),
            reportToken: "TEST"
        )

        XCTAssertEqual(
            report.trips.map { trip in trip.id },
            [included.id]
        )
    }

    func testSummaryTotalsUseConfiguredMileageRate() throws {
        let report = try MileageReportPreparationService.prepare(
            trips: [
                trip(classification: .business, miles: 10),
                trip(classification: .business, miles: 5.5)
            ],
            places: [],
            profile: nil,
            selection: selection(rate: 0.70),
            reportToken: "TEST"
        )

        XCTAssertEqual(report.businessMiles, 15.5, accuracy: 0.001)
        XCTAssertEqual(report.businessTripCount, 2)
        XCTAssertEqual(report.estimatedDeduction, 10.85, accuracy: 0.001)
    }

    func testReportIDAndFilenameAreStableAndSafe() {
        let selection = selection(
            vehicleID: UUID(),
            vehicleLabel: "Work Van / Primary"
        )

        let reportID = MileageReportPreparationService.reportID(
            year: 2026,
            type: .monthly,
            interval: selection.interval,
            token: "ab-12"
        )
        let fileName = MileageReportPreparationService.fileName(for: selection)

        XCTAssertEqual(reportID, "MM-2026-08-AB12")
        XCTAssertEqual(
            fileName,
            "MileMate-August-2026-Work-Van-Primary-Mileage-Report.pdf"
        )
    }

    func testTripsAreSortedChronologically() throws {
        let later = trip(
            date: dateInterval().start.addingTimeInterval(7_200),
            classification: .business,
            miles: 2
        )
        let earlier = trip(
            date: dateInterval().start.addingTimeInterval(3_600),
            classification: .business,
            miles: 3
        )

        let report = try MileageReportPreparationService.prepare(
            trips: [later, earlier],
            places: [],
            profile: nil,
            selection: selection(),
            reportToken: "TEST"
        )

        XCTAssertEqual(
            report.trips.map { trip in trip.id },
            [earlier.id, later.id]
        )
    }

    func testNoBusinessTripsRejectsExport() {
        XCTAssertThrowsError(
            try MileageReportPreparationService.prepare(
                trips: [trip(classification: .personal, miles: 5)],
                places: [],
                profile: nil,
                selection: selection(),
                reportToken: "TEST"
            )
        ) { error in
            XCTAssertEqual(
                error as? MileageReportPreparationError,
                .noBusinessTrips
            )
        }
    }

    func testLongTripListPaginationPreservesEveryRowAndAddsSummary() {
        let heights = Array(repeating: CGFloat(32), count: 80)

        let pages = MileageReportPaginator.pages(
            rowHeights: heights,
            firstPageCapacity: 320,
            subsequentPageCapacity: 640,
            recordSummaryHeight: 140
        )

        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(
            pages.flatMap { page in page.rowIndices },
            Array(0..<80)
        )
        XCTAssertEqual(
            pages.filter { page in page.includesRecordSummary }.count,
            1
        )
        XCTAssertTrue(pages.last?.includesRecordSummary == true)
    }

    private func selection(
        interval: DateInterval? = nil,
        vehicleID: UUID? = nil,
        vehicleLabel: String = "All Vehicles",
        rate: Double = 0.70
    ) -> MileageReportSelection {
        let interval = interval ?? dateInterval()
        return MileageReportSelection(
            type: .monthly,
            interval: interval,
            periodLabel: "August 1, 2026 - August 31, 2026",
            taxYear: 2026,
            vehicleID: vehicleID,
            vehicleLabel: vehicleLabel,
            mileageRate: rate
        )
    }

    private func dateInterval() -> DateInterval {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        )!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    private func trip(
        date: Date? = nil,
        classification: Trip.Classification,
        miles: Double
    ) -> Trip {
        let startedAt = date ?? dateInterval().start.addingTimeInterval(3_600)
        return Trip(
            id: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            originName: "Home",
            destinationName: "Client Office",
            distanceMiles: miles,
            classification: classification,
            purpose: "Client meeting"
        )
    }
}

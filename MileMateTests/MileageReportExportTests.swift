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

    func testZeroMileageBusinessTripRejectsExport() {
        XCTAssertThrowsError(
            try MileageReportPreparationService.prepare(
                trips: [trip(classification: .business, miles: 0)],
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

    func testSharedFilteringSupportsMonthQuarterAndYearIntervals() {
        let calendar = Calendar(identifier: .gregorian)
        let january = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 15)
        ) ?? .distantPast
        let april = calendar.date(
            from: DateComponents(year: 2026, month: 4, day: 15)
        ) ?? .distantPast
        let nextYear = calendar.date(
            from: DateComponents(year: 2027, month: 1, day: 15)
        ) ?? .distantPast
        let trips = [
            trip(date: january, classification: .business, miles: 1),
            trip(date: april, classification: .business, miles: 2),
            trip(date: nextYear, classification: .business, miles: 3)
        ]
        let month = calendar.dateInterval(of: .month, for: january)
            ?? DateInterval(start: january, duration: 2_592_000)
        let quarter = DateInterval(
            start: calendar.date(
                from: DateComponents(year: 2026, month: 1, day: 1)
            ) ?? january,
            end: calendar.date(
                from: DateComponents(year: 2026, month: 4, day: 1)
            ) ?? april
        )
        let year = calendar.dateInterval(of: .year, for: january)
            ?? DateInterval(start: january, duration: 31_536_000)

        XCTAssertEqual(
            MileageReportPreparationService.filteredTrips(
                trips,
                interval: month,
                vehicleID: nil,
                classifications: [.business]
            ).count,
            1
        )
        XCTAssertEqual(
            MileageReportPreparationService.filteredTrips(
                trips,
                interval: quarter,
                vehicleID: nil,
                classifications: [.business]
            ).count,
            1
        )
        XCTAssertEqual(
            MileageReportPreparationService.filteredTrips(
                trips,
                interval: year,
                vehicleID: nil,
                classifications: [.business]
            ).count,
            2
        )
    }

    func testCSVCorrectlyEscapesQuotesCommasAndLineBreaks() {
        XCTAssertEqual(MileageCSVRenderer.escape("Plain"), "Plain")
        XCTAssertEqual(MileageCSVRenderer.escape("A, B"), "\"A, B\"")
        XCTAssertEqual(
            MileageCSVRenderer.escape("He said \"Hi\""),
            "\"He said \"\"Hi\"\"\""
        )
        XCTAssertEqual(
            MileageCSVRenderer.escape("Line 1\nLine 2"),
            "\"Line 1\nLine 2\""
        )
    }

    func testCSVFilenameUsesSelectedPeriodAndSafeVehicleName() {
        let monthly = MileageReportPreparationService.csvFileName(
            for: selection(
                vehicleID: UUID(),
                vehicleLabel: "Work Van / Primary"
            )
        )
        let quarterly = MileageReportPreparationService.csvFileName(
            for: selection(type: .quarterly)
        )
        let annual = MileageReportPreparationService.csvFileName(
            for: selection(type: .annual)
        )

        XCTAssertEqual(
            monthly,
            "MileMate-August-2026-Work-Van-Primary-Business-Mileage.csv"
        )
        XCTAssertEqual(quarterly, "MileMate-Q3-2026-Business-Mileage.csv")
        XCTAssertEqual(annual, "MileMate-2026-Business-Mileage.csv")
    }

    func testCSVAndIRSUsePreparedBusinessReportData() throws {
        var business = trip(classification: .business, miles: 10)
        business.notes = "Receipt, toll"
        let report = try MileageReportPreparationService.prepare(
            trips: [
                trip(classification: .personal, miles: 20),
                business
            ],
            places: [],
            profile: nil,
            selection: selection(rate: 0.70),
            reportToken: "IRS1"
        )
        let csv = MileageCSVRenderer.csvString(for: report)
        let irsName = MileageReportPreparationService.irsFileName(
            for: report.selection
        )

        XCTAssertEqual(report.businessMiles, 10, accuracy: 0.001)
        XCTAssertEqual(report.estimatedDeduction, 7, accuracy: 0.001)
        XCTAssertEqual(report.businessTripCount, 1)
        XCTAssertTrue(csv.contains(",Business,"))
        XCTAssertTrue(csv.contains("\"Receipt, toll\""))
        XCTAssertTrue(irsName.hasSuffix("-IRS-Mileage-Report.pdf"))
    }

    func testAnnualSummaryAggregatesMonthsAndMostActiveMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let january = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 10)
        ) ?? .distantPast
        let march = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 10)
        ) ?? .distantPast
        let summary = MileageReportPreparationService.annualSummary(
            trips: [
                trip(date: january, classification: .business, miles: 4),
                trip(date: march, classification: .business, miles: 12),
                trip(date: march, classification: .personal, miles: 7)
            ],
            year: 2026,
            vehicleID: nil,
            mileageRate: 0.70,
            calendar: calendar
        )

        XCTAssertEqual(summary.businessMiles, 16, accuracy: 0.001)
        XCTAssertEqual(summary.businessTrips, 2)
        XCTAssertEqual(summary.estimatedDeduction, 11.2, accuracy: 0.001)
        XCTAssertEqual(summary.monthlyMileage[0].miles, 4, accuracy: 0.001)
        XCTAssertEqual(summary.monthlyMileage[2].miles, 12, accuracy: 0.001)
        XCTAssertEqual(summary.mostActiveMonth, "Mar")
        XCTAssertEqual(summary.personalMiles, 7, accuracy: 0.001)
    }

    func testAnnualSummaryFindsPrimaryVehicleAndBreakdown() {
        let primary = Vehicle(nickname: "Work Van")
        let secondary = Vehicle(nickname: "Sedan")
        var first = trip(classification: .business, miles: 20)
        first.vehicle = primary.snapshot
        var second = trip(classification: .business, miles: 5)
        second.vehicle = secondary.snapshot

        let summary = MileageReportPreparationService.annualSummary(
            trips: [second, first],
            year: 2026,
            vehicleID: nil,
            mileageRate: 0.70
        )

        XCTAssertEqual(summary.primaryVehicle, "Work Van")
        XCTAssertEqual(summary.vehicleBreakdown.count, 2)
        XCTAssertEqual(summary.vehicleBreakdown.first?.miles, 20)
    }

    func testAnnualSummaryHandlesLegacyTripWithoutVehicle() {
        let summary = MileageReportPreparationService.annualSummary(
            trips: [trip(classification: .business, miles: 3)],
            year: 2026,
            vehicleID: nil,
            mileageRate: 0.70
        )

        XCTAssertEqual(summary.primaryVehicle, "No vehicle assigned")
        XCTAssertEqual(
            summary.vehicleBreakdown.first?.vehicle,
            "No vehicle assigned"
        )
    }

    func testPreparedTotalsMatchReportsSummaryCalculation() throws {
        let business = trip(classification: .business, miles: 9)
        let report = try MileageReportPreparationService.prepare(
            trips: [business, trip(classification: .personal, miles: 4)],
            places: [],
            profile: nil,
            selection: selection(rate: MileageSettings.mileageRate),
            reportToken: "MATCH"
        )
        let screenSummary = MileageSummaryCalculator.summary(for: [business])

        XCTAssertEqual(
            report.businessMiles,
            screenSummary.businessMiles,
            accuracy: 0.001
        )
        XCTAssertEqual(
            report.estimatedDeduction,
            screenSummary.estimatedDeduction,
            accuracy: 0.001
        )
    }

    @MainActor
    func testReportWeekSelectionRequiresBusinessTrips() async {
        let viewModel = ReportsViewModel(repository: MockMileageRepository())
        await viewModel.load()
        let businessTrip = MockData.trips.first { trip in
            trip.classification == .business
        }
        let emptyDate = Calendar.current.date(
            byAdding: .year,
            value: 10,
            to: .now
        ) ?? .distantFuture

        XCTAssertNotNil(
            businessTrip.flatMap { trip in
                viewModel.businessWeek(containing: trip.startedAt)
            }
        )
        XCTAssertNil(viewModel.businessWeek(containing: emptyDate))
    }

    @MainActor
    func testTripsDateFilterComposesWithExistingFilters() async {
        let viewModel = TripsViewModel(repository: MockMileageRepository())
        await viewModel.load()
        guard let trip = MockData.trips.first else {
            XCTFail("Mock data must include a trip")
            return
        }
        viewModel.dateFilter = DateInterval(
            start: trip.startedAt.addingTimeInterval(-1),
            end: trip.startedAt.addingTimeInterval(1)
        )
        viewModel.selection = trip.classification

        XCTAssertEqual(viewModel.filteredTrips.count, 1)
        XCTAssertEqual(viewModel.filteredTrips.first?.id, trip.id)
    }

    private func selection(
        type: MileageReportType = .monthly,
        interval: DateInterval? = nil,
        vehicleID: UUID? = nil,
        vehicleLabel: String = "All Vehicles",
        rate: Double = 0.70
    ) -> MileageReportSelection {
        let interval = interval ?? dateInterval()
        return MileageReportSelection(
            type: type,
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

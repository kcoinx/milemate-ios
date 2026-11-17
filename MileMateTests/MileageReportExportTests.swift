import CoreGraphics
import Foundation
import XCTest
@testable import MileMate

final class MileageReportExportTests: XCTestCase {
    func testPreparationIncludesBusinessTripsOnly() throws {
        let selection = selection()
        let business = trip(classification: .business, miles: 12)
        let zeroMileageBusiness = trip(classification: .business, miles: 0)
        let negativeMileageBusiness = trip(classification: .business, miles: -2)
        let personal = trip(classification: .personal, miles: 20)
        let unclassified = trip(classification: .unclassified, miles: 30)

        let report = try MileageReportPreparationService.prepare(
            trips: [
                personal,
                zeroMileageBusiness,
                business,
                negativeMileageBusiness,
                unclassified
            ],
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
                trip(classification: .business, miles: 0),
                business
            ],
            places: [],
            profile: nil,
            selection: selection(rate: 0.70),
            reportToken: "IRS1"
        )
        let csv = MileageCSVRenderer.csvString(for: report, unit: .miles)
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

    func testCSVUsesSelectedDisplayUnitWithoutChangingReportTotals() throws {
        let report = try MileageReportPreparationService.prepare(
            trips: [trip(classification: .business, miles: 10)],
            places: [],
            profile: nil,
            selection: selection(rate: 0.70),
            reportToken: "UNIT1"
        )

        let milesCSV = MileageCSVRenderer.csvString(for: report, unit: .miles)
        let kilometersCSV = MileageCSVRenderer.csvString(for: report, unit: .kilometers)

        XCTAssertTrue(milesCSV.contains("Distance Miles"))
        XCTAssertTrue(milesCSV.contains(",10.000,"))
        XCTAssertTrue(kilometersCSV.contains("Distance Kilometers"))
        XCTAssertTrue(kilometersCSV.contains(",16.093,"))
        XCTAssertEqual(report.businessMiles, 10, accuracy: 0.000_001)
        XCTAssertEqual(report.estimatedDeduction, 7, accuracy: 0.000_001)
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
                trip(date: march, classification: .business, miles: 0),
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
        let zeroMileageBusiness = trip(classification: .business, miles: 0)
        let trips = [
            business,
            zeroMileageBusiness,
            trip(classification: .personal, miles: 4)
        ]
        let report = try MileageReportPreparationService.prepare(
            trips: trips,
            places: [],
            profile: nil,
            selection: selection(rate: MileageSettings.mileageRate),
            reportToken: "MATCH"
        )
        let screenSummary = MileageReportPreparationService.reportingSummary(
            trips: trips,
            interval: selection().interval,
            vehicleID: nil,
            mileageRate: MileageSettings.mileageRate
        )

        XCTAssertEqual(report.businessTripCount, 1)
        XCTAssertEqual(screenSummary.tripCount, 1)
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
    func testReportChartSelectionRequiresBusinessTrips() async {
        let viewModel = ReportsViewModel(repository: MockMileageRepository())
        await viewModel.load()
        let businessTrip = MockData.trips.first { trip in
            trip.classification == .business
        }
        let dateBeforeSelectedPeriod = Calendar.current.date(
            byAdding: .year,
            value: -10,
            to: .now
        ) ?? .distantPast
        let dateAfterSelectedPeriod = Calendar.current.date(
            byAdding: .year,
            value: 10,
            to: .now
        ) ?? .distantFuture

        XCTAssertNotNil(
            businessTrip.flatMap { trip in
                viewModel.chartInterval(containing: trip.startedAt)
            }
        )
        XCTAssertNil(viewModel.chartInterval(containing: dateBeforeSelectedPeriod))
        XCTAssertNil(viewModel.chartInterval(containing: dateAfterSelectedPeriod))
    }

    @MainActor
    func testReportChartGroupingFollowsSelectedPeriodAndCustomRangeLength() {
        let viewModel = ReportsViewModel(repository: MockMileageRepository())
        let calendar = Calendar.current

        viewModel.period = .month
        XCTAssertEqual(viewModel.chartGrouping, .week)
        XCTAssertEqual(viewModel.chartHeading, "Business distance by week")

        viewModel.period = .quarter
        XCTAssertEqual(viewModel.chartGrouping, .month)
        viewModel.period = .year
        XCTAssertEqual(viewModel.chartGrouping, .month)

        viewModel.period = .custom
        let start = calendar.startOfDay(for: .now)
        viewModel.setCustomStartDate(start)
        viewModel.setCustomEndDate(calendar.date(byAdding: .day, value: 13, to: start)!)
        XCTAssertEqual(viewModel.chartGrouping, .day)

        viewModel.setCustomEndDate(calendar.date(byAdding: .day, value: 30, to: start)!)
        XCTAssertEqual(viewModel.chartGrouping, .week)

        viewModel.setCustomEndDate(calendar.date(byAdding: .day, value: 180, to: start)!)
        XCTAssertEqual(viewModel.chartGrouping, .month)
    }

    @MainActor
    func testEmptyReportChartHeadingUpdatesWhenPeriodChanges() async {
        let viewModel = ReportsViewModel(
            repository: ReportsChartTestRepository(trips: [], vehicles: [])
        )
        await viewModel.load()
        XCTAssertTrue(viewModel.chartMileage.isEmpty)

        viewModel.period = .month
        XCTAssertEqual(viewModel.chartHeading, "Business distance by week")
        viewModel.period = .quarter
        XCTAssertEqual(viewModel.chartHeading, "Business distance by month")
        viewModel.period = .year
        XCTAssertEqual(viewModel.chartHeading, "Business distance by month")

        viewModel.period = .custom
        let start = Calendar.current.startOfDay(for: .now)
        viewModel.setCustomStartDate(start)
        viewModel.setCustomEndDate(
            Calendar.current.date(byAdding: .day, value: 6, to: start)!
        )
        XCTAssertEqual(viewModel.chartHeading, "Business distance by day")
        XCTAssertTrue(viewModel.chartMileage.isEmpty)
    }

    @MainActor
    func testReportChartUsesBusinessTripsWithinDateAndVehicleFilters() async {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let vehicle = Vehicle(nickname: "Work Car")
        let otherVehicle = Vehicle(nickname: "Other Car")
        func chartTrip(
            day: Int,
            classification: Trip.Classification,
            miles: Double,
            vehicle: Vehicle
        ) -> Trip {
            var value = trip(
                date: calendar.date(
                    from: DateComponents(year: 2026, month: 8, day: day)
                )!,
                classification: classification,
                miles: miles
            )
            value.vehicle = vehicle.snapshot
            return value
        }
        let repository = ReportsChartTestRepository(
            trips: [
                chartTrip(day: 2, classification: .business, miles: 8, vehicle: vehicle),
                chartTrip(day: 3, classification: .personal, miles: 20, vehicle: vehicle),
                chartTrip(day: 4, classification: .unclassified, miles: 30, vehicle: vehicle),
                chartTrip(day: 5, classification: .business, miles: 40, vehicle: otherVehicle),
                chartTrip(day: 20, classification: .business, miles: 50, vehicle: vehicle)
            ],
            vehicles: [vehicle, otherVehicle]
        )
        let viewModel = ReportsViewModel(repository: repository)
        viewModel.period = .custom
        viewModel.setCustomStartDate(start)
        viewModel.setCustomEndDate(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        )
        viewModel.selectedVehicleID = vehicle.id
        await viewModel.load()

        XCTAssertEqual(viewModel.chartGrouping, .day)
        XCTAssertEqual(viewModel.chartMileage.count, 1)
        XCTAssertEqual(viewModel.chartMileage.first?.miles, 8)
        XCTAssertNotNil(viewModel.chartInterval(containing: start.addingTimeInterval(86_400)))
        XCTAssertNil(viewModel.chartInterval(containing: start.addingTimeInterval(2 * 86_400)))
    }

    @MainActor
    func testReportPresetIntervalsRemainCalendarBased() {
        let viewModel = ReportsViewModel(repository: MockMileageRepository())
        let calendar = Calendar.current

        viewModel.period = .month
        XCTAssertEqual(viewModel.selectedInterval, calendar.dateInterval(of: .month, for: .now))
        viewModel.period = .quarter
        XCTAssertEqual(
            calendar.component(.month, from: viewModel.selectedInterval.start),
            ((calendar.component(.month, from: .now) - 1) / 3) * 3 + 1
        )
        viewModel.period = .year
        XCTAssertEqual(viewModel.selectedInterval, calendar.dateInterval(of: .year, for: .now))
    }

    @MainActor
    func testCustomRangeIsInclusiveAndRepairsInvalidDates() {
        let viewModel = ReportsViewModel(repository: MockMileageRepository())
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 2, day: 2))!

        viewModel.period = .custom
        viewModel.setCustomStartDate(start)
        viewModel.setCustomEndDate(end)

        XCTAssertEqual(viewModel.selectedInterval.start, calendar.startOfDay(for: start))
        XCTAssertTrue(viewModel.selectedInterval.contains(end.addingTimeInterval(86_399)))
        XCTAssertEqual(viewModel.reportSelection.type, .custom)

        viewModel.setCustomStartDate(end.addingTimeInterval(86_400))
        XCTAssertEqual(viewModel.customStartDate, viewModel.customEndDate)
    }

    func testCustomRangeFilteringTotalsVehiclesAndExportData() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let finalDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3))!
        let end = calendar.date(byAdding: .day, value: 1, to: finalDay)!
        let vehicle = Vehicle(nickname: "Work Car")
        var included = trip(date: start.addingTimeInterval(3_600), classification: .business, miles: 8)
        included.vehicle = vehicle.snapshot
        var finalDayTrip = trip(date: finalDay.addingTimeInterval(80_000), classification: .business, miles: 2)
        finalDayTrip.vehicle = vehicle.snapshot
        var otherVehicle = trip(date: start.addingTimeInterval(7_200), classification: .business, miles: 20)
        otherVehicle.vehicle = Vehicle(nickname: "Other Car").snapshot
        let outside = trip(date: end, classification: .business, miles: 30)
        let interval = DateInterval(start: start, end: end)
        let trips = [included, finalDayTrip, otherVehicle, outside]

        let summary = MileageReportPreparationService.reportingSummary(
            trips: trips,
            interval: interval,
            vehicleID: vehicle.id,
            mileageRate: 0.70
        )
        XCTAssertEqual(summary.tripCount, 2)
        XCTAssertEqual(summary.businessMiles, 10, accuracy: 0.001)

        let report = try MileageReportPreparationService.prepare(
            trips: trips,
            places: [],
            profile: nil,
            selection: selection(
                type: .custom,
                interval: interval,
                vehicleID: vehicle.id,
                vehicleLabel: vehicle.nickname
            ),
            reportToken: "RANGE"
        )
        XCTAssertEqual(report.trips.count, 2)
        XCTAssertEqual(report.businessMiles, summary.businessMiles, accuracy: 0.001)
        XCTAssertTrue(report.fileName.contains("Mileage-Report"))
        XCTAssertTrue(MileageReportPreparationService.csvFileName(for: report.selection).contains("Business-Mileage"))
        XCTAssertTrue(MileageReportPreparationService.irsFileName(for: report.selection).contains("IRS-Mileage-Report"))
    }

    func testSameDayCustomRangeIncludesTheEntireSelectedDay() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let interval = DateInterval(
            start: day,
            end: calendar.date(byAdding: .day, value: 1, to: day)!
        )
        let lateTrip = trip(
            date: day.addingTimeInterval(86_399),
            classification: .business,
            miles: 3
        )

        let summary = MileageReportPreparationService.reportingSummary(
            trips: [lateTrip],
            interval: interval,
            vehicleID: nil,
            mileageRate: 0.70
        )
        XCTAssertEqual(summary.tripCount, 1)
        XCTAssertEqual(summary.businessMiles, 3, accuracy: 0.001)
    }

    func testReportRangeSummaryReconcilesAllClassificationsAndVehicleFilter() {
        let suiteName = "ReportRangeSummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        MileageSettings.setMileageRate(0.70, for: 2026, defaults: defaults)
        defaults.set(25.0, forKey: MileageSettings.taxRateKey)

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let vehicle = Vehicle(nickname: "Work Car")
        func selectedTrip(
            day: Int,
            classification: Trip.Classification,
            miles: Double
        ) -> Trip {
            var value = trip(
                date: calendar.date(
                    from: DateComponents(year: 2026, month: 8, day: day)
                )!,
                classification: classification,
                miles: miles
            )
            value.vehicle = vehicle.snapshot
            return value
        }
        var otherVehicle = selectedTrip(day: 5, classification: .business, miles: 50)
        otherVehicle.vehicle = Vehicle(nickname: "Other Car").snapshot
        let trips = [
            selectedTrip(day: 2, classification: .business, miles: 10),
            selectedTrip(day: 3, classification: .personal, miles: 5),
            selectedTrip(day: 4, classification: .unclassified, miles: 2),
            selectedTrip(day: 6, classification: .business, miles: 0),
            otherVehicle,
            trip(date: end, classification: .business, miles: 100)
        ]

        let summary = ReportRangeSummaryCalculator.summary(
            trips: trips,
            interval: DateInterval(start: start, end: end),
            vehicleID: vehicle.id,
            defaults: defaults
        )

        XCTAssertEqual(summary.businessMiles, 10, accuracy: 0.001)
        XCTAssertEqual(summary.personalMiles, 5, accuracy: 0.001)
        XCTAssertEqual(summary.unclassifiedMiles, 2, accuracy: 0.001)
        XCTAssertEqual(summary.totalMiles, 17, accuracy: 0.001)
        XCTAssertEqual(summary.estimatedDeduction, 7, accuracy: 0.001)
        XCTAssertEqual(summary.estimatedTaxSavings, 1.75, accuracy: 0.001)
    }

    func testReportRangeSummaryUsesDateSpecificRatesForBusinessOnly() {
        let suiteName = "ReportRangeRateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let summary = ReportRangeSummaryCalculator.summary(
            trips: [
                trip(date: january, classification: .business, miles: 10),
                trip(date: july, classification: .business, miles: 10),
                trip(date: july, classification: .personal, miles: 20),
                trip(date: july, classification: .unclassified, miles: 30)
            ],
            interval: DateInterval(start: start, end: end),
            vehicleID: nil,
            defaults: defaults,
            taxPercentage: 20
        )

        XCTAssertEqual(summary.estimatedDeduction, 14.85, accuracy: 0.001)
        XCTAssertEqual(summary.estimatedTaxSavings, 2.97, accuracy: 0.001)
        XCTAssertEqual(summary.totalMiles, 70, accuracy: 0.001)
    }

    func testEmptyCustomRangeProducesHonestZeroSummary() {
        let summary = MileageReportPreparationService.reportingSummary(
            trips: [],
            interval: dateInterval(),
            vehicleID: nil,
            mileageRate: 0.70
        )
        XCTAssertEqual(summary.tripCount, 0)
        XCTAssertEqual(summary.businessMiles, 0)
        XCTAssertEqual(summary.estimatedDeduction, 0)
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

private struct ReportsChartTestRepository: MileageRepository {
    let trips: [Trip]
    let vehicles: [Vehicle]

    func fetchTrips() async throws -> [Trip] { trips }
    func fetchSummary() async throws -> MileageSummary {
        MileageSummaryCalculator.summary(for: trips)
    }
    func fetchProfile() async throws -> UserProfile { MockData.profile }
    func fetchVehicles() async throws -> [Vehicle] { vehicles }
    func save(_ trip: Trip) async throws {}
    func update(_ trip: Trip) async throws {}
    func delete(_ trip: Trip) async throws {}
}

import XCTest
@testable import MileMate

final class MileageDeductionServiceTests: XCTestCase {
    func testMissingSavedRateUsesTwentyTwoPercentDefault() throws {
        try withTemporaryDefaults { defaults in
            XCTAssertEqual(MileageSettings.estimatedTaxPercentage(in: defaults), 22)
        }
    }

    func testSavedRatesIncludingZeroArePreserved() throws {
        try withTemporaryDefaults { defaults in
            for rate in [28.0, 22.0, 0.0] {
                defaults.set(rate, forKey: MileageSettings.taxRateKey)
                XCTAssertEqual(MileageSettings.estimatedTaxPercentage(in: defaults), rate)
            }
        }
    }

    func testSavedRateSurvivesDefaultsRecreation() throws {
        let suiteName = "MileageDeductionServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(24, forKey: MileageSettings.taxRateKey)

        let recreatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(MileageSettings.estimatedTaxPercentage(in: recreatedDefaults), 24)
    }

    func testBusinessDeductionUsesConfiguredRate() {
        XCTAssertEqual(
            MileageDeductionService.deduction(miles: 100, classification: .business, rate: 0.70),
            70,
            accuracy: 0.001
        )
    }

    func testPersonalAndUnclassifiedMilesAreExcluded() {
        XCTAssertEqual(MileageDeductionService.deduction(miles: 100, classification: .personal, rate: 0.70), 0)
        XCTAssertEqual(MileageDeductionService.deduction(miles: 100, classification: .unclassified, rate: 0.70), 0)
    }

    func testEstimatedTaxSavingsUsesPercentage() {
        XCTAssertEqual(
            MileageDeductionService.estimatedTaxSavings(deduction: 100, taxPercentage: 28),
            28,
            accuracy: 0.001
        )
    }

    func testFullPrecisionDeductionIsMultipliedBeforeDisplayRounding() {
        let savings = MileageDeductionService.estimatedTaxSavings(
            deduction: 16.25,
            taxPercentage: 22
        )

        XCTAssertEqual(savings, 3.575, accuracy: 0.000_001)
        XCTAssertEqual(savings.currencyFormatted, "$4")
    }

    func testYTDAndWeeklySavingsUseTheSameSelectedRate() {
        let trips = [makeBusinessTrip(miles: 23.214_285_714)] // $16.25 at $0.70/mi
        let summary = MileageSummaryCalculator.summary(
            for: trips,
            mileageRate: 0.70,
            taxPercentage: 22
        )
        let weeklyDeduction = trips.reduce(0) {
            $0 + MileageDeductionService.deduction(
                miles: $1.distanceMiles,
                classification: $1.classification,
                rate: 0.70
            )
        }
        let weeklySavings = MileageDeductionService.estimatedTaxSavings(
            deduction: weeklyDeduction,
            taxPercentage: 22
        )

        XCTAssertEqual(summary.estimatedTaxSavings, 3.575, accuracy: 0.000_001)
        XCTAssertEqual(weeklySavings, summary.estimatedTaxSavings, accuracy: 0.000_001)
    }

    func testEstimatedDeductionIsUnaffectedByTaxSavingsRate() {
        let trips = [makeBusinessTrip(miles: 100)]
        let zeroPercent = MileageSummaryCalculator.summary(
            for: trips,
            mileageRate: 0.70,
            taxPercentage: 0
        )
        let sixtyPercent = MileageSummaryCalculator.summary(
            for: trips,
            mileageRate: 0.70,
            taxPercentage: 60
        )

        XCTAssertEqual(zeroPercent.estimatedDeduction, 70)
        XCTAssertEqual(sixtyPercent.estimatedDeduction, 70)
        XCTAssertNotEqual(zeroPercent.estimatedTaxSavings, sixtyPercent.estimatedTaxSavings)
    }

    private func withTemporaryDefaults(
        _ test: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "MileageDeductionServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try test(defaults)
    }

    private func makeBusinessTrip(miles: Double) -> Trip {
        Trip(
            id: UUID(),
            startedAt: .now,
            endedAt: .now.addingTimeInterval(600),
            originName: "Origin",
            destinationName: "Destination",
            distanceMiles: miles,
            classification: .business,
            purpose: ""
        )
    }
}

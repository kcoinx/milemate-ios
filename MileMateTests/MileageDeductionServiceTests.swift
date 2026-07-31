import XCTest
@testable import MileMate

final class MileageDeductionServiceTests: XCTestCase {
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
}

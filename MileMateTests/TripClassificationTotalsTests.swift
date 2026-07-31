import Foundation
import XCTest
@testable import MileMate

final class TripClassificationTotalsTests: XCTestCase {
    func testOnlyBusinessTripsContributeToDeductionTotal() {
        let trips = [
            makeTrip(miles: 10, classification: .business),
            makeTrip(miles: 20, classification: .personal),
            makeTrip(miles: 30, classification: .unclassified)
        ]

        let total = MileageSummaryCalculator.summary(
            for: trips,
            mileageRate: 0.70,
            taxPercentage: 28
        ).estimatedDeduction

        XCTAssertEqual(total, 7, accuracy: 0.001)
    }

    private func makeTrip(miles: Double, classification: Trip.Classification) -> Trip {
        Trip(
            id: UUID(),
            startedAt: .now,
            endedAt: .now.addingTimeInterval(600),
            originName: "Origin",
            destinationName: "Destination",
            distanceMiles: miles,
            classification: classification,
            purpose: ""
        )
    }
}

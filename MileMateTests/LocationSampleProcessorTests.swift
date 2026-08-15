import CoreLocation
import XCTest
@testable import MileMate

final class LocationSampleProcessorTests: XCTestCase {
    func testAccumulatesSequentialValidMovement() {
        let now = Date()
        var processor = LocationSampleProcessor()

        XCTAssertTrue(processor.process(sample(latitude: 37.7749, longitude: -122.4194, date: now), now: now))
        XCTAssertTrue(processor.process(
            sample(latitude: 37.7754, longitude: -122.4194, date: now.addingTimeInterval(10)),
            now: now.addingTimeInterval(10)
        ))
        XCTAssertGreaterThan(processor.distanceMeters, 40)
    }

    func testRejectsInvalidAccuracyStaleSamplesAndDrift() {
        let now = Date()
        var processor = LocationSampleProcessor()

        XCTAssertFalse(processor.process(
            sample(latitude: 37.7749, longitude: -122.4194, accuracy: -1, date: now),
            now: now
        ))
        XCTAssertFalse(processor.process(
            sample(latitude: 37.7749, longitude: -122.4194, date: now.addingTimeInterval(-30)),
            now: now
        ))
        XCTAssertTrue(processor.process(sample(latitude: 37.7749, longitude: -122.4194, date: now), now: now))
        XCTAssertFalse(processor.process(
            sample(latitude: 37.77491, longitude: -122.4194, date: now.addingTimeInterval(2)),
            now: now.addingTimeInterval(2)
        ))
        XCTAssertFalse(processor.process(
            sample(latitude: 38.7749, longitude: -122.4194, date: now.addingTimeInterval(3)),
            now: now.addingTimeInterval(3)
        ))
        XCTAssertEqual(processor.distanceMeters, 0)
    }

    func testSequentialCityDrivingSamplesAccumulateApproximatelyThreeMiles() {
        let start = Date()
        var processor = LocationSampleProcessor()

        for index in 0...60 {
            let timestamp = start.addingTimeInterval(Double(index) * 5)
            let sample = sample(
                latitude: 37.7749 + Double(index) * 0.000_72,
                longitude: -122.4194,
                date: timestamp
            )
            XCTAssertEqual(
                processor.processWithResult(sample, now: timestamp),
                .accepted
            )
        }

        XCTAssertGreaterThan(processor.distanceMeters / 1_609.344, 2.8)
        XCTAssertLessThan(processor.distanceMeters / 1_609.344, 3.2)
    }

    func testRejectionReasonsAreSpecificAndPrivacySafe() {
        let now = Date()
        var processor = LocationSampleProcessor()

        XCTAssertEqual(
            processor.processWithResult(
                sample(latitude: 37.7749, longitude: -122.4194, accuracy: 200, date: now),
                now: now
            ),
            .rejectedInvalidAccuracy
        )
        XCTAssertEqual(
            processor.processWithResult(
                sample(latitude: 37.7749, longitude: -122.4194, date: now.addingTimeInterval(-30)),
                now: now
            ),
            .rejectedStale
        )
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        accuracy: Double = 8,
        date: Date
    ) -> LocationSample {
        LocationSample(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: accuracy,
            timestamp: date
        )
    }
}

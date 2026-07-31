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

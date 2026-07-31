import Foundation
import SwiftData

@Model
final class StoredTrip {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var originName: String
    var destinationName: String
    var distanceMiles: Double
    var distanceMeters: Double = 0
    var durationSeconds: Double = 0
    var estimatedDeductionAmount: Double = 0
    var classificationRawValue: String
    var purpose: String
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var routeData: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(trip: Trip) {
        id = trip.id
        startedAt = trip.startedAt
        endedAt = trip.endedAt
        originName = trip.originName
        destinationName = trip.destinationName
        distanceMiles = trip.distanceMiles
        distanceMeters = trip.distanceMiles * 1_609.344
        durationSeconds = trip.duration
        estimatedDeductionAmount = trip.estimatedDeduction
        classificationRawValue = trip.classification.rawValue
        purpose = trip.purpose
        startLatitude = trip.startCoordinate?.latitude
        startLongitude = trip.startCoordinate?.longitude
        endLatitude = trip.endCoordinate?.latitude
        endLongitude = trip.endCoordinate?.longitude
        routeData = (try? JSONEncoder().encode(trip.route)) ?? Data()
        createdAt = trip.createdAt
        updatedAt = trip.updatedAt
    }

    func update(from trip: Trip) {
        startedAt = trip.startedAt
        endedAt = trip.endedAt
        originName = trip.originName
        destinationName = trip.destinationName
        distanceMiles = trip.distanceMiles
        distanceMeters = trip.distanceMiles * 1_609.344
        durationSeconds = trip.duration
        estimatedDeductionAmount = trip.estimatedDeduction
        classificationRawValue = trip.classification.rawValue
        purpose = trip.purpose
        startLatitude = trip.startCoordinate?.latitude
        startLongitude = trip.startCoordinate?.longitude
        endLatitude = trip.endCoordinate?.latitude
        endLongitude = trip.endCoordinate?.longitude
        routeData = (try? JSONEncoder().encode(trip.route)) ?? Data()
        updatedAt = .now
    }

    var domainModel: Trip {
        let route = (try? JSONDecoder().decode([TripCoordinate].self, from: routeData)) ?? []
        return Trip(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            originName: originName,
            destinationName: destinationName,
            distanceMiles: distanceMeters > 0 ? distanceMeters / 1_609.344 : distanceMiles,
            classification: Trip.Classification(rawValue: classificationRawValue) ?? .unclassified,
            purpose: purpose,
            startCoordinate: coordinate(latitude: startLatitude, longitude: startLongitude, fallback: startedAt),
            endCoordinate: coordinate(latitude: endLatitude, longitude: endLongitude, fallback: endedAt),
            route: route,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func coordinate(latitude: Double?, longitude: Double?, fallback: Date) -> TripCoordinate? {
        guard let latitude, let longitude else { return nil }
        return TripCoordinate(latitude: latitude, longitude: longitude, timestamp: fallback)
    }
}

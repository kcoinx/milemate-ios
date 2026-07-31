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
    var classificationRawValue: String
    var purpose: String

    init(trip: Trip) {
        id = trip.id
        startedAt = trip.startedAt
        endedAt = trip.endedAt
        originName = trip.originName
        destinationName = trip.destinationName
        distanceMiles = trip.distanceMiles
        classificationRawValue = trip.classification.rawValue
        purpose = trip.purpose
    }

    var domainModel: Trip {
        Trip(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            originName: originName,
            destinationName: destinationName,
            distanceMiles: distanceMiles,
            classification: Trip.Classification(rawValue: classificationRawValue) ?? .unclassified,
            purpose: purpose
        )
    }
}


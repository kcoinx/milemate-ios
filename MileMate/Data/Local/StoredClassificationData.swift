import Foundation
import SwiftData

@Model
final class StoredFrequentPlace {
    @Attribute(.unique) var id: UUID
    var label: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var createdAt: Date
    var updatedAt: Date

    init(place: FrequentPlace) {
        id = place.id
        label = place.label
        latitude = place.latitude
        longitude = place.longitude
        radiusMeters = place.radiusMeters
        createdAt = place.createdAt
        updatedAt = place.updatedAt
    }

    var domainModel: FrequentPlace {
        FrequentPlace(
            id: id,
            label: label,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from place: FrequentPlace) {
        label = place.label
        latitude = place.latitude
        longitude = place.longitude
        radiusMeters = place.radiusMeters
        updatedAt = .now
    }
}

@Model
final class StoredClassificationRule {
    @Attribute(.unique) var id: UUID
    var startPlaceID: UUID
    var startLabel: String
    var endPlaceID: UUID
    var endLabel: String
    var classificationRawValue: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(rule: ClassificationRule) {
        id = rule.id
        startPlaceID = rule.startPlaceID
        startLabel = rule.startLabel
        endPlaceID = rule.endPlaceID
        endLabel = rule.endLabel
        classificationRawValue = rule.classification.rawValue
        isEnabled = rule.isEnabled
        createdAt = rule.createdAt
        updatedAt = rule.updatedAt
    }

    var domainModel: ClassificationRule {
        ClassificationRule(
            id: id,
            startPlaceID: startPlaceID,
            startLabel: startLabel,
            endPlaceID: endPlaceID,
            endLabel: endLabel,
            classification: Trip.Classification(rawValue: classificationRawValue) ?? .personal,
            isEnabled: isEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from rule: ClassificationRule) {
        startPlaceID = rule.startPlaceID
        startLabel = rule.startLabel
        endPlaceID = rule.endPlaceID
        endLabel = rule.endLabel
        classificationRawValue = rule.classification.rawValue
        isEnabled = rule.isEnabled
        updatedAt = .now
    }
}

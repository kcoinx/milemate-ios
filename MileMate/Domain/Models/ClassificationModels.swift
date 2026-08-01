import CoreLocation
import Foundation

struct FrequentPlace: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var label: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func contains(_ coordinate: TripCoordinate?) -> Bool {
        guard let coordinate else { return false }
        return CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            <= radiusMeters
    }
}

struct ClassificationRule: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var startPlaceID: UUID
    var startLabel: String
    var endPlaceID: UUID
    var endLabel: String
    var classification: Trip.Classification
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        startPlaceID: UUID,
        startLabel: String,
        endPlaceID: UUID,
        endLabel: String,
        classification: Trip.Classification,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.startPlaceID = startPlaceID
        self.startLabel = startLabel
        self.endPlaceID = endPlaceID
        self.endLabel = endLabel
        self.classification = classification
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ClassificationSuggestion: Equatable, Sendable {
    let classification: Trip.Classification
    let explanation: String
    let matchingHistoryCount: Int
}

enum ClassificationSettings {
    static let automaticRulesEnabledKey = "automaticClassificationRulesEnabled"
}

enum SmartClassificationService {
    static let ruleOfferThreshold = 3

    static func matchingPlaces(
        for trip: Trip,
        places: [FrequentPlace]
    ) -> (start: FrequentPlace?, end: FrequentPlace?) {
        (
            places.first { $0.contains(trip.startCoordinate) },
            places.first { $0.contains(trip.endCoordinate) }
        )
    }

    static func suggestion(
        for trip: Trip,
        history: [Trip],
        places: [FrequentPlace]
    ) -> ClassificationSuggestion? {
        let labels = matchingPlaces(for: trip, places: places)
        guard labels.start?.isSensitiveCategory != true,
              labels.end?.isSensitiveCategory != true else {
            return nil
        }
        let matching = history.filter {
            guard $0.id != trip.id, $0.classification != .unclassified else { return false }
            let historicalLabels = matchingPlaces(for: $0, places: places)
            if let start = labels.start, let end = labels.end {
                return historicalLabels.start?.id == start.id && historicalLabels.end?.id == end.id
            }
            return $0.originName == trip.originName && $0.destinationName == trip.destinationName
        }
        guard matching.count >= ruleOfferThreshold else { return nil }
        let grouped = Dictionary(grouping: matching, by: \.classification)
        guard let strongest = grouped.max(by: { $0.value.count < $1.value.count }),
              strongest.value.count >= ruleOfferThreshold,
              Double(strongest.value.count) / Double(matching.count) >= 0.75 else {
            return nil
        }
        let route = labels.start.flatMap { start in
            labels.end.map { "\(start.label) to \($0.label)" }
        } ?? "this route"
        return ClassificationSuggestion(
            classification: strongest.key,
            explanation: "Trips from \(route) were usually marked \(strongest.key.rawValue).",
            matchingHistoryCount: strongest.value.count
        )
    }

    static func matchingRule(
        for trip: Trip,
        places: [FrequentPlace],
        rules: [ClassificationRule]
    ) -> ClassificationRule? {
        let labels = matchingPlaces(for: trip, places: places)
        guard let startID = labels.start?.id, let endID = labels.end?.id else { return nil }
        return rules.first {
            $0.isEnabled && $0.startPlaceID == startID && $0.endPlaceID == endID
        }
    }

    static func applying(_ rule: ClassificationRule, to trip: Trip) -> Trip {
        var updated = trip
        updated.classification = rule.classification
        updated.classificationSource = .approvedRule
        updated.appliedRuleID = rule.id
        updated.updatedAt = .now
        return updated
    }

    static func overriding(
        _ trip: Trip,
        with classification: Trip.Classification
    ) -> Trip {
        var updated = trip
        updated.classification = classification
        updated.classificationSource = .user
        updated.appliedRuleID = nil
        updated.updatedAt = .now
        return updated
    }
}

private extension FrequentPlace {
    var isSensitiveCategory: Bool {
        let normalized = label.lowercased()
        return [
            "medical", "hospital", "clinic", "doctor", "therapy",
            "health", "pharmacy", "rehab"
        ].contains { normalized.contains($0) }
    }
}

enum ReviewQueueService {
    static func pendingTrips(from trips: [Trip]) -> [Trip] {
        trips
            .filter { $0.classification == .unclassified }
            .sorted { $0.startedAt < $1.startedAt }
    }
}

enum VehicleAssignmentService {
    static func defaultVehicle(in vehicles: [Vehicle]) -> Vehicle? {
        vehicles.first(where: \.isDefault) ?? vehicles.first
    }

    static func assigningDefault(to trip: Trip, vehicles: [Vehicle]) -> Trip {
        guard trip.vehicle == nil, let vehicle = defaultVehicle(in: vehicles) else { return trip }
        var updated = trip
        updated.vehicle = vehicle.snapshot
        return updated
    }

    static func enforcingSingleDefault(
        _ selectedID: UUID,
        in vehicles: [Vehicle]
    ) -> [Vehicle] {
        vehicles.map {
            var vehicle = $0
            vehicle.isDefault = vehicle.id == selectedID
            return vehicle
        }
    }

    static func reassigning(
        trips: [Trip],
        from vehicleID: UUID,
        to replacement: Vehicle
    ) -> [Trip] {
        trips.map {
            guard $0.vehicle?.id == vehicleID else { return $0 }
            var trip = $0
            trip.vehicle = replacement.snapshot
            return trip
        }
    }
}

import Foundation

struct TripCoordinate: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

struct Trip: Identifiable, Hashable, Codable, Sendable {
    enum Classification: String, CaseIterable, Codable, Sendable {
        case business = "Business"
        case personal = "Personal"
        case unclassified = "Unclassified"
    }

    let id: UUID
    var startedAt: Date
    var endedAt: Date
    var originName: String
    var destinationName: String
    var distanceMiles: Double
    var classification: Classification
    var purpose: String
    var notes: String
    var startCoordinate: TripCoordinate?
    var endCoordinate: TripCoordinate?
    var route: [TripCoordinate]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        originName: String,
        destinationName: String,
        distanceMiles: Double,
        classification: Classification,
        purpose: String,
        notes: String = "",
        startCoordinate: TripCoordinate? = nil,
        endCoordinate: TripCoordinate? = nil,
        route: [TripCoordinate] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.originName = originName
        self.destinationName = destinationName
        self.distanceMiles = distanceMiles
        self.classification = classification
        self.purpose = purpose
        self.notes = notes
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.route = route
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var estimatedDeduction: Double {
        MileageDeductionService.deduction(
            miles: distanceMiles,
            classification: classification
        )
    }
}

enum TripPurposeOptions {
    static let presets = [
        "Client Meeting",
        "Property Showing",
        "Delivery",
        "Service Call",
        "Site Visit",
        "Supply Run",
        "Office",
        "Healthcare Visit",
        "Inspection"
    ]
    static let other = "Other"
}

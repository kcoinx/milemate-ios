import Foundation

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

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var estimatedDeduction: Double {
        classification == .business ? distanceMiles * 0.70 : 0
    }
}


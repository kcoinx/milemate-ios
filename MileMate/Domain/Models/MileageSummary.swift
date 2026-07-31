import Foundation

struct MileageSummary: Sendable {
    let businessMiles: Double
    let personalMiles: Double
    let tripCount: Int
    let estimatedDeduction: Double
    let estimatedTaxSavings: Double
    let monthlyMiles: [MonthlyMileage]
}

struct MonthlyMileage: Identifiable, Sendable {
    let id = UUID()
    let month: String
    let miles: Double
}


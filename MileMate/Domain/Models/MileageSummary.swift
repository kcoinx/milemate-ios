import Foundation

struct MileageSummary: Sendable {
    let businessMiles: Double
    let personalMiles: Double
    let tripCount: Int
    let estimatedDeduction: Double
    let estimatedTaxSavings: Double
    let monthlyMiles: [MonthlyMileage]

    static let empty = MileageSummary(
        businessMiles: 0,
        personalMiles: 0,
        tripCount: 0,
        estimatedDeduction: 0,
        estimatedTaxSavings: 0,
        monthlyMiles: []
    )
}

struct MonthlyMileage: Identifiable, Sendable {
    let id = UUID()
    let month: String
    let miles: Double
}

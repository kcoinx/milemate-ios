import Foundation

enum MileageSettings {
    static let rateKey = "mileageDeductionRate"
    static let taxRateKey = "estimatedTaxRate"
    static let defaultMileageRate = 0.70
    static let defaultTaxRate = 22.0

    static var mileageRate: Double {
        let value = UserDefaults.standard.double(forKey: rateKey)
        return value > 0 ? value : defaultMileageRate
    }

    static var estimatedTaxPercentage: Double {
        estimatedTaxPercentage(in: .standard)
    }

    static func estimatedTaxPercentage(in defaults: UserDefaults) -> Double {
        guard defaults.object(forKey: taxRateKey) != nil else {
            return defaultTaxRate
        }
        return min(max(defaults.double(forKey: taxRateKey), 0), 100)
    }
}

enum MileageDeductionService {
    static func deduction(
        miles: Double,
        classification: Trip.Classification,
        rate: Double = MileageSettings.mileageRate
    ) -> Double {
        classification == .business ? max(miles, 0) * max(rate, 0) : 0
    }

    static func estimatedTaxSavings(
        deduction: Double,
        taxPercentage: Double = MileageSettings.estimatedTaxPercentage
    ) -> Double {
        max(deduction, 0) * min(max(taxPercentage, 0), 100) / 100
    }
}

enum MileageSummaryCalculator {
    static func summary(
        for trips: [Trip],
        mileageRate: Double = MileageSettings.mileageRate,
        taxPercentage: Double = MileageSettings.estimatedTaxPercentage
    ) -> MileageSummary {
        let business = trips.filter { $0.classification == .business }
        let businessMiles = business.reduce(0) { $0 + $1.distanceMiles }
        let personalMiles = trips
            .filter { $0.classification == .personal }
            .reduce(0) { $0 + $1.distanceMiles }
        let deduction = business.reduce(0) {
            $0 + MileageDeductionService.deduction(
                miles: $1.distanceMiles,
                classification: $1.classification,
                rate: mileageRate
            )
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let grouped = Dictionary(grouping: business) {
            Calendar.current.dateComponents([.year, .month], from: $0.startedAt)
        }
        let monthly = grouped.compactMap { components, monthTrips -> MonthlyMileage? in
            guard let date = Calendar.current.date(from: components) else { return nil }
            return MonthlyMileage(
                month: formatter.string(from: date),
                miles: monthTrips.reduce(0) { $0 + $1.distanceMiles }
            )
        }

        return MileageSummary(
            businessMiles: businessMiles,
            personalMiles: personalMiles,
            tripCount: trips.count,
            estimatedDeduction: deduction,
            estimatedTaxSavings: MileageDeductionService.estimatedTaxSavings(
                deduction: deduction,
                taxPercentage: taxPercentage
            ),
            monthlyMiles: monthly
        )
    }
}

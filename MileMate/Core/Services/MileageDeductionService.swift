import Foundation

enum MileageSettings {
    static let rateKey = "mileageDeductionRate"
    static let taxRateKey = "estimatedTaxRate"
    static let defaultTaxRate = 22.0
    private static let annualRateKeyPrefix = "mileageDeductionRate.year."

    static var defaultMileageRate: Double {
        officialMileageRate(for: .now)
    }

    static var mileageRate: Double {
        mileageRate(for: .now)
    }

    static func mileageRate(
        for date: Date,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> Double {
        let year = calendar.component(.year, from: date)
        if let override = mileageRateOverride(for: year, defaults: defaults) {
            return override
        }
        let currentYear = calendar.component(.year, from: .now)
        let legacyRate = defaults.double(forKey: rateKey)
        if year == currentYear,
           defaults.object(forKey: rateKey) != nil,
           legacyRate > 0,
           abs(legacyRate - 0.70) > 0.000_001 {
            return legacyRate
        }
        return officialMileageRate(for: date, calendar: calendar)
    }

    static func officialMileageRate(
        for date: Date,
        calendar: Calendar = .current
    ) -> Double {
        let components = calendar.dateComponents([.year, .month], from: date)
        switch components.year {
        case 2026:
            return (components.month ?? 1) >= 7 ? 0.76 : 0.725
        case 2025:
            return 0.70
        case 2024:
            return 0.67
        default:
            return 0.70
        }
    }

    static func mileageRateOverride(
        for year: Int,
        defaults: UserDefaults = .standard
    ) -> Double? {
        let key = annualRateKey(for: year)
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    static func setMileageRate(
        _ rate: Double,
        for year: Int,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(max(rate, 0.01), forKey: annualRateKey(for: year))
    }

    static func restoreOfficialMileageRate(
        for year: Int,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: annualRateKey(for: year))
        if year == Calendar.current.component(.year, from: .now) {
            defaults.removeObject(forKey: rateKey)
        }
    }

    static func removeAllMileageRateOverrides(
        defaults: UserDefaults = .standard
    ) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(annualRateKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: rateKey)
    }

    static func officialRateDescription(for year: Int) -> String {
        if year == 2026 {
            return "$0.725 / mi through June, $0.76 / mi beginning July 1"
        }
        let date = Calendar.current.date(
            from: DateComponents(year: year, month: 1, day: 1)
        ) ?? .now
        return officialMileageRate(for: date).formatted(.currency(code: "USD")) + " / mi"
    }

    private static func annualRateKey(for year: Int) -> String {
        annualRateKeyPrefix + String(year)
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
        mileageRate: Double? = nil,
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
                rate: mileageRate ?? MileageSettings.mileageRate(for: $1.startedAt)
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

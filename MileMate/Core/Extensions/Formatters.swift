import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable, Sendable {
    case miles
    case kilometers

    static let kilometersPerMile = 1.609344

    var id: String { rawValue }
    var title: String { self == .miles ? "Miles" : "Kilometers" }
    var abbreviation: String { self == .miles ? "mi" : "km" }
    var distanceLabel: String { self == .miles ? "Miles" : "Kilometers" }

    func value(fromMiles miles: Double) -> Double {
        self == .miles ? miles : miles * Self.kilometersPerMile
    }

    func miles(from value: Double) -> Double {
        self == .miles ? value : value / Self.kilometersPerMile
    }
}

enum DistanceUnitSettings {
    static let key = "distanceUnit"

    static func defaultUnit(for locale: Locale = .current) -> DistanceUnit {
        locale.region?.identifier == "US" ? .miles : .kilometers
    }

    static func registerDefault(
        in defaults: UserDefaults = .standard,
        locale: Locale = .current
    ) {
        defaults.register(defaults: [key: defaultUnit(for: locale).rawValue])
    }

    static func unit(in defaults: UserDefaults = .standard) -> DistanceUnit {
        guard let rawValue = defaults.string(forKey: key),
              let unit = DistanceUnit(rawValue: rawValue) else {
            return defaultUnit()
        }
        return unit
    }
}

extension Double {
    func distanceValue(unit: DistanceUnit = DistanceUnitSettings.unit()) -> Double {
        unit.value(fromMiles: self)
    }

    func distanceFormatted(unit: DistanceUnit = DistanceUnitSettings.unit()) -> String {
        distanceValue(unit: unit).formatted(.number.precision(.fractionLength(1)))
            + " \(unit.abbreviation)"
    }

    var milesFormatted: String {
        distanceFormatted()
    }

    var currencyFormatted: String {
        formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

extension Date {
    var shortDisplay: String {
        formatted(.dateTime.month(.abbreviated).day())
    }

    var tripDisplay: String {
        formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let totalMinutes = max(Int(self) / 60, 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

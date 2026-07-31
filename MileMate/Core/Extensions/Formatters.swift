import Foundation

extension Double {
    var milesFormatted: String {
        formatted(.number.precision(.fractionLength(1))) + " mi"
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

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


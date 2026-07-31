import Foundation
import Observation

@MainActor
@Observable
final class ReportsViewModel {
    enum Period: String, CaseIterable { case month = "Month", quarter = "Quarter", year = "Year" }
    var period: Period = .year
    let summary = MockData.summary
}


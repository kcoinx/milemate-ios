import Foundation
import Observation

@MainActor
@Observable
final class ReportsViewModel {
    enum Period: String, CaseIterable { case month = "Month", quarter = "Quarter", year = "Year" }
    private let repository: any MileageRepository
    var period: Period = .year
    private(set) var summary = MockData.summary

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            summary = try await repository.fetchSummary()
        } catch {
            // Keep the last available summary while the data source recovers.
        }
    }
}

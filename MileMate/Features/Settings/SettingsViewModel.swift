import Observation

@MainActor
@Observable
final class SettingsViewModel {
    struct FrequentPlace: Identifiable, Hashable {
        let name: String
        let visitCount: Int

        var id: String { name }
    }

    private let repository: any MileageRepository
    var smartReminders = true
    var weeklySummary = true
    private(set) var frequentPlaces: [FrequentPlace] = []

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    func loadFrequentPlaces() async {
        let trips = (try? await repository.fetchTrips()) ?? []
        let names = trips.flatMap { [$0.originName, $0.destinationName] }
            .filter { !$0.isEmpty && $0 != "Unknown location" }
        let grouped = Dictionary(grouping: names, by: { $0 })
        frequentPlaces = grouped
            .map { FrequentPlace(name: $0.key, visitCount: $0.value.count) }
            .sorted {
                $0.visitCount == $1.visitCount
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.visitCount > $1.visitCount
            }
    }
}

import Observation

@MainActor
@Observable
final class SettingsViewModel {
    struct FrequentPlace: Identifiable, Hashable {
        let name: String
        let visitCount: Int

        var id: String { name }
    }

    let repository: any MileageRepository
    private(set) var frequentPlaces: [FrequentPlace] = []
    private(set) var classificationRuleCount = 0

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    func loadFrequentPlaces() async {
        async let fetchedTrips = repository.fetchTrips()
        async let fetchedRules = repository.fetchClassificationRules()
        async let fetchedSavedPlaces = repository.fetchFrequentPlaces()
        let trips = (try? await fetchedTrips) ?? []
        let savedPlaceIDs = Set(
            ((try? await fetchedSavedPlaces) ?? []).map(\.id)
        )
        classificationRuleCount = ((try? await fetchedRules) ?? []).filter { rule in
            rule.isEnabled &&
                rule.startPlaceID != rule.endPlaceID &&
                savedPlaceIDs.contains(rule.startPlaceID) &&
                savedPlaceIDs.contains(rule.endPlaceID)
        }
            .count
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

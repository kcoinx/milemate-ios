import Foundation
import Observation

@MainActor
@Observable
final class TripsViewModel {
    private let repository: any MileageRepository
    var selection: Trip.Classification?
    var searchText = ""
    private(set) var trips: [Trip] = []
    private(set) var errorMessage: String?

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    var filteredTrips: [Trip] {
        trips.filter { trip in
            let matchesType = selection == nil || trip.classification == selection
            let matchesSearch = searchText.isEmpty ||
                trip.originName.localizedStandardContains(searchText) ||
                trip.destinationName.localizedStandardContains(searchText) ||
                trip.purpose.localizedStandardContains(searchText)
            return matchesType && matchesSearch
        }
    }

    var totalMiles: Double {
        filteredTrips.reduce(0) { $0 + $1.distanceMiles }
    }

    func load() async {
        do {
            trips = try await repository.fetchTrips()
            errorMessage = nil
        } catch {
            errorMessage = "Trips are temporarily unavailable."
        }
    }
}

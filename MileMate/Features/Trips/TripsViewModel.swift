import Foundation
import Observation

@MainActor
@Observable
final class TripsViewModel {
    var selection: Trip.Classification?
    var searchText = ""
    private(set) var trips = MockData.trips

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
}


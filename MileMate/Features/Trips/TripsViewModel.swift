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
                trip.purpose.localizedStandardContains(searchText) ||
                trip.notes.localizedStandardContains(searchText)
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

    func classify(_ trip: Trip, as classification: Trip.Classification) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        let previous = trips[index]
        var updated = previous
        updated.classification = classification
        updated.updatedAt = .now
        trips[index] = updated

        do {
            try await repository.update(updated)
            errorMessage = nil
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: updated.id)
        } catch {
            trips[index] = previous
            errorMessage = "The trip classification could not be updated."
        }
    }

    func delete(_ trip: Trip) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips.remove(at: index)

        do {
            try await repository.delete(trip)
            errorMessage = nil
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
        } catch {
            trips.insert(trip, at: min(index, trips.count))
            errorMessage = "The trip could not be deleted."
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}

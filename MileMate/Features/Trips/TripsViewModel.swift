import Foundation
import Observation

@MainActor
@Observable
final class TripsViewModel {
    enum VehicleFilter: Hashable {
        case all
        case vehicle(UUID)
        case unassigned
    }

    private let repository: any MileageRepository
    var selection: Trip.Classification?
    var searchText = ""
    var vehicleFilter = VehicleFilter.all
    var dateFilter: DateInterval?
    private(set) var trips: [Trip] = []
    private(set) var vehicles: [Vehicle] = []
    private(set) var errorMessage: String?

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    var filteredTrips: [Trip] {
        trips.filter { trip in
            let matchesType = selection == nil || trip.classification == selection
            let matchesDate = dateFilter?.contains(trip.startedAt) ?? true
            let matchesSearch = searchText.isEmpty ||
                trip.originName.localizedStandardContains(searchText) ||
                trip.destinationName.localizedStandardContains(searchText) ||
                trip.purpose.localizedStandardContains(searchText) ||
                trip.notes.localizedStandardContains(searchText)
            let matchesVehicle: Bool
            switch vehicleFilter {
            case .all:
                matchesVehicle = true
            case .vehicle(let id):
                matchesVehicle = trip.vehicle?.id == id
            case .unassigned:
                matchesVehicle = trip.vehicle == nil
            }
            return matchesType && matchesDate && matchesSearch && matchesVehicle
        }
    }

    var totalMiles: Double {
        filteredTrips.reduce(0) { $0 + $1.distanceMiles }
    }

    var unclassifiedCount: Int {
        trips.filter { $0.classification == .unclassified }.count
    }

    func load() async {
        do {
            async let fetchedTrips = repository.fetchTrips()
            async let fetchedVehicles = repository.fetchVehicles()
            trips = try await fetchedTrips
            vehicles = try await fetchedVehicles
            errorMessage = nil
        } catch {
            errorMessage = "Trips are temporarily unavailable."
        }
    }

    func classify(_ trip: Trip, as classification: Trip.Classification) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        let previous = trips[index]
        let updated = SmartClassificationService.overriding(
            previous,
            with: classification
        )
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

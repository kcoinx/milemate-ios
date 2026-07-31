import Foundation
import SwiftData

@ModelActor
actor SwiftDataMileageRepository: MileageRepository {
    func fetchTrips() async throws -> [Trip] {
        let descriptor = FetchDescriptor<StoredTrip>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func fetchSummary() async throws -> MileageSummary {
        let currentYear = Calendar.current.component(.year, from: .now)
        let allTrips = try await fetchTrips()
        let trips = allTrips.filter {
            Calendar.current.component(.year, from: $0.startedAt) == currentYear
        }
        return MileageSummaryCalculator.summary(for: trips)
    }

    func fetchProfile() async throws -> UserProfile {
        MockData.profile
    }

    func save(_ trip: Trip) async throws {
        modelContext.insert(StoredTrip(trip: trip))
        try modelContext.save()
    }

    func update(_ trip: Trip) async throws {
        let id = trip.id
        var descriptor = FetchDescriptor<StoredTrip>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return }
        stored.update(from: trip)
        try modelContext.save()
    }

    func delete(_ trip: Trip) async throws {
        let id = trip.id
        var descriptor = FetchDescriptor<StoredTrip>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(stored)
        try modelContext.save()
    }
}

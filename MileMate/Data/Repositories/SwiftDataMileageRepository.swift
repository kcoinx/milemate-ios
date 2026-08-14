import Foundation
import SwiftData

@ModelActor
actor SwiftDataMileageRepository: MileageRepository {
    func fetchTrips() async throws -> [Trip] {
        let descriptor = FetchDescriptor<StoredTrip>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let storedTrips = try modelContext.fetch(descriptor)
        let defaultVehicle = try ensureDefaultVehicle()
        var migrated = false
        for storedTrip in storedTrips where storedTrip.vehicleID == nil {
            var trip = storedTrip.domainModel
            trip.vehicle = defaultVehicle.snapshot
            storedTrip.update(from: trip)
            migrated = true
        }
        if migrated { try modelContext.save() }
        return storedTrips.map(\.domainModel)
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

    func fetchVehicles() async throws -> [Vehicle] {
        _ = try ensureDefaultVehicle()
        let descriptor = FetchDescriptor<StoredVehicle>(
            sortBy: [SortDescriptor(\.nickname)]
        )
        return try modelContext.fetch(descriptor)
            .map(\.domainModel)
            .sorted {
                $0.isDefault != $1.isDefault
                    ? $0.isDefault
                    : $0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending
            }
    }

    func saveVehicle(_ vehicle: Vehicle) async throws {
        if vehicle.isDefault {
            let defaults = try modelContext.fetch(
                FetchDescriptor<StoredVehicle>(predicate: #Predicate { $0.isDefault })
            )
            for stored in defaults where stored.id != vehicle.id {
                stored.isDefault = false
                stored.updatedAt = .now
            }
        }
        let id = vehicle.id
        var descriptor = FetchDescriptor<StoredVehicle>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            stored.update(from: vehicle)
        } else {
            modelContext.insert(StoredVehicle(vehicle: vehicle))
        }
        try modelContext.save()
    }

    func deleteVehicle(id: UUID, reassignTo vehicle: Vehicle?) async throws {
        var descriptor = FetchDescriptor<StoredVehicle>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let storedVehicle = try modelContext.fetch(descriptor).first else { return }

        if let vehicle {
            let trips = try modelContext.fetch(FetchDescriptor<StoredTrip>())
                .filter { $0.vehicleID == id }
            for storedTrip in trips {
                var trip = storedTrip.domainModel
                trip.vehicle = vehicle.snapshot
                storedTrip.update(from: trip)
            }
        }
        let wasDefault = storedVehicle.isDefault
        modelContext.delete(storedVehicle)
        try modelContext.save()

        if wasDefault {
            let remaining = try modelContext.fetch(FetchDescriptor<StoredVehicle>())
            if let replacement = remaining.first {
                replacement.isDefault = true
                replacement.updatedAt = .now
                try modelContext.save()
            }
        }
    }

    func fetchFrequentPlaces() async throws -> [FrequentPlace] {
        let descriptor = FetchDescriptor<StoredFrequentPlace>(
            sortBy: [SortDescriptor(\.label)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func saveFrequentPlace(_ place: FrequentPlace) async throws {
        let id = place.id
        var descriptor = FetchDescriptor<StoredFrequentPlace>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            stored.update(from: place)
        } else {
            modelContext.insert(StoredFrequentPlace(place: place))
        }
        try modelContext.save()
    }

    func deleteFrequentPlace(id: UUID) async throws {
        var descriptor = FetchDescriptor<StoredFrequentPlace>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            modelContext.delete(stored)
            try modelContext.save()
        }
    }

    func fetchClassificationRules() async throws -> [ClassificationRule] {
        let descriptor = FetchDescriptor<StoredClassificationRule>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func saveClassificationRule(_ rule: ClassificationRule) async throws {
        let id = rule.id
        var descriptor = FetchDescriptor<StoredClassificationRule>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            stored.update(from: rule)
        } else {
            modelContext.insert(StoredClassificationRule(rule: rule))
        }
        try modelContext.save()
    }

    func deleteClassificationRule(id: UUID) async throws {
        var descriptor = FetchDescriptor<StoredClassificationRule>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            modelContext.delete(stored)
            try modelContext.save()
        }
    }

    func deleteAllLocalData() async throws {
        for trip in try modelContext.fetch(FetchDescriptor<StoredTrip>()) {
            modelContext.delete(trip)
        }
        for vehicle in try modelContext.fetch(FetchDescriptor<StoredVehicle>()) {
            modelContext.delete(vehicle)
        }
        for place in try modelContext.fetch(FetchDescriptor<StoredFrequentPlace>()) {
            modelContext.delete(place)
        }
        for rule in try modelContext.fetch(FetchDescriptor<StoredClassificationRule>()) {
            modelContext.delete(rule)
        }
        try modelContext.save()
    }

    private func ensureDefaultVehicle() throws -> Vehicle {
        let existing = try modelContext.fetch(FetchDescriptor<StoredVehicle>())
        let defaults = existing.filter(\.isDefault)
        if let currentDefault = defaults.first {
            for duplicate in defaults.dropFirst() {
                duplicate.isDefault = false
                duplicate.updatedAt = .now
            }
            if defaults.count > 1 { try modelContext.save() }
            return currentDefault.domainModel
        }
        if let first = existing.first {
            first.isDefault = true
            first.updatedAt = .now
            try modelContext.save()
            return first.domainModel
        }
        let vehicle = Vehicle(
            nickname: UserDefaults.standard.string(forKey: "vehicle.nickname") ?? "My Vehicle",
            year: Int(UserDefaults.standard.string(forKey: "vehicle.year") ?? ""),
            make: UserDefaults.standard.string(forKey: "vehicle.make") ?? "",
            model: UserDefaults.standard.string(forKey: "vehicle.model") ?? "",
            isDefault: true
        )
        modelContext.insert(StoredVehicle(vehicle: vehicle))
        try modelContext.save()
        return vehicle
    }
}

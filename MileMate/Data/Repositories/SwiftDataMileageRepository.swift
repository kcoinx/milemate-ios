import Foundation
import SwiftData

@ModelActor
actor SwiftDataMileageRepository: MileageRepository {
    nonisolated let scopeProvider: LocalDataScopeProvider

    init(modelContainer: ModelContainer, scopeProvider: LocalDataScopeProvider) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.scopeProvider = scopeProvider
    }

    func fetchTrips() async throws -> [Trip] {
        let ownerScope = try activeScopeIdentifier()
        let descriptor = FetchDescriptor<StoredTrip>(
            predicate: #Predicate { $0.ownerScope == ownerScope },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let storedTrips = try modelContext.fetch(descriptor)
        let defaultVehicle = try ensureDefaultVehicle(ownerScope: ownerScope)
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
        let ownerScope = try activeScopeIdentifier()
        modelContext.insert(StoredTrip(trip: trip, ownerScope: ownerScope))
        try modelContext.save()
    }

    func update(_ trip: Trip) async throws {
        let ownerScope = try activeScopeIdentifier()
        let id = trip.id
        var descriptor = FetchDescriptor<StoredTrip>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return }
        stored.update(from: trip)
        try modelContext.save()
    }

    func delete(_ trip: Trip) async throws {
        let ownerScope = try activeScopeIdentifier()
        let id = trip.id
        var descriptor = FetchDescriptor<StoredTrip>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(stored)
        try modelContext.save()
    }

    func fetchVehicles() async throws -> [Vehicle] {
        let ownerScope = try activeScopeIdentifier()
        _ = try ensureDefaultVehicle(ownerScope: ownerScope)
        let descriptor = FetchDescriptor<StoredVehicle>(
            predicate: #Predicate { $0.ownerScope == ownerScope },
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
        let ownerScope = try activeScopeIdentifier()
        if vehicle.isDefault {
            let defaults = try modelContext.fetch(
                FetchDescriptor<StoredVehicle>(
                    predicate: #Predicate { $0.isDefault && $0.ownerScope == ownerScope }
                )
            )
            for stored in defaults where stored.id != vehicle.id {
                stored.isDefault = false
                stored.updatedAt = .now
            }
        }
        let id = vehicle.id
        var descriptor = FetchDescriptor<StoredVehicle>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            stored.update(from: vehicle)
        } else {
            modelContext.insert(StoredVehicle(vehicle: vehicle, ownerScope: ownerScope))
        }
        try modelContext.save()
    }

    func deleteVehicle(id: UUID, reassignTo vehicle: Vehicle?) async throws {
        let ownerScope = try activeScopeIdentifier()
        var descriptor = FetchDescriptor<StoredVehicle>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        guard let storedVehicle = try modelContext.fetch(descriptor).first else { return }

        if let vehicle {
            let trips = try modelContext.fetch(
                FetchDescriptor<StoredTrip>(predicate: #Predicate { $0.ownerScope == ownerScope })
            )
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
            let remaining = try modelContext.fetch(
                FetchDescriptor<StoredVehicle>(predicate: #Predicate { $0.ownerScope == ownerScope })
            )
            if let replacement = remaining.first {
                replacement.isDefault = true
                replacement.updatedAt = .now
                try modelContext.save()
            }
        }
    }

    func fetchFrequentPlaces() async throws -> [FrequentPlace] {
        let ownerScope = try activeScopeIdentifier()
        let descriptor = FetchDescriptor<StoredFrequentPlace>(
            predicate: #Predicate { $0.ownerScope == ownerScope },
            sortBy: [SortDescriptor(\.label)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func saveFrequentPlace(_ place: FrequentPlace) async throws {
        let ownerScope = try activeScopeIdentifier()
        let id = place.id
        var descriptor = FetchDescriptor<StoredFrequentPlace>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            stored.update(from: place)
        } else {
            modelContext.insert(StoredFrequentPlace(place: place, ownerScope: ownerScope))
        }
        try modelContext.save()
    }

    func deleteFrequentPlace(id: UUID) async throws {
        let ownerScope = try activeScopeIdentifier()
        var descriptor = FetchDescriptor<StoredFrequentPlace>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            modelContext.delete(stored)
            try modelContext.save()
        }
    }

    func fetchClassificationRules() async throws -> [ClassificationRule] {
        let ownerScope = try activeScopeIdentifier()
        let descriptor = FetchDescriptor<StoredClassificationRule>(
            predicate: #Predicate { $0.ownerScope == ownerScope },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map(\.domainModel)
    }

    func saveClassificationRule(_ rule: ClassificationRule) async throws {
        let ownerScope = try activeScopeIdentifier()
        let id = rule.id
        var descriptor = FetchDescriptor<StoredClassificationRule>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            stored.update(from: rule)
        } else {
            modelContext.insert(StoredClassificationRule(rule: rule, ownerScope: ownerScope))
        }
        try modelContext.save()
    }

    func deleteClassificationRule(id: UUID) async throws {
        let ownerScope = try activeScopeIdentifier()
        var descriptor = FetchDescriptor<StoredClassificationRule>(
            predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope }
        )
        descriptor.fetchLimit = 1
        if let stored = try modelContext.fetch(descriptor).first {
            modelContext.delete(stored)
            try modelContext.save()
        }
    }

    func deleteAllLocalData() async throws {
        let ownerScope = try activeScopeIdentifier()
        for trip in try modelContext.fetch(
            FetchDescriptor<StoredTrip>(predicate: #Predicate { $0.ownerScope == ownerScope })
        ) {
            modelContext.delete(trip)
        }
        for vehicle in try modelContext.fetch(
            FetchDescriptor<StoredVehicle>(predicate: #Predicate { $0.ownerScope == ownerScope })
        ) {
            modelContext.delete(vehicle)
        }
        for place in try modelContext.fetch(
            FetchDescriptor<StoredFrequentPlace>(predicate: #Predicate { $0.ownerScope == ownerScope })
        ) {
            modelContext.delete(place)
        }
        for rule in try modelContext.fetch(
            FetchDescriptor<StoredClassificationRule>(predicate: #Predicate { $0.ownerScope == ownerScope })
        ) {
            modelContext.delete(rule)
        }
        try modelContext.save()
    }

    func migrateLocalData(from source: LocalDataScope, to destination: LocalDataScope) async throws {
        guard source != destination else { return }
        let sourceID = source.identifier
        let destinationID = destination.identifier
        for model in try modelContext.fetch(
            FetchDescriptor<StoredTrip>(predicate: #Predicate { $0.ownerScope == sourceID })
        ) { model.ownerScope = destinationID }
        for model in try modelContext.fetch(
            FetchDescriptor<StoredVehicle>(predicate: #Predicate { $0.ownerScope == sourceID })
        ) { model.ownerScope = destinationID }
        for model in try modelContext.fetch(
            FetchDescriptor<StoredFrequentPlace>(predicate: #Predicate { $0.ownerScope == sourceID })
        ) { model.ownerScope = destinationID }
        for model in try modelContext.fetch(
            FetchDescriptor<StoredClassificationRule>(predicate: #Predicate { $0.ownerScope == sourceID })
        ) { model.ownerScope = destinationID }
        try modelContext.save()
    }

    private func ensureDefaultVehicle(ownerScope: String) throws -> Vehicle {
        let existing = try modelContext.fetch(
            FetchDescriptor<StoredVehicle>(predicate: #Predicate { $0.ownerScope == ownerScope })
        )
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
        modelContext.insert(StoredVehicle(vehicle: vehicle, ownerScope: ownerScope))
        try modelContext.save()
        return vehicle
    }

    private func activeScopeIdentifier() throws -> String {
        guard let scope = scopeProvider.current else { throw LocalDataScopeError.noActiveAccount }
        return scope.identifier
    }

}

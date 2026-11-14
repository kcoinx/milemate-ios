import Foundation

struct LocalDataScope: Hashable, Sendable {
    let identifier: String

    static func authenticated(userID: String) -> Self {
        Self(identifier: "account:\(userID)")
    }

    static func guest(id: UUID) -> Self {
        Self(identifier: "guest:\(id.uuidString.lowercased())")
    }
}

final class LocalDataScopeProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var storedScope: LocalDataScope?

    init(scope: LocalDataScope? = nil) {
        storedScope = scope
    }

    var current: LocalDataScope? {
        lock.withLock { storedScope }
    }

    func setCurrent(_ scope: LocalDataScope?) {
        lock.withLock { storedScope = scope }
    }
}

enum LocalDataScopeError: LocalizedError {
    case noActiveAccount

    var errorDescription: String? {
        "Choose a MileMate account or guest session before accessing mileage data."
    }
}

protocol MileageRepository: Sendable {
    func fetchTrips() async throws -> [Trip]
    func fetchSummary() async throws -> MileageSummary
    func fetchProfile() async throws -> UserProfile
    func save(_ trip: Trip) async throws
    func update(_ trip: Trip) async throws
    func delete(_ trip: Trip) async throws
    func fetchVehicles() async throws -> [Vehicle]
    func saveVehicle(_ vehicle: Vehicle) async throws
    func deleteVehicle(id: UUID, reassignTo vehicle: Vehicle?) async throws
    func fetchFrequentPlaces() async throws -> [FrequentPlace]
    func saveFrequentPlace(_ place: FrequentPlace) async throws
    func deleteFrequentPlace(id: UUID) async throws
    func fetchClassificationRules() async throws -> [ClassificationRule]
    func saveClassificationRule(_ rule: ClassificationRule) async throws
    func deleteClassificationRule(id: UUID) async throws
    func deleteAllLocalData() async throws
    func migrateLocalData(from source: LocalDataScope, to destination: LocalDataScope) async throws
}

extension MileageRepository {
    func fetchVehicles() async throws -> [Vehicle] { [] }
    func saveVehicle(_ vehicle: Vehicle) async throws {}
    func deleteVehicle(id: UUID, reassignTo vehicle: Vehicle?) async throws {}
    func fetchFrequentPlaces() async throws -> [FrequentPlace] { [] }
    func saveFrequentPlace(_ place: FrequentPlace) async throws {}
    func deleteFrequentPlace(id: UUID) async throws {}
    func fetchClassificationRules() async throws -> [ClassificationRule] { [] }
    func saveClassificationRule(_ rule: ClassificationRule) async throws {}
    func deleteClassificationRule(id: UUID) async throws {}
    func deleteAllLocalData() async throws {}
    func migrateLocalData(from source: LocalDataScope, to destination: LocalDataScope) async throws {}
}

extension Notification.Name {
    static let mileageTripsDidChange = Notification.Name("MileMate.mileageTripsDidChange")
    static let mileageVehiclesDidChange = Notification.Name("MileMate.mileageVehiclesDidChange")
    static let mileageClassificationDataDidChange =
        Notification.Name("MileMate.mileageClassificationDataDidChange")
}

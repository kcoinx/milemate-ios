import SwiftData

@MainActor
struct AppDependencies {
    let mileageRepository: any MileageRepository
    let locationService: any LocationService
    let modelContainer: ModelContainer

    static func live() -> AppDependencies {
        do {
            let container = try ModelContainer(for: StoredTrip.self)
            return AppDependencies(
                mileageRepository: MockMileageRepository(),
                locationService: InactiveLocationService(),
                modelContainer: container
            )
        } catch {
            fatalError("Unable to initialize MileMate storage: \(error.localizedDescription)")
        }
    }
}


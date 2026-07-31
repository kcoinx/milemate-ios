import SwiftData

@MainActor
struct AppDependencies {
    let mileageRepository: any MileageRepository
    let locationService: any LocationService
    let tripCoordinator: ManualTripCoordinator
    let modelContainer: ModelContainer

    static func live() -> AppDependencies {
        do {
            let container = try ModelContainer(for: StoredTrip.self)
            let repository = SwiftDataMileageRepository(modelContainer: container)
            let locationService = CoreLocationService()
            return AppDependencies(
                mileageRepository: repository,
                locationService: locationService,
                tripCoordinator: ManualTripCoordinator(
                    locationService: locationService,
                    repository: repository
                ),
                modelContainer: container
            )
        } catch {
            fatalError("Unable to initialize MileMate storage: \(error.localizedDescription)")
        }
    }
}

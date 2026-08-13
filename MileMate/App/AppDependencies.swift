import SwiftData

@MainActor
struct AppDependencies {
    let mileageRepository: any MileageRepository
    let locationService: any LocationService
    let tripCoordinator: ManualTripCoordinator
    let automaticTripCoordinator: AutomaticTripCoordinator
    let notificationService: any TripNotificationScheduling
    let router: AppRouter
    let modelContainer: ModelContainer

    static func live() -> AppDependencies {
        TripNotificationSettings.registerDefaults()
        do {
            let container = try ModelContainer(
                for: StoredTrip.self,
                StoredVehicle.self,
                StoredFrequentPlace.self,
                StoredClassificationRule.self
            )
            let repository = SwiftDataMileageRepository(modelContainer: container)
            let locationService = CoreLocationService()
            let notificationService = LocalTripNotificationService(repository: repository)
            let manualCoordinator = ManualTripCoordinator(
                locationService: locationService,
                repository: repository,
                notificationService: notificationService
            )
            let automaticCoordinator = AutomaticTripCoordinator(
                locationService: CoreAutomaticLocationService(),
                motionService: CoreMotionActivityService(),
                repository: repository,
                notificationService: notificationService,
                isManualTrackingActive: {
                    switch manualCoordinator.state {
                    case .requestingPermission, .tracking, .reviewing:
                        true
                    case .ready, .permissionDenied, .failed:
                        false
                    }
                }
            )
            let appRouter = AppRouter(
                repository: repository,
                automaticTripCoordinator: automaticCoordinator
            )
            automaticCoordinator.startIfEnabled()
            return AppDependencies(
                mileageRepository: repository,
                locationService: locationService,
                tripCoordinator: manualCoordinator,
                automaticTripCoordinator: automaticCoordinator,
                notificationService: notificationService,
                router: appRouter,
                modelContainer: container
            )
        } catch {
            fatalError("Unable to initialize MileMate storage: \(error.localizedDescription)")
        }
    }
}

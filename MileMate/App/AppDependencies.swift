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
        do {
            let container = try ModelContainer(for: StoredTrip.self)
            let repository = SwiftDataMileageRepository(modelContainer: container)
            let locationService = CoreLocationService()
            let manualCoordinator = ManualTripCoordinator(
                locationService: locationService,
                repository: repository
            )
            let notificationService = LocalTripNotificationService()
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

import SwiftData

@MainActor
struct AppDependencies {
    let mileageRepository: any MileageRepository
    let locationService: any LocationService
    let tripCoordinator: ManualTripCoordinator
    let automaticTripCoordinator: AutomaticTripCoordinator
    let notificationService: any TripNotificationScheduling
    let accountSession: AccountSessionController
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
            let dataScopeProvider = LocalDataScopeProvider()
            let repository = SwiftDataMileageRepository(
                modelContainer: container,
                scopeProvider: dataScopeProvider
            )
            let locationService = CoreLocationService()
            let notificationService = LocalTripNotificationService(repository: repository)
            let accountSession = AccountSessionController(
                repository: repository,
                dataScopeProvider: dataScopeProvider
            )
            let manualCoordinator = ManualTripCoordinator(
                locationService: locationService,
                repository: repository,
                notificationService: notificationService,
                canStartNewTrip: { accountSession.requestTrackingAccess() },
                tripDidSave: { trip in accountSession.recordSavedTrip(trip) }
            )
            let automaticCoordinator = AutomaticTripCoordinator(
                locationService: CoreAutomaticLocationService(),
                motionService: CoreMotionActivityService(),
                repository: repository,
                notificationService: notificationService,
                canStartNewTrip: { accountSession.requestTrackingAccess() },
                tripDidSave: { trip in accountSession.recordSavedTrip(trip) },
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
                accountSession: accountSession,
                router: appRouter,
                modelContainer: container
            )
        } catch {
            fatalError("Unable to initialize MileMate storage: \(error.localizedDescription)")
        }
    }
}

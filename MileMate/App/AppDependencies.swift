import SwiftData

@MainActor
struct AppDependencies {
    let mileageRepository: any MileageRepository
    let locationService: any LocationService
    let tripCoordinator: ManualTripCoordinator
    let automaticTripCoordinator: AutomaticTripCoordinator
    let notificationService: any TripNotificationScheduling
    let purchaseManager: PurchaseManager
    let accountSession: AccountSessionController
    let router: AppRouter
    let modelContainer: ModelContainer

    static func live() -> AppDependencies {
        TripNotificationSettings.registerDefaults()
        DistanceUnitSettings.registerDefault()
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
            let purchaseManager = PurchaseManager()
            let accountSession = AccountSessionController(
                repository: repository,
                dataScopeProvider: repository.scopeProvider,
                proEntitlementProvider: purchaseManager
            )
            let manualCoordinator = ManualTripCoordinator(
                locationService: locationService,
                repository: repository,
                notificationService: notificationService,
                canStartNewTrip: { accountSession.requestTrackingAccess() },
                tripDidSave: { trip in accountSession.recordSavedTrip(trip) },
                dataScopeProvider: repository.scopeProvider
            )
            let automaticCoordinator = AutomaticTripCoordinator(
                locationService: CoreAutomaticLocationService(),
                motionService: CoreMotionActivityService(),
                repository: repository,
                notificationService: notificationService,
                canStartNewTrip: { accountSession.requestTrackingAccess() },
                tripDidSave: { trip in accountSession.recordSavedTrip(trip) },
                dataScopeProvider: repository.scopeProvider,
                isManualTrackingActive: {
                    switch manualCoordinator.state {
                    case .requestingPermission, .tracking, .reviewing:
                        true
                    case .ready, .permissionDenied, .failed:
                        false
                    }
                }
            )
            accountSession.configureSessionTransitionGuard {
                !manualCoordinator.hasProtectedTripState &&
                    !automaticCoordinator.hasProtectedTripState
            }
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
                purchaseManager: purchaseManager,
                accountSession: accountSession,
                router: appRouter,
                modelContainer: container
            )
        } catch {
            fatalError("Unable to initialize MileMate storage: \(error.localizedDescription)")
        }
    }
}

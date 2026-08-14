import Foundation

@MainActor
enum MileMatePreferenceKeys {
    static let resettable = [
        "appAppearance",
        AutomaticTrackingSettings.enabledKey,
        AutomaticTrackingSettings.minimumDistanceKey,
        TripNotificationSettings.completionEnabledKey,
        TripNotificationSettings.remindersEnabledKey,
        ClassificationSettings.automaticRulesEnabledKey,
        TripFeedbackSettings.enabledKey,
        MileageSettings.rateKey,
        MileageSettings.taxRateKey,
        "vehicle.nickname",
        "vehicle.year",
        "vehicle.make",
        "vehicle.model",
        "manualActiveTrip",
        "automaticActiveTrip",
        "automaticPendingTrip"
    ]
}

@MainActor
final class LocalDataDeletionService {
    private let repository: any MileageRepository
    private let manualCoordinator: ManualTripCoordinator
    private let automaticCoordinator: AutomaticTripCoordinator
    private let notificationService: any TripNotificationScheduling
    private let defaults: UserDefaults

    init(
        repository: any MileageRepository,
        manualCoordinator: ManualTripCoordinator,
        automaticCoordinator: AutomaticTripCoordinator,
        notificationService: any TripNotificationScheduling,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.manualCoordinator = manualCoordinator
        self.automaticCoordinator = automaticCoordinator
        self.notificationService = notificationService
        self.defaults = defaults
    }

    func deleteAllData() async throws {
        manualCoordinator.prepareForLocalDataDeletion()
        automaticCoordinator.prepareForLocalDataDeletion()
        notificationService.cancelAllTripNotifications()
        try await repository.deleteAllLocalData()
        for key in MileMatePreferenceKeys.resettable {
            defaults.removeObject(forKey: key)
        }
        TripNotificationSettings.registerDefaults(in: defaults)
        NotificationCenter.default.post(name: .mileageTripsDidChange, object: nil)
        NotificationCenter.default.post(name: .mileageVehiclesDidChange, object: nil)
        NotificationCenter.default.post(name: .mileageClassificationDataDidChange, object: nil)
    }
}

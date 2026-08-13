@preconcurrency import UserNotifications
import Foundation

enum TripNotificationCopy {
    static let completionTitle = "Trip Complete"
    static let reviewTitle = "Trips Waiting for Review"

    static func completionBody(for trip: Trip) -> String {
        let miles = trip.distanceMiles.formatted(.number.precision(.fractionLength(1)))
        if trip.classification == .unclassified {
            return "\(miles) miles recorded. Tap to review."
        }
        return "\(miles) miles recorded and classified as \(trip.classification.rawValue)."
    }

    static func reviewBody(count: Int) -> String {
        count == 1
            ? "1 trip is waiting for review. Tap to classify it."
            : "\(count) trips are waiting for review. Tap to classify them."
    }
}

enum ReviewReminderSchedule {
    static func nextDate(
        after date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components) ?? tomorrow
    }
}

enum TripNotificationSettings {
    static let completionEnabledKey = "tripDetectedNotificationsEnabled"
    static let remindersEnabledKey = "tripReviewRemindersEnabled"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            completionEnabledKey: true,
            remindersEnabledKey: true
        ])
    }

    static var completionNotificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: completionEnabledKey)
    }

    static var remindersEnabled: Bool {
        UserDefaults.standard.bool(forKey: remindersEnabledKey)
    }
}

struct TripNotificationDeliveryPlan: Equatable {
    let sendsTripDetected: Bool
    let sendsReviewReminder: Bool

    static func make(
        authorizationStatus: NotificationPermissionStatus,
        tripDetectedEnabled: Bool,
        reviewRemindersEnabled: Bool
    ) -> TripNotificationDeliveryPlan {
        let authorized = authorizationStatus.allowsScheduling
        return TripNotificationDeliveryPlan(
            sendsTripDetected: authorized && tripDetectedEnabled,
            sendsReviewReminder: authorized && reviewRemindersEnabled
        )
    }

    static func current(
        authorizationStatus: NotificationPermissionStatus
    ) -> TripNotificationDeliveryPlan {
        make(
            authorizationStatus: authorizationStatus,
            tripDetectedEnabled: TripNotificationSettings.completionNotificationsEnabled,
            reviewRemindersEnabled: TripNotificationSettings.remindersEnabled
        )
    }
}

enum NotificationSettingsRecovery: Equatable {
    case none
    case requestPermission
    case openSystemSettings

    init(status: NotificationPermissionStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral:
            self = .none
        case .notDetermined:
            self = .requestPermission
        case .denied, .unavailable:
            self = .openSystemSettings
        }
    }
}

enum NotificationPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral
    case unavailable
}

@MainActor
protocol TripNotificationScheduling: AnyObject {
    var authorizationStatus: NotificationPermissionStatus { get }

    func refreshAuthorizationStatus() async
    func requestAuthorization() async
    func scheduleTripCompletion(for trip: Trip) async
    func reconcileReviewReminder() async
    func cancelNotifications(for tripID: UUID)
    func cancelCompletionNotifications()
    func cancelReminderNotifications()
    func cancelAllTripNotifications()
    func scheduleLongRunningTripReminder(after delay: TimeInterval) async
    func cancelLongRunningTripReminder()
}

@MainActor
final class LocalTripNotificationService: TripNotificationScheduling {
    private enum Identifier {
        static let activeTrip = "active-trip-reminder"
        static let reviewQueue = "review-queue-reminder"
        static func completion(_ tripID: UUID) -> String {
            "trip-completion-\(tripID.uuidString)"
        }

        static func reminder(_ tripID: UUID) -> String {
            "trip-reminder-\(tripID.uuidString)"
        }
    }

    private let center: UNUserNotificationCenter
    private let repository: any MileageRepository
    private var scheduledCompletionTripIDs: Set<UUID> = []
    private var scheduledReminderTripIDs: Set<UUID> = []
    private(set) var authorizationStatus: NotificationPermissionStatus = .notDetermined

    init(
        center: UNUserNotificationCenter = .current(),
        repository: any MileageRepository
    ) {
        self.center = center
        self.repository = repository
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Notification permission never controls automatic trip tracking.
        }
        await refreshAuthorizationStatus()
        if authorizationStatus.allowsScheduling,
           TripNotificationSettings.remindersEnabled {
            await reconcileReviewReminder()
        }
    }

    func scheduleTripCompletion(for trip: Trip) async {
        await refreshAuthorizationStatus()
        let deliveryPlan = TripNotificationDeliveryPlan.current(
            authorizationStatus: authorizationStatus
        )
        guard deliveryPlan.sendsTripDetected || deliveryPlan.sendsReviewReminder else { return }

        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let existingIdentifiers = Set(
            pending.map(\.identifier) + delivered.map { $0.request.identifier }
        )
        let userInfo = [TripNotificationUserInfo.tripIDKey: trip.id.uuidString]

        if deliveryPlan.sendsTripDetected {
            let identifier = Identifier.completion(trip.id)
            if !scheduledCompletionTripIDs.contains(trip.id),
               !existingIdentifiers.contains(identifier) {
                let content = UNMutableNotificationContent()
                content.title = TripNotificationCopy.completionTitle
                content.body = TripNotificationCopy.completionBody(for: trip)
                content.sound = .default
                content.categoryIdentifier = TripNotificationUserInfo.categoryIdentifier
                content.userInfo = userInfo
                try? await center.add(
                    UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
                )
                scheduledCompletionTripIDs.insert(trip.id)
            }
        }

        if deliveryPlan.sendsReviewReminder { await reconcileReviewReminder() }
    }

    func reconcileReviewReminder() async {
        await refreshAuthorizationStatus()
        let deliveryPlan = TripNotificationDeliveryPlan.current(
            authorizationStatus: authorizationStatus
        )
        guard deliveryPlan.sendsReviewReminder else {
            cancelReminderNotifications()
            return
        }
        let trips = (try? await repository.fetchTrips()) ?? []
        let count = ReviewQueueService.pendingTrips(from: trips).count
        let pendingRequests = await center.pendingNotificationRequests()
        let deliveredNotifications = await center.deliveredNotifications()
        let legacyPendingIDs = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix("trip-reminder-") }
        let legacyDeliveredIDs = deliveredNotifications
            .map { $0.request.identifier }
            .filter { $0.hasPrefix("trip-reminder-") }
        center.removePendingNotificationRequests(withIdentifiers: legacyPendingIDs)
        center.removeDeliveredNotifications(withIdentifiers: legacyDeliveredIDs)
        let existingReminderDate = pendingRequests
            .first(where: { $0.identifier == Identifier.reviewQueue })
            .flatMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.reviewQueue])
        guard count > 0 else {
            center.removeDeliveredNotifications(withIdentifiers: [Identifier.reviewQueue])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = TripNotificationCopy.reviewTitle
        content.body = TripNotificationCopy.reviewBody(count: count)
        content.sound = .default
        content.categoryIdentifier = TripNotificationUserInfo.categoryIdentifier
        content.userInfo = [TripNotificationUserInfo.reviewQueueKey: true]
        let calendar = Calendar.autoupdatingCurrent
        let reminderDate = existingReminderDate
            ?? ReviewReminderSchedule.nextDate(calendar: calendar)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(
            UNNotificationRequest(identifier: Identifier.reviewQueue, content: content, trigger: trigger)
        )
    }

    func cancelNotifications(for tripID: UUID) {
        let identifiers = [
            Identifier.completion(tripID),
            Identifier.reminder(tripID)
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        scheduledCompletionTripIDs.remove(tripID)
        scheduledReminderTripIDs.remove(tripID)
    }

    func cancelAllTripNotifications() {
        scheduledCompletionTripIDs.removeAll()
        scheduledReminderTripIDs.removeAll()
        cancelLongRunningTripReminder()
        cancelPendingAndDeliveredNotifications { identifier in
            identifier.hasPrefix("trip-completion-") ||
                identifier.hasPrefix("trip-reminder-") ||
                identifier == Identifier.reviewQueue ||
                identifier == Identifier.activeTrip
        }
    }

    func cancelCompletionNotifications() {
        scheduledCompletionTripIDs.removeAll()
        cancelPendingAndDeliveredNotifications { $0.hasPrefix("trip-completion-") }
    }

    func cancelReminderNotifications() {
        scheduledReminderTripIDs.removeAll()
        cancelPendingAndDeliveredNotifications {
            $0.hasPrefix("trip-reminder-") || $0 == Identifier.reviewQueue
        }
    }

    func scheduleLongRunningTripReminder(after delay: TimeInterval) async {
        await refreshAuthorizationStatus()
        guard authorizationStatus.allowsScheduling else { return }
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.activeTrip])
        let content = UNMutableNotificationContent()
        content.title = "Still driving?"
        content.body = "MileMate is still recording this trip. Open the app to review or stop tracking."
        content.sound = .default
        content.categoryIdentifier = TripNotificationUserInfo.activeTripCategoryIdentifier
        content.userInfo = [TripNotificationUserInfo.activeTripKey: true]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(delay, 60),
            repeats: false
        )
        try? await center.add(
            UNNotificationRequest(
                identifier: Identifier.activeTrip,
                content: content,
                trigger: trigger
            )
        )
        TrackingDiagnostics.log("long-running trip notification scheduled")
    }

    func cancelLongRunningTripReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.activeTrip])
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.activeTrip])
    }

    private func cancelPendingNotifications(
        matching predicate: @escaping @Sendable (String) -> Bool
    ) {
        Task {
            let pending = await center.pendingNotificationRequests()
            let identifiers = pending.map(\.identifier).filter(predicate)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private func cancelPendingAndDeliveredNotifications(
        matching predicate: @escaping @Sendable (String) -> Bool
    ) {
        Task {
            async let pending = center.pendingNotificationRequests()
            async let delivered = center.deliveredNotifications()
            let pendingIDs = (await pending).map(\.identifier).filter(predicate)
            let deliveredIDs = (await delivered).map { $0.request.identifier }.filter(predicate)
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationPermissionStatus {
        switch status {
        case UNAuthorizationStatus.notDetermined:
            return NotificationPermissionStatus.notDetermined
        case UNAuthorizationStatus.denied:
            return NotificationPermissionStatus.denied
        case UNAuthorizationStatus.authorized:
            return NotificationPermissionStatus.authorized
        case UNAuthorizationStatus.provisional:
            return NotificationPermissionStatus.provisional
        case UNAuthorizationStatus.ephemeral:
            return NotificationPermissionStatus.ephemeral
        @unknown default:
            return NotificationPermissionStatus.unavailable
        }
    }
}

extension NotificationPermissionStatus {
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unavailable:
            return false
        }
    }
}

enum TripNotificationUserInfo {
    static let tripIDKey = "tripID"
    static let categoryIdentifier = "MILEMATE_TRIP_REVIEW"
    static let activeTripKey = "activeTrip"
    static let activeTripCategoryIdentifier = "MILEMATE_ACTIVE_TRIP"
    static let reviewQueueKey = "reviewQueue"
}

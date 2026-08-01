@preconcurrency import UserNotifications
import UIKit

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var tripTapHandler: (@MainActor (UUID) -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.content.categoryIdentifier ==
            TripNotificationUserInfo.categoryIdentifier {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let value = response.notification.request.content.userInfo[TripNotificationUserInfo.tripIDKey]
        guard let tripIDString = value as? String,
              let tripID = UUID(uuidString: tripIDString) else {
            return
        }
        Task { @MainActor [weak self] in
            self?.tripTapHandler?(tripID)
        }
    }
}

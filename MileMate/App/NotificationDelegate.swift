import UserNotifications
import UIKit

final class NotificationDelegate: NSObject, UIApplicationDelegate {
    private let routeHandler = NotificationRouteHandler()
    private lazy var userNotificationDelegate = UserNotificationDelegate(
        routeHandler: routeHandler
    )

    var tripTapHandler: (@MainActor (UUID) -> Void)? {
        get { routeHandler.tripTapHandler }
        set { routeHandler.tripTapHandler = newValue }
    }
    var activeTripTapHandler: (@MainActor () -> Void)? {
        get { routeHandler.activeTripTapHandler }
        set { routeHandler.activeTripTapHandler = newValue }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = userNotificationDelegate
        return true
    }
}

@MainActor
private final class NotificationRouteHandler {
    var tripTapHandler: (@MainActor (UUID) -> Void)?
    var activeTripTapHandler: (@MainActor () -> Void)?

    func route(to tripID: UUID) {
        tripTapHandler?(tripID)
    }

    func routeToActiveTrip() {
        activeTripTapHandler?()
    }
}

private final class UserNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let routeHandler: NotificationRouteHandler

    init(routeHandler: NotificationRouteHandler) {
        self.routeHandler = routeHandler
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let options: UNNotificationPresentationOptions =
            notification.request.content.categoryIdentifier ==
            TripNotificationUserInfo.categoryIdentifier
            ? []
            : [.banner, .sound]
        completionHandler(options)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let value = response.notification.request.content.userInfo[TripNotificationUserInfo.tripIDKey]
        let tripID = (value as? String).flatMap(UUID.init(uuidString:))
        let isActiveTrip = response.notification.request.content.userInfo[
            TripNotificationUserInfo.activeTripKey
        ] as? Bool == true
        completionHandler()

        guard tripID != nil || isActiveTrip else {
            return
        }
        Task { @MainActor [routeHandler] in
            if isActiveTrip {
                routeHandler.routeToActiveTrip()
            } else if let tripID {
                routeHandler.route(to: tripID)
            }
        }
    }
}

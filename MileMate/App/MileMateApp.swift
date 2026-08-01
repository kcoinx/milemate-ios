import SwiftData
import SwiftUI
import UIKit

@main
@MainActor
struct MileMateApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self)
    private var notificationDelegate
    private let dependencies: AppDependencies

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        notificationDelegate.tripTapHandler = { tripID in
            Task {
                await dependencies.router.handleNotificationTap(tripID: tripID)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppTabView(dependencies: dependencies)
        }
        .modelContainer(dependencies.modelContainer)
    }
}

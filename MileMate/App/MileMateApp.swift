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
        notificationDelegate.activeTripTapHandler = {
            dependencies.router.selectedTab = .dashboard
        }
        notificationDelegate.reviewQueueTapHandler = {
            dependencies.router.showReviewQueue()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppTabView(dependencies: dependencies)
        }
        .modelContainer(dependencies.modelContainer)
    }
}

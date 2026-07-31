import SwiftData
import SwiftUI

@main
@MainActor
struct MileMateApp: App {
    private let dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            AppTabView(dependencies: dependencies)
        }
        .modelContainer(dependencies.modelContainer)
    }
}

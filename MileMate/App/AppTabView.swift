import SwiftUI

struct AppTabView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .dashboard
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $selection) {
            tab(.dashboard) {
                DashboardView(
                    repository: dependencies.mileageRepository,
                    tripCoordinator: dependencies.tripCoordinator
                )
            }
            tab(.trips) { TripsView(repository: dependencies.mileageRepository) }
            tab(.reports) { ReportsView(repository: dependencies.mileageRepository) }
            tab(.insights) { InsightsView(repository: dependencies.mileageRepository) }
            tab(.settings) { SettingsView(repository: dependencies.mileageRepository) }
        }
        .tint(AppTheme.Color.brand)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                dependencies.tripCoordinator.appDidEnterBackground()
            }
        }
    }

    @ViewBuilder
    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tabItem {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolVariant(selection == tab ? .fill : .none)
                    .scaleEffect(selection == tab ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selection)
            }
        }
        .tag(tab)
    }
}

private enum AppTab: Hashable {
    case dashboard, trips, reports, insights, settings

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .trips: "Trips"
        case .reports: "Reports"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .trips: "car"
        case .reports: "doc.text"
        case .insights: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }
}

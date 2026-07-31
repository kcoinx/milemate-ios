import SwiftUI

struct AppTabView: View {
    @State private var selection: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            tab(.dashboard) { DashboardView() }
            tab(.trips) { TripsView() }
            tab(.reports) { ReportsView() }
            tab(.insights) { InsightsView() }
            tab(.settings) { SettingsView() }
        }
        .tint(AppTheme.Color.brand)
    }

    @ViewBuilder
    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
        }
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
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
        case .trips: "car.fill"
        case .reports: "doc.text.fill"
        case .insights: "chart.xyaxis.line"
        case .settings: "gearshape.fill"
        }
    }
}

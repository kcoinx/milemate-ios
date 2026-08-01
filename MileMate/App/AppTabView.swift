import SwiftUI

struct AppTabView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var router: AppRouter
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _router = Bindable(wrappedValue: dependencies.router)
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            tab(.dashboard) {
                DashboardView(
                    repository: dependencies.mileageRepository,
                    tripCoordinator: dependencies.tripCoordinator,
                    automaticTripCoordinator: dependencies.automaticTripCoordinator,
                    notificationService: dependencies.notificationService
                )
            }
            tab(.trips) {
                TripsView(
                    repository: dependencies.mileageRepository,
                    requestedTrip: $router.requestedTrip,
                    notificationService: dependencies.notificationService
                )
            }
            tab(.reports) { ReportsView(repository: dependencies.mileageRepository) }
            tab(.insights) { InsightsView(repository: dependencies.mileageRepository) }
            tab(.settings) {
                SettingsView(
                    repository: dependencies.mileageRepository,
                    automaticTripCoordinator: dependencies.automaticTripCoordinator,
                    notificationService: dependencies.notificationService
                )
            }
        }
        .tint(AppTheme.Color.brand)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .mileageTripsDidChange)) { notification in
            guard let tripID = notification.object as? UUID else { return }
            Task {
                let trips = (try? await dependencies.mileageRepository.fetchTrips()) ?? []
                if let trip = trips.first(where: { $0.id == tripID }),
                   trip.classification != .unclassified {
                    dependencies.notificationService.cancelNotifications(for: tripID)
                }
            }
        }
        .onChange(of: dependencies.automaticTripCoordinator.pendingTrip?.id) { _, tripID in
            if tripID != nil {
                router.showAutomaticTripReview()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                dependencies.tripCoordinator.appDidEnterBackground()
            case .active:
                dependencies.automaticTripCoordinator.startIfEnabled()
            case .inactive:
                break
            @unknown default:
                break
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
                    .symbolVariant(router.selectedTab == tab ? .fill : .none)
                    .scaleEffect(router.selectedTab == tab ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: router.selectedTab)
            }
        }
        .tag(tab)
    }
}

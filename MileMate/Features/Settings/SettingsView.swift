import CoreLocation
import SwiftUI
import UIKit

enum ManualTrackingRowState: Equatable {
    case actionable
    case automaticModeActive

    init(automaticTrackingEnabled: Bool) {
        self = automaticTrackingEnabled ? .automaticModeActive : .actionable
    }

    var isActionable: Bool { self == .actionable }
}

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Bindable private var automaticTripCoordinator: AutomaticTripCoordinator
    private let notificationService: any TripNotificationScheduling
    private let router: AppRouter
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(AutomaticTrackingSettings.enabledKey) private var automaticTrackingEnabled = false
    @AppStorage(AutomaticTrackingSettings.minimumDistanceKey)
    private var automaticMinimumDistance = AutomaticTrackingSettings.defaultMinimumDistance
    @AppStorage(TripNotificationSettings.completionEnabledKey, store: .standard)
    private var tripDetectedNotificationsEnabled = true
    @AppStorage(TripNotificationSettings.remindersEnabledKey, store: .standard)
    private var tripReviewRemindersEnabled = true
    @AppStorage(ClassificationSettings.automaticRulesEnabledKey)
    private var automaticClassificationEnabled = false
    @State private var showingAutomaticTrackingExplanation = false
    @State private var notificationPermissionStatus = NotificationPermissionStatus.notDetermined
    @AppStorage(TripFeedbackSettings.enabledKey) private var tripFeedbackEnabled = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(
        repository: any MileageRepository,
        automaticTripCoordinator: AutomaticTripCoordinator,
        notificationService: any TripNotificationScheduling,
        router: AppRouter
    ) {
        _viewModel = State(initialValue: SettingsViewModel(repository: repository))
        _automaticTripCoordinator = Bindable(wrappedValue: automaticTripCoordinator)
        self.notificationService = notificationService
        self.router = router
    }

    var body: some View {
        List {
            profileSection

            settingsSection("Tracking") {
                Toggle(isOn: automaticTrackingBinding) {
                    settingLabel(
                        "Automatic Tracking (Recommended)",
                        icon: "location.fill",
                        tint: AppTheme.Color.brand
                    )
                }
                .disabled(
                    automaticTripCoordinator.state == .tracking ||
                    automaticTripCoordinator.state == .reviewing
                )

                if manualTrackingRowState == .automaticModeActive {
                    LabeledContent {
                        Text("Switch modes to use")
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    } label: {
                        settingLabel("Manual Tracking", icon: "play.circle.fill", tint: AppTheme.Color.brand)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Button {
                        router.showManualTracking()
                    } label: {
                        HStack {
                            settingLabel("Manual Tracking", icon: "play.circle.fill", tint: AppTheme.Color.brand)
                            Spacer()
                            Text("Start from Dashboard")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Manual Tracking")
                    .accessibilityValue("Start from Dashboard")
                    .accessibilityHint("Opens the Dashboard manual Start Trip flow")
                }

                Toggle(isOn: $tripFeedbackEnabled) {
                    settingLabel(
                        "Trip Sounds & Haptics",
                        icon: "waveform.and.speaker.fill",
                        tint: AppTheme.Color.brand
                    )
                }

                if automaticTrackingEnabled {
                    Stepper(
                        value: $automaticMinimumDistance,
                        in: 0.10...2.0,
                        step: 0.10
                    ) {
                        LabeledContent(
                            "Ignore Short Trips",
                            value: "Under \(automaticMinimumDistance.milesFormatted)"
                        )
                    }

                    permissionRow(
                        "Location",
                        status: locationPermissionText,
                        icon: "location.circle.fill"
                    )
                    permissionRow(
                        "Motion & Fitness",
                        status: motionPermissionText,
                        icon: "figure.walk.motion"
                    )
                    if TrackingPermissionAction(
                        readiness: automaticTripCoordinator.trackingReadiness
                    ) != nil {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        } label: {
                            Label("Open iPhone Settings", systemImage: "gear")
                        }
                    }
                }

                Toggle(isOn: $automaticClassificationEnabled) {
                    settingLabel(
                        "Automatic Classification",
                        icon: "arrow.triangle.branch",
                        tint: AppTheme.Color.brand
                    )
                }
                destination("Vehicles", icon: "car.side.fill", tint: AppTheme.Color.brand) {
                    VehicleManagementView(repository: viewModel.repository)
                }
                destination("Frequent places", icon: "mappin.and.ellipse", tint: AppTheme.Color.brand) {
                    FrequentPlacesManagementView(repository: viewModel.repository)
                }
                destination("Classification Rules", icon: "list.bullet.rectangle", tint: .indigo) {
                    ClassificationRulesView(repository: viewModel.repository)
                }
            }

            settingsSection("Notifications") {
                Toggle(isOn: $tripDetectedNotificationsEnabled) {
                    settingLabel(
                        "Trip Completion Notifications",
                        icon: "bell.badge.fill",
                        tint: AppTheme.Color.brand
                    )
                }
                .onChange(of: tripDetectedNotificationsEnabled) { _, enabled in
                    if !enabled {
                        notificationService.cancelCompletionNotifications()
                    } else {
                        requestNotificationAuthorizationIfNeeded()
                    }
                }
                Text("Get notified when MileMate finishes recording an automatic trip.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Color.textSecondary)

                Toggle(isOn: $tripReviewRemindersEnabled) {
                    settingLabel(
                        "Trip Review Reminders",
                        icon: "clock.badge.fill",
                        tint: .orange
                    )
                }
                .onChange(of: tripReviewRemindersEnabled) { _, enabled in
                    if !enabled {
                        notificationService.cancelReminderNotifications()
                    } else {
                        requestNotificationAuthorizationIfNeeded()
                        Task { await notificationService.reconcileReviewReminder() }
                    }
                }
                Text("Remind me later about trips that still need classification.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Color.textSecondary)

                if notificationRecovery == .openSystemSettings {
                    Text("Notifications are disabled in iPhone Settings.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Color.textSecondary)

                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Label("Open iPhone Settings", systemImage: "gear")
                    }
                } else if notificationRecovery == .requestPermission {
                    Text("Enable notifications to receive trip alerts and review reminders.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Color.textSecondary)

                    Button {
                        Task {
                            await notificationService.requestAuthorization()
                            notificationPermissionStatus = notificationService.authorizationStatus
                        }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.badge")
                    }
                }
            }

            settingsSection("Tax") {
                destination("IRS rate", icon: "dollarsign.circle.fill", tint: AppTheme.Color.positive) {
                    TaxSettingsView()
                }
                destination("Tax year", icon: "calendar", tint: .indigo) {
                    InformationView(title: "Tax Year", icon: "calendar", message: "MileMate is currently reporting for tax year 2026.")
                }
            }

            settingsSection("MileMate") {
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) {
                        Text($0.rawValue).tag($0.rawValue)
                    }
                } label: {
                    settingLabel("Appearance", icon: "circle.lefthalf.filled", tint: .indigo)
                }
            }

            settingsSection("Privacy & Support") {
                destination("Privacy", icon: "hand.raised.fill", tint: .teal) {
                    InformationView(title: "Privacy", icon: "hand.raised.fill", message: "Your mileage data stays on this device in this milestone.")
                }
                destination("Help", icon: "questionmark.circle.fill", tint: AppTheme.Color.brand) {
                    InformationView(title: "Help", icon: "questionmark.circle.fill", message: "Find answers about trips, deductions, and tax-ready reports.")
                }
                destination("Support", icon: "lifepreserver.fill", tint: .orange) {
                    InformationView(title: "Support", icon: "lifepreserver.fill", message: "We are here to help you get the most from every mile.")
                }
                destination("Send feedback", icon: "bubble.left.and.bubble.right.fill", tint: .purple) {
                    InformationView(title: "Feedback", icon: "bubble.left.and.bubble.right.fill", message: "Tell us how MileMate can make your workday easier.")
                }
                destination("About MileMate", icon: "info.circle.fill", tint: AppTheme.Color.textSecondary) {
                    InformationView(title: "About MileMate", icon: "road.lanes", message: "Mileage clarity for people who drive for work.")
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0 (1)").foregroundStyle(AppTheme.Color.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(AppTheme.Color.canvas)
        .navigationTitle("Settings")
        .task {
            await viewModel.loadFrequentPlaces()
            await notificationService.refreshAuthorizationStatus()
            notificationPermissionStatus = notificationService.authorizationStatus
            await notificationService.reconcileReviewReminder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mileageTripsDidChange)) { _ in
            Task { await viewModel.loadFrequentPlaces() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await notificationService.refreshAuthorizationStatus()
                notificationPermissionStatus = notificationService.authorizationStatus
                await notificationService.reconcileReviewReminder()
            }
        }
        .confirmationDialog(
            "Enable Automatic Tracking?",
            isPresented: $showingAutomaticTrackingExplanation,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                automaticTrackingEnabled = true
                automaticTripCoordinator.setEnabled(true)
                if (tripDetectedNotificationsEnabled || tripReviewRemindersEnabled),
                   notificationPermissionStatus == .notDetermined {
                    Task {
                        await notificationService.requestAuthorization()
                        notificationPermissionStatus = notificationService.authorizationStatus
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MileMate uses Motion & Fitness to recognize driving and Always Location to record work trips in the background. You can also allow notifications so MileMate can tell you when an automatic trip is ready to review.")
        }
    }

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileSettingsView()
            } label: {
                HStack(spacing: AppTheme.Spacing.large) {
                    Text("AM")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.Color.brand.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alex Morgan").font(.appTitle)
                        Text("Independent Consultant")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.small)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Text(title)
        }
    }

    private func settingLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var automaticTrackingBinding: Binding<Bool> {
        Binding(
            get: { automaticTrackingEnabled },
            set: { enabled in
                if enabled {
                    showingAutomaticTrackingExplanation = true
                } else {
                    automaticTrackingEnabled = false
                    automaticTripCoordinator.setEnabled(false)
                }
            }
        )
    }

    private var manualTrackingRowState: ManualTrackingRowState {
        ManualTrackingRowState(automaticTrackingEnabled: automaticTrackingEnabled)
    }

    private var locationPermissionText: String {
        switch automaticTripCoordinator.locationAuthorizationStatus {
        case CLAuthorizationStatus.authorizedAlways:
            return "Always Allowed"
        case CLAuthorizationStatus.authorizedWhenInUse:
            return "While Using App"
        case CLAuthorizationStatus.denied:
            return "Denied"
        case CLAuthorizationStatus.restricted:
            return "Restricted"
        case CLAuthorizationStatus.notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unavailable"
        }
    }

    private var motionPermissionText: String {
        switch automaticTripCoordinator.motionPermissionStatus {
        case MotionPermissionStatus.authorized:
            return "Allowed"
        case MotionPermissionStatus.notDetermined:
            return "Not Requested"
        case MotionPermissionStatus.denied:
            return "Denied"
        case MotionPermissionStatus.restricted:
            return "Restricted"
        case MotionPermissionStatus.unavailable:
            return "Unavailable"
        }
    }

    private var notificationRecovery: NotificationSettingsRecovery {
        NotificationSettingsRecovery(status: notificationPermissionStatus)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard notificationPermissionStatus == .notDetermined else { return }
        Task {
            await notificationService.requestAuthorization()
            notificationPermissionStatus = notificationService.authorizationStatus
        }
    }

    private func permissionRow(_ title: String, status: String, icon: String) -> some View {
        LabeledContent {
            Text(status)
                .foregroundStyle(AppTheme.Color.textSecondary)
        } label: {
            Label(title, systemImage: icon)
                .foregroundStyle(AppTheme.Color.textPrimary)
        }
    }

    private func destination<Destination: View>(
        _ title: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            settingLabel(title, icon: icon, tint: tint)
        }
    }
}

private struct ProfileSettingsView: View {
    @State private var name = "Alex Morgan"
    @State private var occupation = "Independent Consultant"

    var body: some View {
        Form {
            Section("Personal details") {
                TextField("Name", text: $name)
                TextField("Occupation", text: $occupation)
            }
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Profile")
    }
}

private struct TaxSettingsView: View {
    @AppStorage(MileageSettings.rateKey) private var deductionRate = MileageSettings.defaultMileageRate
    @AppStorage(MileageSettings.taxRateKey) private var taxRate = MileageSettings.defaultTaxRate

    var body: some View {
        Form {
            Section("Mileage Rate") {
                LabeledContent("IRS mileage rate", value: deductionRate.formatted(.currency(code: "USD")) + " / mi")
            }
            Section("Estimated Tax Rate") {
                Stepper(value: $taxRate, in: 0...60) {
                    LabeledContent(
                        "Selected rate",
                        value: taxRate.formatted(.number.precision(.fractionLength(0))) + "%"
                    )
                }
                Text("Used only to estimate potential tax savings from your mileage deduction. Actual savings vary.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollIndicators(.hidden)
        .navigationTitle("IRS Rate")
    }
}

private struct InformationView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

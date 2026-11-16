import AuthenticationServices
import CoreLocation
import SwiftUI
import UIKit

enum ManualTrackingRowState: Equatable {
    case selected
    case availableToSelect

    init(automaticTrackingEnabled: Bool) {
        self = automaticTrackingEnabled ? .availableToSelect : .selected
    }

    var isActionable: Bool { true }
    var isSelected: Bool { self == .selected }
}

enum DataDeletionConfirmationState: Equatable {
    case none
    case warning
    case final
}

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    private let manualTripCoordinator: ManualTripCoordinator
    @Bindable private var automaticTripCoordinator: AutomaticTripCoordinator
    private let notificationService: any TripNotificationScheduling
    @Bindable private var accountSession: AccountSessionController
    @Bindable private var purchaseManager: PurchaseManager
    private let router: AppRouter
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(DistanceUnitSettings.key) private var distanceUnit = DistanceUnitSettings.defaultUnit().rawValue
    @AppStorage(AutomaticTrackingSettings.enabledKey) private var automaticTrackingEnabled = false
    @AppStorage(AutomaticTrackingSettings.minimumDistanceKey)
    private var automaticMinimumDistance = AutomaticTrackingSettings.defaultMinimumDistance
    @AppStorage(AutomaticTrackingSettings.tripEndDelayKey)
    private var automaticTripEndDelay = Int(AutomaticTrackingSettings.defaultTripEndDelay)
    @AppStorage(TripNotificationSettings.completionEnabledKey, store: .standard)
    private var tripDetectedNotificationsEnabled = false
    @AppStorage(TripNotificationSettings.remindersEnabledKey, store: .standard)
    private var tripReviewRemindersEnabled = false
    @AppStorage(ClassificationSettings.automaticRulesEnabledKey)
    private var automaticClassificationEnabled = false
    @State private var showingAutomaticTrackingExplanation = false
    @State private var notificationPermissionStatus = NotificationPermissionStatus.notDetermined
    @State private var deletionConfirmation = DataDeletionConfirmationState.none
    @State private var deletionErrorMessage: String?
    @AppStorage(TripFeedbackSettings.enabledKey) private var tripFeedbackEnabled = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(
        repository: any MileageRepository,
        manualTripCoordinator: ManualTripCoordinator,
        automaticTripCoordinator: AutomaticTripCoordinator,
        notificationService: any TripNotificationScheduling,
        accountSession: AccountSessionController,
        purchaseManager: PurchaseManager,
        router: AppRouter
    ) {
        _viewModel = State(initialValue: SettingsViewModel(repository: repository))
        self.manualTripCoordinator = manualTripCoordinator
        _automaticTripCoordinator = Bindable(wrappedValue: automaticTripCoordinator)
        self.notificationService = notificationService
        _accountSession = Bindable(wrappedValue: accountSession)
        _purchaseManager = Bindable(wrappedValue: purchaseManager)
        self.router = router
    }

    var body: some View {
        List {
            accountSection

            settingsSection("Subscription & Billing") {
                NavigationLink {
                    SubscriptionBillingView(
                        purchaseManager: purchaseManager,
                        remainingTrips: accountSession.remainingGuestTrips
                    )
                } label: {
                    HStack {
                        settingLabel("Current Plan", icon: "creditcard.fill", tint: AppTheme.Color.brand)
                        Spacer()
                        Text(subscriptionPlanName)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                }
                .accessibilityHint("Opens purchase, restore, and subscription management options")
            }

            settingsSection("Tracking") {
                Toggle(isOn: automaticTrackingBinding) {
                    settingLabel(
                        "Automatic Tracking (Recommended)",
                        icon: "location.fill",
                        tint: AppTheme.Color.brand
                    )
                }
                .disabled(
                    trackingModeSwitchDisabled
                )

                Button {
                    selectManualTracking()
                } label: {
                    HStack {
                        settingLabel("Manual Tracking", icon: "play.circle.fill", tint: AppTheme.Color.brand)
                        Spacer()
                        Text(manualTrackingRowState.isSelected ? "Selected" : "Switch")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                        Image(systemName: manualTrackingRowState.isSelected ? "checkmark" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                automaticTrackingEnabled
                                    ? AppTheme.Color.textSecondary
                                    : AppTheme.Color.brand
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(trackingModeSwitchDisabled)
                .accessibilityLabel("Manual Tracking")
                .accessibilityValue(automaticTrackingEnabled ? "Not selected" : "Selected")
                .accessibilityHint(
                    automaticTrackingEnabled
                        ? "Switches to Manual Tracking and opens the Dashboard"
                        : "Opens the Dashboard manual Start Trip flow"
                )

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

                    Picker("End Trip After", selection: $automaticTripEndDelay) {
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("20 minutes").tag(1_200)
                    }
                    Text("How long MileMate waits after confirmed inactivity before completing an automatic trip.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Color.textSecondary)

                    Text("PERMISSIONS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    permissionStatusRow(
                        "Location",
                        status: locationPermissionText,
                        icon: "location.circle.fill",
                        isSufficient:
                            automaticTripCoordinator.locationAuthorizationStatus == .authorizedAlways &&
                            automaticTripCoordinator.preciseLocationAvailable
                    )
                    permissionStatusRow(
                        "Motion & Fitness",
                        status: motionPermissionText,
                        icon: "figure.walk.motion",
                        isSufficient: automaticTripCoordinator.motionPermissionStatus == .authorized
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
                if automaticClassificationEnabled && viewModel.classificationRuleCount == 0 {
                    Text("No rules configured")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                } else if automaticClassificationEnabled {
                    Text("Applies approved matching rules automatically.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
                destination("Vehicles", icon: "car.side.fill", tint: AppTheme.Color.brand) {
                    VehicleManagementView(repository: viewModel.repository)
                }
                destination("Frequent Places", icon: "mappin.and.ellipse", tint: AppTheme.Color.brand) {
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
                destination("IRS Rate", icon: "dollarsign.circle.fill", tint: AppTheme.Color.positive) {
                    TaxSettingsView()
                }
                destination("Tax Year", icon: "calendar", tint: .indigo) {
                    AnnualSummaryView(
                        repository: viewModel.repository,
                        initialYear: Calendar.current.component(.year, from: .now),
                        vehicleID: nil
                    )
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

            settingsSection("Preferences") {
                Picker("Distance Unit", selection: $distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.title).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Changes how distances are displayed without changing saved trip data or tax calculations")
            }

            settingsSection("Privacy & Support") {
                destination("Privacy", icon: "hand.raised.fill", tint: .teal) {
                    PrivacyInformationView()
                }
                destination("Help & Support", icon: "lifepreserver.fill", tint: .orange) {
                    HelpSupportView()
                }
                destination("Send feedback", icon: "bubble.left.and.bubble.right.fill", tint: .purple) {
                    SendFeedbackView()
                }
                destination("Contact Support", icon: "questionmark.bubble.fill", tint: .orange) {
                    ContactSupportView()
                }
                destination("About MileMate", icon: "info.circle.fill", tint: AppTheme.Color.textSecondary) {
                    AboutMileMateView()
                }
            }

            Section("Data & Privacy") {
                Button(role: .destructive) {
                    deletionConfirmation = .warning
                } label: {
                    Label("Delete All MileMate Data", systemImage: "trash.fill")
                }
                .frame(minHeight: 44)
                .accessibilityHint("Begins a two-step permanent data deletion confirmation")
            }

            Section {
                Button("Log Out") { accountSession.logOut() }
                    .frame(minHeight: 44)
                    .disabled(accountActionsDisabled)
                    .accessibilityHint("Returns to the MileMate welcome and sign-in screen")
            } header: {
                Text("Session")
            } footer: {
                if accountActionsDisabled {
                    Text("Finish or discard the current trip before changing accounts.")
                }
            }

            if accountSession.isAuthenticated {
                Section {
                    Button("Delete Account", role: .destructive) {
                        accountSession.presentsDeletionConfirmation = true
                    }
                    .frame(minHeight: 44)
                    .disabled(accountSession.isAuthenticating || accountActionsDisabled)
                } footer: {
                    Text("Deletes your sign-in account and only its locally owned MileMate data after confirmation.")
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
        .onReceive(NotificationCenter.default.publisher(for: .mileageClassificationDataDidChange)) { _ in
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
        .alert(
            "Delete All MileMate Data?",
            isPresented: confirmationBinding(for: .warning)
        ) {
            Button("Cancel", role: .cancel) { deletionConfirmation = .none }
            Button("Continue", role: .destructive) {
                deletionConfirmation = .final
            }
        } message: {
            Text("This permanently removes trips and routes, review data, vehicles, frequent places, classification rules, app preferences, and saved active-trip state. Active tracking will be stopped and discarded.")
        }
        .alert(
            "This Cannot Be Undone",
            isPresented: confirmationBinding(for: .final)
        ) {
            Button("Cancel", role: .cancel) { deletionConfirmation = .none }
            Button("Delete All Data", role: .destructive) {
                deletionConfirmation = .none
                deleteAllData()
            }
        } message: {
            Text("MileMate data stored by this app will be permanently deleted. iPhone permission choices will not be changed.")
        }
        .alert(
            "Unable to Delete Data",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "")
        }
        .confirmationDialog(
            "Delete MileMate Account?",
            isPresented: $accountSession.presentsDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await accountSession.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(accountDeletionConfirmationMessage)
        }
        .alert(
            "Account Action Failed",
            isPresented: Binding(
                get: { accountSession.authenticationError != nil },
                set: { if !$0 { accountSession.authenticationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { accountSession.authenticationError = nil }
        } message: {
            Text(accountSession.authenticationError ?? "")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            if let account = accountSession.account {
                HStack(spacing: AppTheme.Spacing.large) {
                    Text(accountInitials(account))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.Color.brand.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.displayName ?? "MileMate Account")
                            .font(.headline)
                        if let email = account.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                                .lineLimit(1)
                        }
                        Text("Signed in with \(account.provider.rawValue)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                LabeledContent {
                    Text("\(accountSession.remainingGuestTrips) of 10 trips remaining")
                        .foregroundStyle(AppTheme.Color.textSecondary)
                } label: {
                    Label("Guest", systemImage: "person.crop.circle")
                }
                SignInWithAppleButton(.continue) { request in
                    accountSession.prepareAppleSignIn(request)
                } onCompletion: { result in
                    accountSession.completeAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: AuthenticationButtonMetrics.height)
                .clipShape(Capsule())
                .disabled(accountSession.isAuthenticating || accountActionsDisabled)
                Button {
                    Task { await accountSession.authenticateWithGoogle() }
                } label: {
                    GoogleAuthenticationLabel()
                }
                .buttonStyle(.plain)
                .disabled(accountSession.isAuthenticating || accountActionsDisabled)
                Text("Signing in moves this guest trial's trips into your account on this iPhone. Cloud backup is not enabled yet.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }
        }
    }

    private var accountActionsDisabled: Bool {
        if manualTripCoordinator.hasProtectedTripState ||
            automaticTripCoordinator.hasProtectedTripState {
            return true
        }
        switch manualTripCoordinator.state {
        case .requestingPermission, .tracking, .reviewing:
            return true
        case .ready, .permissionDenied, .failed:
            break
        }
        switch automaticTripCoordinator.state {
        case .detecting, .tracking, .reviewing:
            return true
        case .disabled, .idle, .permissionRequired, .failed:
            return false
        }
    }

    private var subscriptionPlanName: String {
        guard purchaseManager.isEntitlementReady else { return "Checking…" }
        switch purchaseManager.plan {
        case .free: return "Free"
        case .monthly: return "Pro Monthly"
        case .lifetime: return "Pro Lifetime"
        }
    }

    private var accountDeletionConfirmationMessage: String {
        if accountSession.account?.provider == .apple {
            return "Deleting an Apple account requires secure Apple authorization revocation. MileMate will only complete deletion when that revocation service is configured."
        }
        return "This permanently deletes your authentication account and only its locally owned MileMate data. Other accounts and guest trips are not affected."
    }

    private func accountInitials(_ account: AuthenticatedAccount) -> String {
        let source = account.displayName ?? account.email ?? "MileMate"
        let words = source.split(separator: " ").prefix(2)
        let initials = words.compactMap { word in word.first }.map { character in
            String(character)
        }.joined()
        return initials.isEmpty ? "M" : initials.uppercased()
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

    private var trackingModeSwitchDisabled: Bool {
        manualTripCoordinator.hasProtectedTripState ||
            automaticTripCoordinator.hasProtectedTripState
    }

    private func selectManualTracking() {
        guard !trackingModeSwitchDisabled else { return }
        if automaticTrackingEnabled {
            automaticTrackingEnabled = false
            automaticTripCoordinator.setEnabled(false)
        }
        router.showManualTracking()
    }

    private var locationPermissionText: String {
        switch automaticTripCoordinator.locationAuthorizationStatus {
        case CLAuthorizationStatus.authorizedAlways:
            return automaticTripCoordinator.preciseLocationAvailable
                ? "Always Allowed"
                : "Precise Location Off"
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

    @ViewBuilder
    private func permissionStatusRow(
        _ title: String,
        status: String,
        icon: String,
        isSufficient: Bool
    ) -> some View {
        if isSufficient {
            permissionStatusContent(title, status: status, icon: icon)
        } else {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            } label: {
                permissionStatusContent(title, status: status, icon: icon)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens iPhone Settings to review this permission")
        }
    }

    private func permissionStatusContent(
        _ title: String,
        status: String,
        icon: String
    ) -> some View {
        LabeledContent {
            Text(status).foregroundStyle(AppTheme.Color.textSecondary)
        } label: {
            Label(title, systemImage: icon).foregroundStyle(AppTheme.Color.textPrimary)
        }
        .frame(minHeight: 44)
    }

    private func deleteAllData() {
        Task {
            do {
                let service = LocalDataDeletionService(
                    repository: viewModel.repository,
                    manualCoordinator: manualTripCoordinator,
                    automaticCoordinator: automaticTripCoordinator,
                    notificationService: notificationService
                )
                try await service.deleteAllData()
                router.requestedTrip = nil
                router.requestedTripsFilter = nil
                router.requestedReviewQueue = false
                router.selectedTab = .dashboard
            } catch {
                deletionErrorMessage = "MileMate could not delete all local data. Please try again."
            }
        }
    }

    private func confirmationBinding(
        for state: DataDeletionConfirmationState
    ) -> Binding<Bool> {
        Binding(
            get: { deletionConfirmation == state },
            set: { isPresented in
                if !isPresented, deletionConfirmation == state {
                    deletionConfirmation = .none
                }
            }
        )
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

private struct TaxSettingsView: View {
    @AppStorage(MileageSettings.taxRateKey) private var taxRate = MileageSettings.defaultTaxRate
    @State private var selectedYear = Calendar.current.component(.year, from: .now)
    @State private var customRate = MileageSettings.mileageRate

    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array((2024...max(currentYear, 2026)).reversed())
    }

    var body: some View {
        Form {
            Section("Mileage Rate") {
                Picker("Tax year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(verbatim: String(year)).tag(year)
                    }
                }
                Stepper(value: customRateBinding, in: 0.01...2.00, step: 0.005) {
                    LabeledContent(
                        "Configured rate",
                        value: customRate.formatted(
                            .currency(code: "USD").precision(.fractionLength(3))
                        ) + " / mi"
                    )
                }
                Button("Restore Official Default") {
                    MileageSettings.restoreOfficialMileageRate(for: selectedYear)
                    loadRate()
                }
                Text("Official default: \(MileageSettings.officialRateDescription(for: selectedYear)). Custom rates apply only to the selected tax year.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .settingsDetailScrollBehavior()
        .scrollIndicators(.hidden)
        .navigationTitle("IRS Rate")
        .onAppear { loadRate() }
        .onChange(of: selectedYear) { _, _ in loadRate() }
    }

    private func loadRate() {
        if let override = MileageSettings.mileageRateOverride(for: selectedYear) {
            customRate = override
            return
        }
        let date = Calendar.current.date(
            from: DateComponents(year: selectedYear, month: 12, day: 31)
        ) ?? .now
        customRate = MileageSettings.officialMileageRate(for: date)
    }

    private var customRateBinding: Binding<Double> {
        Binding(
            get: { customRate },
            set: { rate in
                customRate = rate
                MileageSettings.setMileageRate(rate, for: selectedYear)
            }
        )
    }
}

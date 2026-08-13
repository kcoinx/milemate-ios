import CoreLocation
import SwiftUI

struct DashboardView: View {
    private let repository: any MileageRepository
    private let notificationService: any TripNotificationScheduling
    private let router: AppRouter
    @State private var viewModel: DashboardViewModel
    @Bindable private var tripCoordinator: ManualTripCoordinator
    @Bindable private var automaticTripCoordinator: AutomaticTripCoordinator
    @AppStorage(AutomaticTrackingSettings.enabledKey) private var automaticTrackingEnabled = false
    @State private var isPulsing = false
    @State private var hasAppeared = false
    @ScaledMetric(relativeTo: .headline) private var secondaryMetricValueSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var compactMetricValueSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title2) private var activeMetricValueSize: CGFloat = 25
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        repository: any MileageRepository,
        tripCoordinator: ManualTripCoordinator,
        automaticTripCoordinator: AutomaticTripCoordinator,
        notificationService: any TripNotificationScheduling,
        router: AppRouter
    ) {
        self.repository = repository
        self.notificationService = notificationService
        self.router = router
        _viewModel = State(initialValue: DashboardViewModel(repository: repository))
        _tripCoordinator = Bindable(wrappedValue: tripCoordinator)
        _automaticTripCoordinator = Bindable(wrappedValue: automaticTripCoordinator)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                greeting
                deductionHero
                if viewModel.unclassifiedCount > 0 {
                    reviewQueueCard
                }
                lastTrip
                mapSection
                weeklySummary
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(AppTheme.Color.canvas)
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $tripCoordinator.pendingTrip) { trip in
            TripReviewView(trip: trip, repository: repository, coordinator: tripCoordinator) {
                Task { await viewModel.load() }
            }
            .interactiveDismissDisabled()
        }
        .sheet(item: $automaticTripCoordinator.pendingTrip) { trip in
            TripReviewView(trip: trip, repository: repository, coordinator: automaticTripCoordinator) {
                Task { await viewModel.load() }
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            Task { await viewModel.load() }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.55)) { hasAppeared = true }
            }
            updateTrackingPulse()
        }
        .onChange(of: tripCoordinator.state) { _, _ in updateTrackingPulse() }
        .onChange(of: automaticTripCoordinator.state) { _, _ in updateTrackingPulse() }
        .onReceive(NotificationCenter.default.publisher(for: .mileageTripsDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private var reviewQueueCard: some View {
        NavigationLink {
            ReviewQueueView(
                repository: repository,
                notificationService: notificationService
            )
        } label: {
            AppCard {
                HStack(spacing: AppTheme.Spacing.large) {
                    Image(systemName: "tray.full.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.Color.brand, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.unclassifiedCount) \(viewModel.unclassifiedCount == 1 ? "Trip Needs" : "Trips Need") Review")
                            .font(.appHeadline)
                        Text("Review Now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Color.brand)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(greetingText), \(viewModel.profile.firstName)")
                .font(.appLargeTitle)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .foregroundStyle(AppTheme.Color.textSecondary)
        }
        .padding(.top, AppTheme.Spacing.xLarge)
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var deductionHero: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 22, height: 22)
                        .scaleEffect(isRecording && isPulsing ? 1.35 : 0.9)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text(trackingStatus)
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .padding(.horizontal, isRecording ? 10 : 0)
                        .padding(.vertical, isRecording ? 6 : 0)
                        .background(
                            .white.opacity(isRecording ? 0.14 : 0),
                            in: Capsule()
                        )
                    if let trackingSupportingText {
                        Text(trackingSupportingText)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Image(systemName: "location.fill")
            }

            if isRecording {
                activeTripSummary
            } else {
                yearToDateSummary
            }

            if !automaticTrackingEnabled || tripCoordinator.state == .tracking {
                Button {
                    if tripCoordinator.state == .tracking {
                        tripCoordinator.stopTrip()
                    } else {
                        tripCoordinator.startTrip()
                    }
                } label: {
                    Label(
                        tripCoordinator.state == .tracking ? "Stop Trip" : "Start Trip",
                        systemImage: tripCoordinator.state == .tracking ? "stop.fill" : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(.white, in: Capsule())
                    .foregroundStyle(tripCoordinator.state == .tracking ? Color.red : AppTheme.Color.brand)
                }
                .disabled(tripCoordinator.state == .requestingPermission || tripCoordinator.state == .reviewing)
            }

            if let permissionAction {
                Button {
                    router.showTrackingPermissions()
                } label: {
                    Label(permissionAction.title, systemImage: "checklist")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(.white, in: Capsule())
                        .foregroundStyle(AppTheme.Color.brand)
                }
                .accessibilityLabel(permissionAction.title)
            }

            if tripCoordinator.state == .permissionDenied {
                Text("Location access is denied. Enable it in iPhone Settings to record a trip.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            } else if case .failed(let message) = tripCoordinator.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .foregroundStyle(.white)
        .padding(AppTheme.Spacing.card)
        .background {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.33, blue: 0.22), AppTheme.Color.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: AppTheme.Color.brand.opacity(0.28), radius: 28, y: 16)
        .scaleEffect(hasAppeared ? 1 : 0.97)
        .opacity(hasAppeared ? 1 : 0)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: tripCoordinator.state)
    }

    private var activeTripSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIVE DISTANCE")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.72))
                Text(activeDistanceMiles.milesFormatted)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 0.3),
                        value: activeDistanceMiles
                    )
            }

            if let location = activeLocationLabel {
                Label(location, systemImage: "location.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .accessibilityLabel("Current area, \(location)")
            }

            if let vehicle = viewModel.defaultVehicle {
                Label(vehicle.nickname, systemImage: "car.side.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityLabel("Tracking vehicle, \(vehicle.nickname)")
            }

            HStack(spacing: AppTheme.Spacing.medium) {
                activeMetric(
                    "Elapsed Time",
                    value: activeElapsedTime.formattedDuration,
                    icon: "clock.fill"
                )
                activeMetric(
                    "Estimated Deduction",
                    value: activeDeduction.currencyFormatted,
                    icon: "dollarsign.circle.fill"
                )
            }
        }
    }

    private func activeMetric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(
                    .system(
                        size: activeMetricValueSize,
                        weight: .bold,
                        design: .rounded
                    )
                    .monospacedDigit()
                )
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
                .minimumScaleFactor(0.75)
        }
        .padding(AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .accessibilityElement(children: .combine)
    }

    private var yearToDateSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YEAR-TO-DATE DEDUCTION")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.72))
            Text(viewModel.summary.estimatedDeduction.currencyFormatted)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())

            HStack(spacing: AppTheme.Spacing.xLarge) {
                summaryMetric("Today\u{2019}s Miles", value: viewModel.todayBusinessMiles.milesFormatted)
                Divider().overlay(.white.opacity(0.25))
                summaryMetric("Estimated Tax Savings", value: viewModel.summary.estimatedTaxSavings.currencyFormatted)
            }
            .frame(height: 52)
            .padding(.top, AppTheme.Spacing.large)

            HStack {
                Text("Business Miles")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(viewModel.summary.businessMiles.milesFormatted)
                    .font(
                        .system(
                            size: compactMetricValueSize,
                            weight: .semibold,
                            design: .rounded
                        )
                        .monospacedDigit()
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.top, AppTheme.Spacing.small)
        }
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(
                    .system(
                        size: secondaryMetricValueSize,
                        weight: .semibold,
                        design: .rounded
                    )
                    .monospacedDigit()
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var lastTrip: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Recent Trip")
            if let trip = viewModel.recentTrips.first {
                Button {
                    Task { await openRecentTrip(trip) }
                } label: {
                    AppCard {
                        HStack(spacing: AppTheme.Spacing.large) {
                            VStack(spacing: 3) {
                                Circle().fill(AppTheme.Color.textSecondary).frame(width: 8, height: 8)
                                Rectangle().fill(AppTheme.Color.divider).frame(width: 1, height: 25)
                                Circle().fill(AppTheme.Color.brand).frame(width: 8, height: 8)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(trip.originName).font(.subheadline.weight(.medium))
                                Text(trip.destinationName).font(.appHeadline)
                                Text("Completed at \(trip.endedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Color.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(trip.distanceMiles.milesFormatted).font(.appHeadline)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent trip from \(trip.originName) to \(trip.destinationName)")
                .accessibilityHint("Opens this trip's details")
            } else {
                AppCard {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start your first trip").font(.appHeadline)
                            Text("Begin tracking mileage and estimated tax deductions with your first completed trip.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "car.side")
                            .foregroundStyle(AppTheme.Color.brand)
                    }
                }
            }
        }
    }

    private func openRecentTrip(_ trip: Trip) async {
        await router.showTripDetails(tripID: trip.id)
    }

    private func updateTrackingPulse() {
        guard isRecording, !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isPulsing = false }
            return
        }
        isPulsing = false
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: isRecording ? "Live Route" : "Recorded Route")
            if isRecording {
                RouteMapView(
                    origin: "Trip start",
                    destination: "Current location",
                    route: activeRoute,
                    height: 260,
                    showsUserLocation: true,
                    showsEndMarker: false
                )
            } else if let trip = viewModel.recentTrips.first {
                RouteMapView(
                    origin: trip.originName,
                    destination: trip.destinationName,
                    route: trip.route,
                    startCoordinate: trip.startCoordinate,
                    endCoordinate: trip.endCoordinate,
                    height: 260
                )
            } else {
                RouteMapView(origin: "", destination: "", height: 260)
            }
        }
    }

    private var isRecording: Bool {
        tripCoordinator.state == .tracking || automaticTripCoordinator.state == .tracking
    }

    private var trackingStatus: String {
        if tripCoordinator.state == .tracking {
            return "Manual Tracking Active"
        }
        switch automaticTripCoordinator.state {
        case .tracking:
            return "Recording Trip Automatically"
        case .detecting:
            return "Detecting Drive"
        case .reviewing:
            return "Trip Ready for Review"
        case .permissionRequired:
            return missingPermissionStatus
        case .failed:
            return shouldReviewPermissions
                ? missingPermissionStatus
                : "Automatic Tracking Paused"
        default:
            if shouldReviewPermissions {
                return missingPermissionStatus
            }
            return automaticTrackingEnabled
                ? "Automatic Tracking Active"
                : "Ready to Track"
        }
    }

    private var trackingSupportingText: String? {
        if tripCoordinator.state == .tracking {
            return tripCoordinator.backgroundRecordingAvailable
                ? "Your manually started trip is being recorded."
                : "This trip is tracking mileage, but updates may be limited when MileMate is not open until Always Location access is enabled."
        }
        switch automaticTripCoordinator.state {
        case .tracking:
            return "MileMate is recording this qualifying trip automatically."
        case .detecting:
            return "MileMate is checking whether this drive qualifies for automatic recording."
        case .reviewing:
            return "Review and classify your completed trip."
        case .permissionRequired:
            return permissionSupportingText
        case .failed:
            return shouldReviewPermissions
                ? permissionSupportingText
                : "Automatic tracking is temporarily paused."
        default:
            if shouldReviewPermissions {
                return permissionSupportingText
            }
            return automaticTrackingEnabled
                ? "Drive normally. MileMate will automatically detect and record qualifying trips."
                : nil
        }
    }

    private var permissionSupportingText: String {
        switch automaticTripCoordinator.trackingReadiness {
        case .ready:
            return "Drive normally. MileMate will automatically detect and record qualifying trips."
        case .locationPermissionRequired:
            return "Allow Always Location access so MileMate can automatically track trips."
        case .motionPermissionRequired:
            return "Allow Motion & Fitness so MileMate can detect when you are driving."
        case .backgroundCapabilityUnavailable:
            return "MileMate couldn't start automatic tracking. Try restarting the app. If the issue continues, use Manual Tracking."
        case .detectionServicesUnavailable:
            return "MileMate couldn't start automatic tracking. Try restarting the app. If the issue continues, use Manual Tracking."
        }
    }

    private var missingPermissionStatus: String {
        switch automaticTripCoordinator.trackingReadiness {
        case .ready:
            return "Automatic Tracking Active"
        case .locationPermissionRequired:
            return "Location Needed"
        case .motionPermissionRequired:
            return "Motion & Fitness Needed"
        case .backgroundCapabilityUnavailable:
            return "Automatic Tracking Unavailable"
        case .detectionServicesUnavailable:
            return "Automatic Tracking Unavailable"
        }
    }

    private var shouldReviewPermissions: Bool {
        guard automaticTrackingEnabled,
              tripCoordinator.state != .tracking else {
            return false
        }
        switch automaticTripCoordinator.state {
        case .permissionRequired:
            return automaticTripCoordinator.trackingReadiness != .ready
        case .tracking, .detecting, .reviewing:
            return false
        default:
            return automaticTripCoordinator.trackingReadiness != .ready
        }
    }

    private var permissionAction: TrackingPermissionAction? {
        guard automaticTrackingEnabled,
              tripCoordinator.state != .tracking else { return nil }
        return TrackingPermissionAction(readiness: automaticTripCoordinator.trackingReadiness)
    }

    private var activeDistanceMiles: Double {
        tripCoordinator.state == .tracking
            ? tripCoordinator.distanceMiles
            : automaticTripCoordinator.distanceMiles
    }

    private var activeElapsedTime: TimeInterval {
        tripCoordinator.state == .tracking
            ? tripCoordinator.elapsedTime
            : automaticTripCoordinator.elapsedTime
    }

    private var activeDeduction: Double {
        tripCoordinator.state == .tracking
            ? tripCoordinator.currentDeduction
            : automaticTripCoordinator.currentDeduction
    }

    private var activeRoute: [TripCoordinate] {
        tripCoordinator.state == .tracking
            ? tripCoordinator.currentRoute
            : automaticTripCoordinator.currentRoute
    }

    private var activeLocationLabel: String? {
        tripCoordinator.state == .tracking ? tripCoordinator.currentLocationLabel : nil
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "This Week")
            AppCard {
                VStack(spacing: AppTheme.Spacing.large) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                        ProgressRing(
                            progress: min(viewModel.weeklyBusinessMiles / 500, 1),
                            value: viewModel.weeklyBusinessMiles.formatted(.number.precision(.fractionLength(0))),
                            label: "Business\nMiles"
                        )
                        ProgressRing(
                            progress: min(Double(viewModel.weeklyTrips.count) / 20, 1),
                            value: "\(viewModel.weeklyTrips.count)",
                            label: "Trips\nThis Week",
                            tint: AppTheme.Color.positive
                        )
                        ProgressRing(
                            progress: min(viewModel.weeklyDeduction / 350, 1),
                            value: viewModel.weeklyDeduction.currencyFormatted,
                            label: "Estimated\nDeduction",
                            tint: AppTheme.Color.warning
                        )
                    }
                    Divider()
                    HStack {
                        Label("Estimated Tax Savings", systemImage: "arrow.up.right")
                            .foregroundStyle(AppTheme.Color.textSecondary)
                        Spacer()
                        Text(MileageDeductionService.estimatedTaxSavings(deduction: viewModel.weeklyDeduction).currencyFormatted)
                            .font(.appTitle)
                            .foregroundStyle(AppTheme.Color.positive)
                    }
                }
            }
        }
    }
}

import SwiftUI

struct DashboardView: View {
    private let repository: any MileageRepository
    @State private var viewModel: DashboardViewModel
    @Bindable private var tripCoordinator: ManualTripCoordinator
    @State private var isPulsing = false
    @State private var hasAppeared = false

    init(repository: any MileageRepository, tripCoordinator: ManualTripCoordinator) {
        self.repository = repository
        _viewModel = State(initialValue: DashboardViewModel(repository: repository))
        _tripCoordinator = Bindable(wrappedValue: tripCoordinator)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                greeting
                deductionHero
                lastTrip
                mapSection
                weeklySummary
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(AppTheme.Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $tripCoordinator.pendingTrip) { trip in
            TripReviewView(trip: trip, coordinator: tripCoordinator) {
                Task { await viewModel.load() }
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            Task { await viewModel.load() }
            withAnimation(.easeOut(duration: 0.55)) { hasAppeared = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(greetingText), \(viewModel.profile.firstName)")
                    .font(.appLargeTitle)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }
            Spacer()
            Button(action: {}) {
                Image(systemName: "bell")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.Color.surface, in: Circle())
            }
            .accessibilityLabel("Notifications")
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
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 22, height: 22)
                        .scaleEffect(tripCoordinator.state == .tracking && isPulsing ? 1.35 : 0.9)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
                Text(tripCoordinator.state == .tracking ? "MANUAL TRACKING ACTIVE" : "READY TO TRACK")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                Spacer()
                Image(systemName: "location.fill")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("YEAR-TO-DATE ESTIMATED IRS DEDUCTION")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.72))
                Text(viewModel.summary.estimatedDeduction.currencyFormatted)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
            }

            HStack(spacing: AppTheme.Spacing.xLarge) {
                heroMetric(
                    tripCoordinator.state == .tracking ? "Live distance" : "Today's business miles",
                    value: (tripCoordinator.state == .tracking ? tripCoordinator.distanceMiles : viewModel.todayBusinessMiles).milesFormatted
                )
                Divider().overlay(.white.opacity(0.25))
                heroMetric(
                    tripCoordinator.state == .tracking ? "Elapsed time" : "Est. tax savings",
                    value: tripCoordinator.state == .tracking
                        ? tripCoordinator.elapsedTime.formattedDuration
                        : viewModel.summary.estimatedTaxSavings.currencyFormatted
                )
            }
            .frame(height: 48)

            HStack {
                Text(tripCoordinator.state == .tracking ? "Current estimated deduction" : "Year-to-date business miles")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(
                    tripCoordinator.state == .tracking
                        ? tripCoordinator.currentDeduction.currencyFormatted
                        : viewModel.summary.businessMiles.milesFormatted
                )
                .font(.subheadline.weight(.bold))
            }

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
        .padding(AppTheme.Spacing.xLarge)
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
        .accessibilityElement(children: .combine)
    }

    private func heroMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastTrip: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Last trip")
            if tripCoordinator.state == .tracking {
                RouteMapView(
                    origin: "Trip start",
                    destination: "Current location",
                    route: tripCoordinator.currentRoute,
                    height: 260
                )
            } else if let trip = viewModel.recentTrips.first {
                NavigationLink(value: trip) {
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
            } else {
                AppCard {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No completed trips").font(.appHeadline)
                            Text("Start a manual trip to create your first mileage record.")
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
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0, repository: repository) }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                SectionHeader(title: "Live route")
                Spacer()
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Color.brand)
            }
            if let trip = viewModel.recentTrips.first {
                RouteMapView(
                    origin: trip.originName,
                    destination: trip.destinationName,
                    route: trip.route,
                    height: 260
                )
            } else {
                RouteMapView(origin: "Start", destination: "Finish", height: 260)
            }
        }
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "This week")
            AppCard {
                HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    ProgressRing(
                        progress: min(viewModel.weeklyBusinessMiles / 500, 1),
                        value: viewModel.weeklyBusinessMiles.formatted(.number.precision(.fractionLength(0))),
                        label: "Business\nmiles"
                    )
                    ProgressRing(
                        progress: min(Double(viewModel.weeklyTrips.count) / 20, 1),
                        value: "\(viewModel.weeklyTrips.count)",
                        label: "Trips",
                        tint: AppTheme.Color.positive
                    )
                    ProgressRing(
                        progress: min(viewModel.weeklyDeduction / 350, 1),
                        value: viewModel.weeklyDeduction.currencyFormatted,
                        label: "IRS\ndeduction",
                        tint: AppTheme.Color.warning
                    )
                }
                Divider().padding(.vertical, AppTheme.Spacing.large)
                HStack {
                    Label("Estimated tax savings", systemImage: "arrow.up.right")
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

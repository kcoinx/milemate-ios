import SwiftUI

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var isPulsing = false
    @State private var hasAppeared = false

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: DashboardViewModel(repository: repository))
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
        .task { await viewModel.load() }
        .onAppear {
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
                        .scaleEffect(isPulsing ? 1.35 : 0.9)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
                Text("TRACKING ACTIVE")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                Spacer()
                Image(systemName: "location.fill")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ESTIMATED IRS DEDUCTION")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.72))
                Text(viewModel.summary.estimatedDeduction.currencyFormatted)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
            }

            HStack(spacing: AppTheme.Spacing.xLarge) {
                heroMetric("Today's miles", value: "42.6 mi")
                Divider().overlay(.white.opacity(0.25))
                heroMetric("Est. tax savings", value: viewModel.summary.estimatedTaxSavings.currencyFormatted)
            }
            .frame(height: 48)
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
            if let trip = viewModel.recentTrips.first {
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
            }
        }
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
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
            RouteMapView(origin: "Current location", destination: "Next stop", height: 260)
        }
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "This week")
            AppCard {
                HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    ProgressRing(progress: 0.72, value: "486", label: "Business\nmiles")
                    ProgressRing(progress: 0.58, value: "18", label: "Trips", tint: AppTheme.Color.positive)
                    ProgressRing(progress: 0.64, value: "$340", label: "IRS\ndeduction", tint: AppTheme.Color.warning)
                }
                Divider().padding(.vertical, AppTheme.Spacing.large)
                HStack {
                    Label("Estimated tax savings", systemImage: "arrow.up.right")
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Spacer()
                    Text("$95")
                        .font(.appTitle)
                        .foregroundStyle(AppTheme.Color.positive)
                }
            }
        }
    }
}

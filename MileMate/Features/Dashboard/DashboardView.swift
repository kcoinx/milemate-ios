import Charts
import SwiftUI

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                greeting
                deductionHero
                metrics
                mileageChart
                recentTrips
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("MileMate")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) {
                    Image(systemName: "bell")
                }
                .accessibilityLabel("Notifications")
            }
        }
        .task { await viewModel.load() }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Good morning, \(viewModel.profile.firstName)")
                .font(.appLargeTitle)
            Text("Your driving is working for you.")
                .foregroundStyle(AppTheme.Color.textSecondary)
        }
        .padding(.top, AppTheme.Spacing.small)
    }

    private var deductionHero: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            HStack {
                Label("2026 estimated deduction", systemImage: "sparkles")
                    .font(.appHeadline)
                Spacer()
                Text("YTD")
                    .font(.appCaption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.16), in: Capsule())
            }

            Text(viewModel.summary.estimatedDeduction.currencyFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            HStack {
                Label(
                    "\(viewModel.summary.estimatedTaxSavings.currencyFormatted) estimated tax savings",
                    systemImage: "arrow.up.right"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .padding(AppTheme.Spacing.xLarge)
        .background {
            LinearGradient(
                colors: [AppTheme.Color.brand, AppTheme.Color.brand.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        }
        .shadow(color: AppTheme.Color.brand.opacity(0.22), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
    }

    private var metrics: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppTheme.Spacing.medium) {
            MetricCard(
                title: "Business Miles",
                value: viewModel.summary.businessMiles.formatted(.number.precision(.fractionLength(0))),
                systemImage: "road.lanes",
                tint: AppTheme.Color.brand,
                detail: "78% of all miles"
            )
            MetricCard(
                title: "Trips",
                value: "\(viewModel.summary.tripCount)",
                systemImage: "car.side.fill",
                tint: AppTheme.Color.accent,
                detail: "12 this week"
            )
        }
    }

    private var mileageChart: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Business mileage")
                Chart(viewModel.summary.monthlyMiles) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Miles", item.miles)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.Color.brand, AppTheme.Color.accent],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(5)
                }
                .chartYAxis(.hidden)
                .frame(height: 150)
                .accessibilityLabel("Monthly business mileage chart")
            }
        }
    }

    private var recentTrips: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Recent trips")
            AppCard {
                ForEach(Array(viewModel.recentTrips.enumerated()), id: \.element.id) { index, trip in
                    NavigationLink(value: trip) {
                        TripRow(trip: trip)
                    }
                    .buttonStyle(.plain)
                    if index < viewModel.recentTrips.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
    }
}


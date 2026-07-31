import SwiftUI

struct InsightsView: View {
    @State private var viewModel: InsightsViewModel
    @State private var ringProgress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: InsightsViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                weeklyHero
                if !viewModel.hasMeaningfulData {
                    Label(
                        "Complete a few trips to unlock richer insights.",
                        systemImage: "sparkles"
                    )
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Color.textSecondary)
                }
                mileageSplit
                yourDriving
                destinationCard
                progressCard
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
            .opacity(ringProgress > 0 ? 1 : 0)
            .offset(y: ringProgress > 0 ? 0 : 8)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Insights")
        .onAppear {
            Task { await viewModel.load() }
            if reduceMotion {
                ringProgress = 1
            } else {
                withAnimation(.smooth(duration: 0.55)) { ringProgress = 1 }
            }
        }
    }

    private var weeklyHero: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("YOU DROVE")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.Color.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(viewModel.weeklyBusinessMiles.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("mi")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
                Text("Business miles this week")
                    .font(.title3.weight(.semibold))
                if let change = viewModel.weekChangePercentage {
                    HStack(spacing: 7) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(abs(change).formatted(.number.precision(.fractionLength(0))))% compared to last week")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(change >= 0 ? AppTheme.Color.positive : AppTheme.Color.warning)
                    .padding(.top, AppTheme.Spacing.small)
                }
            }
        }
    }

    private var mileageSplit: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Mileage Split")
                HStack(spacing: AppTheme.Spacing.large) {
                    categoryMetric("Business", value: viewModel.businessPercentage, tint: AppTheme.Color.brand)
                    Divider()
                    categoryMetric("Personal", value: viewModel.personalPercentage, tint: AppTheme.Color.warning)
                }
            }
        }
    }

    private func categoryMetric(_ title: String, value: Double, tint: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ZStack {
                Circle().stroke(tint.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: ringProgress * value)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline)
            }
            .frame(width: 76, height: 76)
            Text(title).font(.appHeadline)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var yourDriving: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Your Driving")
                HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                    compactInsight("Most driven day", value: viewModel.hasMeaningfulData ? viewModel.mostDrivenDay : "\u{2014}", detail: "By recorded mileage", icon: "calendar")
                    Divider()
                    compactInsight("Longest trip", value: viewModel.longestTrip?.distanceMiles.milesFormatted ?? Double.zero.milesFormatted, detail: viewModel.longestTrip?.duration.formattedDuration ?? "Not enough data", icon: "road.lanes")
                }
                Divider()
                HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                    compactInsight("Daily average", value: viewModel.averageDailyMiles.milesFormatted, detail: "Across recorded days", icon: "chart.line.uptrend.xyaxis")
                    Divider()
                    compactInsight("Trips", value: "\(viewModel.trips.count)", detail: "All saved trips", icon: "car.side.fill")
                }
            }
        }
    }

    private func compactInsight(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.Color.brand)
                .frame(width: 36, height: 36)
                .background(AppTheme.Color.brand.opacity(0.1), in: Circle())
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Color.textSecondary)
            Text(value)
                .font(.appTitle)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.Color.positive)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var destinationCard: some View {
        AppCard {
            HStack(spacing: AppTheme.Spacing.large) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Color.brand)
                    .frame(width: 54, height: 54)
                    .background(AppTheme.Color.brand.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("Most visited destination")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Text(viewModel.mostVisitedDestination?.name ?? "Not enough data")
                        .font(.appHeadline)
                    Text("\(viewModel.mostVisitedDestination?.count ?? 0) recorded visits")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Color.positive)
                }
                Spacer()
            }
        }
    }

    private var progressCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Monthly progress")
                HStack(alignment: .lastTextBaseline) {
                    Text(viewModel.monthlyBusinessMiles.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("business miles")
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Spacer()
                    Text(viewModel.monthlyProgress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.headline)
                        .foregroundStyle(AppTheme.Color.brand)
                }
                ProgressView(value: viewModel.monthlyProgress)
                    .tint(AppTheme.Color.brand)
                Text("Calculated from saved Business trips this month")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }
        }
    }
}

import SwiftUI

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()
    @State private var ringProgress = 0.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                weeklyHero
                comparison
                SectionHeader(title: "Your driving")
                insightGrid
                destinationCard
                progressCard
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Insights")
        .onAppear {
            withAnimation(.smooth(duration: 0.9)) { ringProgress = 0.76 }
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
                    Text("486")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("mi")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
                Text("Business miles this week")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.right")
                    Text("18% compared to last week")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Color.positive)
                .padding(.top, AppTheme.Spacing.small)
            }
        }
    }

    private var comparison: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            categoryCard("Business", value: "78%", progress: 0.78, tint: AppTheme.Color.brand)
            categoryCard("Personal", value: "22%", progress: 0.22, tint: AppTheme.Color.warning)
        }
    }

    private func categoryCard(_ title: String, value: String, progress: Double, tint: Color) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                ZStack {
                    Circle().stroke(tint.opacity(0.12), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: ringProgress * progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(value).font(.headline)
                }
                .frame(width: 76, height: 76)
                Text(title).font(.appHeadline)
            }
        }
    }

    private var insightGrid: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppTheme.Spacing.medium) {
            compactInsight("Most driven day", value: "Tuesday", detail: "127 miles", icon: "calendar")
            compactInsight("Longest trip", value: "64.8 mi", detail: "1 hr 42 min", icon: "road.lanes")
            compactInsight("Daily average", value: "69.4 mi", detail: "+8.2 this month", icon: "chart.line.uptrend.xyaxis")
            compactInsight("Trips", value: "18", detail: "4 more than last week", icon: "car.side.fill")
        }
    }

    private func compactInsight(_ title: String, value: String, detail: String, icon: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.Color.brand)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.Color.brand.opacity(0.1), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Color.textSecondary)
                Text(value)
                    .font(.appTitle)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Color.positive)
                    .lineLimit(2)
            }
        }
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
                    Text("Downtown Client Office")
                        .font(.appHeadline)
                    Text("12 visits this month")
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
                    Text("1,103")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("/ 1,400 mi")
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Spacer()
                    Text("79%").font(.headline).foregroundStyle(AppTheme.Color.brand)
                }
                ProgressView(value: 0.79)
                    .tint(AppTheme.Color.brand)
                    .scaleEffect(x: 1, y: 2)
                Text("297 miles to your July goal")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }
        }
    }
}

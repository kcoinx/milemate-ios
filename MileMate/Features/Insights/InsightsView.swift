import SwiftUI

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                scoreCard
                SectionHeader(title: "Personalized for you")
                ForEach(viewModel.insights) { insight in
                    insightCard(insight)
                }
                weeklyPattern
            }
            .padding(AppTheme.Spacing.large)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Insights")
    }

    private var scoreCard: some View {
        AppCard {
            HStack(spacing: AppTheme.Spacing.xLarge) {
                ZStack {
                    Circle().stroke(AppTheme.Color.divider.opacity(0.35), lineWidth: 11)
                    Circle()
                        .trim(from: 0, to: Double(viewModel.score) / 100)
                        .stroke(AppTheme.Color.positive, style: .init(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(viewModel.score)")
                        .font(.appMetric)
                }
                .frame(width: 105, height: 105)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Mileage health").font(.appTitle)
                    Text("Excellent")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Color.positive)
                    Text("Your records are consistent and tax-ready.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
            }
        }
    }

    private func insightCard(_ insight: Insight) -> some View {
        let tint: Color = switch insight.kind {
        case .positive: AppTheme.Color.positive
        case .opportunity: AppTheme.Color.warning
        case .information: AppTheme.Color.brand
        }
        return AppCard {
            HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                Image(systemName: insight.systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(insight.title).font(.appHeadline)
                        Spacer()
                        Text(insight.value).font(.subheadline.weight(.bold)).foregroundStyle(tint)
                    }
                    Text(insight.detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var weeklyPattern: some View {
        let days = Array(zip(["M", "T", "W", "T", "F", "S", "S"], [64, 100, 78, 92, 55, 24, 12]))
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Weekly rhythm")
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(days.indices, id: \.self) { index in
                        VStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(AppTheme.Color.brand.opacity(Double(days[index].1) / 120 + 0.15))
                                .frame(height: CGFloat(days[index].1))
                            Text(days[index].0).font(.caption2).foregroundStyle(AppTheme.Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 130, alignment: .bottom)
            }
        }
    }
}

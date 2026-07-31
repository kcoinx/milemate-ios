import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var detail: String?

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())

                Text(value)
                    .font(.appMetric)
                    .foregroundStyle(AppTheme.Color.textPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Color.textSecondary)

                if let detail {
                    Text(detail)
                        .font(.appCaption)
                        .foregroundStyle(tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}


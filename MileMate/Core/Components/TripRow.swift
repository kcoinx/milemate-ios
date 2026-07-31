import SwiftUI

struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            VStack(spacing: 3) {
                Circle()
                    .fill(AppTheme.Color.brand)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(AppTheme.Color.divider)
                    .frame(width: 1, height: 25)
                Image(systemName: "mappin")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Color.accent)
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(trip.destinationName)
                    .font(.appHeadline)
                    .lineLimit(1)
                Text("\(trip.originName) • \(trip.startedAt.shortDisplay)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Color.textSecondary)
                ClassificationBadge(classification: trip.classification)
            }

            Spacer(minLength: AppTheme.Spacing.small)

            VStack(alignment: .trailing, spacing: 5) {
                Text(trip.distanceMiles.milesFormatted)
                    .font(.headline.monospacedDigit())
                Text(trip.estimatedDeduction.currencyFormatted)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Color.positive)
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .accessibilityElement(children: .combine)
    }
}


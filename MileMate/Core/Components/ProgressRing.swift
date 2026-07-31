import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let value: String
    let label: String
    var tint = AppTheme.Color.brand

    @State private var animatedProgress = 0.0

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.13), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.headline.monospacedDigit())
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 82, height: 82)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.smooth(duration: 0.8)) {
                animatedProgress = min(max(progress, 0), 1)
            }
        }
    }
}


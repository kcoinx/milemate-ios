import SwiftUI

struct ClassificationBadge: View {
    let classification: Trip.Classification

    private var tint: Color {
        switch classification {
        case .business: AppTheme.Color.positive
        case .personal: AppTheme.Color.accent
        case .unclassified: AppTheme.Color.warning
        }
    }

    var body: some View {
        Text(classification.rawValue)
            .font(.appCaption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}


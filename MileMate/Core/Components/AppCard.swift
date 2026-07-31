import SwiftUI

struct AppCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Color.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                    .stroke(AppTheme.Color.divider.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(
                color: AppTheme.Shadow.color,
                radius: AppTheme.Shadow.radius,
                y: AppTheme.Shadow.y
            )
    }
}


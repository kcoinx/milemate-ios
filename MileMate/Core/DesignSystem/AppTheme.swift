import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppTheme {
    enum Color {
        static let brand = SwiftUI.Color("BrandColor")
        static let accent = SwiftUI.Color("AccentColor")
        static let positive = SwiftUI.Color("PositiveColor")
        static let warning = SwiftUI.Color("WarningColor")
        static let canvas = SwiftUI.Color(uiColor: .systemGroupedBackground)
        static let surface = SwiftUI.Color(uiColor: .secondarySystemGroupedBackground)
        static let elevated = SwiftUI.Color(uiColor: .tertiarySystemGroupedBackground)
        static let textPrimary = SwiftUI.Color(uiColor: .label)
        static let textSecondary = SwiftUI.Color(uiColor: .secondaryLabel)
        static let divider = SwiftUI.Color(uiColor: .separator)
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
        static let xxLarge: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 22
    }

    enum Shadow {
        static let color = SwiftUI.Color.black.opacity(0.08)
        static let radius: CGFloat = 16
        static let y: CGFloat = 6
    }
}

extension Font {
    static let appLargeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let appTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    static let appHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let appMetric = Font.system(size: 28, weight: .bold, design: .rounded)
    static let appCaption = Font.system(.caption, design: .rounded, weight: .medium)
}

import SwiftUI
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum Appearance: String, CaseIterable { case system = "System", light = "Light", dark = "Dark" }
    var smartReminders = true
    var weeklySummary = true
    var appearance: Appearance = .system

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}


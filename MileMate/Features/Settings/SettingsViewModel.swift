import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var smartReminders = true
    var weeklySummary = true
}

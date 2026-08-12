import AudioToolbox
import Foundation
import UIKit

enum TrackingDiagnostics {
    static func log(_ message: String) {
        #if DEBUG
        print("[MileMate Tracking] \(message)")
        #endif
    }
}

enum TripFeedbackSettings {
    static let enabledKey = "tripSoundsAndHapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

@MainActor
enum TripFeedback {
    static func started() {
        guard TripFeedbackSettings.isEnabled else { return }
        AudioServicesPlaySystemSound(1104)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func completed() {
        guard TripFeedbackSettings.isEnabled else { return }
        AudioServicesPlaySystemSound(1104)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

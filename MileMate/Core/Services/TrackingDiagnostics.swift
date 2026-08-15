import AudioToolbox
import Foundation
import UIKit

@MainActor
enum TrackingDiagnostics {
    private static let historyLimit = 120
    private(set) static var recentHistory: [String] = []

    static func log(_ message: String) {
        #if DEBUG
        let entry = "\(Date().ISO8601Format()) \(message)"
        recentHistory.append(entry)
        if recentHistory.count > historyLimit {
            recentHistory.removeFirst(recentHistory.count - historyLimit)
        }
        print("[MileMate Tracking] \(entry)")
        #endif
    }

    static func resetHistory() {
        recentHistory.removeAll(keepingCapacity: true)
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

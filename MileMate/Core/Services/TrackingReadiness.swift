@preconcurrency import CoreLocation
import Foundation

enum BackgroundLocationCapability {
    static var isAvailable: Bool {
        #if MILEMATE_BACKGROUND_LOCATION
        containsLocationMode(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes"))
        #else
        false
        #endif
    }

    static func containsLocationMode(_ plistValue: Any?) -> Bool {
        if let modes = plistValue as? [String] {
            return modes.contains("location")
        }
        if let mode = plistValue as? String {
            return mode.split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .contains("location")
        }
        return false
    }
}

enum AutomaticTrackingReadiness: Equatable {
    case ready
    case locationPermissionRequired
    case motionPermissionRequired
    case backgroundCapabilityUnavailable

    static func evaluate(
        location: CLAuthorizationStatus,
        motion: MotionPermissionStatus,
        backgroundCapabilityAvailable: Bool
    ) -> AutomaticTrackingReadiness {
        guard location == .authorizedAlways else {
            return .locationPermissionRequired
        }
        guard case .authorized = motion else {
            return .motionPermissionRequired
        }
        guard backgroundCapabilityAvailable else {
            return .backgroundCapabilityUnavailable
        }
        return .ready
    }
}

@preconcurrency import CoreLocation
import Foundation

enum BackgroundLocationCapability {
    static var isAvailable: Bool {
        containsLocationMode(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes"))
    }

    static func containsLocationMode(_ plistValue: Any?) -> Bool {
        if let modes = plistValue as? [String] {
            return modes.contains("location")
        }
        if let modes = plistValue as? [Any] {
            return modes.contains { ($0 as? String) == "location" }
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

enum TrackingPermissionAction: Equatable {
    case location
    case motion

    init?(readiness: AutomaticTrackingReadiness) {
        switch readiness {
        case .locationPermissionRequired:
            self = .location
        case .motionPermissionRequired:
            self = .motion
        case .ready, .backgroundCapabilityUnavailable:
            return nil
        }
    }

    var title: String {
        switch self {
        case .location: "Review Location"
        case .motion: "Review Motion & Fitness"
        }
    }
}

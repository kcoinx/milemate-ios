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
    case detectionServicesUnavailable

    static func evaluate(
        location: CLAuthorizationStatus,
        motion: MotionPermissionStatus,
        backgroundCapabilityAvailable: Bool,
        significantLocationMonitoringAvailable: Bool = true,
        motionActivityMonitoringAvailable: Bool = true
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
        guard significantLocationMonitoringAvailable,
              motionActivityMonitoringAvailable else {
            return .detectionServicesUnavailable
        }
        return .ready
    }
}

struct AutomaticTrackingReadinessSnapshot: Equatable {
    let locationAuthorization: CLAuthorizationStatus
    let motionAuthorization: MotionPermissionStatus
    let backgroundCapabilityAvailable: Bool
    let significantLocationMonitoringAvailable: Bool
    let motionActivityMonitoringAvailable: Bool
    let automaticTrackingEnabled: Bool
    let result: AutomaticTrackingReadiness

    var diagnosticDescription: String {
        """
        Automatic Tracking Readiness:
        Location Authorization: \(locationAuthorization.diagnosticName)
        Motion Authorization: \(motionAuthorization.diagnosticName)
        Background Location Capability: \(backgroundCapabilityAvailable ? "available" : "unavailable")
        Significant Change Monitoring: \(significantLocationMonitoringAvailable ? "available" : "unavailable")
        Motion Activity Monitoring: \(motionActivityMonitoringAvailable ? "available" : "unavailable")
        Automatic Tracking Enabled: \(automaticTrackingEnabled)
        Result: \(result.diagnosticReason)
        """
    }
}

extension AutomaticTrackingReadiness {
    var diagnosticReason: String {
        switch self {
        case .ready: "ready"
        case .locationPermissionRequired: "unavailable — Always Location authorization is required"
        case .motionPermissionRequired: "unavailable — Motion & Fitness authorization is required"
        case .backgroundCapabilityUnavailable: "unavailable — UIBackgroundModes does not contain location"
        case .detectionServicesUnavailable: "unavailable - a required location or motion detection service is unavailable"
        }
    }
}

private extension CLAuthorizationStatus {
    var diagnosticName: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "authorizedAlways"
        case .authorizedWhenInUse: "authorizedWhenInUse"
        @unknown default: "unknown"
        }
    }
}

private extension MotionPermissionStatus {
    var diagnosticName: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .unavailable: "unavailable"
        }
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
        case .ready, .backgroundCapabilityUnavailable, .detectionServicesUnavailable:
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

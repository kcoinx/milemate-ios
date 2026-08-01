@preconcurrency import CoreMotion
import Foundation

enum MotionKind: String, Codable, Sendable {
    case automotive
    case walking
    case running
    case cycling
    case stationary
    case unknown
}

enum MotionConfidence: Int, Codable, Sendable {
    case low
    case medium
    case high
}

struct MotionActivitySample: Codable, Sendable {
    let kind: MotionKind
    let confidence: MotionConfidence
    let timestamp: Date
}

enum MotionPermissionStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

@MainActor
protocol MotionActivityService: AnyObject {
    var permissionStatus: MotionPermissionStatus { get }
    var eventHandler: ((MotionActivitySample) -> Void)? { get set }
    func startUpdates()
    func stopUpdates()
}

@MainActor
final class CoreMotionActivityService: MotionActivityService {
    private let manager = CMMotionActivityManager()
    var eventHandler: ((MotionActivitySample) -> Void)?

    var permissionStatus: MotionPermissionStatus {
        guard CMMotionActivityManager.isActivityAvailable() else {
            return MotionPermissionStatus.unavailable
        }
        let authorizationStatus: CMAuthorizationStatus =
            CMMotionActivityManager.authorizationStatus()
        switch authorizationStatus {
        case CMAuthorizationStatus.notDetermined:
            return MotionPermissionStatus.notDetermined
        case CMAuthorizationStatus.authorized:
            return MotionPermissionStatus.authorized
        case CMAuthorizationStatus.denied:
            return MotionPermissionStatus.denied
        case CMAuthorizationStatus.restricted:
            return MotionPermissionStatus.restricted
        @unknown default:
            return MotionPermissionStatus.unavailable
        }
    }

    func startUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let sample = MotionActivitySample(
                kind: Self.kind(for: activity),
                confidence: Self.confidence(for: activity.confidence),
                timestamp: activity.startDate
            )
            Task { @MainActor [weak self] in
                self?.eventHandler?(sample)
            }
        }
    }

    func stopUpdates() {
        manager.stopActivityUpdates()
    }

    nonisolated private static func kind(for activity: CMMotionActivity) -> MotionKind {
        if activity.automotive { return MotionKind.automotive }
        if activity.cycling { return MotionKind.cycling }
        if activity.running { return MotionKind.running }
        if activity.walking { return MotionKind.walking }
        if activity.stationary { return MotionKind.stationary }
        return MotionKind.unknown
    }

    nonisolated private static func confidence(for confidence: CMMotionActivityConfidence) -> MotionConfidence {
        switch confidence {
        case CMMotionActivityConfidence.low:
            return MotionConfidence.low
        case CMMotionActivityConfidence.medium:
            return MotionConfidence.medium
        case CMMotionActivityConfidence.high:
            return MotionConfidence.high
        @unknown default:
            return MotionConfidence.low
        }
    }
}

#if DEBUG
@MainActor
final class MockMotionActivityService: MotionActivityService {
    var permissionStatus: MotionPermissionStatus = MotionPermissionStatus.authorized
    var eventHandler: ((MotionActivitySample) -> Void)?
    private(set) var isUpdating = false

    func startUpdates() { isUpdating = true }
    func stopUpdates() { isUpdating = false }

    func send(_ sample: MotionActivitySample) {
        guard isUpdating else { return }
        eventHandler?(sample)
    }
}
#endif

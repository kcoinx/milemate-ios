@preconcurrency import CoreLocation
import Foundation

@MainActor
protocol AutomaticLocationService: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var backgroundCapabilityAvailable: Bool { get }
    var eventHandler: ((LocationServiceEvent) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startLowPowerMonitoring()
    func stopLowPowerMonitoring()
    @discardableResult func startPreciseTracking() -> Bool
    func stopPreciseTracking()
}

@MainActor
final class CoreAutomaticLocationService: NSObject, AutomaticLocationService, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var eventHandler: ((LocationServiceEvent) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var backgroundCapabilityAvailable: Bool {
        BackgroundLocationCapability.isAvailable
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startLowPowerMonitoring() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopLowPowerMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    @discardableResult
    func startPreciseTracking() -> Bool {
        guard authorizationStatus == .authorizedAlways else {
            TrackingDiagnostics.log("background tracking unavailable: Always Location is required")
            eventHandler?(.authorizationChanged(authorizationStatus))
            return false
        }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        if backgroundCapabilityAvailable {
            manager.allowsBackgroundLocationUpdates = true
            TrackingDiagnostics.log("background tracking activated")
        } else {
            TrackingDiagnostics.log("background tracking unavailable: location background mode missing")
            eventHandler?(.failed("Background location capability is unavailable."))
            return false
        }
        manager.startUpdatingLocation()
        return true
    }

    func stopPreciseTracking() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.eventHandler?(.authorizationChanged(status))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map {
            LocationSample(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude,
                horizontalAccuracy: $0.horizontalAccuracy,
                timestamp: $0.timestamp,
                speed: $0.speed
            )
        }
        Task { @MainActor [weak self] in
            self?.eventHandler?(.locations(samples))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            return
        }
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.eventHandler?(.failed(message))
        }
    }
}

#if DEBUG
@MainActor
final class MockAutomaticLocationService: AutomaticLocationService {
    var authorizationStatus: CLAuthorizationStatus = CLAuthorizationStatus.authorizedAlways
    var backgroundCapabilityAvailable = true
    var eventHandler: ((LocationServiceEvent) -> Void)?
    private(set) var isLowPowerMonitoring = false
    private(set) var isPreciseTracking = false

    func requestWhenInUseAuthorization() {
        eventHandler?(.authorizationChanged(authorizationStatus))
    }

    func requestAlwaysAuthorization() {
        eventHandler?(.authorizationChanged(authorizationStatus))
    }

    func startLowPowerMonitoring() { isLowPowerMonitoring = true }
    func stopLowPowerMonitoring() { isLowPowerMonitoring = false }
    @discardableResult
    func startPreciseTracking() -> Bool {
        guard authorizationStatus == .authorizedAlways,
              backgroundCapabilityAvailable else { return false }
        isPreciseTracking = true
        return true
    }
    func stopPreciseTracking() { isPreciseTracking = false }

    func send(_ samples: [LocationSample]) {
        eventHandler?(.locations(samples))
    }
}
#endif

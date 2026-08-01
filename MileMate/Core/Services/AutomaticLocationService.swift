@preconcurrency import CoreLocation
import Foundation

@MainActor
protocol AutomaticLocationService: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var eventHandler: ((LocationServiceEvent) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startLowPowerMonitoring()
    func stopLowPowerMonitoring()
    func startPreciseTracking()
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

    func startPreciseTracking() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
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
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
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
    func startPreciseTracking() { isPreciseTracking = true }
    func stopPreciseTracking() { isPreciseTracking = false }

    func send(_ samples: [LocationSample]) {
        eventHandler?(.locations(samples))
    }
}
#endif

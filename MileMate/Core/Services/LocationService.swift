@preconcurrency import CoreLocation
import Foundation

struct LocationSample: Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

enum LocationServiceEvent: Sendable {
    case authorizationChanged(CLAuthorizationStatus)
    case locations([LocationSample])
    case failed(String)
}

@MainActor
protocol LocationService: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var eventHandler: ((LocationServiceEvent) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

@MainActor
final class CoreLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var eventHandler: ((LocationServiceEvent) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
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
                timestamp: $0.timestamp
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

struct LocationSampleProcessor {
    private(set) var acceptedSamples: [LocationSample] = []
    private(set) var distanceMeters = 0.0

    mutating func reset() {
        acceptedSamples = []
        distanceMeters = 0
    }

    @discardableResult
    mutating func process(_ sample: LocationSample, now: Date = .now) -> Bool {
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= 100,
              abs(sample.timestamp.timeIntervalSince(now)) <= 15 else {
            return false
        }

        if let previous = acceptedSamples.last {
            let seconds = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { return false }

            let previousLocation = CLLocation(
                latitude: previous.latitude,
                longitude: previous.longitude
            )
            let currentLocation = CLLocation(
                latitude: sample.latitude,
                longitude: sample.longitude
            )
            let movement = currentLocation.distance(from: previousLocation)

            guard movement >= 3, movement / seconds <= 75 else {
                return false
            }
            distanceMeters += movement
        }

        acceptedSamples.append(sample)
        return true
    }
}

#if DEBUG
@MainActor
final class MockLocationService: LocationService {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var eventHandler: ((LocationServiceEvent) -> Void)?
    private(set) var isUpdating = false

    func requestWhenInUseAuthorization() {
        eventHandler?(.authorizationChanged(authorizationStatus))
    }

    func startUpdatingLocation() {
        isUpdating = true
    }

    func stopUpdatingLocation() {
        isUpdating = false
    }

    func send(_ samples: [LocationSample]) {
        guard isUpdating else { return }
        eventHandler?(.locations(samples))
    }
}
#endif

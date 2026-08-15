@preconcurrency import CoreLocation
import Foundation

struct LocationSample: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
    var speed: Double = -1
}

enum LocationServiceEvent: Sendable {
    case authorizationChanged(CLAuthorizationStatus)
    case locations([LocationSample])
    case failed(String)
}

@MainActor
protocol LocationService: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var backgroundCapabilityAvailable: Bool { get }
    var eventHandler: ((LocationServiceEvent) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    @discardableResult func startUpdatingLocation() -> Bool
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

    var backgroundCapabilityAvailable: Bool {
        BackgroundLocationCapability.isAvailable
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    @discardableResult
    func startUpdatingLocation() -> Bool {
        if authorizationStatus == .authorizedAlways,
           backgroundCapabilityAvailable {
            manager.allowsBackgroundLocationUpdates = true
            TrackingDiagnostics.log("background tracking activated")
        } else {
            TrackingDiagnostics.log("background tracking unavailable")
        }
        manager.startUpdatingLocation()
        return true
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
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

struct LocationSampleProcessor {
    enum Result: Equatable {
        case accepted
        case rejectedInvalidAccuracy
        case rejectedStale
        case rejectedNonIncreasingTime
        case rejectedInsufficientMovement
        case rejectedImplausibleSpeed
    }

    private(set) var acceptedSamples: [LocationSample] = []
    private(set) var distanceMeters = 0.0

    mutating func reset() {
        acceptedSamples = []
        distanceMeters = 0
    }

    mutating func restore(samples: [LocationSample], distanceMeters: Double) {
        acceptedSamples = samples
        self.distanceMeters = max(distanceMeters, 0)
    }

    @discardableResult
    mutating func process(_ sample: LocationSample, now: Date = .now) -> Bool {
        processWithResult(sample, now: now) == .accepted
    }

    @discardableResult
    mutating func processWithResult(_ sample: LocationSample, now: Date = .now) -> Result {
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= 100 else {
            return .rejectedInvalidAccuracy
        }
        guard abs(sample.timestamp.timeIntervalSince(now)) <= 15 else {
            return .rejectedStale
        }

        if let previous = acceptedSamples.last {
            let seconds = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { return .rejectedNonIncreasingTime }

            let previousLocation = CLLocation(
                latitude: previous.latitude,
                longitude: previous.longitude
            )
            let currentLocation = CLLocation(
                latitude: sample.latitude,
                longitude: sample.longitude
            )
            let movement = currentLocation.distance(from: previousLocation)

            guard movement >= 3 else { return .rejectedInsufficientMovement }
            guard movement / seconds <= 75 else { return .rejectedImplausibleSpeed }
            distanceMeters += movement
        }

        acceptedSamples.append(sample)
        return .accepted
    }
}

#if DEBUG
@MainActor
final class MockLocationService: LocationService {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var backgroundCapabilityAvailable = true
    var eventHandler: ((LocationServiceEvent) -> Void)?
    private(set) var isUpdating = false

    func requestWhenInUseAuthorization() {
        eventHandler?(.authorizationChanged(authorizationStatus))
    }

    func requestAlwaysAuthorization() {
        eventHandler?(.authorizationChanged(authorizationStatus))
    }

    @discardableResult
    func startUpdatingLocation() -> Bool {
        isUpdating = true
        return true
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

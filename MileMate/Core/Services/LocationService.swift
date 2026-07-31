import CoreLocation
import Foundation

struct LocationServiceStatus: Sendable {
    let authorization: CLAuthorizationStatus
    let isTracking: Bool
}

protocol LocationService: Sendable {
    func status() async -> LocationServiceStatus
}

/// Milestone-one implementation. It deliberately performs no location requests or tracking.
struct InactiveLocationService: LocationService {
    func status() async -> LocationServiceStatus {
        LocationServiceStatus(authorization: .notDetermined, isTracking: false)
    }
}


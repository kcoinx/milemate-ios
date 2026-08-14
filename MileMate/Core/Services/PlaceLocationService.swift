@preconcurrency import CoreLocation
@preconcurrency import MapKit
import Foundation

struct PlaceLocationSelection: Identifiable, Equatable, Sendable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var id: String {
        "\(latitude),\(longitude),\(name)"
    }
}

enum PlaceLocationError: LocalizedError, Equatable {
    case permissionDenied
    case locationUnavailable
    case noSearchResults

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Location access is unavailable. Allow location access in iPhone Settings to use your current location."
        case .locationUnavailable:
            "MileMate could not determine your current location. Please try again or search for an address."
        case .noSearchResults:
            "No matching locations were found. Try a more specific address or place name."
        }
    }
}

@MainActor
protocol PlaceLocationProviding: AnyObject {
    func search(query: String) async throws -> [PlaceLocationSelection]
    func currentLocation() async throws -> PlaceLocationSelection
    func selection(latitude: Double, longitude: Double) async throws -> PlaceLocationSelection
}

@MainActor
final class ApplePlaceLocationService: NSObject, PlaceLocationProviding, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<(Double, Double), Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func search(query: String) async throws -> [PlaceLocationSelection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        let response = try await MKLocalSearch(request: request).start()
        let results = response.mapItems.prefix(8).map { item in
            let placemark = item.placemark
            return PlaceLocationSelection(
                name: item.name ?? placemark.name ?? trimmed,
                address: Self.address(from: placemark),
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
            )
        }
        guard !results.isEmpty else { throw PlaceLocationError.noSearchResults }
        return results
    }

    func currentLocation() async throws -> PlaceLocationSelection {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            throw PlaceLocationError.permissionDenied
        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            throw PlaceLocationError.locationUnavailable
        }

        let coordinate = try await withCheckedThrowingContinuation { continuation in
            locationContinuation?.resume(throwing: PlaceLocationError.locationUnavailable)
            locationContinuation = continuation
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else {
                locationManager.requestLocation()
            }
        }
        return try await selection(
            latitude: coordinate.0,
            longitude: coordinate.1
        )
    }

    func selection(latitude: Double, longitude: Double) async throws -> PlaceLocationSelection {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
        guard let placemark else { throw PlaceLocationError.locationUnavailable }
        return PlaceLocationSelection(
            name: placemark.name ?? "Selected Location",
            address: Self.address(from: placemark),
            latitude: latitude,
            longitude: longitude
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, self.locationContinuation != nil else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.locationManager.requestLocation()
            case .denied, .restricted:
                self.finishLocationRequest(with: .failure(PlaceLocationError.permissionDenied))
            case .notDetermined:
                break
            @unknown default:
                self.finishLocationRequest(with: .failure(PlaceLocationError.locationUnavailable))
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let coordinate = locations.last.map { location in
            (location.coordinate.latitude, location.coordinate.longitude)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let coordinate {
                self.finishLocationRequest(with: .success(coordinate))
            } else {
                self.finishLocationRequest(with: .failure(PlaceLocationError.locationUnavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finishLocationRequest(with: .failure(PlaceLocationError.locationUnavailable))
        }
    }

    private func finishLocationRequest(with result: Result<(Double, Double), Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(with: result)
    }

    private static func address(from placemark: CLPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { value in value }
            .joined(separator: " ")
        let locality = [placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { value in value }
            .joined(separator: ", ")
        let components = [street, locality]
            .filter { component in !component.isEmpty }
        return components.isEmpty ? (placemark.name ?? "Selected Location") : components.joined(separator: "\n")
    }
}

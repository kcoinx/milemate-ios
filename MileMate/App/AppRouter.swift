import Foundation
import Observation

enum AppTab: Hashable {
    case dashboard
    case trips
    case reports
    case insights
    case settings

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .trips: "Trips"
        case .reports: "Reports"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .trips: "car"
        case .reports: "doc.text"
        case .insights: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }
}

struct TripsFilterRequest: Equatable, Sendable {
    let interval: DateInterval
    let classification: Trip.Classification
    let vehicleID: UUID?
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .dashboard
    var requestedTrip: Trip?
    var requestedTripsFilter: TripsFilterRequest?
    var requestedReviewQueue = false

    private let repository: any MileageRepository
    private weak var automaticTripCoordinator: AutomaticTripCoordinator?

    init(
        repository: any MileageRepository,
        automaticTripCoordinator: AutomaticTripCoordinator
    ) {
        self.repository = repository
        self.automaticTripCoordinator = automaticTripCoordinator
    }

    func showAutomaticTripReview() {
        selectedTab = .dashboard
    }

    func showTrips(
        for interval: DateInterval,
        classification: Trip.Classification,
        vehicleID: UUID?
    ) {
        requestedTripsFilter = TripsFilterRequest(
            interval: interval,
            classification: classification,
            vehicleID: vehicleID
        )
        selectedTab = .trips
    }

    func showTrackingPermissions() {
        selectedTab = .settings
    }

    func showReviewQueue() {
        requestedReviewQueue = true
        selectedTab = .trips
    }

    func showManualTracking() {
        selectedTab = .dashboard
    }

    func showTripDetails(tripID: UUID) async {
        requestedTrip = nil
        selectedTab = .trips
        let trips = (try? await repository.fetchTrips()) ?? []
        requestedTrip = trips.first(where: { $0.id == tripID })
    }

    func handleNotificationTap(tripID: UUID) async {
        if automaticTripCoordinator?.pendingTrip?.id == tripID {
            requestedTrip = nil
            selectedTab = .dashboard
            return
        }

        await showTripDetails(tripID: tripID)
    }
}

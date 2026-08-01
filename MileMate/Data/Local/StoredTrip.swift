import Foundation
import SwiftData

@Model
final class StoredTrip {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var originName: String
    var destinationName: String
    var distanceMiles: Double
    var distanceMeters: Double = 0
    var durationSeconds: Double = 0
    var estimatedDeductionAmount: Double = 0
    var classificationRawValue: String
    var purpose: String
    var notes: String = ""
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var routeData: Data = Data()
    var vehicleID: UUID?
    var vehicleNickname: String?
    var vehicleYear: Int?
    var vehicleMake: String?
    var vehicleModel: String?
    var vehicleLicensePlateNickname: String?
    var classificationSourceRawValue: String?
    var appliedRuleID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(trip: Trip) {
        id = trip.id
        startedAt = trip.startedAt
        endedAt = trip.endedAt
        originName = trip.originName
        destinationName = trip.destinationName
        distanceMiles = trip.distanceMiles
        distanceMeters = trip.distanceMiles * 1_609.344
        durationSeconds = trip.duration
        estimatedDeductionAmount = trip.estimatedDeduction
        classificationRawValue = trip.classification.rawValue
        purpose = trip.purpose
        notes = trip.notes
        startLatitude = trip.startCoordinate?.latitude
        startLongitude = trip.startCoordinate?.longitude
        endLatitude = trip.endCoordinate?.latitude
        endLongitude = trip.endCoordinate?.longitude
        routeData = (try? JSONEncoder().encode(trip.route)) ?? Data()
        applyVehicle(trip.vehicle)
        classificationSourceRawValue = trip.classificationSource?.rawValue
        appliedRuleID = trip.appliedRuleID
        createdAt = trip.createdAt
        updatedAt = trip.updatedAt
    }

    func update(from trip: Trip) {
        startedAt = trip.startedAt
        endedAt = trip.endedAt
        originName = trip.originName
        destinationName = trip.destinationName
        distanceMiles = trip.distanceMiles
        distanceMeters = trip.distanceMiles * 1_609.344
        durationSeconds = trip.duration
        estimatedDeductionAmount = trip.estimatedDeduction
        classificationRawValue = trip.classification.rawValue
        purpose = trip.purpose
        notes = trip.notes
        startLatitude = trip.startCoordinate?.latitude
        startLongitude = trip.startCoordinate?.longitude
        endLatitude = trip.endCoordinate?.latitude
        endLongitude = trip.endCoordinate?.longitude
        routeData = (try? JSONEncoder().encode(trip.route)) ?? Data()
        applyVehicle(trip.vehicle)
        classificationSourceRawValue = trip.classificationSource?.rawValue
        appliedRuleID = trip.appliedRuleID
        updatedAt = .now
    }

    var domainModel: Trip {
        let route = (try? JSONDecoder().decode([TripCoordinate].self, from: routeData)) ?? []
        return Trip(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            originName: originName,
            destinationName: destinationName,
            distanceMiles: distanceMeters > 0 ? distanceMeters / 1_609.344 : distanceMiles,
            classification: Trip.Classification(rawValue: classificationRawValue) ?? .unclassified,
            purpose: purpose,
            notes: notes,
            startCoordinate: coordinate(latitude: startLatitude, longitude: startLongitude, fallback: startedAt),
            endCoordinate: coordinate(latitude: endLatitude, longitude: endLongitude, fallback: endedAt),
            route: route,
            vehicle: vehicleSnapshot,
            classificationSource: Trip.ClassificationSource(rawValue: classificationSourceRawValue ?? "") ?? .user,
            appliedRuleID: appliedRuleID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private var vehicleSnapshot: VehicleSnapshot? {
        guard let vehicleID, let vehicleNickname else { return nil }
        return VehicleSnapshot(
            id: vehicleID,
            nickname: vehicleNickname,
            year: vehicleYear,
            make: vehicleMake ?? "",
            model: vehicleModel ?? "",
            licensePlateNickname: vehicleLicensePlateNickname ?? ""
        )
    }

    private func applyVehicle(_ vehicle: VehicleSnapshot?) {
        vehicleID = vehicle?.id
        vehicleNickname = vehicle?.nickname
        vehicleYear = vehicle?.year
        vehicleMake = vehicle?.make
        vehicleModel = vehicle?.model
        vehicleLicensePlateNickname = vehicle?.licensePlateNickname
    }

    private func coordinate(latitude: Double?, longitude: Double?, fallback: Date) -> TripCoordinate? {
        guard let latitude, let longitude else { return nil }
        return TripCoordinate(latitude: latitude, longitude: longitude, timestamp: fallback)
    }
}

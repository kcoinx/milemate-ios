import Foundation
import SwiftData

@Model
final class StoredVehicle {
    @Attribute(.unique) var id: UUID
    var ownerScope: String?
    var nickname: String
    var year: Int?
    var make: String
    var model: String
    var licensePlateNickname: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    init(vehicle: Vehicle, ownerScope: String? = nil) {
        id = vehicle.id
        self.ownerScope = ownerScope
        nickname = vehicle.nickname
        year = vehicle.year
        make = vehicle.make
        model = vehicle.model
        licensePlateNickname = vehicle.licensePlateNickname
        isDefault = vehicle.isDefault
        createdAt = vehicle.createdAt
        updatedAt = vehicle.updatedAt
    }

    var domainModel: Vehicle {
        Vehicle(
            id: id,
            nickname: nickname,
            year: year,
            make: make,
            model: model,
            licensePlateNickname: licensePlateNickname,
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from vehicle: Vehicle) {
        nickname = vehicle.nickname
        year = vehicle.year
        make = vehicle.make
        model = vehicle.model
        licensePlateNickname = vehicle.licensePlateNickname
        isDefault = vehicle.isDefault
        updatedAt = .now
    }
}

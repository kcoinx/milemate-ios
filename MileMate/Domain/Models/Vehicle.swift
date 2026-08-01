import Foundation

struct Vehicle: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var nickname: String
    var year: Int?
    var make: String
    var model: String
    var licensePlateNickname: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        nickname: String,
        year: Int? = nil,
        make: String = "",
        model: String = "",
        licensePlateNickname: String = "",
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.nickname = nickname
        self.year = year
        self.make = make
        self.model = model
        self.licensePlateNickname = licensePlateNickname
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var snapshot: VehicleSnapshot {
        VehicleSnapshot(
            id: id,
            nickname: nickname,
            year: year,
            make: make,
            model: model,
            licensePlateNickname: licensePlateNickname
        )
    }

    var detail: String {
        [year.map { String($0) }, make.nilIfBlank, model.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct VehicleSnapshot: Hashable, Codable, Sendable {
    let id: UUID
    let nickname: String
    let year: Int?
    let make: String
    let model: String
    let licensePlateNickname: String
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

import Foundation

struct MockMileageRepository: MileageRepository {
    func fetchTrips() async throws -> [Trip] {
        MockData.trips
    }

    func fetchSummary() async throws -> MileageSummary {
        MockData.summary
    }

    func fetchProfile() async throws -> UserProfile {
        MockData.profile
    }

    func save(_ trip: Trip) async throws {}
    func update(_ trip: Trip) async throws {}
    func delete(_ trip: Trip) async throws {}
}

enum MockData {
    private static let calendar = Calendar.current
    private static let now = Date()

    static let profile = UserProfile(
        firstName: "Alex",
        occupation: "Independent Consultant",
        vehicleName: "2024 Tesla Model Y",
        deductionRate: 0.70,
        taxRate: 0.22
    )

    static let trips: [Trip] = [
        trip(daysAgo: 0, hour: 9, duration: 38, from: "Home", to: "Downtown Client Office", miles: 18.4, type: .business, purpose: "Client meeting"),
        trip(daysAgo: 0, hour: 13, duration: 24, from: "Downtown Client Office", to: "The Commons", miles: 9.8, type: .business, purpose: "Project lunch"),
        trip(daysAgo: 1, hour: 16, duration: 42, from: "The Commons", to: "Home", miles: 21.2, type: .personal, purpose: "Commute"),
        trip(daysAgo: 2, hour: 10, duration: 55, from: "Home", to: "Northside Distribution Center", miles: 31.7, type: .business, purpose: "Site visit"),
        trip(daysAgo: 3, hour: 14, duration: 29, from: "Northside Distribution Center", to: "Airport Terminal 2", miles: 14.6, type: .business, purpose: "Vendor pickup"),
        trip(daysAgo: 5, hour: 8, duration: 36, from: "Home", to: "Westlake Co-working", miles: 16.9, type: .unclassified, purpose: "Needs review")
    ]

    static let summary = MileageSummary(
        businessMiles: 4_286.4,
        personalMiles: 1_204.7,
        tripCount: 184,
        estimatedDeduction: 3_000.48,
        estimatedTaxSavings: 660.11,
        monthlyMiles: [
            .init(month: "Jan", miles: 492),
            .init(month: "Feb", miles: 538),
            .init(month: "Mar", miles: 611),
            .init(month: "Apr", miles: 704),
            .init(month: "May", miles: 838),
            .init(month: "Jun", miles: 1_103)
        ]
    )

    private static func trip(
        daysAgo: Int,
        hour: Int,
        duration: Int,
        from origin: String,
        to destination: String,
        miles: Double,
        type: Trip.Classification,
        purpose: String
    ) -> Trip {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let start = calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day) ?? day
        return Trip(
            id: UUID(),
            startedAt: start,
            endedAt: calendar.date(byAdding: .minute, value: duration, to: start) ?? start,
            originName: origin,
            destinationName: destination,
            distanceMiles: miles,
            classification: type,
            purpose: purpose
        )
    }
}

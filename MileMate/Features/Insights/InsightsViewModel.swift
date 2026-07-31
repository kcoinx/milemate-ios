import Foundation
import Observation

struct Insight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let value: String
    let systemImage: String
    let kind: Kind

    enum Kind { case positive, opportunity, information }
}

@MainActor
@Observable
final class InsightsViewModel {
    let score = 86
    let insights: [Insight] = [
        .init(title: "Strong business ratio", detail: "78% of your recorded mileage is business-related—9% above last month.", value: "+9%", systemImage: "arrow.up.right", kind: .positive),
        .init(title: "Review one trip", detail: "A 16.9-mile trip from Monday still needs a classification.", value: "16.9 mi", systemImage: "exclamationmark.circle", kind: .opportunity),
        .init(title: "Your busiest day", detail: "Tuesdays average 127 business miles, more than any other weekday.", value: "127 mi", systemImage: "calendar", kind: .information)
    ]
}


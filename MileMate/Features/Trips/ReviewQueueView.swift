import Observation
import SwiftUI

@MainActor
@Observable
final class ReviewQueueViewModel {
    private let repository: any MileageRepository
    private let notificationService: any TripNotificationScheduling

    private(set) var trips: [Trip] = []
    private(set) var vehicles: [Vehicle] = []
    private(set) var places: [FrequentPlace] = []
    private(set) var history: [Trip] = []
    private(set) var rules: [ClassificationRule] = []
    private(set) var suggestion: ClassificationSuggestion?
    var proposedRule: ClassificationRule?
    private(set) var errorMessage: String?

    init(
        repository: any MileageRepository,
        notificationService: any TripNotificationScheduling
    ) {
        self.repository = repository
        self.notificationService = notificationService
    }

    var currentTrip: Trip? { trips.first }
    var pendingCount: Int { trips.count }

    func load() async {
        do {
            async let fetchedTrips = repository.fetchTrips()
            async let fetchedVehicles = repository.fetchVehicles()
            async let fetchedPlaces = repository.fetchFrequentPlaces()
            async let fetchedRules = repository.fetchClassificationRules()
            history = try await fetchedTrips
            vehicles = try await fetchedVehicles
            places = try await fetchedPlaces
            rules = try await fetchedRules
            trips = ReviewQueueService.pendingTrips(from: history)
            updateSuggestion()
            errorMessage = nil
        } catch {
            errorMessage = "Trips to review are temporarily unavailable."
        }
    }

    func classify(_ classification: Trip.Classification) async {
        guard var trip = currentTrip, classification != .unclassified else { return }
        trip = SmartClassificationService.overriding(trip, with: classification)
        do {
            try await repository.update(trip)
            notificationService.cancelNotifications(for: trip.id)
            history.removeAll { $0.id == trip.id }
            history.append(trip)
            proposedRule = ruleProposal(afterConfirming: trip)
            trips.removeFirst()
            updateSuggestion()
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
        } catch {
            errorMessage = "The trip could not be classified."
        }
    }

    func skip() {
        guard !trips.isEmpty else { return }
        trips.append(trips.removeFirst())
        updateSuggestion()
    }

    func dismissError() {
        errorMessage = nil
    }

    func acceptProposedRule() async {
        guard let proposedRule else { return }
        do {
            try await repository.saveClassificationRule(proposedRule)
            rules.append(proposedRule)
            self.proposedRule = nil
            NotificationCenter.default.post(
                name: .mileageClassificationDataDidChange,
                object: proposedRule.id
            )
        } catch {
            errorMessage = "The classification rule could not be saved."
        }
    }

    func declineProposedRule() {
        proposedRule = nil
    }

    private func updateSuggestion() {
        guard let currentTrip else {
            suggestion = nil
            return
        }
        suggestion = SmartClassificationService.suggestion(
            for: currentTrip,
            history: history,
            places: places
        )
    }

    private func ruleProposal(afterConfirming trip: Trip) -> ClassificationRule? {
        let labels = SmartClassificationService.matchingPlaces(for: trip, places: places)
        guard let start = labels.start, let end = labels.end,
              !rules.contains(where: {
                  $0.startPlaceID == start.id && $0.endPlaceID == end.id
              }) else {
            return nil
        }
        let count = history.filter { historicalTrip in
            guard historicalTrip.classification == trip.classification else { return false }
            let historicalLabels = SmartClassificationService.matchingPlaces(
                for: historicalTrip,
                places: places
            )
            return historicalLabels.start?.id == start.id &&
                historicalLabels.end?.id == end.id
        }.count
        guard count >= SmartClassificationService.ruleOfferThreshold else { return nil }
        return ClassificationRule(
            startPlaceID: start.id,
            startLabel: start.label,
            endPlaceID: end.id,
            endLabel: end.label,
            classification: trip.classification
        )
    }
}

struct ReviewQueueView: View {
    private let repository: any MileageRepository
    @State private var viewModel: ReviewQueueViewModel

    init(
        repository: any MileageRepository,
        notificationService: any TripNotificationScheduling
    ) {
        self.repository = repository
        _viewModel = State(
            initialValue: ReviewQueueViewModel(
                repository: repository,
                notificationService: notificationService
            )
        )
    }

    var body: some View {
        ScrollView {
            if let trip = viewModel.currentTrip {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    queueHeader
                    tripCard(trip)
                    actionButtons
                }
                .padding(AppTheme.Spacing.large)
            } else {
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.circle.fill")
                } description: {
                    Text("Your trips are classified.")
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            }
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Review Trips")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .mileageTripsDidChange)) { _ in
            Task { await viewModel.load() }
        }
        .alert(
            "Unable to update trip",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            proposedRuleTitle,
            isPresented: Binding(
                get: { viewModel.proposedRule != nil },
                set: { if !$0 { viewModel.declineProposedRule() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Accept Rule") {
                Task { await viewModel.acceptProposedRule() }
            }
            Button("Not Now", role: .cancel) { viewModel.declineProposedRule() }
        } message: {
            Text("Only rules you approve can automatically classify future trips.")
        }
    }

    private var proposedRuleTitle: String {
        guard let rule = viewModel.proposedRule else { return "Create Classification Rule?" }
        return "Always classify \(rule.startLabel) to \(rule.endLabel) as \(rule.classification.rawValue)?"
    }

    private var queueHeader: some View {
        HStack {
            Text("\(viewModel.pendingCount) \(viewModel.pendingCount == 1 ? "Trip" : "Trips") Need Review")
                .font(.appTitle)
            Spacer()
            Text("One at a time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Color.textSecondary)
        }
    }

    private func tripCard(_ trip: Trip) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                if !trip.route.isEmpty {
                    RouteMapView(
                        origin: trip.originName,
                        destination: trip.destinationName,
                        route: trip.route,
                        height: 190,
                        interactive: false
                    )
                }

                LabeledContent("Start", value: trip.originName)
                LabeledContent("End", value: trip.destinationName)
                Divider()
                LabeledContent("Date", value: trip.startedAt.tripDisplay)
                LabeledContent("Distance", value: trip.distanceMiles.milesFormatted)
                LabeledContent("Duration", value: trip.duration.formattedDuration)
                LabeledContent("Vehicle", value: trip.vehicle?.nickname ?? "No vehicle assigned")
                LabeledContent(
                    "Estimated deduction if Business",
                    value: MileageDeductionService.deduction(
                        miles: trip.distanceMiles,
                        classification: .business
                    ).currencyFormatted
                )
                if !trip.purpose.isEmpty {
                    LabeledContent("Trip purpose", value: trip.purpose)
                }

                if let suggestion = viewModel.suggestion {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Suggested: \(suggestion.classification.rawValue)")
                                .font(.subheadline.weight(.semibold))
                            Text(suggestion.explanation)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(AppTheme.Color.warning)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack(spacing: AppTheme.Spacing.medium) {
                classificationButton(
                    "Business",
                    icon: "briefcase.fill",
                    tint: AppTheme.Color.brand,
                    classification: .business
                )
                classificationButton(
                    "Personal",
                    icon: "person.fill",
                    tint: AppTheme.Color.warning,
                    classification: .personal
                )
            }

            HStack {
                Button("Skip for now") { viewModel.skip() }
                    .frame(minHeight: 44)
                Spacer()
                if let trip = viewModel.currentTrip {
                    NavigationLink {
                        TripDetailView(trip: trip, repository: repository)
                    } label: {
                        Label("Edit details", systemImage: "pencil")
                    }
                    .frame(minHeight: 44)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private func classificationButton(
        _ title: String,
        icon: String,
        tint: Color,
        classification: Trip.Classification
    ) -> some View {
        Button {
            Task { await viewModel.classify(classification) }
        } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(tint, in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        }
        .accessibilityHint("Classifies this trip as \(title)")
    }
}

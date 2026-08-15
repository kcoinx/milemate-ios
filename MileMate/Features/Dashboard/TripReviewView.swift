import SwiftUI

struct TripReviewView<Coordinator: TripReviewCoordinating>: View {
    let trip: Trip
    let repository: any MileageRepository
    @Bindable var coordinator: Coordinator
    let onSaved: () -> Void

    @State private var classification: Trip.Classification
    @State private var purposeSelection: String
    @State private var customPurpose: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingShortTripConfirmation = false
    @State private var vehicles: [Vehicle] = []
    @State private var selectedVehicleID: UUID?
    @State private var suggestion: ClassificationSuggestion?
    @State private var appliedRule: ClassificationRule?

    init(
        trip: Trip,
        repository: any MileageRepository,
        coordinator: Coordinator,
        onSaved: @escaping () -> Void
    ) {
        self.trip = trip
        self.repository = repository
        _coordinator = Bindable(wrappedValue: coordinator)
        self.onSaved = onSaved
        _classification = State(initialValue: trip.classification)
        if trip.purpose.isEmpty {
            _purposeSelection = State(initialValue: "")
            _customPurpose = State(initialValue: "")
        } else if TripPurposeOptions.presets.contains(trip.purpose) {
            _purposeSelection = State(initialValue: trip.purpose)
            _customPurpose = State(initialValue: "")
        } else {
            _purposeSelection = State(initialValue: TripPurposeOptions.other)
            _customPurpose = State(initialValue: trip.purpose)
        }
        _notes = State(initialValue: trip.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    RouteMapView(
                        origin: coordinator.pendingTrip?.originName ?? trip.originName,
                        destination: coordinator.pendingTrip?.destinationName ?? trip.destinationName,
                        route: coordinator.pendingTrip?.route ?? trip.route,
                        startCoordinate: coordinator.pendingTrip?.startCoordinate ?? trip.startCoordinate,
                        endCoordinate: coordinator.pendingTrip?.endCoordinate ?? trip.endCoordinate,
                        height: 190,
                        interactive: false
                    )
                    LabeledContent("Start", value: coordinator.pendingTrip?.originName ?? trip.originName)
                    LabeledContent("End", value: coordinator.pendingTrip?.destinationName ?? trip.destinationName)
                    LabeledContent("Distance", value: trip.distanceMiles.milesFormatted)
                    LabeledContent("Duration", value: trip.duration.formattedDuration)
                    LabeledContent("Started", value: trip.startedAt.tripDisplay)
                    LabeledContent("Estimated deduction", value: MileageDeductionService.deduction(
                        miles: trip.distanceMiles,
                        classification: classification
                    ).currencyFormatted)
                }

                Section("Classification") {
                    if let suggestion {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Suggested: \(suggestion.classification.rawValue)")
                                    .font(.subheadline.weight(.semibold))
                                Text(suggestion.explanation)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(AppTheme.Color.warning)
                        }
                    }
                    Picker("Classification", selection: $classification) {
                        ForEach(Trip.Classification.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Vehicle") {
                    Picker("Vehicle", selection: $selectedVehicleID) {
                        Text("No vehicle assigned").tag(UUID?.none)
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.nickname).tag(Optional(vehicle.id))
                        }
                    }
                }

                Section("Trip Purpose") {
                    Picker("Purpose", selection: $purposeSelection) {
                        Text("Not specified").tag("")
                        ForEach(TripPurposeOptions.presets, id: \.self) {
                            Text($0).tag($0)
                        }
                        Text(TripPurposeOptions.other).tag(TripPurposeOptions.other)
                    }

                    if purposeSelection == TripPurposeOptions.other {
                        TextField("Custom trip purpose", text: $customPurpose)
                    }
                }

                Section("Notes") {
                    TextField("Optional trip notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        if trip.distanceMiles < 0.10 {
                            showingShortTripConfirmation = true
                        } else {
                            save()
                        }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save Trip")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Color.brand)
                    .disabled(isSaving)
                    .accessibilityHint("Saves this trip with the selected classification and details")

                    Button(role: .destructive) {
                        coordinator.discardPendingTrip()
                    } label: {
                        Text("Discard Trip")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isSaving)
                    .padding(.top, AppTheme.Spacing.small)
                    .accessibilityHint("Permanently discards this recorded trip")
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Review Trip")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadReviewContext() }
            .confirmationDialog(
                "This trip is very short. Save anyway?",
                isPresented: $showingShortTripConfirmation,
                titleVisibility: .visible
            ) {
                Button("Save") { save() }
                Button("Discard", role: .destructive) {
                    coordinator.discardPendingTrip()
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await coordinator.savePendingTrip(
                    classification: classification,
                    purpose: resolvedPurpose,
                    notes: notes,
                    vehicle: selectedVehicle?.snapshot,
                    classificationSource: appliedRule == nil ? .user : .approvedRule,
                    appliedRuleID: appliedRule?.id
                )
                onSaved()
            } catch {
                errorMessage = "The trip could not be saved. Please try again."
                isSaving = false
            }
        }
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == selectedVehicleID }
    }

    private func loadReviewContext() async {
        async let fetchedVehicles = repository.fetchVehicles()
        async let fetchedTrips = repository.fetchTrips()
        async let fetchedPlaces = repository.fetchFrequentPlaces()
        async let fetchedRules = repository.fetchClassificationRules()
        let vehicles = (try? await fetchedVehicles) ?? []
        let history = (try? await fetchedTrips) ?? []
        let places = (try? await fetchedPlaces) ?? []
        let rules = (try? await fetchedRules) ?? []
        self.vehicles = vehicles
        selectedVehicleID = trip.vehicle?.id ?? vehicles.first(where: \.isDefault)?.id
        suggestion = SmartClassificationService.suggestion(
            for: trip,
            history: history,
            places: places
        )
        let automaticClassificationEnabled = UserDefaults.standard.bool(
            forKey: ClassificationSettings.automaticRulesEnabledKey
        )
        if automaticClassificationEnabled,
           let rule = SmartClassificationService.matchingRule(
               for: trip,
               places: places,
               rules: rules,
               automaticClassificationEnabled: automaticClassificationEnabled
           ) {
            appliedRule = rule
            classification = rule.classification
            save()
        }
    }

    private var resolvedPurpose: String {
        purposeSelection == TripPurposeOptions.other
            ? customPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
            : purposeSelection
    }
}

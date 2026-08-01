import SwiftUI

struct TripReviewView: View {
    let trip: Trip
    let coordinator: ManualTripCoordinator
    let onSaved: () -> Void

    @State private var classification: Trip.Classification
    @State private var purposeSelection: String
    @State private var customPurpose: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingShortTripConfirmation = false

    init(trip: Trip, coordinator: ManualTripCoordinator, onSaved: @escaping () -> Void) {
        self.trip = trip
        self.coordinator = coordinator
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
                    Picker("Classification", selection: $classification) {
                        ForEach(Trip.Classification.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
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
                        HStack {
                            Spacer()
                            if isSaving { ProgressView() } else { Text("Save Trip").font(.headline) }
                            Spacer()
                        }
                    }
                    .disabled(isSaving)

                    Button("Discard Trip", role: .destructive) {
                        coordinator.discardPendingTrip()
                    }
                }
            }
            .navigationTitle("Review Trip")
            .navigationBarTitleDisplayMode(.inline)
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
                    notes: notes
                )
                onSaved()
            } catch {
                errorMessage = "The trip could not be saved. Please try again."
                isSaving = false
            }
        }
    }

    private var resolvedPurpose: String {
        purposeSelection == TripPurposeOptions.other
            ? customPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
            : purposeSelection
    }
}

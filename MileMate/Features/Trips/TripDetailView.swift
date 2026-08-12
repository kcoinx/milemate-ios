import SwiftUI

struct TripDetailView: View {
    private let repository: any MileageRepository
    private let originalClassification: Trip.Classification
    private let originalRuleID: UUID?
    @State private var trip: Trip
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var saveError: String?
    @State private var purposeSelection: String
    @State private var customPurpose: String
    @State private var vehicles: [Vehicle] = []
    @State private var selectedVehicleID: UUID?
    @State private var overriddenRule: ClassificationRule?
    @Environment(\.dismiss) private var dismiss

    init(trip: Trip, repository: any MileageRepository) {
        self.repository = repository
        self.originalClassification = trip.classification
        self.originalRuleID = trip.appliedRuleID
        _trip = State(initialValue: trip)
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
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.large) {
                RouteMapView(
                    origin: trip.originName,
                    destination: trip.destinationName,
                    route: trip.route,
                    startCoordinate: trip.startCoordinate,
                    endCoordinate: trip.endCoordinate,
                    height: 330
                )

                routeTimeline
                tripInformation

                if let saveError {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Trip", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(.bordered)
            }
            .padding(AppTheme.Spacing.large)
        }
        .background(AppTheme.Color.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(isEditing ? "Done" : "Edit") {
                if isEditing { persistChanges() }
                isEditing.toggle()
            }
        }
        .confirmationDialog("Delete this trip?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) { deleteTrip() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This trip will be removed from your mileage records.")
        }
        .confirmationDialog(
            "Update the classification rule?",
            isPresented: Binding(
                get: { overriddenRule != nil },
                set: { if !$0 { overriddenRule = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let rule = overriddenRule {
                Button("Update Rule to \(trip.classification.rawValue)") {
                    var updated = rule
                    updated.classification = trip.classification
                    updated.updatedAt = .now
                    overriddenRule = nil
                    Task { try? await repository.saveClassificationRule(updated) }
                }
                Button("Disable Rule", role: .destructive) {
                    var updated = rule
                    updated.isEnabled = false
                    updated.updatedAt = .now
                    overriddenRule = nil
                    Task { try? await repository.saveClassificationRule(updated) }
                }
            }
            Button("Keep Rule", role: .cancel) { overriddenRule = nil }
        } message: {
            Text("This trip was classified by an approved rule. Your override applies immediately.")
        }
        .task {
            vehicles = (try? await repository.fetchVehicles()) ?? []
            selectedVehicleID = trip.vehicle?.id
        }
    }

    private var routeTimeline: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack {
                    Text("Route timeline")
                        .font(.appHeadline)
                    Spacer()
                    if isEditing {
                        Picker("Classification", selection: $trip.classification) {
                            ForEach(Trip.Classification.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .labelsHidden()
                    } else {
                        ClassificationBadge(classification: trip.classification)
                    }
                }

                HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    VStack(spacing: 4) {
                        Circle()
                            .stroke(AppTheme.Color.textSecondary, lineWidth: 2)
                            .frame(width: 12, height: 12)
                        Rectangle()
                            .fill(AppTheme.Color.divider)
                            .frame(width: 2, height: 50)
                        Circle()
                            .fill(AppTheme.Color.brand)
                            .frame(width: 12, height: 12)
                    }
                    .padding(.top, 5)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                        timelineStop(
                            label: "START",
                            time: trip.startedAt.formatted(.dateTime.hour().minute()),
                            location: trip.originName
                        )
                        timelineStop(
                            label: "END",
                            time: trip.endedAt.formatted(.dateTime.hour().minute()),
                            location: trip.destinationName
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Label("Vehicle", systemImage: "car.side.fill")
                        .font(.appHeadline)
                    if isEditing {
                        Picker("Vehicle", selection: $selectedVehicleID) {
                            Text("No vehicle assigned").tag(UUID?.none)
                            ForEach(vehicles) {
                                Text($0.nickname).tag(Optional($0.id))
                            }
                        }
                    } else {
                        Text(trip.vehicle?.nickname ?? "No vehicle assigned")
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                }

                Divider()

                HStack {
                    Label(trip.duration.formattedDuration, systemImage: "clock")
                    Spacer()
                    Label(trip.distanceMiles.milesFormatted, systemImage: "road.lanes")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Color.textSecondary)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func timelineStop(label: String, time: String, location: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.Color.textSecondary)
                Spacer()
                Text(time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }
            Text(location)
                .font(.appHeadline)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var tripInformation: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack {
                    Label("Estimated Deduction", systemImage: "dollarsign.circle.fill")
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Spacer()
                    Text(trip.estimatedDeduction.currencyFormatted)
                        .font(.appTitle)
                        .foregroundStyle(AppTheme.Color.positive)
                }

                Divider()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Label("Trip Purpose", systemImage: "briefcase.fill")
                        .font(.appHeadline)
                    if isEditing {
                        Picker("Trip Purpose", selection: $purposeSelection) {
                            Text("Not specified").tag("")
                            ForEach(TripPurposeOptions.presets, id: \.self) {
                                Text($0).tag($0)
                            }
                            Text(TripPurposeOptions.other).tag(TripPurposeOptions.other)
                        }

                        if purposeSelection == TripPurposeOptions.other {
                            TextField("Custom trip purpose", text: $customPurpose)
                        }
                    } else {
                        Text(trip.purpose.isEmpty ? "Not specified" : trip.purpose)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Label("Notes", systemImage: "note.text")
                        .font(.appHeadline)
                    if isEditing {
                        TextField("Optional trip notes", text: $trip.notes, axis: .vertical)
                            .lineLimit(2...5)
                    } else {
                        Text(trip.notes.isEmpty ? "No notes" : trip.notes)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                }
            }
        }
    }

    private var resolvedPurpose: String {
        purposeSelection == TripPurposeOptions.other
            ? customPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
            : purposeSelection
    }

    private func persistChanges() {
        trip.purpose = resolvedPurpose
        trip.vehicle = vehicles.first { $0.id == selectedVehicleID }?.snapshot
        trip.classificationSource = .user
        trip.appliedRuleID = nil
        trip.updatedAt = .now
        Task {
            do {
                try await repository.update(trip)
                saveError = nil
                NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
                await offerRuleUpdateIfNeeded()
            } catch {
                saveError = "Changes could not be saved."
            }
        }
    }

    private func offerRuleUpdateIfNeeded() async {
        guard trip.classification != originalClassification,
              let originalRuleID else {
            return
        }
        overriddenRule = (try? await repository.fetchClassificationRules())?
            .first { $0.id == originalRuleID }
    }

    private func deleteTrip() {
        Task {
            do {
                try await repository.delete(trip)
                NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
                dismiss()
            } catch {
                saveError = "The trip could not be deleted."
            }
        }
    }
}

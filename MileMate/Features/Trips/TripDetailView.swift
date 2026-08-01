import SwiftUI

struct TripDetailView: View {
    private let repository: any MileageRepository
    @State private var trip: Trip
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var saveError: String?
    @State private var purposeSelection: String
    @State private var customPurpose: String
    @Environment(\.dismiss) private var dismiss

    init(trip: Trip, repository: any MileageRepository) {
        self.repository = repository
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
        trip.updatedAt = .now
        Task {
            do {
                try await repository.update(trip)
                saveError = nil
                NotificationCenter.default.post(name: .mileageTripsDidChange, object: trip.id)
            } catch {
                saveError = "Changes could not be saved."
            }
        }
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

import SwiftUI

struct TripDetailView: View {
    private let repository: any MileageRepository
    @State private var trip: Trip
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    init(trip: Trip, repository: any MileageRepository) {
        self.repository = repository
        _trip = State(initialValue: trip)
    }

    private var averageSpeed: Double {
        guard trip.duration > 0 else { return 0 }
        return trip.distanceMiles / (trip.duration / 3_600)
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
                tripMetrics
                notesCard

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

    private var tripMetrics: some View {
        AppCard {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                HStack {
                    metric("Distance", value: trip.distanceMiles.milesFormatted, icon: "road.lanes")
                    Spacer()
                    metric("Duration", value: trip.duration.formattedDuration, icon: "clock")
                    Spacer()
                    metric("Avg. speed", value: "\(averageSpeed.formatted(.number.precision(.fractionLength(0)))) mph", icon: "speedometer")
                }
                Divider()
                HStack {
                    Text("Estimated IRS deduction")
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Spacer()
                    Text(trip.estimatedDeduction.currencyFormatted)
                        .font(.appTitle)
                        .foregroundStyle(AppTheme.Color.positive)
                }
            }
        }
    }

    private var notesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Label("Trip notes", systemImage: "note.text")
                    .font(.appHeadline)
                if isEditing {
                    TextField("Optional trip notes", text: $trip.purpose, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    Text(trip.purpose.isEmpty ? "No notes" : trip.purpose)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
            }
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(AppTheme.Color.brand)
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(AppTheme.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func persistChanges() {
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

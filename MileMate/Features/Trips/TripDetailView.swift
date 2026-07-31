import SwiftUI

struct TripDetailView: View {
    let trip: Trip
    @State private var showingDeleteConfirmation = false

    private var averageSpeed: Double {
        guard trip.duration > 0 else { return 0 }
        return trip.distanceMiles / (trip.duration / 3_600)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                RouteMapView(
                    origin: trip.originName,
                    destination: trip.destinationName,
                    height: 330
                )

                routeTimeline
                tripMetrics
                notesCard

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
        .toolbar { Button("Edit") {} }
        .confirmationDialog("Delete this trip?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This trip will be removed from your mileage records.")
        }
    }

    private var routeTimeline: some View {
        AppCard {
            HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                VStack(spacing: 4) {
                    Circle().stroke(AppTheme.Color.textSecondary, lineWidth: 2).frame(width: 12, height: 12)
                    Rectangle().fill(AppTheme.Color.divider).frame(width: 2, height: 44)
                    Circle().fill(AppTheme.Color.brand).frame(width: 12, height: 12)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.originName).font(.appHeadline)
                    Text(trip.startedAt.formatted(.dateTime.hour().minute()))
                        .font(.caption).foregroundStyle(AppTheme.Color.textSecondary)
                    Spacer().frame(height: 18)
                    Text(trip.destinationName).font(.appHeadline)
                    Text(trip.endedAt.formatted(.dateTime.hour().minute()))
                        .font(.caption).foregroundStyle(AppTheme.Color.textSecondary)
                }
                Spacer()
                ClassificationBadge(classification: trip.classification)
            }
        }
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
                Text(trip.purpose)
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Color.brand)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

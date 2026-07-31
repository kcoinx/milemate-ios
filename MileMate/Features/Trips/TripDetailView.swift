import MapKit
import SwiftUI

struct TripDetailView: View {
    let trip: Trip

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                Map(initialPosition: .region(.init(
                    center: .init(latitude: 37.7749, longitude: -122.4194),
                    span: .init(latitudeDelta: 0.18, longitudeDelta: 0.18)
                ))) {
                    Marker(trip.originName, coordinate: .init(latitude: 37.735, longitude: -122.445))
                    Marker(trip.destinationName, coordinate: .init(latitude: 37.805, longitude: -122.392))
                        .tint(AppTheme.Color.accent)
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))

                AppCard {
                    VStack(spacing: AppTheme.Spacing.large) {
                        detailRow("Distance", value: trip.distanceMiles.milesFormatted, icon: "road.lanes")
                        Divider()
                        detailRow("Date", value: trip.startedAt.tripDisplay, icon: "calendar")
                        Divider()
                        detailRow("Purpose", value: trip.purpose, icon: "briefcase")
                        Divider()
                        detailRow("Deduction", value: trip.estimatedDeduction.currencyFormatted, icon: "dollarsign.circle")
                    }
                }

                AppCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Classification").font(.appHeadline)
                            Text("Included in your mileage report")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                        }
                        Spacer()
                        ClassificationBadge(classification: trip.classification)
                    }
                }
            }
            .padding(AppTheme.Spacing.large)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Edit") {} }
    }

    private func detailRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(AppTheme.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}


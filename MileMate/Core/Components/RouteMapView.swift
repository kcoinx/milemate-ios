import MapKit
import SwiftUI

struct RouteMapView: View {
    let origin: String
    let destination: String
    var height: CGFloat = 220
    var interactive = true

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                    span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)
                )
            ),
            interactionModes: interactive ? .all : []
        ) {
            Marker(origin, coordinate: CLLocationCoordinate2D(latitude: 37.735, longitude: -122.445))
                .tint(AppTheme.Color.textSecondary)
            Marker(destination, coordinate: CLLocationCoordinate2D(latitude: 37.805, longitude: -122.392))
                .tint(AppTheme.Color.brand)
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .overlay(alignment: .bottomLeading) {
            Label("Route preview", systemImage: "location.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
        }
        .accessibilityLabel("Map preview from \(origin) to \(destination)")
    }
}

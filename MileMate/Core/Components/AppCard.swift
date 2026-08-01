import MapKit
import SwiftUI

struct AppCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Color.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.07) : AppTheme.Color.divider.opacity(0.14),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.07),
                radius: colorScheme == .dark ? 14 : AppTheme.Shadow.radius,
                y: colorScheme == .dark ? 8 : AppTheme.Shadow.y
            )
    }
}

struct ProgressRing: View {
    let progress: Double
    let value: String
    let label: String
    var tint = AppTheme.Color.brand

    @State private var animatedProgress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.13), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.headline.monospacedDigit())
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 82, height: 82)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            if reduceMotion {
                animatedProgress = min(max(progress, 0), 1)
            } else {
                withAnimation(.smooth(duration: 0.8)) {
                    animatedProgress = min(max(progress, 0), 1)
                }
            }
        }
    }
}

struct RouteMapView: View {
    let origin: String
    let destination: String
    var route: [TripCoordinate] = []
    var height: CGFloat = 220
    var interactive = true
    var showsUserLocation = false
    var showsEndMarker = true

    @State private var position: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    @ViewBuilder
    var body: some View {
        if coordinates.isEmpty && !showsUserLocation {
            VStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Color.brand)
                Text("Your recorded route will appear here after your first completed trip.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(AppTheme.Spacing.card)
            .frame(maxWidth: .infinity)
            .frame(minHeight: min(height, 140))
            .background(AppTheme.Color.elevated, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .accessibilityElement(children: .combine)
        } else {
            Map(position: $position, interactionModes: interactive ? .all : []) {
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(AppTheme.Color.brand, lineWidth: 5)
                }
                if let start = coordinates.first {
                    Marker(origin, coordinate: start)
                        .tint(AppTheme.Color.textSecondary)
                }
                if showsEndMarker, let end = coordinates.last {
                    Marker(destination, coordinate: end)
                        .tint(AppTheme.Color.brand)
                }
                if showsUserLocation {
                    UserAnnotation()
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .overlay(alignment: .bottomLeading) {
                Label(showsUserLocation ? "Live Route" : "Recorded Route", systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
            .accessibilityLabel("Recorded route from \(origin) to \(destination)")
            .onAppear { fitRoute() }
            .onChange(of: route) { _, _ in fitRoute() }
        }
    }

    private func fitRoute() {
        guard !coordinates.isEmpty else {
            position = .automatic
            return
        }

        var mapRect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            mapRect = mapRect.union(pointRect)
        }

        let minimumSpan = 1_500.0
        if mapRect.width < minimumSpan || mapRect.height < minimumSpan {
            let center = MKMapPoint(coordinates[coordinates.count / 2])
            mapRect = MKMapRect(
                x: center.x - minimumSpan / 2,
                y: center.y - minimumSpan / 2,
                width: minimumSpan,
                height: minimumSpan
            )
        }
        position = .rect(mapRect.insetBy(dx: -mapRect.width * 0.18, dy: -mapRect.height * 0.18))
    }
}

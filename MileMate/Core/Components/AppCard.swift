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
    var startCoordinate: TripCoordinate?
    var endCoordinate: TripCoordinate?
    var height: CGFloat = 220
    var interactive = true
    var showsUserLocation = false
    var showsEndMarker = true

    @State private var position: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        RouteMapRegionCalculator.displayCoordinates(
            route: route,
            start: startCoordinate,
            end: endCoordinate
        )
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

        position = .rect(RouteMapRegionCalculator.mapRect(for: coordinates))
    }
}

enum RouteMapRegionCalculator {
    static func displayCoordinates(
        route: [TripCoordinate],
        start: TripCoordinate?,
        end: TripCoordinate?
    ) -> [CLLocationCoordinate2D] {
        var points = route.filter { $0.isValid }.map { $0.clLocationCoordinate }
        if let start, start.isValid, !route.contains(start) {
            points.insert(start.clLocationCoordinate, at: 0)
        }
        if let end, end.isValid, !route.contains(end) {
            points.append(end.clLocationCoordinate)
        }
        return points
    }

    static func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        var mapRect = coordinates.reduce(into: MKMapRect.null) { result, coordinate in
            let point = MKMapPoint(coordinate)
            result = result.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let minimumSpan = 1_500.0
        if mapRect.width < minimumSpan {
            let centerX = mapRect.midX
            mapRect = MKMapRect(
                x: centerX - minimumSpan / 2,
                y: mapRect.origin.y,
                width: minimumSpan,
                height: mapRect.height
            )
        }
        if mapRect.height < minimumSpan {
            let centerY = mapRect.midY
            mapRect = MKMapRect(
                x: mapRect.origin.x,
                y: centerY - minimumSpan / 2,
                width: mapRect.width,
                height: minimumSpan
            )
        }
        return mapRect.insetBy(dx: -mapRect.width * 0.18, dy: -mapRect.height * 0.18)
    }
}

private extension TripCoordinate {
    var isValid: Bool {
        CLLocationCoordinate2DIsValid(clLocationCoordinate)
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

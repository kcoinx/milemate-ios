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
            .padding(AppTheme.Spacing.xLarge)
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
            withAnimation(.smooth(duration: 0.8)) {
                animatedProgress = min(max(progress, 0), 1)
            }
        }
    }
}

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

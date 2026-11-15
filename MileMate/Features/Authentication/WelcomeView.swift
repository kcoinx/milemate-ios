import AuthenticationServices
import Foundation
import SwiftUI

enum AuthenticationButtonMetrics {
    static let height: CGFloat = 54
}

struct GoogleAuthenticationLabel: View {
    var usesDarkBackground = false

    var body: some View {
        HStack(spacing: 10) {
            Image("GoogleMark")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            Text("Continue with Google")
                .font(.headline)
                .lineLimit(1)
        }
        .foregroundStyle(usesDarkBackground ? Color.black : AppTheme.Color.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: AuthenticationButtonMetrics.height)
        .background(usesDarkBackground ? Color.white : AppTheme.Color.surface, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.Color.textSecondary.opacity(0.28), lineWidth: 1)
        }
    }
}

struct WelcomeView: View {
    @Bindable var accountSession: AccountSessionController
    let allowsGuestAccess: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var isVisible = false

    var body: some View {
        ZStack {
            cinematicBackground

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        Spacer(minLength: min(max(proxy.size.height * 0.34, 200), 280))

                        VStack(spacing: AppTheme.Spacing.small) {
                            Text(allowsGuestAccess ? "Every Mile Matters." : "Keep Your Miles Moving.")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)

                            Text(welcomeDescription)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: AppTheme.Spacing.small)

                        signInActions
                        guestAccess

                        Spacer(minLength: AppTheme.Spacing.medium)
                    }
                    .frame(maxWidth: 520)
                    .frame(minHeight: max(proxy.size.height - AppTheme.Spacing.large, 0))
                    .padding(.horizontal, AppTheme.Spacing.xLarge)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(welcomeBackground.ignoresSafeArea())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            isVisible = true
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            }
        }
        .onDisappear { isVisible = false }
        .onChange(of: accountSession.isAuthenticated) { _, authenticated in
            if authenticated { dismiss() }
        }
        .alert(
            "Unable to Sign In",
            isPresented: Binding(
                get: { accountSession.authenticationError != nil },
                set: { if !$0 { accountSession.authenticationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { accountSession.authenticationError = nil }
        } message: {
            Text(accountSession.authenticationError ?? "")
        }
        .overlay {
            if accountSession.isAuthenticating {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("Signing in…")
                        .padding(AppTheme.Spacing.xLarge)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var welcomeDescription: String {
        allowsGuestAccess
            ? "Track business drives automatically and keep every mile organized."
            : "Your 10-trip guest trial is complete. Create a free account to keep driving."
    }

    private var welcomeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.025, green: 0.04, blue: 0.06)
            : Color(red: 0.04, green: 0.09, blue: 0.14)
    }

    private var cinematicBackground: some View {
        WelcomeMotionBackground(
            reduceMotion: reduceMotion,
            isActive: isVisible,
            baseColor: welcomeBackground
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var guestAccess: some View {
        if allowsGuestAccess {
            VStack(spacing: AppTheme.Spacing.small) {
                Button {
                    accountSession.continueAsGuest()
                } label: {
                    Text("Try MileMate — 10 Free Trips")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AuthenticationButtonMetrics.height)
                        .background(AppTheme.Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)

                Text("No credit card required.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
            }
        } else {
            Text("Your existing trips remain safely stored on this iPhone.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
    }

    private var signInActions: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            SignInWithAppleButton(.continue) { request in
                accountSession.prepareAppleSignIn(request)
            } onCompletion: { result in
                accountSession.completeAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: AuthenticationButtonMetrics.height)
            .clipShape(Capsule())
            .accessibilityHint("Signs in securely using your Apple Account")

            Button {
                Task { await accountSession.authenticateWithGoogle() }
            } label: {
                GoogleAuthenticationLabel(usesDarkBackground: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Google sign in")
        }
        .disabled(accountSession.isAuthenticating)
    }
}

private struct WelcomeMotionBackground: View {
    let reduceMotion: Bool
    let isActive: Bool
    let baseColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                staticFallback(size: proxy.size)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
                    motionScene(date: timeline.date, size: proxy.size)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func motionScene(date: Date, size: CGSize) -> some View {
        let sceneryPhase = phase(at: date, duration: 16)
        let roadPhase = phase(at: date, duration: 2.8)
        let truckPhase = phase(at: date, duration: 14.5, offset: 0.18)
        let semiPhase = phase(at: date, duration: 12.5, offset: 0.62)
        let sedanPhase = phase(at: date, duration: 8.8, offset: 0.03)

        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: skyColors,
                startPoint: .top,
                endPoint: .bottom
            )

            CinematicSkyline(progress: sceneryPhase, colorScheme: colorScheme)
                .frame(height: size.height * 0.43)
                .offset(y: size.height * 0.04)

            CinematicHighway(progress: roadPhase, colorScheme: colorScheme)
                .frame(height: size.height * 0.52)
                .offset(y: size.height * 0.16)

            PickupTruckView(wheelRotation: truckPhase * 1_440)
                .frame(width: 150, height: 58)
                .position(
                    x: travelX(progress: truckPhase, width: size.width, vehicleWidth: 150),
                    y: size.height * 0.29
                )

            SemiTruckView(wheelRotation: semiPhase * 1_620)
                .frame(width: 172, height: 64)
                .position(
                    x: travelX(progress: semiPhase, width: size.width, vehicleWidth: 172),
                    y: size.height * 0.385
                )

            RideshareSedanView(wheelRotation: sedanPhase * 2_160)
                .frame(width: 108, height: 41)
                .position(
                    x: travelX(progress: sedanPhase, width: size.width, vehicleWidth: 108),
                    y: size.height * 0.44
                )

            fadeOverlay
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func staticFallback(size: CGSize) -> some View {
        Image("WelcomeCinematicBackground")
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay { fadeOverlay }
    }

    private var fadeOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: baseColor.opacity(0.02), location: 0),
                .init(color: baseColor.opacity(0.28), location: 0.32),
                .init(color: baseColor.opacity(0.78), location: 0.55),
                .init(color: baseColor.opacity(0.97), location: 0.68),
                .init(color: baseColor, location: 0.82)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var skyColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.025, green: 0.055, blue: 0.085), Color(red: 0.12, green: 0.18, blue: 0.22)]
            : [Color(red: 0.12, green: 0.22, blue: 0.30), Color(red: 0.30, green: 0.40, blue: 0.44)]
    }

    private func phase(at date: Date, duration: TimeInterval, offset: Double = 0) -> CGFloat {
        let raw = date.timeIntervalSinceReferenceDate / duration + offset
        return CGFloat(raw - floor(raw))
    }

    private func travelX(progress: CGFloat, width: CGFloat, vehicleWidth: CGFloat) -> CGFloat {
        -vehicleWidth + progress * (width + vehicleWidth * 2)
    }
}

private struct CinematicSkyline: View {
    let progress: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            let buildingWidth: CGFloat = 48
            let patternCount = 10
            let period = buildingWidth * CGFloat(patternCount)
            let offset = -progress * period
            let baseY = size.height

            for index in -2...22 {
                let patternIndex = ((index % patternCount) + patternCount) % patternCount
                let height = size.height * (0.28 + CGFloat((patternIndex * 7) % 10) * 0.052)
                let x = CGFloat(index) * buildingWidth + offset
                let building = CGRect(
                    x: x,
                    y: baseY - height,
                    width: buildingWidth - 5,
                    height: height
                )
                let tone = colorScheme == .dark
                    ? Color(red: 0.07, green: 0.10, blue: 0.13)
                    : Color(red: 0.12, green: 0.16, blue: 0.19)
                context.fill(Path(building), with: .color(tone.opacity(0.92)))

                for row in 0..<4 {
                    for column in 0..<3 where (row + column + patternIndex).isMultiple(of: 3) {
                        let window = CGRect(
                            x: building.minX + 8 + CGFloat(column) * 11,
                            y: building.minY + 10 + CGFloat(row) * 15,
                            width: 4,
                            height: 6
                        )
                        context.fill(
                            Path(window),
                            with: .color(Color(red: 0.78, green: 0.70, blue: 0.46).opacity(0.42))
                        )
                    }
                }
            }
        }
    }
}

private struct CinematicHighway: View {
    let progress: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            var road = Path()
            road.move(to: CGPoint(x: 0, y: size.height * 0.16))
            road.addLine(to: CGPoint(x: size.width, y: 0))
            road.addLine(to: CGPoint(x: size.width, y: size.height * 0.92))
            road.addLine(to: CGPoint(x: 0, y: size.height))
            road.closeSubpath()
            let roadColor = colorScheme == .dark
                ? Color(red: 0.075, green: 0.085, blue: 0.095)
                : Color(red: 0.12, green: 0.13, blue: 0.14)
            context.fill(road, with: .color(roadColor))

            var shoulder = Path()
            shoulder.move(to: CGPoint(x: 0, y: size.height * 0.18))
            shoulder.addLine(to: CGPoint(x: size.width, y: size.height * 0.02))
            context.stroke(shoulder, with: .color(.white.opacity(0.42)), lineWidth: 1)

            let dashPeriod: CGFloat = 92
            let dashOffset = -progress * dashPeriod
            for lane in [0.45, 0.70] {
                for index in -2...12 {
                    let x = CGFloat(index) * dashPeriod + dashOffset
                    let dash = CGRect(
                        x: x,
                        y: size.height * lane,
                        width: 48,
                        height: lane == 0.45 ? 2 : 3
                    )
                    context.fill(Path(roundedRect: dash, cornerRadius: 2), with: .color(.white.opacity(0.52)))
                }
            }

            for index in -1...14 {
                let x = CGFloat(index) * 64 - progress * 64
                let post = CGRect(x: x, y: size.height * 0.10, width: 2, height: 17)
                context.fill(Path(post), with: .color(.white.opacity(0.22)))
            }
        }
    }
}

private struct VehicleWheel: View {
    let rotation: Double

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.018, green: 0.022, blue: 0.026))
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            Circle()
                .fill(Color(red: 0.48, green: 0.52, blue: 0.54))
                .padding(3)
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color(red: 0.13, green: 0.15, blue: 0.17).opacity(0.9))
                    .frame(width: 1, height: 6)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
            Circle().fill(Color.gray.opacity(0.82)).frame(width: 2.8, height: 2.8)
        }
        .rotationEffect(.degrees(rotation))
    }
}

private struct PickupTruckView: View {
    let wheelRotation: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PickupBodyShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.28, green: 0.47, blue: 0.56), Color(red: 0.13, green: 0.29, blue: 0.37)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(red: 0.035, green: 0.07, blue: 0.09))
                    .frame(width: proxy.size.width * 0.34, height: proxy.size.height * 0.18)
                    .offset(x: proxy.size.width * 0.055, y: proxy.size.height * 0.27)

                Rectangle()
                    .fill(Color(red: 0.34, green: 0.50, blue: 0.56).opacity(0.68))
                    .frame(width: proxy.size.width * 0.34, height: 2)
                    .offset(x: proxy.size.width * 0.055, y: proxy.size.height * 0.27)

                PickupWindowShape()
                    .fill(Color(red: 0.045, green: 0.10, blue: 0.13))
                    .frame(width: proxy.size.width * 0.34, height: proxy.size.height * 0.24)
                    .offset(x: proxy.size.width * 0.47, y: proxy.size.height * 0.18)

                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: 1.2, height: proxy.size.height * 0.22)
                    .offset(x: proxy.size.width * 0.62, y: proxy.size.height * 0.19)

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: proxy.size.width * 0.82, height: 1)
                    .offset(x: proxy.size.width * 0.10, y: proxy.size.height * 0.55)

                Capsule()
                    .fill(Color(red: 0.92, green: 0.82, blue: 0.56))
                    .frame(width: 6, height: 3)
                    .offset(x: proxy.size.width * 0.93, y: proxy.size.height * 0.49)

                Capsule()
                    .fill(Color(red: 0.74, green: 0.16, blue: 0.12))
                    .frame(width: 4, height: 4)
                    .offset(x: proxy.size.width * 0.025, y: proxy.size.height * 0.48)

                HStack(spacing: proxy.size.width * 0.54) {
                    VehicleWheel(rotation: wheelRotation).frame(width: 16, height: 16)
                    VehicleWheel(rotation: wheelRotation).frame(width: 16, height: 16)
                }
                .offset(x: proxy.size.width * 0.15, y: proxy.size.height * 0.64)
            }
        }
        .shadow(color: .black.opacity(0.32), radius: 3, y: 2)
    }
}

private struct PickupBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.02, y: rect.height * 0.43))
        path.addLine(to: CGPoint(x: rect.width * 0.39, y: rect.height * 0.43))
        path.addLine(to: CGPoint(x: rect.width * 0.46, y: rect.height * 0.17))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.70, y: rect.height * 0.13),
            control: CGPoint(x: rect.width * 0.56, y: rect.height * 0.08)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.80, y: rect.height * 0.40))
        path.addLine(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.44))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.99, y: rect.height * 0.62),
            control: CGPoint(x: rect.maxX, y: rect.height * 0.48)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.96, y: rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.width * 0.04, y: rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.width * 0.01, y: rect.height * 0.63))
        path.closeSubpath()
        return path
    }
}

private struct PickupWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.16, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.66, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SemiTruckView: View {
    let wheelRotation: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                SemiTruckBodyShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.78, green: 0.83, blue: 0.85), Color(red: 0.34, green: 0.40, blue: 0.43)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.37, green: 0.49, blue: 0.54), Color(red: 0.13, green: 0.23, blue: 0.28)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: proxy.size.width * 0.54, height: proxy.size.height * 0.53)
                    .offset(x: proxy.size.width * 0.02, y: proxy.size.height * 0.13)

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: proxy.size.width * 0.50, height: 1)
                    .offset(x: proxy.size.width * 0.04, y: proxy.size.height * 0.20)

                SemiTruckWindowShape()
                    .fill(Color(red: 0.045, green: 0.095, blue: 0.12))
                    .frame(width: proxy.size.width * 0.25, height: proxy.size.height * 0.31)
                    .offset(x: proxy.size.width * 0.61, y: proxy.size.height * 0.17)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: proxy.size.width * 0.27, height: 1)
                    .offset(x: proxy.size.width * 0.60, y: proxy.size.height * 0.52)
                Capsule()
                    .fill(Color(red: 0.95, green: 0.84, blue: 0.58))
                    .frame(width: 6, height: 3)
                    .offset(x: proxy.size.width * 0.955, y: proxy.size.height * 0.54)
                Capsule()
                    .fill(Color(red: 0.72, green: 0.14, blue: 0.11))
                    .frame(width: 3.5, height: 5)
                    .offset(x: proxy.size.width * 0.025, y: proxy.size.height * 0.50)

                VehicleWheel(rotation: wheelRotation)
                    .frame(width: 15, height: 15)
                    .offset(x: proxy.size.width * 0.15, y: proxy.size.height * 0.67)
                VehicleWheel(rotation: wheelRotation)
                    .frame(width: 15, height: 15)
                    .offset(x: proxy.size.width * 0.48, y: proxy.size.height * 0.67)
                VehicleWheel(rotation: wheelRotation)
                    .frame(width: 17, height: 17)
                    .offset(x: proxy.size.width * 0.78, y: proxy.size.height * 0.64)
            }
        }
        .shadow(color: .black.opacity(0.30), radius: 3, y: 2)
    }
}

private struct SemiTruckBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.01, y: rect.height * 0.13))
        path.addLine(to: CGPoint(x: rect.width * 0.57, y: rect.height * 0.13))
        path.addLine(to: CGPoint(x: rect.width * 0.59, y: rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.22))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.49),
            control: CGPoint(x: rect.width * 0.90, y: rect.height * 0.28)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.97, y: rect.height * 0.55))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.99, y: rect.height * 0.71),
            control: CGPoint(x: rect.maxX, y: rect.height * 0.60)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.95, y: rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.width * 0.02, y: rect.height * 0.80))
        path.closeSubpath()
        return path
    }
}

private struct SemiTruckWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width * 0.66, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.82, y: rect.height * 0.16)
        )
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct RideshareSedanView: View {
    let wheelRotation: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                SedanBodyShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.42, blue: 0.52), Color(red: 0.07, green: 0.23, blue: 0.31)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                SedanWindowShape()
                    .fill(Color(red: 0.055, green: 0.10, blue: 0.13))
                    .frame(width: proxy.size.width * 0.48, height: proxy.size.height * 0.29)
                    .offset(x: proxy.size.width * 0.31, y: proxy.size.height * 0.15)
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: 1.1, height: proxy.size.height * 0.25)
                    .offset(x: proxy.size.width * 0.56, y: proxy.size.height * 0.17)
                Rectangle()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: 1.1, height: proxy.size.height * 0.32)
                    .offset(x: proxy.size.width * 0.39, y: proxy.size.height * 0.43)
                Rectangle()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: 1.1, height: proxy.size.height * 0.32)
                    .offset(x: proxy.size.width * 0.68, y: proxy.size.height * 0.43)
                HStack(spacing: proxy.size.width * 0.13) {
                    Capsule().fill(Color.white.opacity(0.36)).frame(width: 6, height: 1.5)
                    Capsule().fill(Color.white.opacity(0.36)).frame(width: 6, height: 1.5)
                }
                .offset(x: proxy.size.width * 0.45, y: proxy.size.height * 0.51)
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: proxy.size.width * 0.76, height: 1)
                    .offset(x: proxy.size.width * 0.12, y: proxy.size.height * 0.57)
                Capsule()
                    .fill(Color(red: 0.16, green: 0.54, blue: 0.40))
                    .frame(width: 8, height: 2)
                    .offset(x: proxy.size.width * 0.82, y: proxy.size.height * 0.54)
                Capsule()
                    .fill(Color(red: 0.95, green: 0.86, blue: 0.63))
                    .frame(width: 5, height: 2.5)
                    .offset(x: proxy.size.width * 0.93, y: proxy.size.height * 0.53)
                Capsule()
                    .fill(Color(red: 0.72, green: 0.14, blue: 0.11))
                    .frame(width: 3.5, height: 3)
                    .offset(x: proxy.size.width * 0.035, y: proxy.size.height * 0.54)
                HStack(spacing: proxy.size.width * 0.53) {
                    VehicleWheel(rotation: wheelRotation).frame(width: 14, height: 14)
                    VehicleWheel(rotation: wheelRotation).frame(width: 14, height: 14)
                }
                .offset(x: proxy.size.width * 0.15, y: proxy.size.height * 0.64)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
    }
}

private struct SedanBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.02, y: rect.height * 0.64))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.23, y: rect.height * 0.43),
            control: CGPoint(x: rect.width * 0.08, y: rect.height * 0.47)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.39, y: rect.height * 0.14))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.70, y: rect.height * 0.17),
            control: CGPoint(x: rect.width * 0.54, y: rect.height * 0.04)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.81, y: rect.height * 0.41))
        path.addLine(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.46))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.98, y: rect.height * 0.63),
            control: CGPoint(x: rect.maxX, y: rect.height * 0.50)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.77))
        path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.77))
        path.closeSubpath()
        return path
    }
}

private struct SedanWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.25, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.70, y: rect.height * 0.07),
            control: CGPoint(x: rect.width * 0.48, y: rect.height * -0.08)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

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
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isActive)) { timeline in
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
        let vanPhase = phase(at: date, duration: 11.5, offset: 0.62)
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

            SemiTruckView(wheelRotation: truckPhase * 1_440)
                .frame(width: 176, height: 62)
                .position(
                    x: travelX(progress: truckPhase, width: size.width, vehicleWidth: 176),
                    y: size.height * 0.29
                )

            DeliveryVanView(wheelRotation: vanPhase * 1_800)
                .frame(width: 119, height: 54)
                .position(
                    x: travelX(progress: vanPhase, width: size.width, vehicleWidth: 119),
                    y: size.height * 0.39
                )

            RideshareSedanView(wheelRotation: sedanPhase * 2_160)
                .frame(width: 98, height: 40)
                .position(
                    x: travelX(progress: sedanPhase, width: size.width, vehicleWidth: 98),
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
            Circle().fill(Color(red: 0.025, green: 0.03, blue: 0.035))
            Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.gray.opacity(0.72))
                    .frame(width: 1.2, height: 7)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle().fill(Color.gray.opacity(0.75)).frame(width: 3.5, height: 3.5)
        }
        .rotationEffect(.degrees(rotation))
    }
}

private struct SemiTruckView: View {
    let wheelRotation: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.55, green: 0.59, blue: 0.61))
                    .frame(width: proxy.size.width * 0.66, height: proxy.size.height * 0.56)
                    .offset(x: proxy.size.width * 0.04, y: proxy.size.height * 0.10)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.black.opacity(0.18))
                            .frame(width: 1)
                            .padding(.vertical, 4)
                    }

                TruckCabShape()
                    .fill(Color(red: 0.21, green: 0.36, blue: 0.44))
                    .frame(width: proxy.size.width * 0.30, height: proxy.size.height * 0.66)
                    .offset(x: proxy.size.width * 0.68, y: proxy.size.height * 0.08)

                TruckWindowShape()
                    .fill(Color(red: 0.08, green: 0.14, blue: 0.18))
                    .frame(width: proxy.size.width * 0.13, height: proxy.size.height * 0.24)
                    .offset(x: proxy.size.width * 0.75, y: proxy.size.height * 0.17)

                Capsule()
                    .fill(Color(red: 0.06, green: 0.08, blue: 0.09))
                    .frame(width: proxy.size.width * 0.92, height: 4)
                    .offset(x: proxy.size.width * 0.04, y: proxy.size.height * 0.64)

                HStack(spacing: proxy.size.width * 0.25) {
                    VehicleWheel(rotation: wheelRotation).frame(width: 15, height: 15)
                    VehicleWheel(rotation: wheelRotation).frame(width: 15, height: 15)
                    VehicleWheel(rotation: wheelRotation).frame(width: 15, height: 15)
                }
                .frame(height: proxy.size.height * 0.25)
                .offset(x: proxy.size.width * 0.14, y: proxy.size.height * 0.60)

                Capsule()
                    .fill(Color(red: 0.86, green: 0.72, blue: 0.34))
                    .frame(width: 5, height: 2)
                    .offset(x: proxy.size.width * 0.94, y: proxy.size.height * 0.50)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
    }
}

private struct TruckCabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.68, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.46),
            control: CGPoint(x: rect.maxX, y: rect.height * 0.12)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.88))
        path.addLine(to: CGPoint(x: 0, y: rect.height * 0.88))
        path.closeSubpath()
        return path
    }
}

private struct TruckWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.68, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DeliveryVanView: View {
    let wheelRotation: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                DeliveryVanBodyShape()
                    .fill(Color(red: 0.78, green: 0.80, blue: 0.78))
                DeliveryVanWindowShape()
                    .fill(Color(red: 0.08, green: 0.15, blue: 0.19))
                    .frame(width: proxy.size.width * 0.24, height: proxy.size.height * 0.30)
                    .offset(x: proxy.size.width * 0.67, y: proxy.size.height * 0.18)
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 1, height: proxy.size.height * 0.42)
                    .offset(x: proxy.size.width * 0.49, y: proxy.size.height * 0.17)
                HStack(spacing: proxy.size.width * 0.54) {
                    VehicleWheel(rotation: wheelRotation).frame(width: 14, height: 14)
                    VehicleWheel(rotation: wheelRotation).frame(width: 14, height: 14)
                }
                .frame(height: proxy.size.height * 0.29)
                .offset(x: proxy.size.width * 0.14, y: proxy.size.height * 0.62)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

private struct DeliveryVanBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.04, y: rect.height * 0.20))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.70, y: rect.height * 0.13),
            control: CGPoint(x: rect.width * 0.12, y: rect.height * 0.08)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.45))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.98, y: rect.height * 0.75),
            control: CGPoint(x: rect.maxX, y: rect.height * 0.56)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.04, y: rect.height * 0.75))
        path.closeSubpath()
        return path
    }
}

private struct DeliveryVanWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.64, y: rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
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
                    .fill(Color(red: 0.11, green: 0.32, blue: 0.42))
                SedanWindowShape()
                    .fill(Color(red: 0.055, green: 0.10, blue: 0.13))
                    .frame(width: proxy.size.width * 0.43, height: proxy.size.height * 0.27)
                    .offset(x: proxy.size.width * 0.34, y: proxy.size.height * 0.17)
                Capsule()
                    .fill(Color(red: 0.16, green: 0.54, blue: 0.40))
                    .frame(width: 9, height: 2)
                    .offset(x: proxy.size.width * 0.85, y: proxy.size.height * 0.59)
                Capsule()
                    .fill(Color.white.opacity(0.58))
                    .frame(width: 5, height: 1.5)
                    .offset(x: proxy.size.width * 0.91, y: proxy.size.height * 0.55)
                HStack(spacing: proxy.size.width * 0.52) {
                    VehicleWheel(rotation: wheelRotation).frame(width: 13, height: 13)
                    VehicleWheel(rotation: wheelRotation).frame(width: 13, height: 13)
                }
                .frame(height: proxy.size.height * 0.33)
                .offset(x: proxy.size.width * 0.14, y: proxy.size.height * 0.61)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
    }
}

private struct SedanBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.03, y: rect.height * 0.67))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.45),
            control: CGPoint(x: rect.width * 0.07, y: rect.height * 0.48)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.15))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.18),
            control: CGPoint(x: rect.width * 0.55, y: rect.height * 0.05)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.43))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.98, y: rect.height * 0.64),
            control: CGPoint(x: rect.width * 0.96, y: rect.height * 0.47)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.78))
        path.closeSubpath()
        return path
    }
}

private struct SedanWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.24, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.69, y: rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

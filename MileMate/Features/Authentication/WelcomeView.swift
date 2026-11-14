import AuthenticationServices
import SwiftUI

enum AuthenticationButtonMetrics {
    static let height: CGFloat = 54
}

struct GoogleAuthenticationLabel: View {
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
        .foregroundStyle(AppTheme.Color.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: AuthenticationButtonMetrics.height)
        .background(AppTheme.Color.surface, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.Color.textSecondary.opacity(0.28), lineWidth: 1)
        }
    }
}

struct WelcomeView: View {
    @Bindable var accountSession: AccountSessionController
    let allowsGuestAccess: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.large) {
                Spacer(minLength: 8)
                WelcomeDrivingScene(reduceMotion: reduceMotion)
                VStack(spacing: AppTheme.Spacing.small) {
                    Text(allowsGuestAccess ? "Every Mile Matters." : "Keep Your Miles Moving.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(allowsGuestAccess
                         ? "Automatically track your drives, organize your trips, and simplify mileage reporting."
                         : "Your 10-trip guest trial is complete. Create a free account to record more drives.")
                        .font(.body)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                signInActions
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
                        Text("Track up to 10 completed trips before creating a free account.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Your existing trips and exports remain available on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, AppTheme.Spacing.xLarge)
            .padding(.vertical, AppTheme.Spacing.medium)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.Color.canvas)
        .scrollBounceBehavior(.basedOnSize)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
        }
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
                GoogleAuthenticationLabel()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Google sign in")
        }
        .disabled(accountSession.isAuthenticating)
    }
}

private struct WelcomeDrivingScene: View {
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let phase = reduceMotion
                    ? 0.56
                    : timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 7.5) / 7.5
                let progress = CGFloat(phase)
                let normalizedX = min(max(progress, 0), 1)
                let carX = -52 + (size.width + 104) * progress
                let carY = size.height * 0.69 - sin(normalizedX * .pi) * 11

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(sceneGradient)

                    WelcomeHillShape(verticalOffset: 0.27)
                        .fill(AppTheme.Color.brand.opacity(colorScheme == .dark ? 0.16 : 0.11))
                    WelcomeHillShape(verticalOffset: 0.35)
                        .fill(roadsideColor.opacity(0.72))

                    roadsideDetails(width: size.width, height: size.height)

                    WelcomeRoadShape()
                        .fill(roadColor)
                    WelcomeLaneShape()
                        .stroke(
                            laneColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [18, 14])
                        )

                    PremiumWelcomeCar()
                        .frame(width: 92, height: 42)
                        .rotationEffect(.degrees(Double(-cos(normalizedX * .pi) * 5)))
                        .position(x: carX, y: carY)
                        .opacity(reduceMotion ? 1 : edgeOpacity(progress))

                    Image("LaunchBrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .padding(7)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(12)
                        .accessibilityLabel("MileMate")
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .stroke(AppTheme.Color.textSecondary.opacity(0.10), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 158)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MileMate car driving along an open road")
    }

    private var sceneGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.035, green: 0.08, blue: 0.12), Color(red: 0.07, green: 0.14, blue: 0.17)]
                : [Color(red: 0.91, green: 0.96, blue: 0.98), Color(red: 0.82, green: 0.92, blue: 0.91)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var roadColor: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.16, blue: 0.18) : Color(red: 0.25, green: 0.29, blue: 0.31)
    }

    private var roadsideColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.25, blue: 0.19) : Color(red: 0.36, green: 0.63, blue: 0.48)
    }

    private var laneColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.48) : Color.white.opacity(0.72)
    }

    @ViewBuilder
    private func roadsideDetails(width: CGFloat, height: CGFloat) -> some View {
        ForEach(0..<5, id: \.self) { index in
            let x = width * (0.20 + CGFloat(index) * 0.19)
            Capsule()
                .fill(roadsideColor.opacity(0.75))
                .frame(width: 4, height: 17)
                .overlay(alignment: .top) {
                    Circle()
                        .fill(roadsideColor)
                        .frame(width: 15, height: 15)
                        .offset(y: -7)
                }
                .position(x: x, y: height * (index.isMultiple(of: 2) ? 0.47 : 0.43))
        }
    }

    private func edgeOpacity(_ progress: CGFloat) -> Double {
        Double(min(min(progress / 0.08, (1 - progress) / 0.08), 1))
    }
}

private struct WelcomeHillShape: Shape {
    let verticalOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * verticalOffset))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * (verticalOffset + 0.08)),
            control1: CGPoint(x: rect.width * 0.28, y: rect.height * (verticalOffset - 0.14)),
            control2: CGPoint(x: rect.width * 0.67, y: rect.height * (verticalOffset + 0.19))
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct WelcomeRoadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.58))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.58),
            control1: CGPoint(x: rect.width * 0.33, y: rect.height * 0.45),
            control2: CGPoint(x: rect.width * 0.67, y: rect.height * 0.45)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct WelcomeLaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.79))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.79),
            control1: CGPoint(x: rect.width * 0.33, y: rect.height * 0.64),
            control2: CGPoint(x: rect.width * 0.67, y: rect.height * 0.64)
        )
        return path
    }
}

private struct PremiumWelcomeCar: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            WelcomeCarBodyShape()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.Color.brand, AppTheme.Color.brand.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 31)
                .offset(y: -4)
            HStack(spacing: 3) {
                WelcomeCarWindowShape(isRear: true)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.48 : 0.72))
                WelcomeCarWindowShape(isRear: false)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.48 : 0.72))
            }
            .frame(width: 39, height: 11)
            .offset(x: 2, y: -22)
            HStack(spacing: 41) {
                wheel
                wheel
            }
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.20), radius: 5, y: 4)
        .accessibilityHidden(true)
    }

    private var wheel: some View {
        Circle()
            .fill(Color(red: 0.06, green: 0.07, blue: 0.08))
            .frame(width: 17, height: 17)
            .overlay {
                Circle().fill(Color.gray.opacity(0.72)).frame(width: 7, height: 7)
            }
    }
}

private struct WelcomeCarWindowShape: Shape {
    let isRear: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isRear {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.width * 0.40, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

private struct WelcomeCarBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.04, y: rect.height * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.19, y: rect.height * 0.45),
            control: CGPoint(x: rect.width * 0.07, y: rect.height * 0.50)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.34, y: rect.height * 0.12))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.67, y: rect.height * 0.13),
            control: CGPoint(x: rect.width * 0.50, y: rect.height * 0.02)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.80, y: rect.height * 0.45))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.97, y: rect.height * 0.67),
            control: CGPoint(x: rect.width * 0.94, y: rect.height * 0.48)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.86))
        path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.86))
        path.closeSubpath()
        return path
    }
}

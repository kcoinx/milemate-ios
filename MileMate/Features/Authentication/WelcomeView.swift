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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: AppTheme.Spacing.large) {
                    Spacer(minLength: AppTheme.Spacing.medium)

                    WelcomeRouteVisual(reduceMotion: reduceMotion)

                    VStack(spacing: AppTheme.Spacing.small) {
                        Text(allowsGuestAccess ? "Every Mile Matters." : "Keep Your Miles Moving.")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text(welcomeDescription)
                            .font(.body)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppTheme.Spacing.medium)

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
        .background(welcomeBackground.ignoresSafeArea())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
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

    private var welcomeDescription: String {
        allowsGuestAccess
            ? "Track business drives automatically and keep every mile organized."
            : "Your 10-trip guest trial is complete. Create a free account to keep driving."
    }

    private var welcomeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.025, green: 0.04, blue: 0.06)
            : Color(red: 0.975, green: 0.97, blue: 0.955)
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
                    .foregroundStyle(AppTheme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            Text("Your existing trips remain safely stored on this iPhone.")
                .font(.footnote)
                .foregroundStyle(AppTheme.Color.textSecondary)
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
                GoogleAuthenticationLabel()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Google sign in")
        }
        .disabled(accountSession.isAuthenticating)
    }
}

private struct WelcomeRouteVisual: View {
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image("LaunchBrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityLabel("MileMate")

            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
                GeometryReader { proxy in
                    let progress = routeProgress(at: timeline.date)
                    let point = WelcomeRoutePath.point(at: progress, in: proxy.size)

                    ZStack {
                        WelcomeRoutePath()
                            .stroke(
                                routeColor,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )

                        routeEndpoint
                            .position(WelcomeRoutePath.point(at: 0, in: proxy.size))
                        routeEndpoint
                            .position(WelcomeRoutePath.point(at: 1, in: proxy.size))

                        Circle()
                            .fill(AppTheme.Color.brand)
                            .frame(width: 12, height: 12)
                            .overlay {
                                Circle()
                                    .fill(colorScheme == .dark ? Color.black : Color.white)
                                    .frame(width: 4, height: 4)
                            }
                            .position(point)
                            .opacity(reduceMotion ? 1 : markerOpacity(progress))
                    }
                }
            }
            .frame(width: 250, height: 58)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MileMate")
    }

    private var routeColor: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.47, blue: 0.58)
            : Color(red: 0.18, green: 0.29, blue: 0.39)
    }

    private var routeEndpoint: some View {
        Circle()
            .fill(AppTheme.Color.brand.opacity(0.55))
            .frame(width: 5, height: 5)
    }

    private func routeProgress(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0.58 }
        return CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6.5) / 6.5)
    }

    private func markerOpacity(_ progress: CGFloat) -> Double {
        Double(min(min(progress / 0.08, (1 - progress) / 0.08), 1))
    }
}

private struct WelcomeRoutePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: Self.point(at: 0, in: rect.size))
        path.addCurve(
            to: Self.point(at: 1, in: rect.size),
            control1: CGPoint(x: rect.width * 0.29, y: rect.height * 0.02),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * 0.98)
        )
        return path
    }

    static func point(at progress: CGFloat, in size: CGSize) -> CGPoint {
        let t = min(max(progress, 0), 1)
        let inverse = 1 - t
        let start = CGPoint(x: size.width * 0.04, y: size.height * 0.72)
        let control1 = CGPoint(x: size.width * 0.29, y: size.height * 0.02)
        let control2 = CGPoint(x: size.width * 0.66, y: size.height * 0.98)
        let end = CGPoint(x: size.width * 0.96, y: size.height * 0.28)

        return CGPoint(
            x: inverse * inverse * inverse * start.x
                + 3 * inverse * inverse * t * control1.x
                + 3 * inverse * t * t * control2.x
                + t * t * t * end.x,
            y: inverse * inverse * inverse * start.y
                + 3 * inverse * inverse * t * control1.y
                + 3 * inverse * t * t * control2.y
                + t * t * t * end.y
        )
    }
}

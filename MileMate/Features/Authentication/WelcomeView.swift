import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @Bindable var accountSession: AccountSessionController
    let allowsGuestAccess: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var routeRotation = -35.0

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                Spacer(minLength: 24)
                brandVisual
                VStack(spacing: AppTheme.Spacing.medium) {
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
                                .frame(height: 54)
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
                Spacer(minLength: 20)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, AppTheme.Spacing.xLarge)
            .padding(.vertical, AppTheme.Spacing.large)
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

    private var brandVisual: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Color.brand.opacity(0.10))
                .frame(width: 190, height: 190)
            Circle()
                .stroke(
                    AppTheme.Color.textPrimary.opacity(0.13),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 158, height: 158)
            Circle()
                .trim(from: 0.08, to: 0.34)
                .stroke(
                    AppTheme.Color.brand.opacity(0.55),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 158, height: 158)
            Image("LaunchBrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .accessibilityLabel("MileMate")
            Image(systemName: "car.side.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(AppTheme.Color.brand, in: Capsule())
                .shadow(color: AppTheme.Color.brand.opacity(0.25), radius: 5, y: 2)
                .offset(y: -79)
                .rotationEffect(.degrees(90))
                .rotationEffect(.degrees(routeRotation))
                .accessibilityHidden(true)
        }
        .onAppear {
            routeRotation = -35
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                routeRotation = 325
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                routeRotation = -35
            } else {
                withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                    routeRotation = 325
                }
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
            .frame(height: 54)
            .clipShape(Capsule())
            .accessibilityHint("Signs in securely using your Apple Account")

            Button {
                Task { await accountSession.authenticateWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Image("GoogleMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("Continue with Google")
                        .font(.headline)
                }
                .foregroundStyle(AppTheme.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(AppTheme.Color.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(AppTheme.Color.textSecondary.opacity(0.28), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Google sign in")
        }
        .disabled(accountSession.isAuthenticating)
    }
}

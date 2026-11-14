import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @Bindable var accountSession: AccountSessionController
    let allowsGuestAccess: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

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
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Color.brand)
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
                .fill(AppTheme.Color.brand.opacity(0.12))
                .frame(width: 190, height: 190)
            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(
                    AppTheme.Color.brand.gradient,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 12])
                )
                .rotationEffect(.degrees(-25))
                .frame(width: 158, height: 158)
            Image("LaunchBrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .accessibilityLabel("MileMate")
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
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
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
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.Color.textPrimary)
            .accessibilityHint("Opens Google sign in")
        }
        .disabled(accountSession.isAuthenticating)
    }
}

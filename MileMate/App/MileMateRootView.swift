import SwiftUI

struct MileMateRootView: View {
    let dependencies: AppDependencies
    @Bindable private var accountSession: AccountSessionController

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _accountSession = Bindable(wrappedValue: dependencies.accountSession)
    }

    var body: some View {
        Group {
            if accountSession.requiresWelcome {
                WelcomeView(accountSession: accountSession, allowsGuestAccess: true)
                    .transition(.opacity)
            } else {
                AppTabView(dependencies: dependencies)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: accountSession.requiresWelcome)
        .onChange(of: accountSession.requiresWelcome) { wasRequired, isRequired in
            if wasRequired && !isRequired {
                dependencies.automaticTripCoordinator.startIfEnabled()
            }
        }
        .onChange(of: accountSession.isReconcilingGuestTrial) { wasReconciling, isReconciling in
            if wasReconciling && !isReconciling {
                dependencies.automaticTripCoordinator.startIfEnabled()
            }
        }
        .onChange(of: accountSession.isAuthenticated) { _, authenticated in
            if authenticated {
                dependencies.automaticTripCoordinator.startIfEnabled()
            }
        }
        .sheet(isPresented: $accountSession.presentsUpgrade) {
            WelcomeView(accountSession: accountSession, allowsGuestAccess: false)
                .presentationDetents([.large])
        }
    }
}

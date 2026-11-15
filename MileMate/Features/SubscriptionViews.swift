import StoreKit
import SwiftUI

struct ProPaywallView: View {
    @Bindable var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xLarge) {
                    VStack(spacing: AppTheme.Spacing.medium) {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(AppTheme.Color.brand)
                            .frame(width: 72, height: 72)
                            .background(AppTheme.Color.brand.opacity(0.12), in: Circle())
                        Text("Drive Without Limits")
                            .font(.appLargeTitle)
                            .multilineTextAlignment(.center)
                        Text("Upgrade to MileMate Pro for unlimited trip tracking and continued access to every MileMate feature.")
                            .font(.body)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: AppTheme.Spacing.medium) {
                        purchaseCard(
                            title: "Pro Monthly",
                            price: purchaseManager.monthlyProduct?.displayPrice,
                            detail: "Auto-renews monthly until canceled.",
                            badge: nil,
                            disabled: purchaseManager.hasLifetimeAccess
                        ) {
                            await purchaseManager.purchaseMonthly()
                        }
                        purchaseCard(
                            title: "Pro Lifetime",
                            price: purchaseManager.lifetimeProduct?.displayPrice,
                            detail: purchaseManager.hasMonthlySubscription
                                ? "Manage the active monthly subscription before purchasing Lifetime Pro."
                                : "One purchase. No recurring billing.",
                            badge: "BEST VALUE",
                            disabled: purchaseManager.hasMonthlySubscription || purchaseManager.hasLifetimeAccess
                        ) {
                            await purchaseManager.purchaseLifetime()
                        }
                    }

                    if purchaseManager.isLoadingProducts {
                        ProgressView("Loading App Store products…")
                    } else if !purchaseManager.isConfigured {
                        Text("MileMate Pro products are not configured for this build.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await purchaseManager.restorePurchases() }
                    } label: {
                        if purchaseManager.isRestoring {
                            ProgressView()
                        } else {
                            Text("Restore Purchases")
                        }
                    }
                    .disabled(purchaseManager.isRestoring || purchaseManager.isPurchasing)

                    if purchaseManager.hasMonthlySubscription {
                        Button("Manage Subscription") { openManageSubscriptions() }
                    }

                    Text("Payment is charged to your App Store account. Monthly subscriptions renew automatically unless canceled. Deleting MileMate does not cancel billing.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: AppTheme.Spacing.large) {
                        NavigationLink("Privacy Policy") {
                            PrivacyInformationView()
                        }
                        if let termsURL = URL(
                            string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                        ) {
                            Link("Terms of Use", destination: termsURL)
                        }
                    }
                    .font(.footnote)
                }
                .padding(AppTheme.Spacing.xLarge)
            }
            .background(AppTheme.Color.canvas)
            .navigationTitle("MileMate Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") { dismiss() }
                }
            }
            .onChange(of: purchaseManager.hasProAccess) { _, hasPro in
                if hasPro { dismiss() }
            }
            .alert(
                "Purchase Unavailable",
                isPresented: Binding(
                    get: { purchaseManager.errorMessage != nil },
                    set: { if !$0 { purchaseManager.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { purchaseManager.errorMessage = nil }
            } message: {
                Text(purchaseManager.errorMessage ?? "")
            }
        }
    }

    private func purchaseCard(
        title: String,
        price: String?,
        detail: String,
        badge: String?,
        disabled: Bool,
        purchase: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await purchase() }
        } label: {
            AppCard {
                HStack(spacing: AppTheme.Spacing.large) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                        HStack(spacing: 8) {
                            Text(title).font(.headline)
                            if let badge {
                                Text(badge)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.Color.brand)
                            }
                        }
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    if purchaseManager.isPurchasing {
                        ProgressView()
                    } else {
                        Text(price ?? "Unavailable")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(disabled ? AppTheme.Color.textSecondary : AppTheme.Color.brand)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled || price == nil || purchaseManager.isPurchasing)
    }

    private func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        openURL(url)
    }
}

struct SubscriptionBillingView: View {
    @Bindable var purchaseManager: PurchaseManager
    let remainingTrips: Int
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false

    var body: some View {
        List {
            Section("Current Plan") {
                LabeledContent("Plan", value: planName)
                if case .monthly(let expirationDate) = purchaseManager.plan,
                   let expirationDate {
                    LabeledContent(
                        "Paid Through",
                        value: expirationDate.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if !purchaseManager.hasProAccess {
                    LabeledContent("Free Trips Remaining", value: "\(remainingTrips) of 10")
                }
            }

            Section("Billing") {
                if !purchaseManager.hasProAccess {
                    Button("Upgrade to Pro") { showingPaywall = true }
                }
                Button("Restore Purchases") {
                    Task { await purchaseManager.restorePurchases() }
                }
                .disabled(purchaseManager.isRestoring || purchaseManager.isPurchasing)
                Button("Manage Subscription") { openManageSubscriptions() }
            }

            Section {
                Text("Monthly billing is managed by Apple. Canceling retains Pro access through the paid period. Deleting MileMate does not cancel a subscription. Lifetime Pro does not expire unless Apple revokes or refunds the transaction.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }

            if let status = purchaseManager.statusMessage {
                Section { Text(status).foregroundStyle(AppTheme.Color.textSecondary) }
            }
        }
        .navigationTitle("Subscription & Billing")
        .sheet(isPresented: $showingPaywall) {
            ProPaywallView(purchaseManager: purchaseManager)
        }
        .task { await purchaseManager.prepare() }
        .alert(
            "Purchase Unavailable",
            isPresented: Binding(
                get: { purchaseManager.errorMessage != nil },
                set: { if !$0 { purchaseManager.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { purchaseManager.errorMessage = nil }
        } message: {
            Text(purchaseManager.errorMessage ?? "")
        }
    }

    private var planName: String {
        guard purchaseManager.isEntitlementReady else { return "Checking…" }
        switch purchaseManager.plan {
        case .free: "Free"
        case .monthly: "MileMate Pro Monthly"
        case .lifetime: "MileMate Pro Lifetime"
        }
    }

    private func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        openURL(url)
    }
}

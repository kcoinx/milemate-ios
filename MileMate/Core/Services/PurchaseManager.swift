import Foundation
import Observation
import OSLog
import StoreKit

enum ProPlan: Equatable, Sendable {
    case free
    case monthly(expirationDate: Date?)
    case lifetime

    var hasProAccess: Bool {
        self != .free
    }
}

struct StoreKitProductConfiguration: Equatable, Sendable {
    static let monthlyBundleKey = "MileMateProMonthlyProductID"
    static let lifetimeBundleKey = "MileMateProLifetimeProductID"

    let monthlyProductID: String
    let lifetimeProductID: String

    static func fromBundle(_ bundle: Bundle = .main) -> StoreKitProductConfiguration? {
        guard let monthly = bundle.object(forInfoDictionaryKey: monthlyBundleKey) as? String,
              let lifetime = bundle.object(forInfoDictionaryKey: lifetimeBundleKey) as? String else {
            return nil
        }
        let monthlyID = monthly.trimmingCharacters(in: .whitespacesAndNewlines)
        let lifetimeID = lifetime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !monthlyID.isEmpty, !lifetimeID.isEmpty, monthlyID != lifetimeID else { return nil }
        return StoreKitProductConfiguration(
            monthlyProductID: monthlyID,
            lifetimeProductID: lifetimeID
        )
    }
}

struct StoreKitEntitlementSnapshot: Equatable, Sendable {
    let plan: ProPlan
    let hasMonthlySubscription: Bool
    let encounteredUnverifiedManagedTransaction: Bool
}

@MainActor
protocol ProEntitlementProviding: AnyObject {
    var hasProAccess: Bool { get }
    var isEntitlementReady: Bool { get }
}

@MainActor
final class FreeProEntitlementProvider: ProEntitlementProviding {
    var hasProAccess: Bool { false }
    var isEntitlementReady: Bool { true }
}

enum PurchaseManagerError: LocalizedError {
    case configurationMissing
    case productUnavailable
    case unverifiedTransaction
    case existingMonthlySubscription
    case lifetimeAlreadyOwned

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "MileMate Pro products are not configured for this build."
        case .productUnavailable:
            "This purchase is temporarily unavailable. Please try again later."
        case .unverifiedTransaction:
            "The App Store could not verify this purchase. Pro access was not unlocked."
        case .existingMonthlySubscription:
            "Manage or cancel the active monthly subscription before purchasing Lifetime Pro."
        case .lifetimeAlreadyOwned:
            "Lifetime Pro is already active for this App Store account."
        }
    }
}

@MainActor
@Observable
final class PurchaseManager: ProEntitlementProviding {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MileMate",
        category: "StoreKit"
    )

    private let configuration: StoreKitProductConfiguration?
    private let appStoreSync: @MainActor () async throws -> Void
    private let entitlementLoader: @MainActor (StoreKitProductConfiguration) async -> StoreKitEntitlementSnapshot
    private var updatesTask: Task<Void, Never>?
    private var entitlementRefreshTask: Task<StoreKitEntitlementSnapshot, Never>?
    private var entitlementRefreshID: UUID?

    private(set) var plan: ProPlan = .free
    private(set) var monthlyProduct: Product?
    private(set) var lifetimeProduct: Product?
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isEntitlementReady = false
    private(set) var hasMonthlySubscription = false
    var errorMessage: String?
    var statusMessage: String?

    var hasProAccess: Bool { plan.hasProAccess }
    var hasLifetimeAccess: Bool { plan == .lifetime }
    var isConfigured: Bool { configuration != nil }

    init(
        configuration: StoreKitProductConfiguration? = .fromBundle(),
        appStoreSync: @escaping @MainActor () async throws -> Void = {
            try await AppStore.sync()
        },
        entitlementLoader: @escaping @MainActor (StoreKitProductConfiguration) async -> StoreKitEntitlementSnapshot = {
            await PurchaseManager.loadVerifiedEntitlements(configuration: $0)
        },
        automaticallyPrepares: Bool = true,
        observesTransactionUpdates: Bool = true
    ) {
        self.configuration = configuration
        self.appStoreSync = appStoreSync
        self.entitlementLoader = entitlementLoader
        if observesTransactionUpdates {
            updatesTask = Task { [weak self] in
                guard let self else { return }
                await self.observeTransactionUpdates()
            }
        }
        if automaticallyPrepares {
            Task { [weak self] in
                await self?.prepare()
            }
        }
    }

    func prepare() async {
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        guard let configuration else {
            errorMessage = PurchaseManagerError.configurationMissing.localizedDescription
            return
        }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        let requestedProductIDs = [
            configuration.monthlyProductID,
            configuration.lifetimeProductID
        ]
        Self.logger.info(
            "Requesting StoreKit products: \(requestedProductIDs.joined(separator: ", "), privacy: .public)"
        )
        do {
            let products = try await Product.products(for: requestedProductIDs)
            Self.logger.info("StoreKit returned \(products.count) product(s)")
            for product in products {
                let productType = String(describing: product.type)
                Self.logger.info(
                    "StoreKit product returned: id=\(product.id, privacy: .public), type=\(productType, privacy: .public)"
                )
                let isValidMonthly = product.id == configuration.monthlyProductID &&
                    product.type == .autoRenewable
                let isValidLifetime = product.id == configuration.lifetimeProductID &&
                    product.type == .nonConsumable
                if !isValidMonthly && !isValidLifetime {
                    Self.logger.error(
                        "Rejecting StoreKit product during validation: id=\(product.id, privacy: .public), type=\(productType, privacy: .public)"
                    )
                }
            }
            monthlyProduct = products.first {
                $0.id == configuration.monthlyProductID && $0.type == .autoRenewable
            }
            lifetimeProduct = products.first {
                $0.id == configuration.lifetimeProductID && $0.type == .nonConsumable
            }
            if monthlyProduct == nil || lifetimeProduct == nil {
                if monthlyProduct == nil {
                    Self.logger.error(
                        "No valid monthly StoreKit product was returned for id=\(configuration.monthlyProductID, privacy: .public); expected type=autoRenewable"
                    )
                }
                if lifetimeProduct == nil {
                    Self.logger.error(
                        "No valid lifetime StoreKit product was returned for id=\(configuration.lifetimeProductID, privacy: .public); expected type=nonConsumable"
                    )
                }
                errorMessage = PurchaseManagerError.productUnavailable.localizedDescription
            }
        } catch {
            Self.logger.error(
                "StoreKit product request failed: \(String(describing: error), privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    func purchaseMonthly() async {
        guard !hasLifetimeAccess else {
            errorMessage = PurchaseManagerError.lifetimeAlreadyOwned.localizedDescription
            return
        }
        await purchase(monthlyProduct)
    }

    func purchaseLifetime() async {
        guard !hasMonthlySubscription else {
            errorMessage = PurchaseManagerError.existingMonthlySubscription.localizedDescription
            return
        }
        guard !hasLifetimeAccess else {
            errorMessage = PurchaseManagerError.lifetimeAlreadyOwned.localizedDescription
            return
        }
        await purchase(lifetimeProduct)
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        defer { isRestoring = false }
        do {
            try await appStoreSync()
            await refreshEntitlements(forceFresh: true, allowWhileRestoring: true)
            statusMessage = hasProAccess
                ? "MileMate Pro has been restored."
                : "No active MileMate Pro purchase was found."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        guard !isRestoring else { return }
        await refreshEntitlements(forceFresh: false, allowWhileRestoring: false)
    }

    private func refreshEntitlements(
        forceFresh: Bool,
        allowWhileRestoring: Bool
    ) async {
        guard let configuration else {
            plan = .free
            hasMonthlySubscription = false
            isEntitlementReady = true
            return
        }

        if forceFresh, let existingTask = entitlementRefreshTask {
            _ = await existingTask.value
            entitlementRefreshTask = nil
            entitlementRefreshID = nil
        } else if let existingTask = entitlementRefreshTask,
                  let existingID = entitlementRefreshID {
            let snapshot = await existingTask.value
            guard entitlementRefreshID == existingID else { return }
            entitlementRefreshTask = nil
            entitlementRefreshID = nil
            guard allowWhileRestoring || !isRestoring else { return }
            apply(snapshot)
            isEntitlementReady = true
            return
        }

        let refreshID = UUID()
        let loader = entitlementLoader
        let task = Task { await loader(configuration) }
        entitlementRefreshID = refreshID
        entitlementRefreshTask = task
        let snapshot = await task.value
        guard entitlementRefreshID == refreshID else { return }
        entitlementRefreshTask = nil
        entitlementRefreshID = nil
        guard allowWhileRestoring || !isRestoring else { return }
        apply(snapshot)
        isEntitlementReady = true
    }

    private func apply(_ snapshot: StoreKitEntitlementSnapshot) {
        if snapshot.encounteredUnverifiedManagedTransaction,
           snapshot.plan == .free,
           plan.hasProAccess {
            errorMessage = PurchaseManagerError.unverifiedTransaction.localizedDescription
            return
        }
        plan = snapshot.plan
        hasMonthlySubscription = snapshot.hasMonthlySubscription
    }

    static func loadVerifiedEntitlements(
        configuration: StoreKitProductConfiguration
    ) async -> StoreKitEntitlementSnapshot {
        var monthlyExpiration: Date?
        var hasActiveMonthly = false
        var ownsLifetime = false
        var encounteredUnverifiedManagedTransaction = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == configuration.monthlyProductID ||
                        transaction.productID == configuration.lifetimeProductID,
                      transaction.revocationDate == nil else {
                    continue
                }
                if transaction.productID == configuration.lifetimeProductID {
                    ownsLifetime = true
                } else {
                    hasActiveMonthly = true
                    monthlyExpiration = transaction.expirationDate
                }
            case .unverified(let transaction, _):
                if transaction.productID == configuration.monthlyProductID ||
                    transaction.productID == configuration.lifetimeProductID {
                    encounteredUnverifiedManagedTransaction = true
                }
            }
        }

        let plan: ProPlan
        if ownsLifetime {
            plan = .lifetime
        } else if hasActiveMonthly {
            plan = .monthly(expirationDate: monthlyExpiration)
        } else {
            plan = .free
        }
        return StoreKitEntitlementSnapshot(
            plan: plan,
            hasMonthlySubscription: hasActiveMonthly,
            encounteredUnverifiedManagedTransaction: encounteredUnverifiedManagedTransaction
        )
    }

    private func purchase(_ product: Product?) async {
        guard let product else {
            errorMessage = isConfigured
                ? PurchaseManagerError.productUnavailable.localizedDescription
                : PurchaseManagerError.configurationMissing.localizedDescription
            return
        }
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    throw PurchaseManagerError.unverifiedTransaction
                }
                await transaction.finish()
                await refreshEntitlements()
                statusMessage = hasProAccess ? "MileMate Pro is now active." : nil
            case .pending:
                statusMessage = "This purchase is pending App Store approval."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The App Store returned an unknown purchase result."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }
            switch result {
            case .verified(let transaction):
                guard isManagedProduct(transaction.productID) else { continue }
                await transaction.finish()
                if transaction.revocationDate != nil {
                    await refreshEntitlements(forceFresh: true, allowWhileRestoring: true)
                } else {
                    await refreshEntitlements()
                }
            case .unverified(let transaction, _):
                guard isManagedProduct(transaction.productID) else { continue }
                errorMessage = PurchaseManagerError.unverifiedTransaction.localizedDescription
            }
        }
    }

    private func isManagedProduct(_ productID: String) -> Bool {
        guard let configuration else { return false }
        return productID == configuration.monthlyProductID ||
            productID == configuration.lifetimeProductID
    }
}

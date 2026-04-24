import Adapty
import Foundation
import SwiftUI

@MainActor
final class PaywallStore: ObservableObject {
    static let placementId = "onboarding_main"

    @Published var weeklyPrice: String = "$7.99"
    @Published var yearlyPrice: String = "$34.99"
    @Published var isPurchasing = false
    @Published var lastError: String?

    /// Whether the paywall must be purchased/dismissed only by subscribing
    /// (hard paywall) or can be closed with an X / skip button (soft
    /// paywall).
    ///
    /// Driven by Adapty's paywall `remoteConfig` — set a `hard_paywall: true`
    /// key in the Adapty dashboard on the `onboarding_main` placement to
    /// flip every installed build into hard-paywall mode without shipping
    /// a new binary. Defaults to `false` (soft) so shipping with no remote
    /// config in place stays safe.
    ///
    /// A local `UserDefaults` key (`debug.hardPaywall`) also forces it on
    /// in DEBUG builds for simulator testing.
    @Published var hardPaywall: Bool = false

    private var paywall: AdaptyPaywall?
    private var products: [AdaptyPaywallProduct] = []

    func loadPaywall() async {
        do {
            let paywall = try await Adapty.getPaywall(placementId: Self.placementId)
            self.paywall = paywall
            let products = try await Adapty.getPaywallProducts(paywall: paywall)
            self.products = products
            for p in products {
                if p.vendorProductId.contains("weekly") {
                    weeklyPrice = p.localizedPrice ?? weeklyPrice
                } else if p.vendorProductId.contains("yearly") {
                    yearlyPrice = p.localizedPrice ?? yearlyPrice
                }
            }
            hardPaywall = Self.resolveHardPaywall(from: paywall)
        } catch {
            lastError = error.localizedDescription
            // On load failure we still honor the debug override so
            // simulator testing works without a live Adapty connection.
            hardPaywall = Self.debugOverride() ?? false
        }
    }

    /// Pulls `hard_paywall` out of the Adapty paywall's `remoteConfig`.
    /// Accepts a Bool or a string ("true"/"1"/"yes") so whoever edits the
    /// dashboard doesn't have to worry about typing exactly "true".
    /// DEBUG override takes precedence when present.
    private static func resolveHardPaywall(from paywall: AdaptyPaywall) -> Bool {
        if let override = debugOverride() { return override }

        guard let dict = paywall.remoteConfig?.dictionary else { return false }
        if let b = dict["hard_paywall"] as? Bool { return b }
        if let s = dict["hard_paywall"] as? String {
            switch s.lowercased() {
            case "true", "1", "yes", "on": return true
            default: return false
            }
        }
        return false
    }

    private static func debugOverride() -> Bool? {
        #if DEBUG
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "debug.hardPaywall") != nil else { return nil }
        return defaults.bool(forKey: "debug.hardPaywall")
        #else
        return nil
        #endif
    }

    func product(for plan: PaywallPlan) -> AdaptyPaywallProduct? {
        products.first { p in
            let id = p.vendorProductId
            switch plan {
            case .weekly: return id.contains("weekly")
            case .yearly: return id.contains("yearly")
            }
        }
    }

    @discardableResult
    func purchase(plan: PaywallPlan) async -> Bool {
        guard let product = product(for: plan) else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Adapty.makePurchase(product: product)
            return result.profile?.accessLevels["premium"]?.isActive == true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restore() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let profile = try await Adapty.restorePurchases()
            return profile.accessLevels["premium"]?.isActive == true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

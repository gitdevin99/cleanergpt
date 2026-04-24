import Adapty
import Foundation
import SwiftUI

enum FreeAction: String, CaseIterable {
    case photoDelete
    case videoDelete
    case videoCompress
    case duplicateCluster
    case vaultAdd
    case contactMerge
    case emailCleanup
    case speakerClean

    var limit: Int {
        switch self {
        case .photoDelete:      return 10
        case .videoDelete:      return 3
        case .videoCompress:    return 3
        case .duplicateCluster: return 1
        case .vaultAdd:         return 0
        case .contactMerge:     return 0
        case .emailCleanup:     return 0
        case .speakerClean:     return 1
        }
    }

    var displayName: String {
        switch self {
        case .photoDelete:      return "photo deletes"
        case .videoDelete:      return "video deletes"
        case .videoCompress:    return "video compresses"
        case .duplicateCluster: return "duplicate cluster cleanups"
        case .vaultAdd:         return "Secret Vault adds"
        case .contactMerge:     return "contact merges"
        case .emailCleanup:     return "inbox cleanups"
        case .speakerClean:     return "water & dust removal"
        }
    }

    var storageKey: String { "freeUsage.\(rawValue)" }
}

/// Which subscription tier the user is currently on. Drives copy everywhere
/// we show a paywall or a "Manage Subscription" row — weekly subscribers
/// should see an upsell to yearly, yearly subscribers should not see a
/// paywall at all (just manage/cancel).
enum SubscriptionPlan: String {
    case none        // Free tier
    case weekly
    case yearly
    case lifetime    // Defensive — we don't sell this today, but Adapty supports it
    case other       // Paid but we can't tell which tier (shouldn't happen in practice)

    var displayName: String {
        switch self {
        case .none:     return "Free"
        case .weekly:   return "Weekly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        case .other:    return "Pro"
        }
    }
}

@MainActor
final class EntitlementStore: ObservableObject {
    static let shared = EntitlementStore()

    @Published var isPremium: Bool = false
    @Published var usage: [FreeAction: Int] = [:]

    // MARK: - Subscription state (driven by Adapty)

    /// Which tier the active subscription is on. `.none` when free.
    @Published var currentPlan: SubscriptionPlan = .none

    /// When the current access level expires. `nil` for lifetime or free.
    /// For weekly/yearly this is the next renewal date if `willRenew` is
    /// true, or the end-of-access date if the user has cancelled.
    @Published var expiresAt: Date?

    /// Apple's `willRenew` flag. `false` means the user has cancelled
    /// auto-renewal — access is still live until `expiresAt`, but we
    /// should surface "Re-enable auto-renew" copy.
    @Published var willRenew: Bool = true

    /// True if the current period is a free trial (introductory offer).
    /// Informational — used to say "Trial ends April 25" instead of
    /// "Renews April 25".
    @Published var isInTrial: Bool = false

    /// Product id returned by Adapty — kept for debug/telemetry.
    @Published var vendorProductId: String?

    // MARK: - Debug

    @Published var debugForceFree: Bool = false

    private let defaults = UserDefaults.standard
    private static let debugForceFreeKey = "debug.forceFreeTier"

    init() {
        for action in FreeAction.allCases {
            usage[action] = defaults.integer(forKey: action.storageKey)
        }
        #if DEBUG
        debugForceFree = defaults.bool(forKey: Self.debugForceFreeKey)
        #else
        debugForceFree = false
        #endif
        Task { await refreshFromAdapty() }
    }

    func refreshFromAdapty() async {
        do {
            let profile = try await Adapty.getProfile()
            let access = profile.accessLevels["premium"]
            let active = access?.isActive == true

            let wasPremium = isPremium
            isPremium = active && !debugForceFree

            if let access, active {
                currentPlan = Self.plan(from: access.vendorProductId)
                expiresAt = access.expiresAt
                willRenew = access.willRenew
                isInTrial = access.activeIntroductoryOfferType == "free_trial"
                vendorProductId = access.vendorProductId
            } else {
                currentPlan = .none
                expiresAt = nil
                willRenew = true
                isInTrial = false
                vendorProductId = nil
            }

            // If the user just became premium, nuke the nag campaign — paying
            // users should never see a "Upgrade to Pro" push.
            if isPremium && !wasPremium {
                NotificationScheduler.shared.cancelAll()
            }
        } catch {
            // Keep whatever we had; offline or not yet activated.
        }
    }

    /// Maps an Adapty `vendor_product_id` to our internal plan enum.
    /// Keeps the string matching in one place so UI code never has to
    /// sniff product ids directly.
    private static func plan(from vendorProductId: String) -> SubscriptionPlan {
        let id = vendorProductId.lowercased()
        if id.contains("week") { return .weekly }
        if id.contains("year") || id.contains("annual") { return .yearly }
        if id.contains("lifetime") { return .lifetime }
        return .other
    }

    // MARK: - Debug override

    func setDebugForceFree(_ force: Bool) {
        debugForceFree = force
        defaults.set(force, forKey: Self.debugForceFreeKey)
        Task { await refreshFromAdapty() }
    }

    /// Returns remaining free uses. `nil` means premium (unlimited).
    func remaining(_ action: FreeAction) -> Int? {
        if isPremium { return nil }
        return max(0, action.limit - (usage[action] ?? 0))
    }

    func canUse(_ action: FreeAction) -> Bool {
        if isPremium { return true }
        return (usage[action] ?? 0) < action.limit
    }

    /// Records `count` uses. Returns true if the action was allowed, false if
    /// the attempt pushed past the free-tier limit (caller should surface the
    /// upgrade gate).
    @discardableResult
    func recordUse(_ action: FreeAction, count: Int = 1) -> Bool {
        if isPremium { return true }
        let current = usage[action] ?? 0
        let newTotal = current + count
        usage[action] = newTotal
        defaults.set(newTotal, forKey: action.storageKey)
        return newTotal <= action.limit
    }

    /// Resets all free-tier counters. Useful after a successful purchase.
    func resetAllUsage() {
        for action in FreeAction.allCases {
            usage[action] = 0
            defaults.set(0, forKey: action.storageKey)
        }
    }
}

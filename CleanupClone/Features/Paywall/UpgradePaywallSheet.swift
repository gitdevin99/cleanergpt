import SwiftUI
import PostHog

/// Paywall shown when a free user hits the upgrade gate. Paying users of
/// any tier never see this — upgrades/downgrades/cancellations are handled
/// through Apple's Subscriptions UI, not in-app.
struct UpgradePaywallSheet: View {
    let onDismiss: () -> Void
    let onPurchased: () -> Void

    @EnvironmentObject private var paywallStore: PaywallStore
    @EnvironmentObject private var entitlements: EntitlementStore

    @State private var selectedPlan: PaywallPlan = .yearly
    @State private var closeVisible: Bool = false
    @State private var isWorking: Bool = false
    @State private var statusMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            CleanupTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                PaywallContentStep(
                    selectedPlan: $selectedPlan,
                    hideWeeklyOption: false,
                    headlineOverride: nil,
                    subheadlineOverride: nil
                )
                .environmentObject(paywallStore)

                VStack(spacing: 10) {
                    Button(action: subscribe) {
                        HStack {
                            if isWorking { ProgressView().tint(.white) }
                            Text(isWorking ? "Processing…" : continueTitle)
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(CleanupTheme.electricBlue, in: Capsule(style: .continuous))
                    }
                    .disabled(isWorking)

                    Button(action: restore) {
                        Text("Restore purchases")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }
                    .disabled(isWorking)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(CleanupTheme.background)
            }

            // Soft paywall: close X fades in after a delay. Hard paywall:
            // the X never renders — users must subscribe or restore.
            // `paywallStore.hardPaywall` is driven by Adapty remote config
            // so the soft/hard switch is server-side, no rebuild needed.
            if !paywallStore.hardPaywall {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .opacity(closeVisible ? 1 : 0)
                    .allowsHitTesting(closeVisible)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
            }
        }
        .task {
            // Defensive: any paying tier should never see this sheet. If they
            // somehow land here (stale state, race), bounce out — showing a
            // subscriber an "Upgrade" screen is wrong.
            if entitlements.isPremium {
                onDismiss()
                return
            }
            await paywallStore.loadPaywall()
            PostHogSDK.shared.capture(
                "upgrade_paywall_shown",
                properties: [
                    "from_plan": entitlements.currentPlan.rawValue,
                    "hard_paywall": paywallStore.hardPaywall
                ]
            )
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeIn(duration: 0.25)) { closeVisible = true }
        }
    }

    private var continueTitle: String {
        selectedPlan == .yearly ? "Start 3-day free trial" : "Continue"
    }

    private func subscribe() {
        isWorking = true
        statusMessage = nil
        PostHogSDK.shared.capture("upgrade_paywall_cta",
            properties: [
                "plan": selectedPlan.rawValue,
                "from_plan": entitlements.currentPlan.rawValue
            ])
        Task {
            let success = await paywallStore.purchase(plan: selectedPlan)
            await entitlements.refreshFromAdapty()
            isWorking = false
            if success {
                onPurchased()
            } else {
                statusMessage = paywallStore.lastError ?? "Purchase not completed."
            }
        }
    }

    private func restore() {
        isWorking = true
        statusMessage = nil
        Task {
            let active = await paywallStore.restore()
            await entitlements.refreshFromAdapty()
            isWorking = false
            if active {
                onPurchased()
            } else {
                statusMessage = "No active subscription found."
            }
        }
    }
}

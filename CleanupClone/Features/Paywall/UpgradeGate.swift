import SwiftUI
import PostHog

struct UpgradeGateContext: Identifiable, Equatable {
    let id = UUID()
    let action: FreeAction
    let title: String
    let subtitle: String

    static func forAction(_ action: FreeAction) -> UpgradeGateContext {
        switch action {
        case .photoDelete:
            return .init(action: action,
                         title: "You've cleaned your free photos 🎉",
                         subtitle: "Upgrade to delete unlimited photos and free up all your storage.")
        case .videoDelete:
            return .init(action: action,
                         title: "Free video cleanups used",
                         subtitle: "Upgrade to keep deleting videos without limits.")
        case .videoCompress:
            return .init(action: action,
                         title: "Free compressions used",
                         subtitle: "Upgrade to compress unlimited videos and save GBs.")
        case .duplicateCluster:
            return .init(action: action,
                         title: "Unlock all duplicate cleanups",
                         subtitle: "Upgrade to clear every duplicate and similar cluster in one tap.")
        case .vaultAdd:
            return .init(action: action,
                         title: "Secret Vault is a Pro feature",
                         subtitle: "Upgrade to hide photos in your private, locked vault.")
        case .contactMerge:
            return .init(action: action,
                         title: "Clean your contacts with Pro",
                         subtitle: "Upgrade to merge duplicates and back up iCloud contacts.")
        case .emailCleanup:
            return .init(action: action,
                         title: "Clear your inbox with Pro",
                         subtitle: "Upgrade to unsubscribe and delete promotional emails in bulk.")
        case .speakerClean:
            return .init(action: action,
                         title: "Free water & dust removal used",
                         subtitle: "Upgrade for unlimited full-length speaker water ejection and dust removal.")
        }
    }
}

struct UpgradeGateSheet: View {
    let context: UpgradeGateContext
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var entitlements: EntitlementStore

    private let perks: [String] = [
        "Unlimited photo & video cleanups",
        "Remove every duplicate & similar",
        "Secret Vault, Contacts, Email cleaner",
        "Full-length water ejection & dust removal",
        "No ads · cancel anytime"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 18)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [CleanupTheme.electricBlue.opacity(0.35),
                                     CleanupTheme.electricBlue.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 14)

            Text(context.title)
                .font(CleanupFont.hero(22))
                .foregroundStyle(CleanupTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(context.subtitle)
                .font(CleanupFont.body(14))
                .foregroundStyle(CleanupTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            if context.action.limit > 0 {
                usageBar
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
            } else {
                Spacer().frame(height: 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(perks, id: \.self) { perk in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CleanupTheme.electricBlue)
                        Text(perk)
                            .font(CleanupFont.body(13))
                            .foregroundStyle(CleanupTheme.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 18)

            VStack(spacing: 10) {
                Button(action: {
                    PostHogSDK.shared.capture("upgrade_gate_tapped",
                        properties: ["action": context.action.rawValue, "choice": "upgrade"])
                    onUpgrade()
                }) {
                    Text("Upgrade to Pro")
                        .font(CleanupFont.body(16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(CleanupTheme.electricBlue, in: Capsule(style: .continuous))
                }

                Button(action: {
                    PostHogSDK.shared.capture("upgrade_gate_tapped",
                        properties: ["action": context.action.rawValue, "choice": "dismiss"])
                    onDismiss()
                }) {
                    Text("Maybe later")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(CleanupTheme.background)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            PostHogSDK.shared.capture("upgrade_gate_shown",
                properties: ["action": context.action.rawValue])
        }
    }

    private var usageBar: some View {
        let used = entitlements.usage[context.action] ?? 0
        let limit = context.action.limit
        let progress = min(1, Double(used) / Double(max(1, limit)))
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(CleanupTheme.electricBlue)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(used) of \(limit) free \(context.action.displayName) used")
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(CleanupTheme.textTertiary)
                Spacer()
            }
        }
    }
}

extension View {
    func upgradeGate(_ context: Binding<UpgradeGateContext?>,
                     onUpgrade: @escaping () -> Void) -> some View {
        self.sheet(item: context) { ctx in
            UpgradeGateSheet(
                context: ctx,
                onUpgrade: {
                    context.wrappedValue = nil
                    onUpgrade()
                },
                onDismiss: { context.wrappedValue = nil }
            )
        }
    }
}

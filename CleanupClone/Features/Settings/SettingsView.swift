import StoreKit
import SwiftUI
import UIKit

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var appFlow: AppFlow
    @EnvironmentObject private var entitlements: EntitlementStore

    @State private var showThemes = false
    @State private var showDeviceStatus = false
    @State private var showWidgetGallery = false
    @State private var showShareSheet = false
    @State private var signOutConfirmationVisible = false
    @State private var restoreStatus: String?

    private var legalTermsURL: URL? { URL(string: "https://cleanergpt.app/terms") }
    private var legalPrivacyURL: URL? { URL(string: "https://cleanergpt.app/privacy") }
    private var supportMailURL: URL? {
        let subject = "CleanerGPT Support"
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        return URL(string: "mailto:hello@cleanergpt.app?subject=\(encoded)")
    }
    private var appStoreShareURL: URL {
        // Placeholder — swap for the real App Store link once the listing is live.
        URL(string: "https://cleanergpt.app")!
    }
    private var shareMessage: String {
        "Clean up your iPhone with CleanerGPT — \(appStoreShareURL.absoluteString)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    // Free users see the "Pro Offer" card. Paying users see
                    // their current plan + Manage Subscription instead —
                    // showing "Get it now" to someone already paying is
                    // confusing and makes the app look unaware of its own
                    // state.
                    if entitlements.isPremium {
                        currentPlanCard
                    } else {
                        proOfferCard
                    }
                    accountSection
                    appManagementSection
                    appSettingsSection
                    helpSection
                    legalSection
                    #if DEBUG
                    debugSection
                    #endif

                    if let restoreStatus {
                        Text(restoreStatus)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            .background(CleanupTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showThemes) {
                ThemePickerSheet()
                    .environmentObject(appFlow)
            }
            .sheet(isPresented: $showDeviceStatus) {
                NavigationStack {
                    DeviceStatusView()
                        .environmentObject(appFlow)
                }
            }
            .sheet(isPresented: $showWidgetGallery) {
                NavigationStack {
                    WidgetGalleryView()
                        .environmentObject(appFlow)
                        .environmentObject(entitlements)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareMessage])
            }
            .confirmationDialog(
                "Sign out of \(appFlow.gmailAccount?.email ?? "email")?",
                isPresented: $signOutConfirmationVisible,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await appFlow.disconnectGmail()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CleanupTheme.electricBlue)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Settings")
                .font(CleanupFont.sectionTitle(22))
                .foregroundStyle(.white)

            Spacer()

            // Keep title centered with a matching-width spacer.
            Color.clear.frame(width: 40, height: 40)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .offset(y: 12)
        }
        .padding(.bottom, 12)
    }

    /// Shown to users who already have premium. Just a quiet "you're on Pro"
    /// indicator — no renewal date, no manage-subscription row, no upsell.
    /// Apple's own Subscriptions screen owns all of that, and surfacing it
    /// here just duplicates state we can't reliably keep in sync.
    private var currentPlanCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#0F3A23"), Color(hex: "#072A17")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(CleanupTheme.accentGreen.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CleanupTheme.accentGreen.opacity(0.9))
                        .frame(width: 40, height: 40)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pro Active")
                        .font(CleanupFont.sectionTitle(20))
                        .foregroundStyle(.white)
                    Text("You have full access to every feature.")
                        .font(CleanupFont.body(13))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CleanupTheme.accentGreen)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .frame(minHeight: 110)
    }

    private var proOfferCard: some View {
        Button {
            appFlow.requestUpgrade(for: .photoDelete)
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#0F3A23"), Color(hex: "#072A17")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(CleanupTheme.accentGreen.opacity(0.25), lineWidth: 1)
                    )

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(CleanupTheme.accentGreen.opacity(0.9))
                            .frame(width: 40, height: 40)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PRO OFFER")
                            .font(CleanupFont.sectionTitle(20))
                            .foregroundStyle(.white)
                        Text("Premium features")
                            .font(CleanupFont.body(13))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }

                    Spacer()

                    Text("Get it now")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(hex: "#B6DAFF"))
                        )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .frame(minHeight: 110)
        }
        .buttonStyle(.plain)
    }

    private var accountSection: some View {
        settingsSection(title: "Account") {
            settingsRow(icon: "arrow.uturn.backward.circle.fill", title: "Restore Purchase") {
                Task { await restorePurchase() }
            }
        }
    }

    @ViewBuilder
    private var appManagementSection: some View {
        if appFlow.gmailAccount != nil {
            settingsSection(title: "App Management") {
                settingsRow(icon: "envelope.fill", title: "Sign Out from Email") {
                    signOutConfirmationVisible = true
                }
            }
        }
    }

    private var appSettingsSection: some View {
        settingsSection(title: "App Settings") {
            VStack(spacing: 0) {
                settingsRow(icon: "iphone", title: "Themes") {
                    showThemes = true
                }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                settingsRow(icon: "square.grid.2x2.fill", title: "Widgets") {
                    showWidgetGallery = true
                }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                settingsRow(icon: "gauge.with.dots.needle.67percent", title: "Device Status") {
                    showDeviceStatus = true
                }
            }
        }
    }

    private var helpSection: some View {
        settingsSection(title: "Help & Feedback") {
            VStack(spacing: 0) {
                settingsRow(icon: "envelope.fill", title: "Contact Us") {
                    if let url = supportMailURL {
                        openURL(url)
                    }
                }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                settingsRow(icon: "hand.thumbsup.fill", title: "Rate App") {
                    requestReview()
                }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                settingsRow(icon: "heart.fill", title: "Share App") {
                    showShareSheet = true
                }
            }
        }
    }

    private var legalSection: some View {
        settingsSection(title: "Legal") {
            VStack(spacing: 0) {
                settingsRow(icon: "link", title: "Terms of Use") {
                    if let url = legalTermsURL { openURL(url) }
                }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                settingsRow(icon: "link", title: "Privacy Policy") {
                    if let url = legalPrivacyURL { openURL(url) }
                }
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        settingsSection(title: "Debug") {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(CleanupTheme.electricBlue.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: entitlements.isPremium ? "checkmark.seal.fill" : "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(entitlements.isPremium ? CleanupTheme.accentGreen : CleanupTheme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entitlements.isPremium ? "Premium active" : "Free tier")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)
                        Text(freeUsageSummary)
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)

                Toggle(isOn: Binding(
                    get: { entitlements.debugForceFree },
                    set: { entitlements.setDebugForceFree($0) }
                )) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(CleanupTheme.electricBlue.opacity(0.18))
                                .frame(width: 32, height: 32)
                            Image(systemName: "lock.slash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CleanupTheme.electricBlue)
                        }
                        Text("Force free tier (override sandbox)")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)
                    }
                }
                .tint(CleanupTheme.electricBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)

                // Hard-paywall simulator override. Flips `debug.hardPaywall`
                // in UserDefaults, which `PaywallStore` reads on next
                // `loadPaywall()` and prefers over the Adapty remoteConfig
                // value. Clear the toggle (triple-tap "Reset overrides"
                // below) to fall back to the live Adapty config.
                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "debug.hardPaywall") },
                    set: {
                        UserDefaults.standard.set($0, forKey: "debug.hardPaywall")
                        restoreStatus = $0
                            ? "Hard paywall forced — reload paywall to see."
                            : "Soft paywall forced — reload paywall to see."
                    }
                )) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(CleanupTheme.electricBlue.opacity(0.18))
                                .frame(width: 32, height: 32)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CleanupTheme.electricBlue)
                        }
                        Text("Force hard paywall")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)
                    }
                }
                .tint(CleanupTheme.electricBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)

                settingsRow(icon: "xmark.circle", title: "Clear paywall override") {
                    UserDefaults.standard.removeObject(forKey: "debug.hardPaywall")
                    restoreStatus = "Paywall override cleared — using Adapty remote config."
                }

                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)

                settingsRow(icon: "arrow.counterclockwise", title: "Reset free-tier counters") {
                    entitlements.resetAllUsage()
                    restoreStatus = "Free-tier counters reset."
                }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                settingsRow(icon: "arrow.clockwise", title: "Refresh premium status") {
                    Task { await entitlements.refreshFromAdapty() }
                }
            }
        }
    }

    private var freeUsageSummary: String {
        FreeAction.allCases
            .map { "\($0.rawValue):\(entitlements.usage[$0] ?? 0)/\($0.limit)" }
            .joined(separator: " · ")
    }
    #endif

    // MARK: - Building blocks

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(CleanupFont.sectionTitle(18))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)

            GlassCard(cornerRadius: 18) {
                content()
            }
        }
    }

    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CleanupTheme.electricBlue.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CleanupTheme.electricBlue)
                }

                Text(title)
                    .font(CleanupFont.body(15))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CleanupTheme.electricBlue)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// Modern StoreKit 2 restore. Even without IAP products wired up, this is
    /// safe to call — it prompts the user to authenticate with Apple ID and
    /// returns, at which point we just tell them nothing was found.
    private func restorePurchase() async {
        restoreStatus = "Checking…"
        do {
            try await AppStore.sync()
            // After AppStore.sync, Adapty needs a beat to receive the updated
            // receipt — then we pull the latest profile so plan / expiry /
            // willRenew repopulate everywhere (Settings card, paywall, etc.).
            await entitlements.refreshFromAdapty()
            restoreStatus = entitlements.isPremium
                ? "Subscription restored."
                : "No purchases to restore."
        } catch {
            restoreStatus = "Restore failed. Please try again."
        }
    }
}

// MARK: - Theme Picker Sheet

private struct ThemePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        NavigationStack {
            ZStack {
                CleanupTheme.background.ignoresSafeArea()

                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        themeRow(.automatic)
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 20)
                        themeRow(.dark)
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 20)
                        lightComingSoonRow
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CleanupTheme.card.opacity(0.75))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Text("Light mode is being polished for every screen in the app. Coming in the next update.")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Spacer()
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CleanupTheme.electricBlue)
                }
            }
        }
    }

    private func themeRow(_ option: AppAppearance) -> some View {
        let isSelected = appFlow.appearancePreference == option
        return Button {
            appFlow.appearancePreference = option
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option == .automatic ? "circle.lefthalf.filled" : "moon.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CleanupTheme.electricBlue)
                    .frame(width: 28)

                Text(option.title)
                    .font(CleanupFont.body(15))
                    .foregroundStyle(.white)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CleanupTheme.electricBlue)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lightComingSoonRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CleanupTheme.textSecondary)
                .frame(width: 28)

            Text("Light")
                .font(CleanupFont.body(15))
                .foregroundStyle(CleanupTheme.textSecondary)

            Spacer()

            Text("Coming soon")
                .font(CleanupFont.caption(11))
                .foregroundStyle(CleanupTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .opacity(0.55)
    }
}

// MARK: - Device Status (re-exposed inside Settings)

/// Thin wrapper so we can present `AppStatusView` in a sheet without the
/// NavigationLink machinery that caused the duplicate back button.
private struct DeviceStatusView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppStatusView()
            .onAppear {
                // AppStatusView's leading chevron calls dismiss() via its own
                // @Environment(\.dismiss) — that correctly dismisses our sheet.
            }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

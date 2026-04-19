import SwiftUI

private enum EmailCleanerScreen {
    case home
    case unsubscribe
    case junkMail
}

struct EmailCleanerView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appFlow: AppFlow

    @State private var screen: EmailCleanerScreen = .home

    private let previewSenders: [GmailSenderSummary] = [
        .init(id: "google", name: "Google", email: "no-reply@accounts.google.com", emailCount: 9, unsubscribeURL: URL(string: "https://support.google.com/accounts")),
        .init(id: "temu", name: "Temu", email: "temu@commerce.temumail.com", emailCount: 172, unsubscribeURL: URL(string: "https://www.temu.com")),
        .init(id: "stripe", name: "Stripe", email: "notifications@stripe.com", emailCount: 43, unsubscribeURL: URL(string: "https://stripe.com"))
    ]

    private let previewCategories: [GmailCategorySummary] = [
        .init(id: "Social", title: "Social Media", labelID: "CATEGORY_SOCIAL", messageCount: 18),
        .init(id: "Promotions", title: "Promotions", labelID: "CATEGORY_PROMOTIONS", messageCount: 32),
        .init(id: "Updates", title: "Updates", labelID: "CATEGORY_UPDATES", messageCount: 14),
        .init(id: "Newsletters", title: "Forum", labelID: "CATEGORY_FORUMS", messageCount: 11),
        .init(id: "Notifications", title: "Spam", labelID: "SPAM", messageCount: 7)
    ]

    private let senderPalettes: [[Color]] = [
        [Color(hex: "#5FA5FF"), Color(hex: "#346CFF")],
        [Color(hex: "#8B7BFF"), Color(hex: "#5B46FF")],
        [Color(hex: "#44D3B8"), Color(hex: "#178F86")],
        [Color(hex: "#FFB45A"), Color(hex: "#FF7F50")],
        [Color(hex: "#FF79A8"), Color(hex: "#C73D7A")]
    ]

    private var senders: [GmailSenderSummary] {
        appFlow.isGmailConnected ? appFlow.gmailSenderSummaries : previewSenders
    }

    private var junkCategories: [GmailCategorySummary] {
        appFlow.isGmailConnected ? appFlow.gmailCategorySummaries : previewCategories
    }

    private var currentTitle: String {
        switch screen {
        case .home:
            "Email Cleaner"
        case .unsubscribe:
            "Unsubscribe"
        case .junkMail:
            "Junk Mail"
        }
    }

    private var trailingSymbol: String? {
        switch screen {
        case .home:
            appFlow.isGmailConnected ? "arrow.clockwise" : nil
        case .unsubscribe:
            nil
        case .junkMail:
            "slider.horizontal.3"
        }
    }

    private var selectedJunkCount: Int {
        appFlow.emailPreferences.selectedFilters.count
    }

    private var unsubscribeCount: Int {
        senders.filter { appFlow.emailPreferences.senderChoices[$0.id] == "unsubscribe" }.count
    }

    private var syncStatusText: String {
        guard let syncedAt = appFlow.gmailLastSyncedAt else {
            return "Just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: syncedAt, relativeTo: Date())
    }

    var body: some View {
        FeatureScreen(
            title: currentTitle,
            leadingSymbol: "chevron.left",
            trailingSymbol: trailingSymbol,
            leadingAction: { handleLeadingAction() },
            trailingAction: { handleTrailingAction() }
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    switch screen {
                    case .home:
                        homeContent
                    case .unsubscribe:
                        unsubscribeContent
                    case .junkMail:
                        junkMailContent
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var homeContent: some View {
        VStack(spacing: 14) {
            statusCard

            entryCard(
                title: "Unsubscribe",
                subtitle: appFlow.isGmailConnected
                    ? "Review noisy senders and keep or remove them fast."
                    : "Preview recurring senders before linking Gmail.",
                value: unsubscribeCount == 0 ? "\(senders.count)" : "\(unsubscribeCount)",
                action: { screen = .unsubscribe }
            )

            entryCard(
                title: "Junk Mail",
                subtitle: appFlow.isGmailConnected
                    ? "Clean Social, Promotions, Updates, and Spam."
                    : "Pick the categories you want the cleaner to target.",
                value: "\(selectedJunkCount)",
                action: { screen = .junkMail }
            )

            rulesCard
        }
    }

    private var unsubscribeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisHint(
                appFlow.isGmailConnected
                    ? "Scanning live Gmail senders..."
                    : "Previewing the unsubscribe flow before Gmail is connected."
            )

            if senders.isEmpty {
                GlassCard(cornerRadius: 24) {
                    Text("No recurring senders found yet.")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            } else {
                ForEach(senders) { sender in
                    unsubscribeSenderCard(sender)
                }
            }
        }
    }

    private var junkMailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisHint(
                appFlow.isGmailConnected
                    ? "Using live Gmail labels and category totals."
                    : "Previewing the junk-mail categories before Gmail is connected."
            )

            ForEach(junkCategories) { category in
                junkCategoryRow(category)
            }

            GlassProminentCTA {
                screen = .home
            } label: {
                Text(selectedJunkCount == 0 ? "Select categories" : "Save cleanup rules")
                    .font(CleanupFont.body(18))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .disabled(selectedJunkCount == 0)
            .opacity(selectedJunkCount == 0 ? 0.45 : 1)
            .padding(.top, 10)
        }
    }

    private var statusCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                if let account = appFlow.gmailAccount {
                    Text("Gmail connected")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        accountAvatar(for: account)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.displayName)
                                .font(CleanupFont.sectionTitle(18))
                                .foregroundStyle(.white)
                            Text(account.email)
                                .font(CleanupFont.body(14))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }
                    }

                    HStack(spacing: 10) {
                        statusPill(title: "Gmail", value: "Connected", tint: CleanupTheme.accentGreen)
                        statusPill(title: "Synced", value: syncStatusText, tint: CleanupTheme.electricBlue)
                        statusPill(title: "Senders", value: "\(senders.count)", tint: Color(hex: "#7C8BFF"))
                    }

                    HStack(spacing: 10) {
                        secondaryActionButton(
                            title: appFlow.isRefreshingGmail ? "Refreshing..." : "Refresh",
                            tint: CleanupTheme.electricBlue
                        ) {
                            Task {
                                await appFlow.refreshGmailMailbox()
                            }
                        }
                        .disabled(appFlow.isRefreshingGmail)

                        secondaryActionButton(title: "Disconnect", tint: CleanupTheme.accentRed) {
                            Task {
                                await appFlow.disconnectGmail()
                            }
                        }
                    }
                } else {
                    Text("Connect Gmail to organize your inbox")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        statusPill(title: "Gmail", value: "Not Connected", tint: Color(hex: "#F6B14B"))
                        statusPill(title: "Mode", value: "Preview UI", tint: CleanupTheme.electricBlue)
                        statusPill(title: "Flow", value: "2 steps", tint: Color(hex: "#7C8BFF"))
                    }

                    inboxCueRow

                    GlassProminentCTA {
                        Task {
                            await appFlow.connectGmail()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if appFlow.isConnectingGmail {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(appFlow.isConnectingGmail ? "Connecting Gmail..." : "Connect Gmail")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .disabled(appFlow.isConnectingGmail)
                }

                if let gmailErrorMessage = appFlow.gmailErrorMessage {
                    Text(gmailErrorMessage)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.accentRed)
                }
            }
        }
    }

    private func entryCard(title: String, subtitle: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlassCard(cornerRadius: 22) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(CleanupFont.sectionTitle(20))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(CleanupFont.body(13))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Text(value)
                        .font(CleanupFont.sectionTitle(20))
                        .foregroundStyle(CleanupTheme.electricBlue)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rulesCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cleaner Rules")
                    .font(CleanupFont.sectionTitle(18))
                    .foregroundStyle(.white)

                Toggle("Archive instead of delete", isOn: Binding(
                    get: { appFlow.emailPreferences.archiveInsteadOfDelete },
                    set: { value in
                        appFlow.updateEmailPreferences { $0.archiveInsteadOfDelete = value }
                    }
                ))
                .tint(CleanupTheme.accentGreen)

                Toggle("Skip starred messages", isOn: Binding(
                    get: { appFlow.emailPreferences.excludeStarred },
                    set: { value in
                        appFlow.updateEmailPreferences { $0.excludeStarred = value }
                    }
                ))
                .tint(CleanupTheme.accentGreen)
            }
            .foregroundStyle(.white)
        }
    }

    private func analysisHint(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(CleanupTheme.electricBlue)
            Text(text)
                .font(CleanupFont.body(13))
                .foregroundStyle(CleanupTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var inboxCueRow: some View {
        HStack(spacing: 10) {
            cuePill(symbol: "envelope.fill", title: "Senders")
            cuePill(symbol: "tag.fill", title: "Categories")
            cuePill(symbol: "link", title: "Actions")
        }
    }

    private func cuePill(symbol: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(CleanupFont.caption(11))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule(style: .continuous))
    }

    private func unsubscribeSenderCard(_ sender: GmailSenderSummary) -> some View {
        let choice = appFlow.emailPreferences.senderChoices[sender.id] ?? "keep"

        return GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(LinearGradient(colors: iconPalette(for: sender), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Text(iconText(for: sender))
                                .font(CleanupFont.sectionTitle(20))
                                .foregroundStyle(iconForeground(for: sender))
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sender.name)
                            .font(CleanupFont.sectionTitle(20))
                            .foregroundStyle(.white)
                        Text(sender.email)
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }

                    Spacer()

                    Text("\(sender.emailCount) emails")
                        .font(CleanupFont.badge(12))
                        .foregroundStyle(CleanupTheme.accentGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CleanupTheme.accentGreen.opacity(0.12), in: Capsule(style: .continuous))
                }

                if sender.unsubscribeURL != nil {
                    Text("Unsubscribe link available")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.electricBlue)
                }

                HStack(spacing: 10) {
                    senderChoiceButton(title: "Keep", selected: choice == "keep") {
                        appFlow.updateEmailPreferences {
                            $0.senderChoices[sender.id] = "keep"
                        }
                    }

                    senderChoiceButton(title: "Unsubscribe", selected: choice == "unsubscribe") {
                        appFlow.updateEmailPreferences {
                            $0.senderChoices[sender.id] = "unsubscribe"
                        }

                        if let unsubscribeURL = sender.unsubscribeURL {
                            openURL(unsubscribeURL)
                        }
                    }
                }

                HStack {
                    Text("Delete all from this sender")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appFlow.emailPreferences.deleteAllAfterUnsubscribe.contains(sender.id) },
                        set: { enabled in
                            appFlow.updateEmailPreferences {
                                if enabled {
                                    $0.deleteAllAfterUnsubscribe.insert(sender.id)
                                } else {
                                    $0.deleteAllAfterUnsubscribe.remove(sender.id)
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(CleanupTheme.electricBlue)
                }
            }
        }
    }

    private func senderChoiceButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CleanupFont.body(15))
                .foregroundStyle(selected ? Color.black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Group {
                        if selected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(CleanupTheme.electricBlue)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(CleanupTheme.electricBlue.opacity(0.65), lineWidth: 1.5)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    private func junkCategoryRow(_ category: GmailCategorySummary) -> some View {
        let isSelected = appFlow.emailPreferences.selectedFilters.contains(category.id)

        return Button {
            appFlow.updateEmailPreferences {
                if isSelected {
                    $0.selectedFilters.remove(category.id)
                } else {
                    $0.selectedFilters.insert(category.id)
                }
            }
        } label: {
            GlassCard(cornerRadius: 20) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? CleanupTheme.electricBlue : Color.white.opacity(0.08))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                        Text(category.title)
                            .font(CleanupFont.sectionTitle(18))
                            .foregroundStyle(.white)
                        Text("Total \(category.messageCount)")
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textTertiary)
                        }
                    }

                    Spacer()

                    Text("\(category.messageCount)")
                        .font(CleanupFont.sectionTitle(18))
                        .foregroundStyle(CleanupTheme.electricBlue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statusPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(CleanupFont.caption(11))
                .foregroundStyle(CleanupTheme.textTertiary)
            Text(value)
                .font(CleanupFont.badge(12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.3))
        }
    }

    private func secondaryActionButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CleanupFont.body(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.18))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tint.opacity(0.35))
                }
        }
        .buttonStyle(.plain)
    }

    private func accountAvatar(for account: GmailAccountSummary) -> some View {
        Group {
            if let avatarURL = account.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(CleanupTheme.electricBlue.opacity(0.18))
                        .overlay {
                            ProgressView()
                                .tint(.white)
                        }
                }
            } else {
                Circle()
                    .fill(CleanupTheme.electricBlue.opacity(0.18))
                    .overlay {
                        Text(String(account.displayName.prefix(1)).uppercased())
                            .font(CleanupFont.sectionTitle(18))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func iconText(for sender: GmailSenderSummary) -> String {
        if sender.name.lowercased() == "google" {
            return "G"
        }
        return String(sender.name.prefix(1)).uppercased()
    }

    private func iconForeground(for sender: GmailSenderSummary) -> Color {
        sender.name.lowercased() == "google" ? Color(hex: "#4285F4") : .white
    }

    private func iconPalette(for sender: GmailSenderSummary) -> [Color] {
        if sender.name.lowercased() == "google" {
            return [Color.white, Color(hex: "#D2E4FF")]
        }

        return senderPalettes[abs(sender.email.hashValue) % senderPalettes.count]
    }

    private func handleLeadingAction() {
        switch screen {
        case .home:
            appFlow.closeFeature()
        case .unsubscribe, .junkMail:
            screen = .home
        }
    }

    private func handleTrailingAction() {
        switch screen {
        case .home:
            if appFlow.isGmailConnected {
                Task {
                    await appFlow.refreshGmailMailbox()
                }
            }
        case .unsubscribe:
            break
        case .junkMail:
            appFlow.updateEmailPreferences { _ in }
        }
    }
}

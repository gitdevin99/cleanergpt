import SwiftUI
import WebKit

private enum EmailCleanerScreen: Hashable {
    case home
    case unsubscribe
    case junkMail
    case categoryDetail(categoryID: String)
    case emailDetail(messageID: String)
}

private enum UnsubscribeRowState: Equatable {
    case idle
    case inProgress
    case done
    case failed
}

struct EmailCleanerView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appFlow: AppFlow

    @State private var screenStack: [EmailCleanerScreen] = [.home]
    @State private var unsubscribeStates: [String: UnsubscribeRowState] = [:]

    // Category-detail state
    @State private var currentCategoryID: String?
    @State private var currentCategoryMessages: [GmailMessagePreview] = []
    @State private var currentCategoryTotalEstimate: Int = 0
    @State private var currentCategoryNextPage: String?
    @State private var isLoadingCategoryPage = false
    @State private var selectedMessageIDs: Set<String> = []
    @State private var isSelectAllMode = false
    @State private var isDeletingMessages = false
    @State private var categoryErrorMessage: String?

    // Detail state
    @State private var currentDetailMessageID: String?
    @State private var currentDetail: GmailMessageDetail?
    @State private var isLoadingDetail = false
    @State private var detailErrorMessage: String?

    private let senderPalettes: [[Color]] = [
        [Color(hex: "#5FA5FF"), Color(hex: "#346CFF")],
        [Color(hex: "#8B7BFF"), Color(hex: "#5B46FF")],
        [Color(hex: "#44D3B8"), Color(hex: "#178F86")],
        [Color(hex: "#FFB45A"), Color(hex: "#FF7F50")],
        [Color(hex: "#FF79A8"), Color(hex: "#C73D7A")]
    ]

    private var screen: EmailCleanerScreen {
        screenStack.last ?? .home
    }

    /// Counts and lists are driven entirely by the live Gmail connection.
    /// Before the user connects (or after they disconnect) we show a clean
    /// zero state — no hardcoded demo data — so the numbers on the Email
    /// Cleaner home always reflect reality.
    private var senders: [GmailSenderSummary] {
        appFlow.isGmailConnected ? appFlow.gmailSenderSummaries : []
    }

    private var junkCategories: [GmailCategorySummary] {
        appFlow.isGmailConnected ? appFlow.gmailCategorySummaries : []
    }

    private var currentCategory: GmailCategorySummary? {
        guard let id = currentCategoryID else { return nil }
        return junkCategories.first { $0.id == id }
    }

    private var currentTitle: String {
        switch screen {
        case .home: return "Email Cleaner"
        case .unsubscribe: return "Unsubscribe"
        case .junkMail: return "Junk Mail"
        case .categoryDetail: return currentCategory?.title ?? "Junk Mail"
        case .emailDetail: return "Message"
        }
    }

    private var trailingSymbol: String? {
        switch screen {
        case .home: return appFlow.isGmailConnected ? "arrow.clockwise" : nil
        case .junkMail: return "slider.horizontal.3"
        case .categoryDetail, .emailDetail, .unsubscribe: return nil
        }
    }

    // Real counts
    private var unsubscribeAvailableCount: Int {
        senders.filter { $0.unsubscribeURL != nil || $0.mailtoUnsubscribe != nil }.count
    }

    private var junkTotalCount: Int {
        junkCategories.reduce(0) { $0 + $1.messageCount }
    }

    private var unsubscribeSubtitle: String {
        if appFlow.isGmailConnected {
            return "Review noisy senders and keep or remove them fast."
        }
        return "Connect Gmail to see recurring senders."
    }

    private var junkMailSubtitle: String {
        if appFlow.isGmailConnected {
            return "Clean Social, Promotions, Updates, and Spam."
        }
        return "Connect Gmail to see junk-mail categories."
    }

    private var unsubscribeHint: String {
        if appFlow.isGmailConnected { return "Scanning live Gmail senders..." }
        return "Connect Gmail to see your recurring senders."
    }

    private var junkMailHint: String {
        if appFlow.isGmailConnected { return "Use smart folders to get rid of junk mail." }
        return "Connect Gmail to see your junk mail."
    }

    private var syncStatusText: String {
        guard let syncedAt = appFlow.gmailLastSyncedAt else { return "Just now" }
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
            switch screen {
            case .home, .unsubscribe, .junkMail:
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        switch screen {
                        case .home: homeContent
                        case .unsubscribe: unsubscribeContent
                        case .junkMail: junkMailContent
                        default: EmptyView()
                        }
                    }
                    .padding(.bottom, 24)
                }
            case .categoryDetail:
                categoryDetailContent
            case .emailDetail:
                emailDetailContent
            }
        }
    }

    // MARK: - Home

    private var homeContent: some View {
        VStack(spacing: 14) {
            statusCard

            entryCard(
                title: "Unsubscribe",
                subtitle: unsubscribeSubtitle,
                value: "\(unsubscribeAvailableCount)",
                action: { push(.unsubscribe) }
            )

            entryCard(
                title: "Junk Mail",
                subtitle: junkMailSubtitle,
                value: junkCategories.isEmpty ? "0" : formattedCount(junkTotalCount),
                action: { push(.junkMail) }
            )

            rulesCard
        }
    }

    // MARK: - Unsubscribe list

    private var unsubscribeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisHint(unsubscribeHint)

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

    // MARK: - Junk Mail category grid

    private var junkMailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisHint(junkMailHint)

            if junkCategories.isEmpty {
                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No categories to show")
                            .font(CleanupFont.sectionTitle(18))
                            .foregroundStyle(.white)
                        Text("Connect Gmail from the Email Cleaner home to see your junk-mail categories.")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }
                }
            } else {
                ForEach(junkCategories) { category in
                    junkCategoryRow(category)
                }
            }
        }
    }

    private var selectAllIconName: String {
        let loaded = currentCategoryMessages.map(\.id)
        let allLoadedSelected = !loaded.isEmpty && selectedMessageIDs.isSuperset(of: loaded)
        return allLoadedSelected ? "checkmark.circle.fill" : "circle"
    }

    private var selectAllButtonTitle: String {
        let loaded = currentCategoryMessages.map(\.id)
        let allLoadedSelected = !loaded.isEmpty && selectedMessageIDs.isSuperset(of: loaded)
        return allLoadedSelected ? "Deselect all" : "Select all"
    }

    private var headerStatusText: String {
        if !selectedMessageIDs.isEmpty {
            return "\(selectedMessageIDs.count) selected"
        }
        // Show real-time count: "loaded / total", growing as pages come in.
        let loaded = currentCategoryMessages.count
        let total = max(currentCategoryTotalEstimate, loaded)
        if loaded == 0 {
            return "Loading..."
        }
        if currentCategoryNextPage == nil {
            return "\(loaded) of \(loaded)"
        }
        return "\(loaded) of \(formattedCount(total))"
    }

    // MARK: - Category detail (paginated list w/ multi-select)

    private var categoryDetailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    let loaded = currentCategoryMessages.map(\.id)
                    let allLoadedSelected = !loaded.isEmpty && selectedMessageIDs.isSuperset(of: loaded)
                    if allLoadedSelected {
                        selectedMessageIDs.removeAll()
                    } else {
                        selectedMessageIDs.formUnion(loaded)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectAllIconName)
                            .font(.system(size: 15, weight: .semibold))
                        Text(selectAllButtonTitle)
                            .font(CleanupFont.body(14))
                    }
                    .foregroundStyle(CleanupTheme.electricBlue)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(headerStatusText)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
            .padding(.horizontal, 4)

            if let categoryErrorMessage {
                Text(categoryErrorMessage)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.accentRed)
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(currentCategoryMessages.enumerated()), id: \.element.id) { index, message in
                        messageRow(message)
                            .onAppear {
                                // Trigger ~10 rows before the end so the next
                                // page is warm by the time the user reaches it.
                                let threshold = max(currentCategoryMessages.count - 10, 0)
                                if index >= threshold, currentCategoryNextPage != nil, !isLoadingCategoryPage {
                                    Task { await loadNextCategoryPage() }
                                }
                            }
                    }

                    if isLoadingCategoryPage {
                        HStack {
                            Spacer()
                            ProgressView().tint(CleanupTheme.electricBlue)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                    } else if currentCategoryNextPage != nil {
                        Button {
                            Task { await loadNextCategoryPage() }
                        } label: {
                            Text("Load more")
                                .font(CleanupFont.body(14))
                                .foregroundStyle(CleanupTheme.electricBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(CleanupTheme.electricBlue.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    } else if !currentCategoryMessages.isEmpty {
                        Text("All \(currentCategoryMessages.count) loaded")
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.bottom, 80)
            }

            if !selectedMessageIDs.isEmpty {
                Button {
                    Task { await deleteSelectedMessages() }
                } label: {
                    HStack(spacing: 10) {
                        if isDeletingMessages {
                            ProgressView().tint(.white)
                        }
                        Text(isDeletingMessages ? "Deleting..." : "Delete emails")
                            .font(CleanupFont.body(16))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(CleanupTheme.accentRed.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .disabled(isDeletingMessages)
            }
        }
    }

    private func messageRow(_ message: GmailMessagePreview) -> some View {
        let isSelected = selectedMessageIDs.contains(message.id)
        return HStack(spacing: 12) {
            // Dedicated checkbox tap target — toggles selection only.
            Button {
                toggleSelection(message.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? CleanupTheme.electricBlue : CleanupTheme.textTertiary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Row body — tap opens the email preview.
            Button {
                openDetail(messageID: message.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(message.fromName)
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(relativeDate(message.date))
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CleanupTheme.textTertiary)
                    }
                    Text(message.subject)
                        .font(CleanupFont.body(13))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .lineLimit(1)
                    if !message.snippet.isEmpty {
                        Text(message.snippet)
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? CleanupTheme.electricBlue.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? CleanupTheme.electricBlue.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private func toggleSelection(_ id: String) {
        if selectedMessageIDs.contains(id) {
            selectedMessageIDs.remove(id)
        } else {
            selectedMessageIDs.insert(id)
        }
    }

    private func openDetail(messageID: String) {
        currentDetailMessageID = messageID
        currentDetail = nil
        detailErrorMessage = nil
        push(.emailDetail(messageID: messageID))
        Task { await loadDetail(messageID: messageID) }
    }

    // MARK: - Detail

    private var emailDetailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoadingDetail, currentDetail == nil {
                HStack {
                    Spacer()
                    ProgressView().tint(CleanupTheme.electricBlue)
                    Spacer()
                }
                .padding(.top, 40)
            } else if let detail = currentDetail {
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.subject)
                        .font(CleanupFont.sectionTitle(20))
                        .foregroundStyle(.white)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detail.fromName)
                                .font(CleanupFont.body(14))
                                .foregroundStyle(.white)
                            Text(detail.fromEmail)
                                .font(CleanupFont.caption(12))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }
                        Spacer()
                        if let date = detail.date {
                            Text(DateFormatter.emailDetail.string(from: date))
                                .font(CleanupFont.caption(11))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 4)

                EmailBodyWebView(html: detail.htmlBody, fallbackText: detail.plainBody)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let detailErrorMessage {
                Text(detailErrorMessage)
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.accentRed)
            }
        }
    }

    private func loadDetail(messageID: String) async {
        guard appFlow.isGmailConnected else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let detail = try await GmailService.shared.fetchMessageDetail(messageID: messageID)
            if currentDetailMessageID == messageID {
                currentDetail = detail
            }
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Pagination

    private func openCategory(_ category: GmailCategorySummary) {
        currentCategoryID = category.id
        currentCategoryMessages = []
        currentCategoryNextPage = nil
        currentCategoryTotalEstimate = category.messageCount
        selectedMessageIDs.removeAll()
        isSelectAllMode = false
        categoryErrorMessage = nil
        push(.categoryDetail(categoryID: category.id))
        Task { await loadNextCategoryPage(initial: true) }
    }

    private func loadNextCategoryPage(initial: Bool = false) async {
        guard appFlow.isGmailConnected, !isLoadingCategoryPage else { return }
        guard let category = currentCategory else { return }
        if !initial && currentCategoryNextPage == nil { return }

        isLoadingCategoryPage = true
        defer { isLoadingCategoryPage = false }

        do {
            let page = try await GmailService.shared.listMessages(
                labelID: category.labelID,
                pageToken: currentCategoryNextPage,
                pageSize: 50
            )
            if currentCategoryID == category.id {
                currentCategoryMessages.append(contentsOf: page.messages)
                currentCategoryNextPage = page.nextPageToken
                currentCategoryTotalEstimate = max(currentCategoryTotalEstimate, page.totalEstimate)
            }
        } catch {
            categoryErrorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedMessages() async {
        guard appFlow.isGmailConnected, !selectedMessageIDs.isEmpty else { return }
        guard await MainActor.run(body: { appFlow.gateSingleAction(.emailCleanup) }) else { return }
        isDeletingMessages = true

        let ids = Array(selectedMessageIDs)
        do {
            if appFlow.emailPreferences.archiveInsteadOfDelete {
                try await GmailService.shared.archiveMessages(ids: ids)
            } else {
                try await GmailService.shared.trashMessages(ids: ids)
            }

            // Optimistic local update so the UI reflects the delete
            // immediately, then release the spinner.
            let deletedIDs = selectedMessageIDs
            currentCategoryMessages.removeAll { deletedIDs.contains($0.id) }
            currentCategoryTotalEstimate = max(0, currentCategoryTotalEstimate - deletedIDs.count)
            selectedMessageIDs.removeAll()
            isSelectAllMode = false
            isDeletingMessages = false

            // Kick off the full mailbox refresh in the background — it
            // re-discovers senders and can take several seconds; the user
            // doesn't need to wait for it to see their delete succeeded.
            Task { await appFlow.refreshGmailMailbox() }
        } catch {
            categoryErrorMessage = error.localizedDescription
            isDeletingMessages = false
        }
    }

    // MARK: - Status card

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
                            Task { await appFlow.refreshGmailMailbox() }
                        }
                        .disabled(appFlow.isRefreshingGmail)

                        secondaryActionButton(title: "Disconnect", tint: CleanupTheme.accentRed) {
                            Task { await appFlow.disconnectGmail() }
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
                        Task { await appFlow.connectGmail() }
                    } label: {
                        HStack(spacing: 10) {
                            if appFlow.isConnectingGmail {
                                ProgressView().tint(.white)
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
                    set: { value in appFlow.updateEmailPreferences { $0.archiveInsteadOfDelete = value } }
                ))
                .tint(CleanupTheme.accentGreen)

                Toggle("Skip starred messages", isOn: Binding(
                    get: { appFlow.emailPreferences.excludeStarred },
                    set: { value in appFlow.updateEmailPreferences { $0.excludeStarred = value } }
                ))
                .tint(CleanupTheme.accentGreen)
            }
            .foregroundStyle(.white)
        }
    }

    private func analysisHint(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(CleanupTheme.electricBlue)
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
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(title).font(CleanupFont.caption(11))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule(style: .continuous))
    }

    // MARK: - Unsubscribe sender card

    private func unsubscribeSenderCard(_ sender: GmailSenderSummary) -> some View {
        let rowState = unsubscribeStates[sender.id] ?? .idle
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

                if sender.supportsOneClickPost {
                    Text("One-click unsubscribe available")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.accentGreen)
                } else if sender.unsubscribeURL != nil || sender.mailtoUnsubscribe != nil {
                    Text("Unsubscribe link available")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.electricBlue)
                }

                HStack(spacing: 10) {
                    senderChoiceButton(title: "Keep", selected: choice == "keep") {
                        appFlow.updateEmailPreferences { $0.senderChoices[sender.id] = "keep" }
                    }

                    unsubscribeButton(sender: sender, state: rowState, selected: choice == "unsubscribe")
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
                                if enabled { $0.deleteAllAfterUnsubscribe.insert(sender.id) }
                                else { $0.deleteAllAfterUnsubscribe.remove(sender.id) }
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(CleanupTheme.electricBlue)
                }
            }
        }
    }

    private func unsubscribeButton(sender: GmailSenderSummary, state: UnsubscribeRowState, selected: Bool) -> some View {
        Button {
            Task { await performUnsubscribe(sender: sender) }
        } label: {
            HStack(spacing: 8) {
                switch state {
                case .inProgress:
                    ProgressView().tint(selected ? .black : .white)
                    Text("Unsubscribing...")
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                    Text("Unsubscribed")
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Retry")
                case .idle:
                    Text("Unsubscribe")
                }
            }
            .font(CleanupFont.body(15))
            .foregroundStyle(buttonForeground(state: state, selected: selected))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Group {
                    if state == .done {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CleanupTheme.accentGreen)
                    } else if state == .failed {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CleanupTheme.accentRed.opacity(0.3))
                    } else if selected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CleanupTheme.electricBlue)
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CleanupTheme.electricBlue.opacity(0.65), lineWidth: 1.5)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .inProgress)
    }

    private func buttonForeground(state: UnsubscribeRowState, selected: Bool) -> Color {
        switch state {
        case .done: return .white
        case .failed: return .white
        case .inProgress: return selected ? .black : .white
        case .idle: return selected ? .black : .white
        }
    }

    private func performUnsubscribe(sender: GmailSenderSummary) async {
        guard appFlow.isGmailConnected else {
            if let url = sender.unsubscribeURL { openURL(url) }
            return
        }

        appFlow.updateEmailPreferences { $0.senderChoices[sender.id] = "unsubscribe" }
        unsubscribeStates[sender.id] = .inProgress

        do {
            let result = try await GmailService.shared.unsubscribe(sender: sender)
            switch result {
            case .oneClickPosted, .mailtoSent:
                unsubscribeStates[sender.id] = .done
            case .openURL(let url):
                openURL(url)
                unsubscribeStates[sender.id] = .done
            case .notAvailable:
                unsubscribeStates[sender.id] = .failed
            }

            if appFlow.emailPreferences.deleteAllAfterUnsubscribe.contains(sender.id) {
                _ = try? await GmailService.shared.trashAllFromSender(sender.email)
            }
        } catch {
            unsubscribeStates[sender.id] = .failed
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
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CleanupTheme.electricBlue)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CleanupTheme.electricBlue.opacity(0.65), lineWidth: 1.5)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    private func junkCategoryRow(_ category: GmailCategorySummary) -> some View {
        Button {
            if appFlow.isGmailConnected {
                openCategory(category)
            }
        } label: {
            GlassCard(cornerRadius: 20) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.title)
                            .font(CleanupFont.sectionTitle(18))
                            .foregroundStyle(.white)
                        Text("Total: \(formattedCount(category.messageCount))")
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textTertiary)
                    }
                    Spacer()
                    Text("\(formattedCount(category.messageCount))")
                        .font(CleanupFont.sectionTitle(18))
                        .foregroundStyle(CleanupTheme.electricBlue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CleanupTheme.textSecondary)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.3))
        }
    }

    private func secondaryActionButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CleanupFont.body(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.18)))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.35)) }
        }
        .buttonStyle(.plain)
    }

    private func accountAvatar(for account: GmailAccountSummary) -> some View {
        Group {
            if let avatarURL = account.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(CleanupTheme.electricBlue.opacity(0.18)).overlay { ProgressView().tint(.white) }
                }
            } else {
                Circle().fill(CleanupTheme.electricBlue.opacity(0.18)).overlay {
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
        if sender.name.lowercased() == "google" { return "G" }
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

    // MARK: - Navigation

    private func push(_ s: EmailCleanerScreen) {
        screenStack.append(s)
    }

    private func pop() {
        if screenStack.count > 1 {
            screenStack.removeLast()
        }
    }

    private func handleLeadingAction() {
        switch screen {
        case .home:
            appFlow.closeFeature()
        default:
            pop()
        }
    }

    private func handleTrailingAction() {
        switch screen {
        case .home:
            if appFlow.isGmailConnected {
                Task { await appFlow.refreshGmailMailbox() }
            }
        case .junkMail:
            appFlow.updateEmailPreferences { _ in }
        default:
            break
        }
    }

    // MARK: - Helpers

    private func formattedCount(_ count: Int) -> String {
        if count >= 500 { return "499+" }
        return "\(count)"
    }

    private func relativeDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yy"
        return f.string(from: date)
    }
}

// MARK: - WebView

private struct EmailBodyWebView: UIViewRepresentable {
    let html: String?
    let fallbackText: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.scrollView.backgroundColor = .white
        view.backgroundColor = .white
        view.isOpaque = true
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let html, !html.isEmpty {
            let wrapped = """
            <!doctype html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:12px;color:#111;}img{max-width:100%;height:auto;}a{color:#0b63d9;}</style>
            </head><body>\(html)</body></html>
            """
            uiView.loadHTMLString(wrapped, baseURL: nil)
        } else if let fallbackText, !fallbackText.isEmpty {
            let escaped = fallbackText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            uiView.loadHTMLString("<html><body style='font-family:-apple-system;padding:12px;'>\(escaped)</body></html>", baseURL: nil)
        } else {
            uiView.loadHTMLString("<html><body style='font-family:-apple-system;padding:12px;color:#888;'>No content available.</body></html>", baseURL: nil)
        }
    }
}

private extension DateFormatter {
    static let emailDetail: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

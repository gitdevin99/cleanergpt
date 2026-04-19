import SwiftUI

private enum EmailCleanerScreen {
    case home
    case unsubscribe
    case junkMail
}

private struct EmailSenderPreview: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    let emailCount: Int
    let iconText: String
    let iconColors: [Color]
}

private struct JunkCategoryPreview: Identifiable, Hashable {
    let id: String
    let title: String
    let senderCount: Int
}

struct EmailCleanerView: View {
    @EnvironmentObject private var appFlow: AppFlow

    @State private var screen: EmailCleanerScreen = .home

    private let senders: [EmailSenderPreview] = [
        .init(id: "google", name: "Google", email: "no-reply@accounts.google.com", emailCount: 9, iconText: "G", iconColors: [Color.white, Color(hex: "#D2E4FF")]),
        .init(id: "temu", name: "Temu", email: "temu@commerce.temumail.com", emailCount: 172, iconText: "T", iconColors: [Color(hex: "#5FA5FF"), Color(hex: "#3D5AFE")]),
        .init(id: "stripe", name: "Stripe", email: "notifications@stripe.com", emailCount: 43, iconText: "S", iconColors: [Color(hex: "#8B7BFF"), Color(hex: "#5B46FF")])
    ]

    private let junkCategories: [JunkCategoryPreview] = [
        .init(id: "Social", title: "Social Media", senderCount: 18),
        .init(id: "Promotions", title: "Promotions", senderCount: 32),
        .init(id: "Updates", title: "Updates", senderCount: 14),
        .init(id: "Newsletters", title: "Forum", senderCount: 11),
        .init(id: "Notifications", title: "Spam", senderCount: 7)
    ]

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
            "checkmark.circle.fill"
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

    var body: some View {
        FeatureScreen(
            title: currentTitle,
            leadingSymbol: "chevron.left",
            trailingSymbol: trailingSymbol,
            leadingAction: { handleLeadingAction() },
            trailingAction: { handleTrailingAction() }
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
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
        VStack(spacing: 18) {
            statusCard
            entryCard(
                title: "Unsubscribe",
                subtitle: "Review recurring senders and decide what to keep or remove.",
                value: unsubscribeCount == 0 ? "\(senders.count)" : "\(unsubscribeCount)",
                action: { screen = .unsubscribe }
            )
            entryCard(
                title: "Junk Mail",
                subtitle: "Pick categories you want the cleaner to sweep first.",
                value: "\(selectedJunkCount)",
                action: { screen = .junkMail }
            )
            rulesCard
            nextStepCard
        }
    }

    private var unsubscribeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisHint("Analyzing recurring senders...")

            ForEach(senders) { sender in
                unsubscribeSenderCard(sender)
            }
        }
    }

    private var junkMailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisHint("Analyzing categories...")

            ForEach(junkCategories) { category in
                junkCategoryRow(category)
            }

            GlassProminentCTA {
                screen = .home
            } label: {
                Text(selectedJunkCount == 0 ? "Select categories" : "Delete emails")
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
                Text("Connect Gmail to organize your inbox")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)

                Text("Start with unsubscribe decisions and junk-mail categories now. Once Gmail is connected, this screen can scan real senders, Gmail labels, and bulk actions.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)

                HStack(spacing: 10) {
                    statusPill(title: "Gmail", value: "Not Connected", tint: Color(hex: "#F6B14B"))
                    statusPill(title: "Ready", value: "Local Rules Saved", tint: CleanupTheme.electricBlue)
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
                            .font(CleanupFont.sectionTitle(22))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Text(value)
                        .font(CleanupFont.sectionTitle(20))
                        .foregroundStyle(CleanupTheme.electricBlue)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rulesCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cleaner Rules")
                    .font(CleanupFont.sectionTitle(20))
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

    private var nextStepCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next Step")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                Text("Add Google Sign-In plus Gmail API scopes, then replace these previews with live senders, real category counts, and unsubscribe or trash actions.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private func analysisHint(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(CleanupTheme.electricBlue)
            Text(text)
                .font(CleanupFont.body(14))
                .foregroundStyle(CleanupTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func unsubscribeSenderCard(_ sender: EmailSenderPreview) -> some View {
        let choice = appFlow.emailPreferences.senderChoices[sender.id] ?? "keep"

        return GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(LinearGradient(colors: sender.iconColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Text(sender.iconText)
                                .font(CleanupFont.sectionTitle(20))
                                .foregroundStyle(sender.iconText == "G" ? Color(hex: "#4285F4") : .white)
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
                .font(CleanupFont.body(16))
                .foregroundStyle(selected ? Color.black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
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

    private func junkCategoryRow(_ category: JunkCategoryPreview) -> some View {
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
                            Text("Total \(category.senderCount)")
                                .font(CleanupFont.caption(11))
                                .foregroundStyle(CleanupTheme.textTertiary)
                        }
                        Text(isSelected ? "Included in junk-mail cleanup." : "Tap to include in bulk cleanup.")
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }

                    Spacer()

                    Text("\(category.senderCount)")
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
            appFlow.updateEmailPreferences { _ in }
        case .unsubscribe:
            break
        case .junkMail:
            appFlow.updateEmailPreferences { _ in }
        }
    }
}

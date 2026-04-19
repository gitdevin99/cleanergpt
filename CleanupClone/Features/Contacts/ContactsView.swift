import SwiftUI

struct ContactsView: View {
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        NavigationStack {
            FeatureScreen(
                title: "Contacts",
                leadingSymbol: "chevron.left",
                trailingSymbol: "arrow.clockwise",
                leadingAction: { appFlow.closeFeature() },
                trailingAction: { Task { await appFlow.scanContacts() } }
            ) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if !appFlow.contactsAuthorization.isReadable {
                            permissionCard
                        } else if appFlow.isScanningContacts {
                            loadingCard
                        } else if appFlow.duplicateContactGroups.isEmpty {
                            emptyCard
                        } else {
                            summaryCard
                            groupsList
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var permissionCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Need access to start scanning")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)

                Text("Scan your address book, group duplicates, and keep the strongest card.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)

                PrimaryCTAButton(title: "Allow Contacts Access") {
                    Task {
                        _ = await appFlow.requestContactsAccessIfNeeded()
                    }
                }
            }
        }
    }

    private var loadingCard: some View {
        GlassCard(cornerRadius: 24) {
            HStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                Text("Scanning contacts...")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(.white)
            }
        }
    }

    private var emptyCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("No duplicate contacts found")
                    .font(CleanupFont.sectionTitle(22))
                    .foregroundStyle(.white)
                Text("Your contact list already looks clean.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(appFlow.duplicateContactGroups.count) duplicate group(s)")
                    .font(CleanupFont.sectionTitle(22))
                    .foregroundStyle(.white)
                Text("Review each group and keep the best version with one tap.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var groupsList: some View {
        VStack(spacing: 12) {
            ForEach(appFlow.duplicateContactGroups) { group in
                NavigationLink {
                    DuplicateContactGroupView(group: group)
                } label: {
                    GlassCard(cornerRadius: 24) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(CleanupFont.sectionTitle(20))
                                    .foregroundStyle(.white)
                                Text("\(group.duplicateCount) matching contacts")
                                    .font(CleanupFont.body(15))
                                    .foregroundStyle(CleanupTheme.textSecondary)
                                Text(group.secondaryLine)
                                    .font(CleanupFont.caption(12))
                                    .foregroundStyle(CleanupTheme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DuplicateContactGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    let group: DuplicateContactGroup

    @State private var statusMessage: String?
    @State private var isMerging = false

    var body: some View {
        FeatureScreen(
            title: group.title,
            leadingSymbol: "chevron.left",
            trailingSymbol: nil,
            leadingAction: { dismiss() }
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    GlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(group.duplicateCount) contacts will be reduced to 1")
                                .font(CleanupFont.sectionTitle(22))
                                .foregroundStyle(.white)
                            Text("Cleanup keeps the richest card and removes the extras.")
                                .font(CleanupFont.body(15))
                                .foregroundStyle(CleanupTheme.textSecondary)
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(CleanupFont.caption(12))
                                    .foregroundStyle(CleanupTheme.accentGreen)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(group.contacts) { contact in
                            GlassCard(cornerRadius: 22) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(contact.fullName)
                                        .font(CleanupFont.sectionTitle(18))
                                        .foregroundStyle(.white)
                                    Text(contact.phones.joined(separator: " • ").ifEmpty("No phone number"))
                                        .font(CleanupFont.caption(12))
                                        .foregroundStyle(CleanupTheme.textSecondary)
                                    Text(contact.emails.joined(separator: " • ").ifEmpty("No email"))
                                        .font(CleanupFont.caption(12))
                                        .foregroundStyle(CleanupTheme.textTertiary)
                                }
                            }
                        }
                    }

                    if isMerging {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        PrimaryCTAButton(title: "Keep Best Version") {
                            Task {
                                isMerging = true
                                let success = await appFlow.mergeDuplicateContacts(group: group)
                                isMerging = false
                                if success {
                                    statusMessage = "Duplicates removed."
                                } else {
                                    statusMessage = "No changes were made."
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

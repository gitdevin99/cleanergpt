import SwiftUI

// MARK: - Main Contacts View

struct ContactsView: View {
    @EnvironmentObject private var appFlow: AppFlow
    @State private var activeScreen: ContactScreen = .main

    enum ContactScreen: Hashable {
        case main
        case duplicates
        case incomplete
        case allContacts
        case backups
        case cleaning
        case congratulations
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch activeScreen {
                case .main:
                    ContactsMainScreen(activeScreen: $activeScreen)
                case .duplicates:
                    DuplicateMergeScreen(activeScreen: $activeScreen)
                case .incomplete:
                    IncompleteContactsScreen(activeScreen: $activeScreen)
                case .allContacts:
                    AllContactsScreen(activeScreen: $activeScreen)
                case .backups:
                    BackupsScreen(activeScreen: $activeScreen)
                case .cleaning:
                    CleaningProgressScreen(activeScreen: $activeScreen)
                case .congratulations:
                    CongratulationsScreen(activeScreen: $activeScreen)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: activeScreen)
            .navigationBarHidden(true)
            .onAppear {
                if let pending = appFlow.pendingContactScreen {
                    activeScreen = pending
                    appFlow.pendingContactScreen = nil
                }
            }
            .onChange(of: appFlow.pendingContactScreen) { _, newValue in
                if let newValue {
                    activeScreen = newValue
                    appFlow.pendingContactScreen = nil
                }
            }
        }
    }
}

// MARK: - Main Screen

private struct ContactsMainScreen: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Binding var activeScreen: ContactsView.ContactScreen

    var body: some View {
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
                        scanningCard
                    } else {
                        sectionCards
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .task {
            if appFlow.contactsAuthorization.isReadable, appFlow.allContacts.isEmpty {
                await appFlow.scanContacts()
            }
        }
        // When the user goes to iOS Settings to flip Contacts access
        // on and comes back, didBecomeActive fires. Refresh the cached
        // permission status and kick off the first scan automatically
        // so they don't have to tap anything else.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            appFlow.refreshPermissions()
            if appFlow.contactsAuthorization.isReadable, appFlow.allContacts.isEmpty {
                Task { await appFlow.scanContacts() }
            }
        }
    }

    private var permissionCard: some View {
        // Two-state CTA, same pattern as Photos / Calendar:
        //   • notDetermined  → "Continue" (fires the system prompt).
        //   • denied / restricted → "Open Settings" (deep-link into
        //     iOS Settings; iOS will not re-show the permission alert
        //     once it's been denied, so a "Continue" button at that
        //     point would silently no-op forever — exactly the bug
        //     the user hit).
        // Apple guideline 5.1.1(iv): pre-prompt button copy must be
        // neutral, not action-claim language like "Allow Contacts
        // Access". The body text above conveys what the access is for.
        let deniedPath = appFlow.contactsAuthorization.needsSettingsRedirect
        return GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(deniedPath ? "Turn on contacts access" : "Need access to start scanning")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)

                Text(deniedPath
                     ? "Contacts access was turned off. Open Settings to turn it back on so we can scan your address book, group duplicates, and keep the strongest card."
                     : "Scan your address book, group duplicates, and keep the strongest card.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)

                PrimaryCTAButton(title: deniedPath ? "Open Settings" : "Continue") {
                    if deniedPath {
                        appFlow.openSystemSettings()
                    } else {
                        Task {
                            _ = await appFlow.requestContactsAccessIfNeeded()
                        }
                    }
                }
            }
        }
    }

    private var scanningCard: some View {
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

    private var sectionCards: some View {
        VStack(spacing: 12) {
            contactSectionRow(
                icon: "person.2.fill",
                title: "Duplicate",
                count: appFlow.contactAnalysisSummary.duplicateGroupCount,
                subtitle: "\(appFlow.contactAnalysisSummary.duplicateContactCount) contacts can be merged",
                color: CleanupTheme.electricBlue,
                enabled: appFlow.contactAnalysisSummary.duplicateGroupCount > 0
            ) {
                activeScreen = .duplicates
            }

            contactSectionRow(
                icon: "person.fill.questionmark",
                title: "Incomplete",
                count: appFlow.incompleteContacts.count,
                subtitle: "Missing name, phone, or email",
                color: Color(hex: "#FFB445"),
                enabled: !appFlow.incompleteContacts.isEmpty
            ) {
                activeScreen = .incomplete
            }

            contactSectionRow(
                icon: "person.crop.circle",
                title: "All Contacts",
                count: appFlow.contactAnalysisSummary.totalCount,
                subtitle: "Browse & manage your contacts",
                color: CleanupTheme.accentGreen,
                enabled: appFlow.contactAnalysisSummary.totalCount > 0
            ) {
                activeScreen = .allContacts
            }

            contactSectionRow(
                icon: "externaldrive.fill.badge.person.crop",
                title: "Backups",
                count: appFlow.contactBackupService.backups.count,
                subtitle: backupsSubtitle,
                color: CleanupTheme.accentCyan,
                enabled: true
            ) {
                activeScreen = .backups
            }
        }
    }

    /// Subtitle shown under the Backups row — honest about whether we're
    /// storing in iCloud or locally, and shows last backup date if we have one.
    private var backupsSubtitle: String {
        if let last = appFlow.contactBackupService.lastBackupDate {
            let df = DateFormatter()
            df.dateFormat = "MMM d, yyyy"
            let prefix = appFlow.contactBackupService.isUsingICloud ? "Last iCloud backup" : "Last backup"
            return "\(prefix): \(df.string(from: last))"
        }
        return appFlow.contactBackupService.isUsingICloud
            ? "Save a copy to iCloud"
            : "Save a local copy of your contacts"
    }

    private func contactSectionRow(
        icon: String,
        title: String,
        count: Int,
        subtitle: String,
        color: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassCard(cornerRadius: 22) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(color.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(title)
                                .font(CleanupFont.sectionTitle(18))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(count)")
                                .font(CleanupFont.sectionTitle(20))
                                .foregroundStyle(color)
                        }
                        Text(subtitle)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }
}

// MARK: - Duplicate Merge Screen

private struct DuplicateMergeScreen: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Binding var activeScreen: ContactsView.ContactScreen

    /// Per-contact selection. A group is merged if it has 2+ selected contacts
    /// (you can't merge a group down to one without duplicates to fold in).
    /// Default on first open: every contact selected — matches the competitor
    /// screenshot where everything is checked out of the gate.
    @State private var selectedContactIDs: Set<String> = []
    @State private var showMergePreview = false

    private var groups: [DuplicateContactGroup] {
        appFlow.duplicateContactGroups
    }

    /// Groups where the user has kept enough contacts selected to actually
    /// perform a merge (need at least 2 to fold together).
    private var mergeableGroups: [DuplicateContactGroup] {
        groups.compactMap { group in
            let kept = group.contacts.filter { selectedContactIDs.contains($0.id) }
            return kept.count >= 2 ? group : nil
        }
    }

    private var totalContactsToMerge: Int {
        mergeableGroups.reduce(0) { $0 + max(0, $1.duplicateCount - 1) }
    }

    private var totalSelected: Int {
        // Across all groups, how many contact rows are currently checked.
        let allIDs = Set(groups.flatMap { $0.contacts.map(\.id) })
        return selectedContactIDs.intersection(allIDs).count
    }

    private var allContactIDs: Set<String> {
        Set(groups.flatMap { $0.contacts.map(\.id) })
    }

    var body: some View {
        FeatureScreen(
            title: "Duplicates",
            leadingSymbol: "chevron.left",
            leadingAction: { activeScreen = .main },
            trailingContent: {
                Button {
                    toggleSelectAllGlobal()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedContactIDs == allContactIDs
                              ? "checkmark.circle.fill"
                              : "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(selectedContactIDs == allContactIDs ? "Deselect All" : "Select All")
                            .font(CleanupFont.body(14))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(CleanupTheme.card.opacity(0.8))
                    )
                }
            }
        ) {
            VStack(spacing: 0) {
                // Count line under the title, like the competitor's "89 Contacts"
                HStack {
                    Text("\(appFlow.contactAnalysisSummary.duplicateContactCount) Contacts")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Spacer()
                }
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(groups) { group in
                            DuplicateGroupCard(
                                group: group,
                                selectedContactIDs: $selectedContactIDs
                            )
                        }
                    }
                    .padding(.bottom, totalContactsToMerge > 0 ? 100 : 24)
                }

                // Bottom CTA — single action, matches competitor's "See Merge Preview"
                if totalContactsToMerge > 0 {
                    PrimaryCTAButton(title: "See Merge Preview") {
                        showMergePreview = true
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            // Default: every contact in every group is selected — so the user
            // can tap straight to Merge Preview without fiddling.
            if selectedContactIDs.isEmpty {
                selectedContactIDs = allContactIDs
            }
        }
        .sheet(isPresented: $showMergePreview) {
            MergePreviewSheet(
                groups: mergeableGroups,
                totalContactsToMerge: totalContactsToMerge,
                onConfirm: {
                    showMergePreview = false
                    startMerge()
                }
            )
        }
    }

    private func toggleSelectAllGlobal() {
        if selectedContactIDs == allContactIDs {
            selectedContactIDs.removeAll()
        } else {
            selectedContactIDs = allContactIDs
        }
    }

    private func startMerge() {
        guard appFlow.gateSingleAction(.contactMerge) else { return }
        let toMerge = mergeableGroups
        activeScreen = .cleaning
        Task {
            _ = await appFlow.bulkMergeDuplicateContacts(groups: toMerge)
            try? await Task.sleep(nanoseconds: 500_000_000)
            activeScreen = .congratulations
        }
    }
}

/// Flat card — shows the group title + every contact inline with a red
/// checkbox each, and a per-group "Select All / Deselect All" control. No
/// accordion, no hidden rows. Directly modeled on the competitor screenshot.
private struct DuplicateGroupCard: View {
    let group: DuplicateContactGroup
    @Binding var selectedContactIDs: Set<String>

    private var allGroupSelected: Bool {
        group.contacts.allSatisfy { selectedContactIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with per-group Select All / Deselect All
            HStack {
                Text("\(group.duplicateCount) Duplicate Contacts")
                    .font(CleanupFont.sectionTitle(16))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    toggleGroupSelectAll()
                } label: {
                    Text(allGroupSelected ? "Deselect All" : "Select All")
                        .font(CleanupFont.body(13))
                        .foregroundStyle(allGroupSelected
                                         ? CleanupTheme.textSecondary
                                         : CleanupTheme.electricBlue)
                }
                .buttonStyle(.plain)
            }

            // Every duplicate contact laid out directly — no tap to expand.
            VStack(spacing: 10) {
                ForEach(group.contacts) { contact in
                    duplicateRow(contact)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CleanupTheme.card.opacity(0.55))
        )
    }

    private func duplicateRow(_ contact: ContactRecord) -> some View {
        let isSelected = selectedContactIDs.contains(contact.id)
        let primaryDetail = contact.phones.first ?? contact.emails.first ?? "No phone or email"
        return Button {
            toggleContact(contact.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.fullName.isEmpty ? "Unnamed Contact" : contact.fullName)
                        .font(CleanupFont.body(15).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(primaryDetail)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                // Red circular checkbox, matching the competitor's visual.
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.white.opacity(0.35),
                            lineWidth: 1.5
                        )
                        .background(
                            Circle().fill(isSelected ? CleanupTheme.accentRed : Color.clear)
                        )
                        .frame(width: 26, height: 26)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CleanupTheme.background.opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleContact(_ id: String) {
        if selectedContactIDs.contains(id) {
            selectedContactIDs.remove(id)
        } else {
            selectedContactIDs.insert(id)
        }
    }

    private func toggleGroupSelectAll() {
        if allGroupSelected {
            for contact in group.contacts { selectedContactIDs.remove(contact.id) }
        } else {
            for contact in group.contacts { selectedContactIDs.insert(contact.id) }
        }
    }
}

/// Preview sheet that shows what the merged contacts will look like before
/// the user commits. The old accordion lived inline and buried this; now
/// it's one tap from a clearly-labeled CTA.
private struct MergePreviewSheet: View {
    let groups: [DuplicateContactGroup]
    let totalContactsToMerge: Int
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                CleanupTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(groups) { group in
                            mergedGroupCard(group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }

                VStack {
                    Spacer()
                    PrimaryCTAButton(
                        title: "Merge \(groups.count) group\(groups.count == 1 ? "" : "s") (\(totalContactsToMerge) contact\(totalContactsToMerge == 1 ? "" : "s"))"
                    ) {
                        onConfirm()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Merge Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CleanupTheme.electricBlue)
                }
            }
        }
    }

    private func mergedGroupCard(_ group: DuplicateContactGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CleanupTheme.accentGreen)
                Text("Merged contact")
                    .font(CleanupFont.body(13))
                    .foregroundStyle(CleanupTheme.accentGreen)
            }
            HStack(spacing: 12) {
                ContactAvatar(
                    initials: group.mergedPreview.initials,
                    size: 38,
                    color: CleanupTheme.accentGreen
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.mergedPreview.fullName)
                        .font(CleanupFont.body(15).weight(.semibold))
                        .foregroundStyle(.white)
                    if !group.mergedPreview.phones.isEmpty {
                        Text(group.mergedPreview.phones.joined(separator: " • "))
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .lineLimit(2)
                    }
                    if !group.mergedPreview.emails.isEmpty {
                        Text(group.mergedPreview.emails.joined(separator: " • "))
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CleanupTheme.accentGreen.opacity(0.08))
                    .strokeBorder(CleanupTheme.accentGreen.opacity(0.22), lineWidth: 1)
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CleanupTheme.card.opacity(0.55))
        )
    }
}

// MARK: - All Contacts Screen

private struct AllContactsScreen: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Binding var activeScreen: ContactsView.ContactScreen
    @State private var searchText = ""
    @State private var selectedIDs: Set<String> = []
    @State private var isSelecting = false
    @State private var isDeleting = false

    private var filteredContacts: [ContactRecord] {
        if searchText.isEmpty {
            return appFlow.allContacts
        }
        let query = searchText.lowercased()
        return appFlow.allContacts.filter {
            $0.fullName.lowercased().contains(query) ||
            $0.phones.contains(where: { $0.contains(query) }) ||
            $0.emails.contains(where: { $0.lowercased().contains(query) })
        }
    }

    private var sectionedContacts: [(letter: String, contacts: [ContactRecord])] {
        let grouped = Dictionary(grouping: filteredContacts) { $0.sectionLetter }
        let letters = grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }
        return letters.map { (letter: $0, contacts: grouped[$0] ?? []) }
    }

    /// Only A-Z and # for the sidebar — non-Latin sections get lumped into #
    private var sidebarLetters: [String] {
        let latinLetters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))
        var present: [String] = []
        var hasOther = false
        for section in sectionedContacts {
            if latinLetters.contains(section.letter) {
                present.append(section.letter)
            } else {
                hasOther = true
            }
        }
        if hasOther { present.append("#") }
        return present
    }

    var body: some View {
        FeatureScreen(
            title: "All Contacts",
            leadingSymbol: "chevron.left",
            leadingAction: { activeScreen = .main }
        ) {
            VStack(spacing: 12) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CleanupTheme.textTertiary)
                    TextField("Search contacts", text: $searchText)
                        .font(CleanupFont.body(15))
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CleanupTheme.card.opacity(0.7))
                )

                // Selection toolbar
                HStack {
                    Text("\(filteredContacts.count) contacts")
                        .font(CleanupFont.body(13))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    } label: {
                        Text(isSelecting ? "Cancel" : "Select")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.electricBlue)
                    }
                    if isSelecting {
                        Button {
                            if selectedIDs.count == filteredContacts.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(filteredContacts.map(\.id))
                            }
                        } label: {
                            Text(selectedIDs.count == filteredContacts.count ? "Deselect all" : "Select all")
                                .font(CleanupFont.body(14))
                                .foregroundStyle(CleanupTheme.electricBlue)
                        }
                        .padding(.leading, 8)
                    }
                }

                // Contact list with alphabetical index
                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(sectionedContacts, id: \.letter) { section in
                                    // Invisible anchor for sidebar scroll-to
                                    Color.clear
                                        .frame(height: 0)
                                        .id(section.letter)

                                    ForEach(section.contacts) { contact in
                                        ContactListRow(
                                            contact: contact,
                                            isSelecting: isSelecting,
                                            isSelected: selectedIDs.contains(contact.id),
                                            onToggle: {
                                                if selectedIDs.contains(contact.id) {
                                                    selectedIDs.remove(contact.id)
                                                } else {
                                                    selectedIDs.insert(contact.id)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, isSelecting && !selectedIDs.isEmpty ? 80 : 24)
                        }
                        .onChange(of: searchText) { _, _ in
                            selectedIDs.removeAll()
                        }

                        // Alphabetical sidebar — pinned to trailing edge
                        if searchText.isEmpty, sidebarLetters.count > 1 {
                            AlphabetSidebar(letters: sidebarLetters) { letter in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    proxy.scrollTo(letter, anchor: .top)
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                            .padding(.trailing, -8)
                        }
                    }
                }

                // Delete button
                if isSelecting, !selectedIDs.isEmpty {
                    Button {
                        isDeleting = true
                        Task {
                            _ = await appFlow.deleteContacts(ids: selectedIDs)
                            selectedIDs.removeAll()
                            isDeleting = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text("Delete \(selectedIDs.count) contacts")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(CleanupTheme.accentRed.opacity(isDeleting ? 0.5 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(isDeleting)
                    .buttonStyle(.plain)
                }
            }
        }
    }

}

private struct ContactListRow: View {
    let contact: ContactRecord
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            if isSelecting { onToggle() }
        }) {
            HStack(spacing: 12) {
                if isSelecting {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? CleanupTheme.electricBlue : Color.white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle().fill(isSelected ? CleanupTheme.electricBlue : Color.clear)
                            )
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                ContactAvatar(initials: contact.initials, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.fullName)
                        .font(CleanupFont.body(15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let detail = contact.phones.first ?? contact.emails.first {
                        Text(detail)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider()
            .background(CleanupTheme.divider)
    }
}

private struct AlphabetSidebar: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var dragLetter: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(CleanupTheme.electricBlue)
                    .frame(width: 14, height: 13)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 3)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let totalHeight = CGFloat(letters.count) * 13 + 6
                    let y = max(0, min(value.location.y - 3, totalHeight - 1))
                    let index = min(Int(y / 13), letters.count - 1)
                    let letter = letters[max(0, index)]
                    if letter != dragLetter {
                        dragLetter = letter
                        onSelect(letter)
                    }
                }
                .onEnded { _ in
                    dragLetter = nil
                }
        )
    }
}

// MARK: - Incomplete Contacts Screen

private struct IncompleteContactsScreen: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Binding var activeScreen: ContactsView.ContactScreen
    @State private var selectedIDs: Set<String> = []
    @State private var isSelecting = false
    @State private var isDeleting = false

    var body: some View {
        FeatureScreen(
            title: "Incomplete",
            leadingSymbol: "chevron.left",
            leadingAction: { activeScreen = .main }
        ) {
            VStack(spacing: 12) {
                HStack {
                    Text("\(appFlow.incompleteContacts.count) contacts with missing info")
                        .font(CleanupFont.body(13))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    } label: {
                        Text(isSelecting ? "Cancel" : "Select")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.electricBlue)
                    }
                    if isSelecting {
                        Button {
                            if selectedIDs.count == appFlow.incompleteContacts.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(appFlow.incompleteContacts.map(\.id))
                            }
                        } label: {
                            Text(selectedIDs.count == appFlow.incompleteContacts.count ? "Deselect all" : "Select all")
                                .font(CleanupFont.body(14))
                                .foregroundStyle(CleanupTheme.electricBlue)
                        }
                        .padding(.leading, 8)
                    }
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(appFlow.incompleteContacts) { contact in
                            IncompleteContactRow(
                                contact: contact,
                                isSelecting: isSelecting,
                                isSelected: selectedIDs.contains(contact.id),
                                onToggle: {
                                    if selectedIDs.contains(contact.id) {
                                        selectedIDs.remove(contact.id)
                                    } else {
                                        selectedIDs.insert(contact.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.bottom, isSelecting && !selectedIDs.isEmpty ? 80 : 24)
                }

                if isSelecting, !selectedIDs.isEmpty {
                    Button {
                        isDeleting = true
                        Task {
                            _ = await appFlow.deleteContacts(ids: selectedIDs)
                            selectedIDs.removeAll()
                            isDeleting = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text("Delete \(selectedIDs.count) contacts")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(CleanupTheme.accentRed.opacity(isDeleting ? 0.5 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(isDeleting)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct IncompleteContactRow: View {
    let contact: ContactRecord
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    private var missingFields: String {
        var missing: [String] = []
        let trimmed = contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Unnamed Contact" { missing.append("Name") }
        if contact.phones.isEmpty { missing.append("Phone") }
        if contact.emails.isEmpty { missing.append("Email") }
        return missing.isEmpty ? "Incomplete" : "Missing: \(missing.joined(separator: ", "))"
    }

    var body: some View {
        Button(action: {
            if isSelecting { onToggle() }
        }) {
            HStack(spacing: 12) {
                if isSelecting {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? CleanupTheme.electricBlue : Color.white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle().fill(isSelected ? CleanupTheme.electricBlue : Color.clear)
                            )
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                ContactAvatar(initials: contact.initials, size: 38, color: Color(hex: "#FFB445"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.fullName)
                        .font(CleanupFont.body(15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(missingFields)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(Color(hex: "#FFB445"))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider()
            .background(CleanupTheme.divider)
    }
}

// MARK: - Cleaning Progress Screen

private struct CleaningProgressScreen: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Binding var activeScreen: ContactsView.ContactScreen
    @State private var rotationAngle: Double = 0

    var body: some View {
        ZStack {
            CleanupTheme.background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Animated spinner
                ZStack {
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [CleanupTheme.electricBlue, CleanupTheme.electricBlue.opacity(0.1), CleanupTheme.electricBlue],
                                center: .center
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(rotationAngle))

                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(CleanupTheme.electricBlue)
                }

                VStack(spacing: 10) {
                    Text("Cleaning...")
                        .font(CleanupFont.sectionTitle(26))
                        .foregroundStyle(.white)

                    Text("We're sweeping away the clutter for you")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    if appFlow.contactCleaningProgress.total > 0 {
                        Text("\(appFlow.contactCleaningProgress.done) of \(appFlow.contactCleaningProgress.total) groups")
                            .font(CleanupFont.caption(13))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - Congratulations Screen

private struct CongratulationsScreen: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Binding var activeScreen: ContactsView.ContactScreen

    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var confettiVisible = false
    @State private var glowScale: CGFloat = 0.5
    @State private var glowOpacity: Double = 0
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        ZStack {
            CleanupTheme.background
                .ignoresSafeArea()

            // Confetti particles
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
            }

            VStack(spacing: 0) {
                Spacer()

                // Glow ring
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [CleanupTheme.accentGreen.opacity(0.3), CleanupTheme.accentGreen.opacity(0)],
                                center: .center,
                                startRadius: 20,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(glowScale)
                        .opacity(glowOpacity)

                    // Checkmark circle
                    ZStack {
                        Circle()
                            .fill(CleanupTheme.accentGreen)
                            .frame(width: 90, height: 90)
                            .shadow(color: CleanupTheme.accentGreen.opacity(0.5), radius: 20, y: 4)

                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
                }

                VStack(spacing: 12) {
                    Text("Congratulations!")
                        .font(CleanupFont.hero(32))
                        .foregroundStyle(.white)

                    Text("You've cleaned your contacts")
                        .font(CleanupFont.body(16))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
                .opacity(textOpacity)
                .padding(.top, 32)

                Spacer()

                PrimaryCTAButton(title: "Done") {
                    appFlow.resetContactCleaningState()
                    activeScreen = .main
                }
                .opacity(textOpacity)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Glow expands
        withAnimation(.easeOut(duration: 0.6)) {
            glowScale = 1.2
            glowOpacity = 1
        }

        // Checkmark bounces in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0).delay(0.15)) {
            checkmarkScale = 1
            checkmarkOpacity = 1
        }

        // Text fades in
        withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
            textOpacity = 1
        }

        // Confetti
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            spawnConfetti()
        }

        // Glow pulses
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowScale = 1.4
                glowOpacity = 0.6
            }
        }
    }

    private func spawnConfetti() {
        let colors: [Color] = [
            CleanupTheme.electricBlue,
            CleanupTheme.accentGreen,
            Color(hex: "#FFB445"),
            CleanupTheme.accentCyan,
            Color(hex: "#E33C7B"),
            Color.white
        ]

        particles = (0..<40).map { i in
            ConfettiParticle(
                id: i,
                x: CGFloat.random(in: -180...180),
                y: CGFloat.random(in: -400 ... -100),
                size: CGFloat.random(in: 4...10),
                color: colors.randomElement() ?? .white,
                opacity: 1
            )
        }

        // Animate falling
        withAnimation(.easeIn(duration: 2.0)) {
            particles = particles.map { p in
                ConfettiParticle(
                    id: p.id,
                    x: p.x + CGFloat.random(in: -40...40),
                    y: p.y + CGFloat.random(in: 500...800),
                    size: p.size,
                    color: p.color,
                    opacity: 0
                )
            }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var opacity: Double
}

// MARK: - Shared Components

private struct ContactAvatar: View {
    let initials: String
    var size: CGFloat = 40
    var color: Color = CleanupTheme.electricBlue

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: size, height: size)
            Text(initials)
                .font(.system(size: size * 0.35, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

// MARK: - Backups Screen

private struct BackupsScreen: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Binding var activeScreen: ContactsView.ContactScreen

    @State private var selectedBackupIDs: Set<String> = []
    @State private var showRestoreConfirm = false
    @State private var showDeleteConfirm = false
    @State private var statusMessage: String?
    @State private var backupTarget: ContactBackup?

    private var service: ContactBackupService { appFlow.contactBackupService }
    private var backups: [ContactBackup] { service.backups }
    private var isAllSelected: Bool {
        !backups.isEmpty && selectedBackupIDs.count == backups.count
    }
    private var sectionTitle: String {
        service.isUsingICloud ? "iCloud backups" : "Backups"
    }

    var body: some View {
        FeatureScreen(
            title: "Backups",
            leadingSymbol: "chevron.left",
            leadingAction: { activeScreen = .main },
            trailingContent: {
                if !backups.isEmpty {
                    Button {
                        toggleSelectAll()
                    } label: {
                        Text(isAllSelected ? "Deselect all" : "Select all")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.electricBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
            }
        ) {
            VStack(spacing: 0) {
                autoBackupCard
                    .padding(.bottom, 18)

                if backups.isEmpty {
                    emptyState
                } else {
                    backupsList
                }

                Spacer(minLength: 12)

                bottomActions
            }
        }
        .onAppear {
            service.refreshBackups()
        }
        .alert("Restore selected backup?", isPresented: $showRestoreConfirm, presenting: backupTarget) { backup in
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                Task { await restore(backup: backup) }
            }
        } message: { backup in
            Text("This will add \(backup.contactCount) contacts from \(Self.longDateFormatter.string(from: backup.createdAt)) to your address book. Existing contacts are not changed. You may see duplicates afterward — use the Duplicate merger to clean them up.")
        }
        .alert("Delete \(selectedBackupIDs.count) backup\(selectedBackupIDs.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("This only removes the backup file. Your contacts are not affected.")
        }
    }

    // MARK: - Subviews

    private var autoBackupCard: some View {
        GlassCard(cornerRadius: 18) {
            HStack(spacing: 14) {
                Text("Auto-backup")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(.white)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.autoBackupEnabled },
                    set: { service.autoBackupEnabled = $0 }
                ))
                .labelsHidden()
                .tint(CleanupTheme.electricBlue)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(CleanupTheme.textSecondary)
                .padding(.top, 40)
            Text("No backups yet")
                .font(CleanupFont.sectionTitle(18))
                .foregroundStyle(.white)
            Text(service.isUsingICloud
                 ? "Tap Backup now to save a copy of your \(appFlow.contactAnalysisSummary.totalCount) contacts to iCloud."
                 : "Tap Backup now to save a copy of your \(appFlow.contactAnalysisSummary.totalCount) contacts locally.")
                .font(CleanupFont.body(13))
                .foregroundStyle(CleanupTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var backupsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: service.isUsingICloud ? "icloud.fill" : "internaldrive.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.white.opacity(0.06))
                    )
                Text(sectionTitle)
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(backups) { backup in
                        backupRow(backup)
                        if backup.id != backups.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.05))
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CleanupTheme.card.opacity(0.6))
                )
            }
            .frame(maxHeight: 360)
        }
    }

    private func backupRow(_ backup: ContactBackup) -> some View {
        let isSelected = selectedBackupIDs.contains(backup.id)
        return Button {
            backupTarget = backup
            showRestoreConfirm = true
        } label: {
            HStack(spacing: 12) {
                Button {
                    toggleSelection(for: backup)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(isSelected ? CleanupTheme.electricBlue : Color.white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? CleanupTheme.electricBlue : Color.clear)
                            )
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFormatter.string(from: backup.createdAt))
                        .font(CleanupFont.body(15))
                        .foregroundStyle(.white)
                    Text("at " + Self.timeFormatter.string(from: backup.createdAt))
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }

                Spacer()

                Text("\(backup.contactCount)")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.electricBlue)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CleanupTheme.electricBlue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.white.opacity(0.04) : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            if let statusMessage {
                Text(statusMessage)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            if !selectedBackupIDs.isEmpty {
                // Restore (secondary) + Delete (primary) layout, matching the
                // competitor's two-button footer when selection is active.
                Button {
                    if let backup = backups.first(where: { selectedBackupIDs.contains($0.id) }) {
                        backupTarget = backup
                        showRestoreConfirm = true
                    }
                } label: {
                    Text("Restore backup")
                        .font(CleanupFont.body(16))
                        .foregroundStyle(CleanupTheme.electricBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(CleanupTheme.electricBlue.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedBackupIDs.count != 1)
                .opacity(selectedBackupIDs.count == 1 ? 1 : 0.45)

                PrimaryCTAButton(title: "Delete \(selectedBackupIDs.count) backup\(selectedBackupIDs.count == 1 ? "" : "s")") {
                    showDeleteConfirm = true
                }
            } else {
                PrimaryCTAButton(title: service.isWorking ? "Backing up…" : "Backup now") {
                    Task { await backupNow() }
                }
                .disabled(service.isWorking)
                .opacity(service.isWorking ? 0.6 : 1)
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Actions

    private func toggleSelection(for backup: ContactBackup) {
        if selectedBackupIDs.contains(backup.id) {
            selectedBackupIDs.remove(backup.id)
        } else {
            selectedBackupIDs.insert(backup.id)
        }
    }

    private func toggleSelectAll() {
        if isAllSelected {
            selectedBackupIDs.removeAll()
        } else {
            selectedBackupIDs = Set(backups.map(\.id))
        }
    }

    private func backupNow() async {
        statusMessage = nil
        if let result = await service.createBackup() {
            statusMessage = "Saved \(result.contactCount) contacts."
            // Refresh count on dashboard card too.
            await appFlow.scanContacts()
        } else {
            statusMessage = "Couldn't create backup. Please try again."
        }
    }

    private func restore(backup: ContactBackup) async {
        statusMessage = nil
        let added = await service.restoreBackup(backup)
        if added > 0 {
            statusMessage = "Restored \(added) contacts."
            await appFlow.scanContacts()
        } else {
            statusMessage = "Restore failed or no contacts to restore."
        }
    }

    private func deleteSelected() {
        let toDelete = backups.filter { selectedBackupIDs.contains($0.id) }
        service.deleteBackups(toDelete)
        selectedBackupIDs.removeAll()
        Task { await appFlow.scanContacts() }
    }

    // Formatters
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

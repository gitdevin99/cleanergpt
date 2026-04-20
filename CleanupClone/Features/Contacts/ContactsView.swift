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
                case .cleaning:
                    CleaningProgressScreen(activeScreen: $activeScreen)
                case .congratulations:
                    CongratulationsScreen(activeScreen: $activeScreen)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: activeScreen)
            .navigationBarHidden(true)
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
        }
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
    @State private var selectedGroupIDs: Set<String> = []
    @State private var expandedGroupID: String?

    private var groups: [DuplicateContactGroup] {
        appFlow.duplicateContactGroups
    }

    var body: some View {
        FeatureScreen(
            title: "Duplicates",
            leadingSymbol: "chevron.left",
            leadingAction: { activeScreen = .main }
        ) {
            VStack(spacing: 0) {
                // Top bar with select all
                HStack {
                    Text("\(groups.count) duplicate groups")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Spacer()
                    Button {
                        if selectedGroupIDs.count == groups.count {
                            selectedGroupIDs.removeAll()
                        } else {
                            selectedGroupIDs = Set(groups.map(\.id))
                        }
                    } label: {
                        Text(selectedGroupIDs.count == groups.count ? "Deselect all" : "Select all")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.electricBlue)
                    }
                }
                .padding(.bottom, 12)

                // Groups list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(groups) { group in
                            DuplicateGroupCard(
                                group: group,
                                isSelected: selectedGroupIDs.contains(group.id),
                                isExpanded: expandedGroupID == group.id,
                                onToggleSelect: {
                                    if selectedGroupIDs.contains(group.id) {
                                        selectedGroupIDs.remove(group.id)
                                    } else {
                                        selectedGroupIDs.insert(group.id)
                                    }
                                },
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        expandedGroupID = expandedGroupID == group.id ? nil : group.id
                                    }
                                }
                            )
                        }
                    }
                    .padding(.bottom, 100)
                }

                // Bottom merge button
                if !selectedGroupIDs.isEmpty {
                    let selectedGroups = groups.filter { selectedGroupIDs.contains($0.id) }
                    let totalMerge = selectedGroups.reduce(0) { $0 + max(0, $1.duplicateCount - 1) }

                    PrimaryCTAButton(title: "Merge \(selectedGroupIDs.count) groups (\(totalMerge) contacts)") {
                        let toMerge = selectedGroups
                        activeScreen = .cleaning
                        Task {
                            _ = await appFlow.bulkMergeDuplicateContacts(groups: toMerge)
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            activeScreen = .congratulations
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            selectedGroupIDs = Set(groups.map(\.id))
        }
    }
}

private struct DuplicateGroupCard: View {
    let group: DuplicateContactGroup
    let isSelected: Bool
    let isExpanded: Bool
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 12) {
                    // Checkbox
                    Button(action: onToggleSelect) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isSelected ? CleanupTheme.electricBlue : Color.white.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? CleanupTheme.electricBlue : Color.clear)
                                )
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Contact avatar
                    ContactAvatar(initials: group.mergedPreview.initials, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(CleanupFont.sectionTitle(16))
                            .foregroundStyle(.white)
                        Text("\(group.duplicateCount) contacts • \(group.secondaryLine)")
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                // Expanded detail
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        // Merged preview
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CleanupTheme.accentGreen)
                            Text("Merged contact")
                                .font(CleanupFont.body(13))
                                .foregroundStyle(CleanupTheme.accentGreen)
                        }
                        .padding(.top, 12)

                        mergedPreviewCard

                        Text("Contacts to merge")
                            .font(CleanupFont.body(13))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .padding(.top, 4)

                        ForEach(group.contacts) { contact in
                            contactDetailRow(contact)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var mergedPreviewCard: some View {
        HStack(spacing: 12) {
            ContactAvatar(initials: group.mergedPreview.initials, size: 36, color: CleanupTheme.accentGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.mergedPreview.fullName)
                    .font(CleanupFont.body(14))
                    .foregroundStyle(.white)
                if !group.mergedPreview.phones.isEmpty {
                    Text(group.mergedPreview.phones.joined(separator: " • "))
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .lineLimit(1)
                }
                if !group.mergedPreview.emails.isEmpty {
                    Text(group.mergedPreview.emails.joined(separator: " • "))
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CleanupTheme.accentGreen.opacity(0.08))
                .strokeBorder(CleanupTheme.accentGreen.opacity(0.2), lineWidth: 1)
        )
    }

    private func contactDetailRow(_ contact: ContactRecord) -> some View {
        HStack(spacing: 10) {
            ContactAvatar(initials: contact.initials, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.fullName)
                    .font(CleanupFont.body(13))
                    .foregroundStyle(.white)
                Text(contact.phones.first ?? contact.emails.first ?? "No details")
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(CleanupTheme.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
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

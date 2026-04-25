import SwiftUI

/// Apple Calendar (EventKit) cleanup surface.
///
/// All heavy lifting lives on `AppFlow`:
/// - `requestEventsAccessIfNeeded()` asks for full-access permission
///   (iOS 17+ collapsed read+write into one grant)
/// - `scanEvents()` populates `pastEvents` with every event whose end
///   date is in the past, across all calendars the user has granted
/// - `deleteEvents(with:)` removes the selected events from EventKit
///   (respecting `canDelete` — subscribed holiday calendars are
///   read-only and silently skipped)
///
/// This view is purely presentation: search, select, confirm.
///
/// Visual language mirrors `ContactsView` — same `FeatureScreen` shell,
/// same circular-checkbox row, same floating "Clean N events" CTA — so
/// users who've used one cleanup tab already know this one.
struct EventsCleanupView: View {
    @EnvironmentObject var appFlow: AppFlow
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedIDs: Set<String> = []
    @State private var isSelecting = false
    @State private var isDeleting = false
    @State private var showResult = false
    @State private var resultMessage = ""

    // MARK: - Derived data

    private var filteredEvents: [EventRecord] {
        let all = appFlow.pastEvents
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter {
            $0.title.lowercased().contains(query) ||
            $0.calendarName.lowercased().contains(query)
        }
    }

    /// Groups events by year of their start date, newest year first. The
    /// year header matches the competitor's "2026" blue bar look. Events
    /// without a start date fall into "Older" so the user can still find
    /// and delete them.
    private var sectionedEvents: [(key: String, events: [EventRecord])] {
        let grouped = Dictionary(grouping: filteredEvents) { (record: EventRecord) -> String in
            guard let date = record.startDate else { return "Older" }
            let year = Calendar.current.component(.year, from: date)
            return String(year)
        }
        return grouped.keys.sorted { lhs, rhs in
            // "Older" always sinks to the bottom.
            if lhs == "Older" { return false }
            if rhs == "Older" { return true }
            return lhs > rhs
        }.map { (key: $0, events: grouped[$0] ?? []) }
    }

    private var deletableSelectedCount: Int {
        let deletableIDs = Set(filteredEvents.filter(\.canDelete).map(\.id))
        return selectedIDs.intersection(deletableIDs).count
    }

    // MARK: - Body

    var body: some View {
        FeatureScreen(
            title: "Events",
            leadingSymbol: "chevron.left",
            leadingAction: { dismiss() }
        ) {
            Group {
                if !appFlow.eventsAuthorization.isReadable {
                    permissionGate
                } else if appFlow.isScanningEvents && appFlow.pastEvents.isEmpty {
                    loadingState
                } else if appFlow.pastEvents.isEmpty {
                    emptyState
                } else {
                    contentList
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if appFlow.eventsAuthorization.isReadable, appFlow.pastEvents.isEmpty {
                await appFlow.scanEvents()
            }
        }
        // When the user goes to iOS Settings to flip Calendar access on
        // and comes back, didBecomeActive fires. Refresh the cached
        // permission status and kick off the first scan automatically
        // so they don't have to tap anything else.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            appFlow.refreshPermissions()
            if appFlow.eventsAuthorization.isReadable, appFlow.pastEvents.isEmpty {
                Task { await appFlow.scanEvents() }
            }
        }
        .alert("Events cleanup", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - States

    private var permissionGate: some View {
        // Two-state CTA, matching the Photos / Contacts cards:
        //   • notDetermined  → "Continue" (fires the system prompt).
        //   • denied / restricted → "Open Settings" (deep-link into
        //     iOS Settings; iOS will not re-show the prompt once
        //     denied, so a button that retries the request would
        //     just silently no-op — exactly the bug the user hit).
        // Apple guideline 5.1.1(iv): pre-prompt button must be
        // neutral wording, never "Allow access". Explanation text
        // above the button still conveys what we'll do.
        let deniedPath = appFlow.eventsAuthorization.needsSettingsRedirect
        return VStack(spacing: 16) {
            Spacer(minLength: 40)
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(CleanupTheme.electricBlue)
            Text(deniedPath ? "Turn on calendar access" : "Calendar access needed")
                .font(CleanupFont.sectionTitle(20))
                .foregroundStyle(.white)
            Text(deniedPath
                 ? "Calendar access was turned off. Open Settings to turn it back on so we can find old events you can safely remove. Your events never leave your device."
                 : "Cleanup needs calendar access to find old events you can safely remove. Your events never leave your device.")
                .font(CleanupFont.body(14))
                .foregroundStyle(CleanupTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button {
                if deniedPath {
                    appFlow.openSystemSettings()
                } else {
                    Task { _ = await appFlow.requestEventsAccessIfNeeded() }
                }
            } label: {
                Text(deniedPath ? "Open Settings" : "Continue")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(CleanupTheme.electricBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)
            ProgressView()
                .tint(CleanupTheme.electricBlue)
                .scaleEffect(1.3)
            Text("Scanning your calendars…")
                .font(CleanupFont.body(14))
                .foregroundStyle(CleanupTheme.textSecondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(CleanupTheme.accentGreen)
            Text("All clean")
                .font(CleanupFont.sectionTitle(20))
                .foregroundStyle(.white)
            Text("You have no past events to remove.")
                .font(CleanupFont.body(14))
                .foregroundStyle(CleanupTheme.textSecondary)
            Spacer()
        }
    }

    private var contentList: some View {
        VStack(spacing: 12) {
            summaryCard

            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CleanupTheme.textTertiary)
                TextField("Search events", text: $searchText)
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
                Text("\(filteredEvents.count) past events")
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
                        let deletableIDs = filteredEvents.filter(\.canDelete).map(\.id)
                        if selectedIDs.count == deletableIDs.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(deletableIDs)
                        }
                    } label: {
                        let deletableIDs = filteredEvents.filter(\.canDelete).map(\.id)
                        Text(selectedIDs.count == deletableIDs.count && !deletableIDs.isEmpty
                             ? "Deselect all"
                             : "Select all")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.electricBlue)
                    }
                    .padding(.leading, 8)
                }
            }

            // Year-grouped event list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sectionedEvents, id: \.key) { section in
                        Section {
                            ForEach(section.events) { event in
                                EventListRow(
                                    event: event,
                                    isSelecting: isSelecting,
                                    isSelected: selectedIDs.contains(event.id),
                                    onToggle: {
                                        guard event.canDelete else { return }
                                        if selectedIDs.contains(event.id) {
                                            selectedIDs.remove(event.id)
                                        } else {
                                            selectedIDs.insert(event.id)
                                        }
                                    }
                                )
                            }
                        } header: {
                            EventYearHeader(label: section.key)
                        }
                    }
                }
                .padding(.bottom, isSelecting && !selectedIDs.isEmpty ? 90 : 24)
            }
            .onChange(of: searchText) { _, _ in
                selectedIDs.removeAll()
            }
        }
        .overlay(alignment: .bottom) {
            if isSelecting, !selectedIDs.isEmpty {
                cleanCTA
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 20) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CleanupTheme.electricBlue.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CleanupTheme.electricBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appFlow.eventAnalysisSummary.pastEventCount) past events")
                        .font(CleanupFont.sectionTitle(18))
                        .foregroundStyle(.white)
                    Text("Safe to remove from your calendar")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var cleanCTA: some View {
        Button {
            isDeleting = true
            let deletableIDs = filteredEvents
                .filter { $0.canDelete && selectedIDs.contains($0.id) }
                .map(\.id)
            Task {
                let success = await appFlow.deleteEvents(with: deletableIDs)
                selectedIDs.removeAll()
                isDeleting = false
                resultMessage = success
                    ? "Removed \(deletableIDs.count) event\(deletableIDs.count == 1 ? "" : "s")."
                    : "Some events couldn't be removed. Read-only calendars (like subscribed holidays) can only be hidden in iOS Settings."
                showResult = true
            }
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text("Clean \(deletableSelectedCount) event\(deletableSelectedCount == 1 ? "" : "s")")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(CleanupTheme.electricBlue.opacity(isDeleting ? 0.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(isDeleting || deletableSelectedCount == 0)
    }
}

// MARK: - Row

private struct EventListRow: View {
    let event: EventRecord
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
                            .strokeBorder(
                                isSelected ? CleanupTheme.electricBlue
                                            : Color.white.opacity(event.canDelete ? 0.3 : 0.12),
                                lineWidth: 1.5
                            )
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
                    .opacity(event.canDelete ? 1 : 0.5)
                    .transition(.scale.combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(CleanupFont.body(15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(event.calendarName)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textTertiary)
                        .lineLimit(1)
                }
                .opacity(event.canDelete ? 1 : 0.55)

                Spacer()

                Text(event.dateLine)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelecting && !event.canDelete)

        Divider()
            .background(CleanupTheme.divider)
    }
}

// MARK: - Year header

private struct EventYearHeader: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(CleanupFont.body(14).weight(.semibold))
                .foregroundStyle(CleanupTheme.electricBlue)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(CleanupTheme.background)
    }
}

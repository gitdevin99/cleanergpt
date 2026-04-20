import Photos
import SwiftUI

private enum DashboardSection: String, CaseIterable, Identifiable {
    case photos
    case videos
    case contacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: "Photos"
        case .videos: "Videos"
        case .contacts: "Contacts"
        }
    }
}

struct DashboardHomeView: View {
    var body: some View {
        NavigationStack {
            DashboardView()
                .navigationBarHidden(true)
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appFlow: AppFlow

    @State private var selectedSection: DashboardSection = .photos

    private var photoCategories: [DashboardCategorySummary] {
        [
            summary(for: .duplicates),
            summary(for: .similar),
            DashboardCategorySummary(
                kind: .screenshots,
                count: summary(for: .similarScreenshots).count,
                totalBytes: summary(for: .similarScreenshots).totalBytes
            )
        ]
    }

    private var videoCategories: [DashboardCategorySummary] {
        let order: [DashboardCategoryKind] = [.similarVideos, .shortRecordings, .screenRecordings, .videos]
        return order
            .map { kind in summary(for: kind) }
            .filter { $0.count > 0 }
    }

    private func summary(for kind: DashboardCategoryKind) -> DashboardCategorySummary {
        appFlow.dashboardCategories.first(where: { $0.kind == kind }) ?? DashboardCategorySummary(kind: kind, count: 0, totalBytes: 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                storageCard
                sectionPicker
                sectionContent
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 108)
        }
        .refreshable {
            await refreshForVisibleSection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                NavigationLink {
                    AppStatusView()
                } label: {
                    GlassIconLabel(symbol: "gearshape.fill")
                }
                .modifier(GlassActionChrome())

                Spacer()

                Text("Ai Cleaner")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                PremiumPill()
            }

            UsageBar(
                progress: max(0.04, min(appFlow.scanProgress == 0 ? 0.04 : appFlow.scanProgress, 1)),
                palette: LinearGradient(
                    colors: [CleanupTheme.electricBlue, Color(hex: "#6FE2FF")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 5)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                Text(appFlow.isScanningLibrary ? "Analyzing files on your device..." : appFlow.scanStatusText)
                    .font(CleanupFont.body(13))
            }
            .foregroundStyle(CleanupTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
        }
    }

    private var storageCard: some View {
        GlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Storage")
                    .font(CleanupFont.body(13))
                    .foregroundStyle(.white.opacity(0.9))

                (
                    Text(ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.usedBytes))
                        .font(CleanupFont.hero(22))
                        .foregroundStyle(.white)
                    +
                    Text(" of \(ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.totalBytes))")
                        .font(CleanupFont.body(16))
                        .foregroundStyle(CleanupTheme.textSecondary)
                )

                UsageBar(progress: max(0.04, min(appFlow.storageSnapshot.progress, 1)), palette: CleanupTheme.warmBar)
                    .frame(height: 7)

                NavigationLink {
                    SmartCleaningView()
                } label: {
                    HStack(spacing: 8) {
                        Text("AI Smart Clean")
                            .font(CleanupFont.body(16))
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .background(CleanupTheme.cta)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: CleanupTheme.electricBlue.opacity(0.22), radius: 12, y: 7)
                .buttonStyle(.plain)
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Dashboard Section", selection: $selectedSection) {
            ForEach(DashboardSection.allCases) { section in
                Text(section.title)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .photos:
            photoSection
        case .videos:
            videoSection
        case .contacts:
            contactsSection
        }
    }

    private var photoSection: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(photoCategories) { item in
                    NavigationLink {
                        MediaCategoryReviewView(category: item.kind)
                    } label: {
                        categoryCard(item, compact: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            NavigationLink {
                CompressView()
            } label: {
                wideActionCard(
                    eyebrow: "Want to save up extra space?",
                    title: "Compress",
                    accent: CleanupTheme.accentCyan
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SpeakerCleanView()
            } label: {
                wideActionCard(
                    eyebrow: "Dust or water in your speaker?",
                    title: "Speaker Clean",
                    accent: Color(hex: "#2DD4BF")
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var videoSection: some View {
        VStack(spacing: 10) {
            ForEach(videoCategories) { item in
                NavigationLink {
                    MediaCategoryReviewView(category: item.kind)
                } label: {
                    categoryCard(item, compact: false)
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                CompressView()
            } label: {
                wideActionCard(
                    eyebrow: "Shrink your biggest videos",
                    title: "Open Compressor",
                    accent: CleanupTheme.accentGreen
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var contactsSection: some View {
        VStack(spacing: 10) {
            GlassCard(cornerRadius: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Duplicate contacts")
                        .font(CleanupFont.sectionTitle(18))
                        .foregroundStyle(.white)

                    Text("\(appFlow.duplicateContactGroups.count) groups ready to review")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)

                    GlassProminentCTA {
                        appFlow.selectTab(.contacts)
                    } label: {
                        Text("Open Contacts")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                }
            }
        }
    }

    private func categoryCard(_ item: DashboardCategorySummary, compact: Bool) -> some View {
        let isAnalyzing = appFlow.isScanningLibrary && selectedSection != .contacts
        let hasResults = item.count > 0 || item.totalBytes > 0
        let previewClusters = appFlow.mediaClusters(for: reviewCategory(for: item.kind))

        return GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.kind.title) (\(item.count))")
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textSecondary)
                        Text(cardValue(for: item, isAnalyzing: isAnalyzing, hasResults: hasResults))
                            .font(CleanupFont.sectionTitle(compact ? 17 : 20))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }

                HStack(alignment: .bottom) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 4)
                        Circle()
                            .trim(from: 0.12, to: ringTrim(for: item, isAnalyzing: isAnalyzing, hasResults: hasResults))
                            .stroke(item.kind.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-140))
                    }
                    .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)

                    Spacer()

                    Group {
                        if isAnalyzing && previewClusters.isEmpty {
                            cardLoadingPreview(accent: item.kind.accent, compact: compact)
                        } else {
                            ClusterStackPreview(clusters: previewClusters)
                        }
                    }
                        .frame(width: compact ? 62 : 84, height: compact ? 48 : 66)
                }

                if isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(item.kind.accent)
                        Text(cardStatus(for: item, hasResults: hasResults))
                            .font(CleanupFont.caption(10))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func reviewCategory(for kind: DashboardCategoryKind) -> DashboardCategoryKind {
        switch kind {
        case .screenshots:
            return .similarScreenshots
        default:
            return kind
        }
    }

    private func cardValue(for item: DashboardCategorySummary, isAnalyzing: Bool, hasResults: Bool) -> String {
        if hasResults {
            return ByteCountFormatter.cleanupString(fromByteCount: item.totalBytes)
        }
        if isAnalyzing {
            return "Analyzing..."
        }
        return ByteCountFormatter.cleanupString(fromByteCount: item.totalBytes)
    }

    private func ringTrim(for item: DashboardCategorySummary, isAnalyzing: Bool, hasResults: Bool) -> CGFloat {
        if hasResults {
            return 0.96
        }
        if isAnalyzing {
            return max(0.34, min(0.92, 0.12 + (appFlow.scanProgress * 0.84)))
        }
        return 0.96
    }

    private func cardStatus(for item: DashboardCategorySummary, hasResults: Bool) -> String {
        if hasResults {
            return "\(item.count) found so far"
        }
        let scanned = max(appFlow.scannedLibraryItems, 0)
        let total = max(appFlow.totalLibraryItems, 0)
        if total > 0 {
            return "Scanning \(scanned.formatted()) of \(total.formatted())"
        }
        return "Preparing media analysis"
    }

    private func cardLoadingPreview(accent: Color, compact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.07),
                                accent.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(
                        width: compact ? 16 : 22,
                        height: compact ? [22, 30, 26][index] : [30, 42, 36][index]
                    )
            }
        }
    }

    private func wideActionCard(eyebrow: String, title: String, accent: Color) -> some View {
        GlassCard(cornerRadius: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Text(title)
                        .font(CleanupFont.sectionTitle(20))
                        .foregroundStyle(.white)
                }

                Spacer()

                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accent)
                    }
            }
        }
    }

    private func refreshForVisibleSection() async {
        switch selectedSection {
        case .photos, .videos:
            await appFlow.scanLibrary()
        case .contacts:
            await appFlow.scanContacts()
        }
    }
}

private enum SmartCleanPanel: String, CaseIterable, Hashable {
    case photos
    case videos
    case contacts
    case events
}

private enum SmartCleanAnalysisPhase {
    case idle
    case running
    case complete
}

private enum SmartCleanDestination: Identifiable, Hashable {
    case media(DashboardCategoryKind, preselectAll: Bool)
    case events(preselectAll: Bool)

    var id: String {
        switch self {
        case let .media(category, preselectAll):
            return "media-\(category.rawValue)-\(preselectAll)"
        case let .events(preselectAll):
            return "events-\(preselectAll)"
        }
    }
}

struct SmartCleaningView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    @State private var expandedPanels: Set<SmartCleanPanel> = [.photos]
    @State private var selectedRowIDs: Set<String> = []
    @State private var analysisPhase: SmartCleanAnalysisPhase = .idle
    @State private var analysisStatus = "Review device storage and cleanup suggestions."
    @State private var reviewDestination: SmartCleanDestination?

    private var usedStoragePercent: Int {
        Int((appFlow.storageSnapshot.progress * 100).rounded())
    }

    private var totalPhotoSavingsBytes: Int64 {
        summary(for: .duplicates).totalBytes
        + summary(for: .similar).totalBytes
        + summary(for: .screenshots).totalBytes
        + summary(for: .similarScreenshots).totalBytes
    }

    private var totalVideoSavingsBytes: Int64 {
        summary(for: .similarVideos).totalBytes
    }

    private var totalSavingsBytes: Int64 {
        totalPhotoSavingsBytes + totalVideoSavingsBytes
    }

    private var totalSuggestedItems: Int {
        summary(for: .duplicates).count
        + summary(for: .similar).count
        + summary(for: .screenshots).count
        + summary(for: .similarScreenshots).count
        + summary(for: .similarVideos).count
        + appFlow.contactAnalysisSummary.duplicateContactCount
        + appFlow.contactAnalysisSummary.incompleteCount
        + appFlow.eventAnalysisSummary.pastEventCount
    }

    private var selectedSuggestionCount: Int {
        SmartCleanPanel.allCases.reduce(0) { partialResult, panel in
            partialResult + enabledRows(for: panel).filter { selectedRowIDs.contains($0.id) }.count
        }
    }

    var body: some View {
        FeatureScreen(
            title: "Smart Cleaning",
            leadingSymbol: "chevron.left",
            trailingSymbol: nil,
            leadingAction: { dismiss() },
        ) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    summaryHero
                    sectionHeader("Optimize your storage")
                    smartPanel(.photos)
                    smartPanel(.videos)
                    smartPanel(.contacts)
                    smartPanel(.events)
                    startButton
                }
                .padding(.bottom, 28)
            }
        }
        .task {
            guard analysisPhase == .idle else { return }
            await runAnalysis()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $reviewDestination) { destination in
            switch destination {
            case let .media(category, preselectAll):
                MediaCategoryReviewView(category: category, preselectAll: preselectAll)
            case let .events(preselectAll):
                EventReviewView(preselectAll: preselectAll)
            }
        }
    }

    private var summaryHero: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Storage health")
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textSecondary)

                        Text("Free up \(ByteCountFormatter.cleanupString(fromByteCount: totalSavingsBytes))")
                            .font(CleanupFont.sectionTitle(24))
                            .foregroundStyle(.white)

                        Text("\(totalSuggestedItems) suggestions ready")
                            .font(CleanupFont.body(13))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    SmartCleanGauge(
                        value: CGFloat(appFlow.storageSnapshot.progress),
                        segments: gaugeSegments
                    )
                    .frame(width: 104, height: 104)
                    .overlay {
                        VStack(spacing: 2) {
                            Text("\(max(1, min(99, usedStoragePercent)))%")
                                .font(CleanupFont.sectionTitle(24))
                                .foregroundStyle(.white)
                            Text("used")
                                .font(CleanupFont.caption(10))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    legendChip(title: "Photos", color: CleanupTheme.electricBlue)
                    legendChip(title: "Videos", color: CleanupTheme.accentGreen)
                    legendChip(title: "Contacts", color: Color(hex: "#7C6BFF"))
                    legendChip(title: "Events", color: Color(hex: "#C66DFF"))
                }

                HStack(spacing: 8) {
                    Image(systemName: analysisPhase == .running ? "waveform.path.ecg" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(analysisPhase == .running ? CleanupTheme.electricBlue : CleanupTheme.accentGreen)
                    Text(analysisStatus)
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }
        }
    }

    private func smartPanel(_ panel: SmartCleanPanel) -> some View {
        let isExpanded = expandedPanels.contains(panel)

        return GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    toggle(panel)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(panelColor(panel))
                            .frame(width: 4, height: 42)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(panelTitle(panel))
                                .font(CleanupFont.sectionTitle(18))
                                .foregroundStyle(.white)
                            Text(panelSummary(panel))
                                .font(CleanupFont.caption(12))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(panelValue(panel))
                                .font(CleanupFont.badge(13))
                                .foregroundStyle(.white)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    HStack {
                        Text(selectionSummary(for: panel))
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textSecondary)
                        Spacer()
                        if enabledRows(for: panel).count > 1 {
                            Button(allRowsSelected(in: panel) ? "Clear" : "Select all") {
                                toggleAllRows(in: panel)
                            }
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.electricBlue)
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(panelRows(panel)) { row in
                            smartRow(row)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func smartRow(_ row: SmartCleanRow) -> some View {
        Group {
            if let category = row.category, row.isEnabled {
                HStack(spacing: 0) {
                    Button {
                        toggleSelection(for: row)
                    } label: {
                        selectionIndicator(for: row)
                            .frame(width: 32, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MediaCategoryReviewView(category: category, preselectAll: isSelected(row))
                    } label: {
                        rowBody(row, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.leading, 32)
                        .opacity(row.showsDivider ? 1 : 0)
                }
            } else if row.kind == .contactsPermission {
                Button {
                    Task {
                        _ = await appFlow.requestContactsAccessIfNeeded()
                        await runAnalysis()
                    }
                } label: {
                    rowContent(row)
                }
                .buttonStyle(.plain)
            } else if row.kind == .eventsPermission {
                Button {
                    Task {
                        _ = await appFlow.requestEventsAccessIfNeeded()
                        await runAnalysis()
                    }
                } label: {
                    rowContent(row)
                }
                .buttonStyle(.plain)
            } else if row.kind == .toggleOnly {
                Button {
                    toggleSelection(for: row)
                } label: {
                    rowContent(row)
                }
                .buttonStyle(.plain)
            } else if row.kind == .openContacts {
                Button {
                    appFlow.selectTab(.contacts)
                    dismiss()
                } label: {
                    rowContent(row)
                }
                .buttonStyle(.plain)
            } else {
                rowContent(row)
            }
        }
    }

    private func rowContent(_ row: SmartCleanRow) -> some View {
        HStack(spacing: 12) {
            selectionIndicator(for: row)
            rowBody(row, showsChevron: row.isEnabled)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.leading, 32)
                .opacity(row.showsDivider ? 1 : 0)
        }
    }

    private func selectionIndicator(for row: SmartCleanRow) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(row.isEnabled ? (isSelected(row) ? panelColor(row.panel).opacity(0.9) : Color.white.opacity(0.08)) : Color.white.opacity(0.04))
            .frame(width: 20, height: 20)
            .overlay {
                if row.kind == .contactsPermission {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else if row.kind == .eventsPermission {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else if row.isEnabled, isSelected(row) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }

    private func rowBody(_ row: SmartCleanRow, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(CleanupFont.body(14))
                    .foregroundStyle(row.isEnabled ? .white : CleanupTheme.textSecondary)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textTertiary)
                }
            }

            Spacer()

            Text(row.value)
                .font(CleanupFont.body(14))
                .foregroundStyle(row.isEnabled ? CleanupTheme.textSecondary : CleanupTheme.textTertiary)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var startButton: some View {
        Button {
            openSuggestedCleanup()
        } label: {
            Text(callToActionTitle)
                .font(CleanupFont.body(16))
                .foregroundStyle(.white.opacity(hasSuggestions ? 1 : 0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .background {
            if hasSuggestions {
                CleanupTheme.cta
            } else {
                Color.white.opacity(0.08)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .buttonStyle(.plain)
        .disabled(!hasSuggestions)
        .padding(.top, 10)
    }

    private var hasSuggestions: Bool {
        totalSuggestedItems > 0
    }

    private var callToActionTitle: String {
        if !hasSuggestions {
            return "Analysis up to date"
        }

        if selectedSuggestionCount > 0 {
            return "Review \(selectedSuggestionCount) Selected"
        }

        return "Select items to review"
    }

    private var gaugeSegments: [(Color, CGFloat)] {
        let photo = max(CGFloat(totalPhotoSavingsBytes), 1)
        let video = max(CGFloat(totalVideoSavingsBytes), 1)
        let contacts = max(CGFloat(appFlow.contactAnalysisSummary.duplicateContactCount + appFlow.contactAnalysisSummary.incompleteCount) * 2_500_000, 1)
        let events = max(CGFloat(appFlow.eventAnalysisSummary.pastEventCount) * 200_000, 1)
        let total = photo + video + contacts + events

        return [
            (CleanupTheme.electricBlue, photo / total),
            (CleanupTheme.accentGreen, video / total),
            (Color(hex: "#7C6BFF"), contacts / total),
            (Color(hex: "#C66DFF"), events / total)
        ]
    }

    private func runAnalysis() async {
        analysisPhase = .running
        analysisStatus = "Refreshing device storage..."
        appFlow.refreshDeviceAndStorage()
        appFlow.refreshPermissions()

        if appFlow.photoAuthorization.isReadable {
            analysisStatus = "Analyzing photos and videos..."
            await appFlow.scanLibrary()
        } else {
            analysisStatus = "Photo access is needed for media analysis."
        }

        if appFlow.contactsAuthorization.isReadable {
            analysisStatus = "Reviewing contacts..."
            await appFlow.scanContacts()
        } else if !appFlow.photoAuthorization.isReadable {
            analysisStatus = "Grant access to analyze media and contacts."
        } else {
            analysisStatus = "Grant contact access to include address-book cleanup."
        }

        if appFlow.eventsAuthorization.isReadable {
            analysisStatus = "Reviewing calendar events..."
            await appFlow.scanEvents()
        }

        if appFlow.photoAuthorization.isReadable, appFlow.contactsAuthorization.isReadable || appFlow.eventsAuthorization.isReadable {
            analysisStatus = totalSuggestedItems == 0
                ? "Analysis complete. Your device looks clean."
                : "Analysis complete. Suggestions are ready to review."
        }

        selectedRowIDs = []
        analysisPhase = .complete
    }

    private func openSuggestedCleanup() {
        let selectedIDs = selectedRowIDs

        guard !selectedIDs.isEmpty else { return }

        for row in enabledRows(for: .photos) + enabledRows(for: .videos) {
            guard selectedIDs.contains(row.id), let category = row.category, summary(for: category).count > 0 else { continue }
            reviewDestination = .media(category, preselectAll: true)
            return
        }

        if selectedIDs.contains("contacts-duplicate"), appFlow.contactAnalysisSummary.duplicateGroupCount > 0 {
            appFlow.selectTab(.contacts)
            dismiss()
            return
        }

        if selectedIDs.contains("events-past"), appFlow.eventAnalysisSummary.pastEventCount > 0 {
            reviewDestination = .events(preselectAll: true)
            return
        }
    }

    private func toggle(_ panel: SmartCleanPanel) {
        if expandedPanels.contains(panel) {
            expandedPanels.remove(panel)
        } else {
            expandedPanels.insert(panel)
        }
    }

    private func summary(for kind: DashboardCategoryKind) -> DashboardCategorySummary {
        appFlow.dashboardCategories.first(where: { $0.kind == kind })
            ?? DashboardCategorySummary(kind: kind, count: 0, totalBytes: 0)
    }

    private func panelTitle(_ panel: SmartCleanPanel) -> String {
        switch panel {
        case .photos: "Analyzing Photos"
        case .videos: "Videos"
        case .contacts: "Contacts"
        case .events: "Events"
        }
    }

    private func panelSummary(_ panel: SmartCleanPanel) -> String {
        switch panel {
        case .photos:
            appFlow.photoAuthorization.isReadable
                ? "Duplicates, similar shots, screenshots"
                : "Allow Photos access to analyze your library"
        case .videos:
            appFlow.photoAuthorization.isReadable
                ? "Similar video groups and large clips"
                : "Video analysis requires Photos access"
        case .contacts:
            appFlow.contactsAuthorization.isReadable
                ? "Duplicates, incomplete cards, total contacts"
                : "Allow Contacts access for real address-book stats"
        case .events:
            appFlow.eventsAuthorization.isReadable
                ? "Past events ready for bulk review"
                : "Allow Calendar access for past-event cleanup"
        }
    }

    private func panelValue(_ panel: SmartCleanPanel) -> String {
        switch panel {
        case .photos:
            appFlow.photoAuthorization.isReadable
                ? ByteCountFormatter.cleanupString(fromByteCount: totalPhotoSavingsBytes)
                : "Locked"
        case .videos:
            appFlow.photoAuthorization.isReadable
                ? ByteCountFormatter.cleanupString(fromByteCount: totalVideoSavingsBytes)
                : "Locked"
        case .contacts:
            appFlow.contactsAuthorization.isReadable
                ? "\(appFlow.contactAnalysisSummary.totalCount)"
                : "Locked"
        case .events:
            appFlow.eventsAuthorization.isReadable
                ? "\(appFlow.eventAnalysisSummary.pastEventCount)"
                : "Locked"
        }
    }

    private func panelColor(_ panel: SmartCleanPanel) -> Color {
        switch panel {
        case .photos: CleanupTheme.electricBlue
        case .videos: CleanupTheme.accentGreen
        case .contacts: Color(hex: "#7C6BFF")
        case .events: Color(hex: "#C66DFF")
        }
    }

    private func panelRows(_ panel: SmartCleanPanel) -> [SmartCleanRow] {
        switch panel {
        case .photos:
            guard appFlow.photoAuthorization.isReadable else {
                return [
                    SmartCleanRow(
                        id: "photos-locked",
                        panel: .photos,
                        kind: .locked,
                        title: "Photos access required",
                        subtitle: "Grant access from onboarding or device settings.",
                        value: "",
                        isEnabled: false,
                        showsDivider: false,
                        category: nil
                    )
                ]
            }

            return [
                SmartCleanRow(id: "photos-similar", panel: .photos, kind: .media, title: "Similar", subtitle: nil, value: "\(summary(for: .similar).count)", isEnabled: summary(for: .similar).count > 0, showsDivider: true, category: .similar),
                SmartCleanRow(id: "photos-duplicate", panel: .photos, kind: .media, title: "Duplicate", subtitle: nil, value: "\(summary(for: .duplicates).count)", isEnabled: summary(for: .duplicates).count > 0, showsDivider: true, category: .duplicates),
                SmartCleanRow(id: "photos-screenshots", panel: .photos, kind: .media, title: "Screenshots", subtitle: nil, value: "\(summary(for: .screenshots).count)", isEnabled: summary(for: .screenshots).count > 0, showsDivider: true, category: .screenshots),
                SmartCleanRow(id: "photos-similar-screenshots", panel: .photos, kind: .media, title: "Similar Screenshots", subtitle: nil, value: "\(summary(for: .similarScreenshots).count)", isEnabled: summary(for: .similarScreenshots).count > 0, showsDivider: false, category: .similarScreenshots)
            ]
        case .videos:
            guard appFlow.photoAuthorization.isReadable else {
                return [
                    SmartCleanRow(
                        id: "videos-locked",
                        panel: .videos,
                        kind: .locked,
                        title: "Video analysis unavailable",
                        subtitle: "Grant Photos access to scan videos.",
                        value: "",
                        isEnabled: false,
                        showsDivider: false,
                        category: nil
                    )
                ]
            }

            return [
                SmartCleanRow(id: "videos-similar", panel: .videos, kind: .media, title: "Duplicates", subtitle: nil, value: "\(summary(for: .similarVideos).count)", isEnabled: summary(for: .similarVideos).count > 0, showsDivider: true, category: .similarVideos),
                SmartCleanRow(id: "videos-short", panel: .videos, kind: .media, title: "Short Recordings", subtitle: nil, value: "\(summary(for: .shortRecordings).count)", isEnabled: summary(for: .shortRecordings).count > 0, showsDivider: true, category: .shortRecordings),
                SmartCleanRow(id: "videos-screen", panel: .videos, kind: .media, title: "Screen Recordings", subtitle: nil, value: "\(summary(for: .screenRecordings).count)", isEnabled: summary(for: .screenRecordings).count > 0, showsDivider: true, category: .screenRecordings),
                SmartCleanRow(id: "videos-all", panel: .videos, kind: .media, title: "All Videos", subtitle: nil, value: "\(summary(for: .videos).count)", isEnabled: summary(for: .videos).count > 0, showsDivider: false, category: .videos)
            ]
        case .contacts:
            guard appFlow.contactsAuthorization.isReadable else {
                return [
                    SmartCleanRow(id: "contacts-permission", panel: .contacts, kind: .contactsPermission, title: "Allow Contacts Access", subtitle: "Scan duplicate and incomplete contact cards.", value: "", isEnabled: true, showsDivider: false, category: nil)
                ]
            }

            return [
                SmartCleanRow(id: "contacts-duplicate", panel: .contacts, kind: .openContacts, title: "Duplicate", subtitle: "Names, numbers, emails", value: "\(appFlow.contactAnalysisSummary.duplicateContactCount) / \(appFlow.contactAnalysisSummary.duplicateContactCount)", isEnabled: appFlow.contactAnalysisSummary.duplicateGroupCount > 0, showsDivider: true, category: nil),
                SmartCleanRow(id: "contacts-incomplete", panel: .contacts, kind: .toggleOnly, title: "Incomplete", subtitle: "Missing name or contact info", value: "\(appFlow.contactAnalysisSummary.incompleteCount) / \(appFlow.contactAnalysisSummary.incompleteCount)", isEnabled: appFlow.contactAnalysisSummary.incompleteCount > 0, showsDivider: true, category: nil),
                SmartCleanRow(id: "contacts-all", panel: .contacts, kind: .locked, title: "All Contacts", subtitle: nil, value: "\(appFlow.contactAnalysisSummary.totalCount)", isEnabled: false, showsDivider: true, category: nil),
                SmartCleanRow(id: "contacts-backups", panel: .contacts, kind: .locked, title: "Backups", subtitle: "Last backup", value: "\(appFlow.contactAnalysisSummary.backupCount)", isEnabled: false, showsDivider: false, category: nil)
            ]
        case .events:
            guard appFlow.eventsAuthorization.isReadable else {
                return [
                    SmartCleanRow(id: "events-permission", panel: .events, kind: .eventsPermission, title: "Allow Calendar Access", subtitle: "Scan past events for bulk cleanup.", value: "", isEnabled: true, showsDivider: false, category: nil)
                ]
            }

            return [
                SmartCleanRow(id: "events-past", panel: .events, kind: .toggleOnly, title: "Past", subtitle: "Past events are permanently deleted", value: "\(appFlow.eventAnalysisSummary.pastEventCount) / \(appFlow.eventAnalysisSummary.pastEventCount)", isEnabled: appFlow.eventAnalysisSummary.pastEventCount > 0, showsDivider: false, category: nil)
            ]
        }
    }

    private func enabledRows(for panel: SmartCleanPanel) -> [SmartCleanRow] {
        panelRows(panel).filter(\.isEnabled)
    }

    private func selectionSummary(for panel: SmartCleanPanel) -> String {
        let enabled = enabledRows(for: panel)
        let selected = enabled.filter { selectedRowIDs.contains($0.id) }
        return "\(selected.count) of \(enabled.count) selected"
    }

    private func allRowsSelected(in panel: SmartCleanPanel) -> Bool {
        let enabled = enabledRows(for: panel)
        guard !enabled.isEmpty else { return false }
        return enabled.allSatisfy { selectedRowIDs.contains($0.id) }
    }

    private func toggleAllRows(in panel: SmartCleanPanel) {
        let ids = Set(enabledRows(for: panel).map(\.id))
        if ids.isSubset(of: selectedRowIDs) {
            selectedRowIDs.subtract(ids)
        } else {
            selectedRowIDs.formUnion(ids)
        }
    }

    private func toggleSelection(for row: SmartCleanRow) {
        guard row.isEnabled else { return }
        if selectedRowIDs.contains(row.id) {
            selectedRowIDs.remove(row.id)
        } else {
            selectedRowIDs.insert(row.id)
        }
    }

    private func isSelected(_ row: SmartCleanRow) -> Bool {
        selectedRowIDs.contains(row.id)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(CleanupFont.sectionTitle(16))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 2)
    }

    private func legendChip(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(CleanupFont.caption(11))
                .foregroundStyle(CleanupTheme.textSecondary)
        }
    }
}

private struct SmartCleanRow: Identifiable {
    enum Kind {
        case media
        case locked
        case contactsPermission
        case eventsPermission
        case openContacts
        case toggleOnly
    }

    let id: String
    let panel: SmartCleanPanel
    let kind: Kind
    let title: String
    let subtitle: String?
    let value: String
    let isEnabled: Bool
    let showsDivider: Bool
    let category: DashboardCategoryKind?
}

private struct SmartCleanGauge: View {
    let value: CGFloat
    let segments: [(Color, CGFloat)]

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(112))

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: segmentStart(at: index), to: segmentEnd(at: index))
                    .stroke(segment.0, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(112))
            }
        }
        .padding(6)
    }

    private func segmentStart(at index: Int) -> CGFloat {
        let base = CGFloat(0.12)
        let sweep = CGFloat(0.76)
        let prior = segments.prefix(index).reduce(CGFloat.zero) { $0 + max(0, $1.1) }
        return base + (prior * sweep)
    }

    private func segmentEnd(at index: Int) -> CGFloat {
        let base = CGFloat(0.12)
        let sweep = CGFloat(0.76)
        let upto = segments.prefix(index + 1).reduce(CGFloat.zero) { $0 + max(0, $1.1) }
        return min(0.88, base + (upto * sweep))
    }
}

struct MediaCategoryReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    let category: DashboardCategoryKind
    let preselectAll: Bool

    @State private var selectedClusterIDs: Set<String> = []
    @State private var selectedAssetIDs: Set<String> = []
    @State private var isDeleting = false
    @State private var statusMessage: String?
    @State private var didApplyInitialSelection = false
    @State private var reviewRoute: ClusterReviewRoute?
    @State private var visibleClusterCount = 50
    @State private var isShowingFilterSheet = false
    @State private var appliedFilter = MediaReviewFilter()
    @State private var draftFilter = MediaReviewFilter()

    /// Cached filtered results — rebuilt only when source data or filter changes.
    @State private var cachedFilteredClusters: [MediaCluster] = []
    @State private var cachedFilteredAssets: [MediaAssetRecord] = []
    @State private var lastClusterCount = -1
    @State private var lastAssetCount = -1

    /// Drag-to-select state for screenshot gallery.
    @StateObject private var dragSelect = DragSelectState()

    /// Presents the fullscreen video preview sheet for a specific asset.
    @State private var videoPreviewAssetID: String?

    init(category: DashboardCategoryKind, preselectAll: Bool = false) {
        self.category = category
        self.preselectAll = preselectAll
    }

    private var sourceCategory: DashboardCategoryKind {
        category
    }

    private var reviewAssets: [MediaAssetRecord] {
        appFlow.mediaAssets(for: sourceCategory)
    }

    private var clusters: [MediaCluster] {
        appFlow.mediaClusters(for: sourceCategory)
    }

    private var filteredReviewAssets: [MediaAssetRecord] {
        cachedFilteredAssets
    }

    private var filteredClusters: [MediaCluster] {
        cachedFilteredClusters
    }

    private func rebuildFilteredCaches() {
        cachedFilteredClusters = appliedFilter.apply(to: clusters)
        cachedFilteredAssets = appliedFilter.apply(to: reviewAssets)
        lastClusterCount = clusters.count
        lastAssetCount = reviewAssets.count
    }

    private var isRefiningExactClusters: Bool {
        appFlow.isRefiningClusters(for: sourceCategory)
    }

    private var usesFlatScreenshotGallery: Bool {
        category == .screenshots
            || category == .videos
            || category == .shortRecordings
            || category == .screenRecordings
    }

    private var flatGalleryIsVideo: Bool {
        category == .videos || category == .shortRecordings || category == .screenRecordings
    }

    private var selectedDeletionIDs: [String] {
        if usesFlatScreenshotGallery {
            guard !selectedAssetIDs.isEmpty else { return [] }
            return selectedAssetIDs.filter { id in
                cachedFilteredAssets.contains { $0.id == id }
            }.sorted()
        }

        guard !selectedClusterIDs.isEmpty else { return [] }
        var result = Set<String>()
        for cluster in cachedFilteredClusters where selectedClusterIDs.contains(cluster.id) {
            let candidates = cluster.assets.dropFirst().map(\.id)
            result.formUnion(candidates)
        }
        return Array(result)
    }

    private var displayedClusters: [MediaCluster] {
        Array(cachedFilteredClusters.prefix(visibleClusterCount))
    }

    var body: some View {
        FeatureScreen(
            title: category.title,
            leadingSymbol: "chevron.left",
            trailingSymbol: "arrow.clockwise",
            leadingAction: { dismiss() },
            trailingAction: { Task { await appFlow.scanLibrary() } }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if !appFlow.photoAuthorization.isReadable {
                    permissionCard
                } else if filteredContentIsEmpty {
                    emptyState
                } else {
                    if usesFlatScreenshotGallery {
                        screenshotGallery
                    } else {
                        actionBar
                        clusterList
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedClusterIDs)
            .animation(.easeInOut(duration: 0.2), value: selectedAssetIDs)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $reviewRoute) { route in
            ClusterDetailReviewView(
                sourceCategory: route.sourceCategory,
                clusterID: route.clusterID,
                displayTitle: route.displayTitle
            )
        }
        .sheet(item: Binding(
            get: { videoPreviewAssetID.map { VideoPreviewRoute(id: $0) } },
            set: { videoPreviewAssetID = $0?.id }
        )) { route in
            VideoZoomPreviewSheet(
                assets: cachedFilteredAssets,
                initialAssetID: route.id,
                selectedAssetIDs: $selectedAssetIDs,
                accent: sourceCategory.accent
            )
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            MediaReviewFilterSheet(
                filter: $draftFilter,
                accent: sourceCategory.accent,
                canClear: draftFilter.isActive,
                onClear: {
                    draftFilter = MediaReviewFilter()
                },
                onApply: {
                    appliedFilter = draftFilter
                    // rebuildFilteredCaches is called by onChange(of: appliedFilter)
                    visibleClusterCount = min(50, cachedFilteredClusters.count)
                    selectedClusterIDs.formIntersection(Set(cachedFilteredClusters.map(\.id)))
                    selectedAssetIDs.formIntersection(Set(cachedFilteredAssets.map(\.id)))
                    isShowingFilterSheet = false
                }
            )
        }
        .task {
            rebuildFilteredCaches()
            applyInitialSelectionIfNeeded()
            syncScreenshotSelection()
        }
        .onChange(of: clusters.count) { _, newCount in
            guard newCount != lastClusterCount else { return }
            rebuildFilteredCaches()
            selectedClusterIDs.formIntersection(Set(cachedFilteredClusters.map(\.id)))
            applyInitialSelectionIfNeeded()
            syncScreenshotSelection()
        }
        .onChange(of: reviewAssets.count) { _, newCount in
            guard newCount != lastAssetCount else { return }
            rebuildFilteredCaches()
        }
        .onChange(of: appliedFilter) { _, newValue in
            draftFilter = newValue
            rebuildFilteredCaches()
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(filteredItemCount) items")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)
                    Text(ByteCountFormatter.cleanupString(fromByteCount: filteredTotalBytes))
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    if usesFlatScreenshotGallery {
                        Text(selectedAssetIDs.isEmpty ? "Select screenshots to remove in one pass" : "\(selectedAssetIDs.count) screenshot(s) selected")
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textTertiary)
                    } else {
                        Text("\(cachedFilteredClusters.count) exact sets ready to review")
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textTertiary)
                    }
                    if appliedFilter.isActive {
                        Text(filterSummaryLine)
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(sourceCategory.accent)
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(category.accent)
                    }
                    if isRefiningExactClusters && usesFlatScreenshotGallery == false {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(sourceCategory.accent)
                            Text("Refining exact similar sets with low-res previews")
                                .font(CleanupFont.caption(11))
                                .foregroundStyle(CleanupTheme.textTertiary)
                        }
                    }
                }

                Spacer()

                Circle()
                    .fill(sourceCategory.accent.opacity(0.14))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(sourceCategory.accent)
                    }
            }
        }
    }

    private var permissionCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Photo access is needed to review and delete media.")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(.white)
                PrimaryCTAButton(title: "Allow Photos Access") {
                    Task {
                        _ = await appFlow.requestPhotoAccessIfNeeded()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(category.emptyTitle)
                    .font(CleanupFont.sectionTitle(22))
                    .foregroundStyle(.white)
                Text(appliedFilter.isActive ? "No items match the current filter. Adjust the date range or sort and try again." : (usesFlatScreenshotGallery ? "Refresh after your next scan or come back once more screenshots are available." : "Keep scanning or refresh after adding more photos or videos."))
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(alignment: .center) {
            Button(selectedClusterIDs.count == selectableClusters.count ? "Clear" : "Select all duplicates") {
                if selectedClusterIDs.count == selectableClusters.count {
                    selectedClusterIDs.removeAll()
                } else {
                    selectedClusterIDs = Set(selectableClusters.map(\.id))
                }
            }
            .font(CleanupFont.body(15))
            .foregroundStyle(sourceCategory.accent)

            Button(action: openFilterSheet) {
                filterPillLabel
            }
            .buttonStyle(.plain)

            Spacer()

            if isDeleting {
                ProgressView()
                    .tint(.white)
            } else {
                PrimaryCTAButton(title: selectedDeletionIDs.isEmpty ? "Delete Selected" : "Delete \(selectedDeletionIDs.count) Duplicates") {
                    Task {
                        isDeleting = true
                        let deleteCount = selectedDeletionIDs.count
                        let success = await appFlow.deleteAssets(with: selectedDeletionIDs)
                        isDeleting = false
                        if success {
                            statusMessage = "Deleted \(deleteCount) item(s)."
                            selectedClusterIDs.removeAll()
                        } else {
                            statusMessage = "Delete failed. Please try again."
                        }
                    }
                }
                .disabled(selectedDeletionIDs.isEmpty)
                .opacity(selectedDeletionIDs.isEmpty ? 0.5 : 1)
                .frame(maxWidth: 220)
            }
        }
    }

    private var screenshotGallery: some View {
        let assets = cachedFilteredAssets
        let accentColor = sourceCategory.accent

        return VStack(alignment: .leading, spacing: 16) {
            screenshotActionBar

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: flatGalleryIsVideo ? Self.videoGridColumns : Self.screenshotGridColumns, spacing: 12) {
                    ForEach(assets) { asset in
                        if flatGalleryIsVideo {
                            VideoGalleryCell(
                                asset: asset,
                                isSelected: selectedAssetIDs.contains(asset.id),
                                accent: accentColor,
                                onTap: { toggleScreenshotSelection(asset.id) },
                                onExpand: { videoPreviewAssetID = asset.id }
                            )
                            .modifier(DragSelectCellModifier(id: asset.id, coordinateSpace: "screenshotGrid"))
                        } else {
                            Button {
                                toggleScreenshotSelection(asset.id)
                            } label: {
                                ScreenshotGalleryCell(
                                    asset: asset,
                                    isSelected: selectedAssetIDs.contains(asset.id),
                                    accent: accentColor
                                )
                            }
                            .buttonStyle(.plain)
                            .modifier(DragSelectCellModifier(id: asset.id, coordinateSpace: "screenshotGrid"))
                        }
                    }
                }
                .coordinateSpace(name: "screenshotGrid")
                .onPreferenceChange(DragSelectCellFrameKey.self) { frames in
                    dragSelect.cellFrames = frames
                }
                .modifier(DragSelectGestureModifier(
                    enabled: true,
                    coordinateSpace: "screenshotGrid",
                    dragSelect: dragSelect,
                    assets: assets,
                    selectedAssetIDs: $selectedAssetIDs
                ))
                .padding(.bottom, 120)
            }
            .scrollDisabled(dragSelect.isDragging)

            screenshotDeleteBar
        }
    }

    private var clusterList: some View {
        let displayed = displayedClusters
        let accentColor = sourceCategory.accent

        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                if cachedFilteredClusters.isEmpty {
                    clusterErrorState
                } else {
                    ForEach(displayed) { cluster in
                        ClusterSummaryCard(
                            cluster: cluster,
                            accent: accentColor,
                            isSelected: selectedClusterIDs.contains(cluster.id),
                            duplicateCount: max(cluster.assets.count - 1, 0),
                            onToggleSelection: {
                                toggleClusterSelection(cluster.id)
                            },
                            onOpen: {
                                reviewRoute = ClusterReviewRoute(
                                    sourceCategory: sourceCategory,
                                    clusterID: cluster.id,
                                    displayTitle: category.title
                                )
                            }
                        )
                        .onAppear {
                            if let idx = displayed.firstIndex(where: { $0.id == cluster.id }) {
                                if idx >= displayed.count - 8 {
                                    loadMoreClustersIfNeeded()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var screenshotActionBar: some View {
        HStack(spacing: 12) {
            Button(selectedAssetIDs.count == cachedFilteredAssets.count ? "Clear" : "Select all") {
                if selectedAssetIDs.count == cachedFilteredAssets.count {
                    selectedAssetIDs.removeAll()
                } else {
                    selectedAssetIDs = Set(cachedFilteredAssets.map(\.id))
                }
            }
            .font(CleanupFont.body(15))
            .foregroundStyle(sourceCategory.accent)
            .buttonStyle(.plain)

            Button(action: openFilterSheet) {
                filterPillLabel
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var screenshotDeleteBar: some View {
        let noun = flatGalleryIsVideo ? "Videos" : "Screenshots"
        return PrimaryCTAButton(title: selectedAssetIDs.isEmpty ? "Delete Selected" : "Delete \(selectedAssetIDs.count) \(noun)") {
            Task {
                guard !selectedDeletionIDs.isEmpty else { return }
                isDeleting = true
                let deleteCount = selectedDeletionIDs.count
                let success = await appFlow.deleteAssets(with: selectedDeletionIDs)
                isDeleting = false

                if success {
                    statusMessage = "Deleted \(deleteCount) item(s)."
                    selectedAssetIDs.removeAll()
                } else {
                    statusMessage = "Delete failed. Please try again."
                }
            }
        }
        .disabled(selectedAssetIDs.isEmpty || isDeleting)
        .opacity(selectedAssetIDs.isEmpty ? 0.5 : 1)
        .overlay {
            if isDeleting {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var clusterErrorState: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Exact groups are still being built")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                Text("Cleanup is still refining visually matching sets for this category. Leave the screen open or refresh in a moment.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private func applyInitialSelectionIfNeeded() {
        guard usesFlatScreenshotGallery == false else { return }
        guard preselectAll, !didApplyInitialSelection, !selectableClusters.isEmpty else { return }
        selectedClusterIDs = Set(selectableClusters.map(\.id))
        didApplyInitialSelection = true
    }

    private var selectableClusters: [MediaCluster] {
        cachedFilteredClusters.filter { $0.assets.count > 1 }
    }

    private func deletionCandidateIDs(in cluster: MediaCluster) -> [String] {
        guard cluster.assets.count > 1 else { return [] }
        return Array(cluster.assets.dropFirst().map(\.id))
    }

    private func toggleClusterSelection(_ clusterID: String) {
        if selectedClusterIDs.contains(clusterID) {
            selectedClusterIDs.remove(clusterID)
        } else {
            selectedClusterIDs.insert(clusterID)
        }
    }

    private func loadMoreClustersIfNeeded() {
        guard visibleClusterCount < cachedFilteredClusters.count else { return }
        visibleClusterCount = min(visibleClusterCount + 50, cachedFilteredClusters.count)
    }

    private func preheatIdentifiers(around displayedIndex: Int) -> [String] {
        let radius = 5
        let lowerBound = max(displayedIndex - radius, 0)
        let upperBound = min(displayedIndex + radius, displayedClusters.count - 1)
        guard lowerBound <= upperBound else { return [] }

        return Array(displayedClusters[lowerBound...upperBound])
            .flatMap { Array($0.assets.prefix(2)).map(\.id) }
    }

    private static let screenshotGridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private static let videoGridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private func syncScreenshotSelection() {
        guard usesFlatScreenshotGallery else { return }
        let validIDs = Set(cachedFilteredAssets.map(\.id))
        selectedAssetIDs.formIntersection(validIDs)
        guard preselectAll, !didApplyInitialSelection, !cachedFilteredAssets.isEmpty else { return }
        selectedAssetIDs = validIDs
        didApplyInitialSelection = true
    }

    private func toggleScreenshotSelection(_ id: String) {
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
    }

    private var filteredItemCount: Int {
        usesFlatScreenshotGallery ? cachedFilteredAssets.count : cachedFilteredClusters.reduce(into: 0) { $0 += $1.assets.count }
    }

    private var filteredTotalBytes: Int64 {
        usesFlatScreenshotGallery ? cachedFilteredAssets.reduce(into: Int64(0)) { $0 += $1.sizeInBytes } : cachedFilteredClusters.reduce(into: Int64(0)) { $0 += $1.totalBytes }
    }

    private var filteredContentIsEmpty: Bool {
        usesFlatScreenshotGallery ? cachedFilteredAssets.isEmpty : cachedFilteredClusters.isEmpty
    }

    private var filterSummaryLine: String {
        if let rangeLine = appliedFilter.dateRangeLine {
            return "\(appliedFilter.sortMode.title) • \(rangeLine)"
        }
        return appliedFilter.sortMode.title
    }

    private var filterPillLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .bold))
            Text(appliedFilter.sortMode.shortTitle)
                .font(CleanupFont.body(13))
        }
        .foregroundStyle(appliedFilter.isActive ? .white : CleanupTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background((appliedFilter.isActive ? sourceCategory.accent.opacity(0.18) : Color.white.opacity(0.05)), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(appliedFilter.isActive ? sourceCategory.accent.opacity(0.42) : Color.white.opacity(0.05))
        )
    }

    private func openFilterSheet() {
        draftFilter = appliedFilter
        isShowingFilterSheet = true
    }
}

private struct MediaReviewFilterSheet: View {
    @Binding var filter: MediaReviewFilter
    let accent: Color
    let canClear: Bool
    let onClear: () -> Void
    let onApply: () -> Void

    var body: some View {
        ScreenContainer {
            VStack(spacing: 18) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 52, height: 5)
                    .padding(.top, 10)

                VStack(spacing: 18) {
                    Text("Filter by")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select date range")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)

                        DatePicker("From", selection: fromBinding, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(accent)

                        DatePicker("To", selection: toBinding, in: (filter.startDate ?? Date.distantPast)...Date.distantFuture, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(accent)

                        Button("Clear selection") {
                            filter.startDate = nil
                            filter.endDate = nil
                        }
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Display first")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(MediaReviewSortMode.allCases) { mode in
                                Button {
                                    filter.sortMode = mode
                                } label: {
                                    Text(mode.title)
                                        .font(CleanupFont.body(15))
                                        .foregroundStyle(filter.sortMode == mode ? Color.black.opacity(0.84) : CleanupTheme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(filter.sortMode == mode ? accent.opacity(0.9) : Color.white.opacity(0.05))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        if canClear {
                            Button("Clear") {
                                onClear()
                            }
                            .font(CleanupFont.body(15))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .buttonStyle(.plain)
                        }

                        Button("Apply") {
                            onApply()
                        }
                        .font(CleanupFont.body(16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(CleanupTheme.cta, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(Color(hex: "#242424").opacity(0.94), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06))
                )
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .presentationDetents([.fraction(0.68)])
        .presentationDragIndicator(.hidden)
    }

    private var fromBinding: Binding<Date> {
        Binding(
            get: { filter.startDate ?? filter.endDate ?? Date() },
            set: { newValue in
                filter.startDate = newValue
                if let endDate = filter.endDate, endDate < newValue {
                    filter.endDate = newValue
                }
            }
        )
    }

    private var toBinding: Binding<Date> {
        Binding(
            get: { filter.endDate ?? filter.startDate ?? Date() },
            set: { newValue in
                filter.endDate = newValue
                if let startDate = filter.startDate, startDate > newValue {
                    filter.startDate = newValue
                }
            }
        )
    }
}

private struct MediaReviewFilter: Equatable {
    var sortMode: MediaReviewSortMode = .newest
    var startDate: Date?
    var endDate: Date?

    var isActive: Bool {
        sortMode != .newest || startDate != nil || endDate != nil
    }

    var dateRangeLine: String? {
        guard startDate != nil || endDate != nil else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(startDate.map { formatter.string(from: $0) } ?? "Any") - \(endDate.map { formatter.string(from: $0) } ?? "Any")"
    }

    func apply(to assets: [MediaAssetRecord]) -> [MediaAssetRecord] {
        // Short-circuit: no date filter and default sort → return as-is (already sorted by AppFlow)
        if startDate == nil && endDate == nil && sortMode == .newest {
            return assets
        }
        return assets.filter(matchesDateRange).sorted(by: assetComparator)
    }

    func apply(to clusters: [MediaCluster]) -> [MediaCluster] {
        // Short-circuit: no date filter and default sort → return as-is (already sorted by AppFlow)
        if startDate == nil && endDate == nil && sortMode == .newest {
            return clusters
        }
        return clusters.compactMap { cluster in
            let filteredAssets = cluster.assets.filter(matchesDateRange)
            guard !filteredAssets.isEmpty else { return nil }
            return MediaCluster(
                id: cluster.id,
                category: cluster.category,
                assets: filteredAssets,
                totalBytes: filteredAssets.reduce(0) { $0 + $1.sizeInBytes },
                subtitle: cluster.subtitle
            )
        }
        .sorted(by: clusterComparator)
    }

    private func matchesDateRange(_ asset: MediaAssetRecord) -> Bool {
        guard startDate != nil || endDate != nil else { return true }
        guard let createdAt = asset.createdAt else { return false }

        if let startDate, createdAt < Calendar.current.startOfDay(for: startDate) {
            return false
        }

        if let endDate,
           let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate),
           createdAt > endOfDay {
            return false
        }

        return true
    }

    private func assetComparator(lhs: MediaAssetRecord, rhs: MediaAssetRecord) -> Bool {
        switch sortMode {
        case .newest:
            return compareDates(lhs.createdAt, rhs.createdAt, descending: true)
        case .oldest:
            return compareDates(lhs.createdAt, rhs.createdAt, descending: false)
        case .largest:
            return compareSizes(lhs.sizeInBytes, rhs.sizeInBytes, lhsDate: lhs.createdAt, rhsDate: rhs.createdAt, descending: true)
        case .smallest:
            return compareSizes(lhs.sizeInBytes, rhs.sizeInBytes, lhsDate: lhs.createdAt, rhsDate: rhs.createdAt, descending: false)
        }
    }

    private func clusterComparator(lhs: MediaCluster, rhs: MediaCluster) -> Bool {
        switch sortMode {
        case .newest:
            return compareDates(lhs.assets.first?.createdAt, rhs.assets.first?.createdAt, descending: true)
        case .oldest:
            return compareDates(lhs.assets.first?.createdAt, rhs.assets.first?.createdAt, descending: false)
        case .largest:
            return compareSizes(lhs.totalBytes, rhs.totalBytes, lhsDate: lhs.assets.first?.createdAt, rhsDate: rhs.assets.first?.createdAt, descending: true)
        case .smallest:
            return compareSizes(lhs.totalBytes, rhs.totalBytes, lhsDate: lhs.assets.first?.createdAt, rhsDate: rhs.assets.first?.createdAt, descending: false)
        }
    }

    private func compareDates(_ lhs: Date?, _ rhs: Date?, descending: Bool) -> Bool {
        let lhsDate = lhs ?? .distantPast
        let rhsDate = rhs ?? .distantPast
        return descending ? lhsDate > rhsDate : lhsDate < rhsDate
    }

    private func compareSizes(_ lhs: Int64, _ rhs: Int64, lhsDate: Date?, rhsDate: Date?, descending: Bool) -> Bool {
        if lhs == rhs {
            return compareDates(lhsDate, rhsDate, descending: true)
        }
        return descending ? lhs > rhs : lhs < rhs
    }
}

private enum MediaReviewSortMode: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case largest
    case smallest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .largest: "Largest"
        case .smallest: "Smallest"
        }
    }

    var shortTitle: String { title }
}

struct EventReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    let preselectAll: Bool

    @State private var selectedEventIDs: Set<String> = []
    @State private var isDeleting = false
    @State private var statusMessage: String?
    @State private var didApplyInitialSelection = false

    init(preselectAll: Bool = false) {
        self.preselectAll = preselectAll
    }

    private var events: [EventRecord] {
        appFlow.pastEvents
    }

    private var deletableEvents: [EventRecord] {
        events.filter(\.canDelete)
    }

    var body: some View {
        FeatureScreen(
            title: "Past Events",
            leadingSymbol: "chevron.left",
            trailingSymbol: "arrow.clockwise",
            leadingAction: { dismiss() },
            trailingAction: { Task { await appFlow.scanEvents() } }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                if !appFlow.eventsAuthorization.isReadable {
                    permissionCard
                } else if events.isEmpty {
                    emptyState
                } else {
                    actionBar
                    eventList
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedEventIDs)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: events.map(\.id)) {
            guard preselectAll, !didApplyInitialSelection, !deletableEvents.isEmpty else { return }
            selectedEventIDs = Set(deletableEvents.map(\.id))
            didApplyInitialSelection = true
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(events.count) past events")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)
                    Text("Live calendar cleanup")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Text("\(deletableEvents.count) can be deleted from writable calendars.")
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textTertiary)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(Color(hex: "#C66DFF"))
                    }
                }

                Spacer()

                Circle()
                    .fill(Color(hex: "#C66DFF").opacity(0.14))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "#C66DFF"))
                    }
            }
        }
    }

    private var permissionCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Calendar access is needed to review and delete past events.")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(.white)
                PrimaryCTAButton(title: "Allow Calendar Access") {
                    Task {
                        _ = await appFlow.requestEventsAccessIfNeeded()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("No past events found")
                    .font(CleanupFont.sectionTitle(22))
                    .foregroundStyle(.white)
                Text("Refresh after granting access or after your calendar changes.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(alignment: .center) {
            Button(selectedEventIDs.count == deletableEvents.count ? "Clear Selection" : "Select All") {
                if selectedEventIDs.count == deletableEvents.count {
                    selectedEventIDs.removeAll()
                } else {
                    selectedEventIDs = Set(deletableEvents.map(\.id))
                }
            }
            .font(CleanupFont.body(15))
            .foregroundStyle(Color(hex: "#C66DFF"))
            .disabled(deletableEvents.isEmpty)
            .opacity(deletableEvents.isEmpty ? 0.45 : 1)

            Spacer()

            if isDeleting {
                ProgressView()
                    .tint(.white)
            } else {
                PrimaryCTAButton(title: selectedEventIDs.isEmpty ? "Delete Selected" : "Delete \(selectedEventIDs.count) Selected") {
                    Task {
                        isDeleting = true
                        let deleteCount = selectedEventIDs.count
                        let success = await appFlow.deleteEvents(with: Array(selectedEventIDs))
                        isDeleting = false
                        if success {
                            statusMessage = "Deleted \(deleteCount) event(s)."
                            selectedEventIDs.removeAll()
                        } else {
                            statusMessage = "Delete failed. Please try again."
                        }
                    }
                }
                .disabled(selectedEventIDs.isEmpty)
                .opacity(selectedEventIDs.isEmpty ? 0.5 : 1)
                .frame(maxWidth: 220)
            }
        }
    }

    private var eventList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(events) { event in
                    Button {
                        toggle(event.id)
                    } label: {
                        GlassCard(cornerRadius: 20) {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(
                                        event.canDelete
                                            ? (selectedEventIDs.contains(event.id) ? Color(hex: "#C66DFF").opacity(0.9) : Color.white.opacity(0.08))
                                            : Color.white.opacity(0.04)
                                    )
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if selectedEventIDs.contains(event.id) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                        } else if !event.canDelete {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(CleanupTheme.textSecondary)
                                        }
                                    }

                                eventDateBadge(event)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(event.title)
                                            .font(CleanupFont.body(15))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(2)

                                        if event.isAllDay {
                                            detailPill("All-day")
                                        }
                                        if !event.canDelete {
                                            detailPill("Read-only")
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        detailPill(event.calendarName)
                                        detailPill(event.dateLine)
                                    }

                                    Text(event.subtitle)
                                        .font(CleanupFont.caption(11))
                                        .foregroundStyle(CleanupTheme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(CleanupTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!event.canDelete)
                    .opacity(event.canDelete ? 1 : 0.7)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func toggle(_ id: String) {
        guard let event = events.first(where: { $0.id == id }), event.canDelete else { return }
        if selectedEventIDs.contains(id) {
            selectedEventIDs.remove(id)
        } else {
            selectedEventIDs.insert(id)
        }
    }

    private func eventDateBadge(_ event: EventRecord) -> some View {
        VStack(spacing: 2) {
            Text(monthToken(for: event.startDate))
                .font(CleanupFont.caption(9))
                .foregroundStyle(Color(hex: "#C66DFF"))
            Text(dayToken(for: event.startDate))
                .font(CleanupFont.sectionTitle(18))
                .foregroundStyle(.white)
        }
        .frame(width: 48, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func detailPill(_ title: String) -> some View {
        Text(title)
            .font(CleanupFont.caption(10))
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule(style: .continuous))
    }

    private func monthToken(for date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).uppercased()
    }

    private func dayToken(for date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

struct AppStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        FeatureScreen(
            title: "Device Status",
            leadingSymbol: "chevron.left",
            trailingSymbol: "arrow.clockwise",
            leadingAction: { dismiss() },
            trailingAction: { Task { await appFlow.bootstrapIfNeeded() } }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow(title: "Device", value: appFlow.deviceSnapshot.deviceName)
                        statusRow(title: "Model", value: appFlow.deviceSnapshot.modelName)
                        statusRow(title: "iOS", value: appFlow.deviceSnapshot.systemVersion)
                        statusRow(title: "Battery", value: appFlow.deviceSnapshot.batteryDescription)
                    }
                }

                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow(title: "Total Storage", value: ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.totalBytes))
                        statusRow(title: "Used Storage", value: ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.usedBytes))
                        statusRow(title: "Free Storage", value: ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.freeBytes))
                    }
                }

                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Permissions")
                            .font(CleanupFont.sectionTitle(20))
                            .foregroundStyle(.white)

                        HStack {
                            Text("Photos")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                            Spacer()
                            permissionPill(appFlow.photoAuthorization.isReadable ? "Allowed" : "Not Allowed", color: appFlow.photoAuthorization.isReadable ? CleanupTheme.accentGreen : CleanupTheme.accentRed)
                        }

                        HStack {
                            Text("Contacts")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                            Spacer()
                            permissionPill(appFlow.contactsAuthorization.isReadable ? "Allowed" : "Not Allowed", color: appFlow.contactsAuthorization.isReadable ? CleanupTheme.accentGreen : CleanupTheme.accentRed)
                        }

                        PrimaryCTAButton(title: "Refresh Device Scan") {
                            Task {
                                await appFlow.bootstrapIfNeeded()
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(CleanupFont.body(16))
                .foregroundStyle(CleanupTheme.textSecondary)
            Spacer()
            Text(value)
                .font(CleanupFont.body(16))
                .foregroundStyle(.white)
        }
    }

    private func permissionPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(CleanupFont.badge(12))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.14), in: Capsule(style: .continuous))
    }
}

private struct ClusterStackPreview: View {
    let clusters: [MediaCluster]

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(Array(previewAssets.enumerated()), id: \.offset) { index, asset in
                PhotoThumbnailView(localIdentifier: asset.id)
                    .frame(width: 34, height: 48)
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(x: -CGFloat(max(previewAssets.count - index - 1, 0)) * 9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .clipped()
    }

    private var previewAssets: [MediaAssetRecord] {
        Array(clusters.flatMap(\.assets).prefix(3))
    }
}

private struct ClusterReviewRoute: Identifiable, Hashable {
    let sourceCategory: DashboardCategoryKind
    let clusterID: String
    let displayTitle: String

    var id: String {
        "\(sourceCategory.rawValue)-\(clusterID)"
    }
}

private struct ClusterSummaryCard: View {
    let cluster: MediaCluster
    let accent: Color
    let isSelected: Bool
    let duplicateCount: Int
    let onToggleSelection: () -> Void
    let onOpen: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cluster.title)
                            .font(CleanupFont.sectionTitle(20))
                            .foregroundStyle(.white)
                        Text(cluster.sizeLine)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .padding(.bottom, 2)
                        if let subtitle = cluster.subtitle {
                            Text(subtitle)
                                .font(CleanupFont.caption(11))
                                .foregroundStyle(CleanupTheme.textTertiary)
                        }
                    }

                    Spacer(minLength: 0)

                    Button(isSelected ? "Selected" : "Select duplicates") {
                        onToggleSelection()
                    }
                    .font(CleanupFont.body(14))
                    .foregroundStyle(isSelected ? .white : accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? accent.opacity(0.92) : accent.opacity(0.12))
                    )
                    .buttonStyle(.plain)
                }
                .zIndex(1)

                Button(action: onOpen) {
                    ClusterPreviewBoard(cluster: cluster, accent: accent)
                }
                .frame(height: previewBoardHeight)
                .clipped()
                .buttonStyle(.plain)

                Divider()
                    .overlay(Color.white.opacity(0.06))

                footerBar
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(duplicateSummary)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
                Text("Open this set to choose the best image")
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(CleanupTheme.textTertiary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Review")
                    .font(CleanupFont.badge(12))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(accent)
        }
    }

    private var duplicateSummary: String {
        if duplicateCount == 1 {
            return "Keep 1 image, remove 1 duplicate"
        }
        return "Keep 1 image, remove \(duplicateCount) duplicates"
    }

    private var previewBoardHeight: CGFloat {
        min(cluster.assets.count, 5) <= 2 ? 174 : 194
    }
}

private struct ClusterPreviewBoard: View {
    let cluster: MediaCluster
    let accent: Color

    var body: some View {
        ZStack {
            boardBackground

            GeometryReader { proxy in
                let spacing: CGFloat = 10
                let boardHeight = proxy.size.height
                let leadWidth = leadColumnWidth(totalWidth: proxy.size.width, spacing: spacing)
                let trailingWidth = max(proxy.size.width - leadWidth - spacing, 0)
                let trailingTileSize = max((boardHeight - spacing) / 2, 0)

                HStack(spacing: spacing) {
                    ClusterPreviewTile(
                        localIdentifier: previewAssets.first?.id,
                        badgeText: "Keep",
                        accent: accent,
                        overlayCount: nil,
                        targetPointSize: 180
                    )
                    .frame(width: leadWidth, height: boardHeight)

                    if previewAssets.count > 1 {
                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                ForEach(0..<2, id: \.self) { index in
                                    secondaryTile(at: index, totalWidth: trailingWidth, spacing: spacing, tileHeight: trailingTileSize)
                                }
                            }

                            HStack(spacing: spacing) {
                                ForEach(2..<4, id: \.self) { index in
                                    secondaryTile(at: index, totalWidth: trailingWidth, spacing: spacing, tileHeight: trailingTileSize)
                                }
                            }
                        }
                        .frame(width: trailingWidth, height: boardHeight)
                    }
                }
            }
        }
        .padding(12)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var previewAssets: [MediaAssetRecord] {
        Array(cluster.assets.prefix(5))
    }

    private var duplicatePreviewAssets: [MediaAssetRecord] {
        Array(previewAssets.dropFirst())
    }

    private var boardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.black.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04))
            )
    }

    private func leadColumnWidth(totalWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        if previewAssets.count <= 2 {
            return max((totalWidth - spacing) / 2, 0)
        }
        return floor(totalWidth * 0.48)
    }

    private func tileWidth(totalWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        max((totalWidth - spacing) / 2, 0)
    }

    @ViewBuilder
    private func secondaryTile(at index: Int, totalWidth: CGFloat, spacing: CGFloat, tileHeight: CGFloat) -> some View {
        if duplicatePreviewAssets.indices.contains(index) {
            let asset = duplicatePreviewAssets[index]
            ClusterPreviewTile(
                localIdentifier: asset.id,
                badgeText: nil,
                accent: accent,
                overlayCount: overlayCount(for: index),
                targetPointSize: 112
            )
            .frame(width: tileWidth(totalWidth: totalWidth, spacing: spacing), height: tileHeight)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.03))
                )
                .frame(width: tileWidth(totalWidth: totalWidth, spacing: spacing), height: tileHeight)
        }
    }

    private func overlayCount(for index: Int) -> Int? {
        let extraCount = cluster.assets.count - previewAssets.count
        let isLastPreview = index == min(max(duplicatePreviewAssets.count - 1, 0), 3)
        return isLastPreview && extraCount > 0 ? extraCount : nil
    }
}

private struct ClusterPreviewTile: View {
    let localIdentifier: String?
    let badgeText: String?
    let accent: Color
    let overlayCount: Int?
    var targetPointSize: CGFloat = 112

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let localIdentifier {
                PhotoThumbnailView(localIdentifier: localIdentifier, targetPointSize: targetPointSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            }

            if let overlayCount {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.52))
                    .overlay {
                        Text("+\(overlayCount)")
                            .font(CleanupFont.sectionTitle(18))
                            .foregroundStyle(.white)
                    }
            }

            if let badgeText {
                VStack {
                    Spacer()
                    HStack {
                        Text(badgeText)
                            .font(CleanupFont.badge(10))
                            .foregroundStyle(Color(hex: "#13331E"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#7DFF99"), in: Capsule(style: .continuous))
                        Spacer()
                    }
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ClusterDetailReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    let sourceCategory: DashboardCategoryKind
    let clusterID: String
    let displayTitle: String

    @State private var selectedAssetIDs: Set<String> = []
    @State private var isDeleting = false
    @State private var statusMessage: String?
    @State private var previewAssetID: String?
    @State private var previewSelection = 0

    private var cluster: MediaCluster? {
        appFlow.mediaClusters(for: sourceCategory).first { $0.id == clusterID }
    }

    private var assets: [MediaAssetRecord] {
        cluster?.assets ?? []
    }

    private var defaultKeepAssetID: String? {
        assets.first?.id
    }

    private var deletableAssetIDs: [String] {
        let selected = selectedAssetIDs.subtracting([defaultKeepAssetID].compactMap { $0 })
        return assets
            .map(\.id)
            .filter { selected.contains($0) }
    }

    var body: some View {
        FeatureScreen(
            title: cluster?.title ?? displayTitle,
            leadingSymbol: "chevron.left",
            trailingSymbol: nil,
            leadingAction: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                if assets.isEmpty {
                    emptyState
                } else {
                    actionBar
                    selectionGrid
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: assets.map(\.id)) {
            syncSelection()
        }
        .sheet(
            isPresented: Binding(
                get: { previewAssetID != nil },
                set: { isPresented in
                    if !isPresented {
                        previewAssetID = nil
                    }
                }
            )
        ) {
            if let selectedAssetID = previewAssetID {
                ClusterZoomPreviewSheet(
                    assets: assets,
                    initialAssetID: selectedAssetID,
                    selectedAssetIDs: $selectedAssetIDs,
                    accent: sourceCategory.accent
                )
            }
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(cluster?.subtitle ?? "Exact visual match cluster")
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)

                Text(detailSummary)
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)

                Text("Select duplicates to remove. The first image stays protected as the default keep choice.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)

                if let statusMessage {
                    Text(statusMessage)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(sourceCategory.accent)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(selectedAssetIDs.count == duplicateCandidates.count ? "Clear" : "Select all") {
                if selectedAssetIDs.count == duplicateCandidates.count {
                    selectedAssetIDs.removeAll()
                } else {
                    selectedAssetIDs = Set(duplicateCandidates.map(\.id))
                }
            }
            .font(CleanupFont.body(14))
            .foregroundStyle(sourceCategory.accent)
            .buttonStyle(.plain)

            Spacer()

            if isDeleting {
                ProgressView()
                    .tint(.white)
            } else {
                PrimaryCTAButton(title: deletableAssetIDs.isEmpty ? "Delete Selected" : "Delete \(deletableAssetIDs.count) Selected") {
                    Task {
                        guard !deletableAssetIDs.isEmpty else { return }
                        isDeleting = true
                        let deleteCount = deletableAssetIDs.count
                        let success = await appFlow.deleteAssets(with: deletableAssetIDs)
                        isDeleting = false

                        if success {
                            statusMessage = "Deleted \(deleteCount) item(s)."
                            dismiss()
                        } else {
                            statusMessage = "Delete failed. Please try again."
                        }
                    }
                }
                .disabled(deletableAssetIDs.isEmpty)
                .opacity(deletableAssetIDs.isEmpty ? 0.5 : 1)
                .frame(maxWidth: 220)
            }
        }
    }

    private var emptyState: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("This cluster is empty now")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                Text("The selected duplicates were removed from your library.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var selectionGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    ClusterDetailAssetCell(
                        asset: asset,
                        isProtected: index == 0,
                        isSelected: selectedAssetIDs.contains(asset.id),
                        accent: sourceCategory.accent,
                        onToggle: {
                            toggleSelection(for: asset, isProtected: index == 0)
                        },
                        onZoom: {
                            previewAssetID = asset.id
                        }
                    )
                    .onAppear {
                        PhotoThumbnailView.startCaching(localIdentifiers: detailPreheatIdentifiers(around: index))
                    }
                    .onDisappear {
                        PhotoThumbnailView.stopCaching(localIdentifiers: detailPreheatIdentifiers(around: index))
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var gridColumns: [GridItem] {
        let count = assets.count <= 4 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var detailSummary: String {
        if deletableAssetIDs.count == 1 {
            return "1 duplicate selected for deletion"
        }
        return "\(deletableAssetIDs.count) duplicates selected for deletion"
    }

    private var duplicateCandidates: [MediaAssetRecord] {
        Array(assets.dropFirst())
    }

    private func syncSelection() {
        let validIDs = Set(duplicateCandidates.map(\.id))
        selectedAssetIDs.formIntersection(validIDs)
        if selectedAssetIDs.isEmpty, let firstDuplicate = duplicateCandidates.first?.id {
            selectedAssetIDs = [firstDuplicate]
        }
        if let previewAssetID, assets.contains(where: { $0.id == previewAssetID }) == false {
            self.previewAssetID = nil
        }
    }

    private func toggleSelection(for asset: MediaAssetRecord, isProtected: Bool) {
        guard isProtected == false else { return }

        if selectedAssetIDs.contains(asset.id) {
            selectedAssetIDs.remove(asset.id)
        } else {
            selectedAssetIDs.insert(asset.id)
        }
    }

    private func detailPreheatIdentifiers(around index: Int) -> [String] {
        let radius = 8
        let lowerBound = max(index - radius, 0)
        let upperBound = min(index + radius, assets.count - 1)
        guard lowerBound <= upperBound else { return [] }
        return Array(assets[lowerBound...upperBound]).map(\.id)
    }
}

private struct VideoPreviewRoute: Identifiable, Hashable {
    let id: String
}

private struct DragSelectGestureModifier: ViewModifier {
    let enabled: Bool
    let coordinateSpace: String
    @ObservedObject var dragSelect: DragSelectState
    let assets: [MediaAssetRecord]
    @Binding var selectedAssetIDs: Set<String>

    func body(content: Content) -> some View {
        if enabled {
            // Long-press-then-drag: a quick vertical swipe still scrolls,
            // but press & hold (~0.25s) enters drag-select mode and every
            // cell the finger passes over is toggled in sync with the
            // anchor's initial state (Photos-style). Haptic on enter.
            let gesture = LongPressGesture(minimumDuration: 0.22)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace)))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag?):
                        if !dragSelect.isDragging {
                            dragSelect.orderedIDs = assets.map(\.id)
                            dragSelect.dragBegan(at: drag.startLocation, currentSelection: selectedAssetIDs)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        if let newSelection = dragSelect.dragMoved(to: drag.location) {
                            selectedAssetIDs = newSelection
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    if let finalSelection = dragSelect.dragEnded() {
                        selectedAssetIDs = finalSelection
                    }
                }
            content.simultaneousGesture(gesture)
        } else {
            content
        }
    }
}

private struct VideoGalleryCell: View {
    let asset: MediaAssetRecord
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void
    let onExpand: () -> Void

    private var durationLabel: String {
        let total = Int(asset.duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var sizeLabel: String {
        ByteCountFormatter.cleanupString(fromByteCount: asset.sizeInBytes)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Tile content (tap = toggle selection)
            Button(action: onTap) {
                PhotoThumbnailView(localIdentifier: asset.id, targetPointSize: 420)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                            .shadow(color: .black.opacity(0.6), radius: 4)
                    }
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 5) {
                            Text(durationLabel)
                                .font(CleanupFont.caption(11))
                            Text("·")
                                .font(CleanupFont.caption(11))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(sizeLabel)
                                .font(CleanupFont.caption(11))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.62), in: Capsule(style: .continuous))
                        .padding(8)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // Selection checkmark
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? accent : Color.black.opacity(0.5))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)

            // Expand icon (tap = open preview)
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? accent : Color.white.opacity(0.05), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ScreenshotGalleryCell: View {
    let asset: MediaAssetRecord
    let isSelected: Bool
    let accent: Color

    private var aspectRatio: CGFloat {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 9 / 16 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnailView(localIdentifier: asset.id, targetPointSize: 220)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? accent : Color.black.opacity(0.38))
                .frame(width: 28, height: 28)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(8)
        }
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? accent : Color.white.opacity(0.05), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct VideoZoomPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let assets: [MediaAssetRecord]
    let initialAssetID: String
    @Binding var selectedAssetIDs: Set<String>
    let accent: Color

    @State private var currentIndex: Int = 0

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Preview")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)

                    Spacer()

                    Button(currentSelected ? "Selected" : "Select") {
                        toggleCurrentSelection()
                    }
                    .font(CleanupFont.body(14))
                    .foregroundStyle(currentSelected ? .white : accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(currentSelected ? accent.opacity(0.92) : accent.opacity(0.12))
                    )
                    .buttonStyle(.plain)
                }

                TabView(selection: $currentIndex) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        ZoomableAssetPreview(
                            asset: asset,
                            isProtected: false,
                            isSelected: selectedAssetIDs.contains(asset.id),
                            accent: accent,
                            isVisible: index == currentIndex
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                HStack(spacing: 10) {
                    Text("\(currentIndex + 1) / \(assets.count)")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Spacer()
                    if let current = currentAsset {
                        Text("\(formattedDuration(current.duration)) · \(ByteCountFormatter.cleanupString(fromByteCount: current.sizeInBytes))")
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }
                }

                Text("Swipe to preview, tap Select to mark for deletion.")
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .onAppear {
            currentIndex = max(assets.firstIndex(where: { $0.id == initialAssetID }) ?? 0, 0)
            prefetchNeighbors()
        }
        .onChange(of: currentIndex) { _, _ in
            prefetchNeighbors()
        }
    }

    private var currentAsset: MediaAssetRecord? {
        guard assets.indices.contains(currentIndex) else { return nil }
        return assets[currentIndex]
    }

    private var currentSelected: Bool {
        guard let currentAsset else { return false }
        return selectedAssetIDs.contains(currentAsset.id)
    }

    private func toggleCurrentSelection() {
        guard let currentAsset else { return }
        if selectedAssetIDs.contains(currentAsset.id) {
            selectedAssetIDs.remove(currentAsset.id)
        } else {
            selectedAssetIDs.insert(currentAsset.id)
        }
    }

    private func prefetchNeighbors() {
        var ids: [String] = []
        for offset in [-2, -1, 1, 2] {
            let idx = currentIndex + offset
            guard assets.indices.contains(idx), assets[idx].mediaType == .video else { continue }
            ids.append(assets[idx].id)
        }
        VideoPrefetcher.shared.prefetch(identifiers: ids)

        // Keep a small window around the current index; drop the rest.
        var keep = Set(ids)
        if let current = currentAsset { keep.insert(current.id) }
        VideoPrefetcher.shared.keep(keep)
    }

    private func formattedDuration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ClusterZoomPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let assets: [MediaAssetRecord]
    let initialAssetID: String
    @Binding var selectedAssetIDs: Set<String>
    let accent: Color

    @State private var currentIndex = 0

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Preview")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)

                    Spacer()

                    Button(currentAssetProtected ? "Protected" : (currentAssetSelected ? "Selected" : "Select")) {
                        toggleCurrentSelection()
                    }
                    .font(CleanupFont.body(14))
                    .foregroundStyle(currentAssetProtected ? CleanupTheme.textSecondary : (currentAssetSelected ? .white : accent))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(currentAssetProtected ? Color.white.opacity(0.06) : (currentAssetSelected ? accent.opacity(0.92) : accent.opacity(0.12)))
                    )
                    .buttonStyle(.plain)
                    .disabled(currentAssetProtected)
                }

                TabView(selection: $currentIndex) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        ZoomableAssetPreview(
                            asset: asset,
                            isProtected: index == 0,
                            isSelected: selectedAssetIDs.contains(asset.id),
                            accent: accent,
                            isVisible: index == currentIndex
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, _ in
                        Capsule(style: .continuous)
                            .fill(index == currentIndex ? accent : Color.white.opacity(0.14))
                            .frame(width: index == currentIndex ? 20 : 8, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text(helpText)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .onAppear {
            currentIndex = max(assets.firstIndex(where: { $0.id == initialAssetID }) ?? 0, 0)
            prefetchNeighbors()
        }
        .onChange(of: currentIndex) { _, _ in
            prefetchNeighbors()
        }
    }

    private func prefetchNeighbors() {
        var ids: [String] = []
        for offset in [-2, -1, 1, 2] {
            let idx = currentIndex + offset
            guard assets.indices.contains(idx), assets[idx].mediaType == .video else { continue }
            ids.append(assets[idx].id)
        }
        VideoPrefetcher.shared.prefetch(identifiers: ids)
        var keep = Set(ids)
        if let current = currentAsset { keep.insert(current.id) }
        VideoPrefetcher.shared.keep(keep)
    }

    private var currentAsset: MediaAssetRecord? {
        guard assets.indices.contains(currentIndex) else { return nil }
        return assets[currentIndex]
    }

    private var currentAssetProtected: Bool {
        currentIndex == 0
    }

    private var currentAssetSelected: Bool {
        guard let currentAsset else { return false }
        return selectedAssetIDs.contains(currentAsset.id)
    }

    private var helpText: String {
        if currentAssetProtected {
            return "The first item stays protected as the keep choice."
        }
        return "Swipe to compare, then tick duplicates you want to remove."
    }

    private func toggleCurrentSelection() {
        guard let currentAsset, currentAssetProtected == false else { return }
        if selectedAssetIDs.contains(currentAsset.id) {
            selectedAssetIDs.remove(currentAsset.id)
            return
        }
        selectedAssetIDs.insert(currentAsset.id)
    }
}

private struct ClusterDetailAssetCell: View {
    let asset: MediaAssetRecord
    let isProtected: Bool
    let isSelected: Bool
    let accent: Color
    let onToggle: () -> Void
    let onZoom: () -> Void

    private var isVideo: Bool { asset.mediaType == .video }

    var body: some View {
        ZStack {
            PhotoThumbnailView(localIdentifier: asset.id, targetPointSize: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Play icon overlay for videos
            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            }

            VStack {
                HStack {
                    Button(action: onZoom) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.4), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isProtected == false {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? accent : Color.black.opacity(0.46))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }

                Spacer()

                // Bottom row: Keep badge + video duration
                HStack {
                    if isProtected {
                        Text("Keep")
                            .font(CleanupFont.badge(10))
                            .foregroundStyle(Color(hex: "#13331E"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#7DFF99"), in: Capsule(style: .continuous))
                    }

                    Spacer()

                    if isVideo {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7))
                            Text(formattedDuration(asset.duration))
                                .font(CleanupFont.badge(10))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6), in: Capsule(style: .continuous))
                    }
                }
            }
            .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isProtected || isSelected ? accent : Color.white.opacity(0.06), lineWidth: isProtected || isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            onToggle()
        }
    }

    private func formattedDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ZoomableAssetPreview: View {
    let asset: MediaAssetRecord
    let isProtected: Bool
    let isSelected: Bool
    let accent: Color
    let isVisible: Bool

    init(asset: MediaAssetRecord, isProtected: Bool, isSelected: Bool, accent: Color, isVisible: Bool = true) {
        self.asset = asset
        self.isProtected = isProtected
        self.isSelected = isSelected
        self.accent = accent
        self.isVisible = isVisible
    }

    private var isVideo: Bool { asset.mediaType == .video }

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if isVideo {
                    VideoPlayerView(localIdentifier: asset.id, autoPlay: isVisible)
                } else {
                    PhotoPreviewView(localIdentifier: asset.id)
                }
            }
            .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    if isProtected {
                        Text("Best")
                            .font(CleanupFont.badge(10))
                            .foregroundStyle(Color(hex: "#13331E"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#7DFF99"), in: Capsule(style: .continuous))
                    }
                    if isVideo {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text(formattedDuration(asset.duration))
                                .font(CleanupFont.badge(10))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule(style: .continuous))
                    }
                }
                .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                if isProtected == false {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? accent : Color.black.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(12)
                }
            }
            .frame(height: 520)
        }
    }

    private func formattedDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

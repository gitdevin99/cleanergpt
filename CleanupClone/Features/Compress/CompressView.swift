import SwiftUI

private enum CompressionMediaSection: String, CaseIterable, Identifiable {
    case photos
    case videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: "Photos"
        case .videos: "Videos"
        }
    }

    var singularTitle: String {
        switch self {
        case .photos: "photo"
        case .videos: "video"
        }
    }
}

private enum CompressionQualityChoice: String, CaseIterable, Identifiable {
    case high
    case medium
    case percentage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "High Quality"
        case .medium: "Medium Quality"
        case .percentage: "Percentage"
        }
    }
}

private enum CompressionStage {
    case selection
    case quality
    case processing
    case success
}

private struct CompressionRunSummary {
    let compressedCount: Int
    let compressedBytes: Int64
    let savedBytes: Int64
    let originalsDeleted: Bool
    let deleteSucceeded: Bool
}

struct CompressView: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Environment(\.dismiss) private var dismiss

    private static let assetPageSize = 36
    private static let assetPrefetchThreshold = 8

    @State private var selectedSection: CompressionMediaSection = .photos
    @State private var selectedQuality: CompressionQualityChoice = .medium
    @State private var customPercentage: Double = 60
    @State private var selectedAssetIDs: Set<String> = []
    @State private var stage: CompressionStage = .selection
    @State private var isRunningBatch = false
    @State private var showDeletePrompt = false
    @State private var runSummary: CompressionRunSummary?
    @State private var displayedAssetLimit = Self.assetPageSize
    /// Local ID of the asset the user tapped to expand in the fullscreen
    /// preview sheet. `nil` while the sheet is closed.
    @State private var previewAssetID: String?
    @StateObject private var dragSelect = DragSelectState()

    /// Use cached arrays from AppFlow instead of recomputing on every render.
    private var visibleAssets: [MediaAssetRecord] {
        switch selectedSection {
        case .photos:
            appFlow.cachedCompressiblePhotos
        case .videos:
            appFlow.cachedCompressibleVideos
        }
    }

    private var pagedVisibleAssets: [MediaAssetRecord] {
        Array(visibleAssets.prefix(displayedAssetLimit))
    }

    private var hasMoreVisibleAssets: Bool {
        visibleAssets.count > displayedAssetLimit
    }

    private var selectedAssets: [MediaAssetRecord] {
        guard !selectedAssetIDs.isEmpty else { return [] }
        return visibleAssets.filter { selectedAssetIDs.contains($0.id) }
    }

    private var leadAsset: MediaAssetRecord? {
        selectedAssets.first
    }

    private var estimatedSavedBytes: Int64 {
        selectedAssets.reduce(into: Int64(0)) { partial, asset in
            partial += max(0, asset.sizeInBytes - estimatedCompressedBytes(for: asset))
        }
    }

    private var totalVisibleBytes: Int64 {
        visibleAssets.reduce(into: Int64(0)) { $0 += $1.sizeInBytes }
    }

    private var totalVisibleEstimatedSavedBytes: Int64 {
        visibleAssets.reduce(into: Int64(0)) { partial, asset in
            partial += max(0, asset.sizeInBytes - estimatedCompressedBytes(for: asset))
        }
    }

    private var selectionButtonTitle: String {
        guard !selectedAssets.isEmpty else { return "Select files to compress" }
        let count = selectedAssets.count
        let unit = count == 1 ? selectedSection.singularTitle : selectedSection.title.lowercased()
        return "Compress \(count) \(unit)"
    }

    private var qualityButtonTitle: String {
        let saved = ByteCountFormatter.cleanupString(fromByteCount: estimatedSavedBytes)
        return selectedAssets.isEmpty ? "Compress" : "Compress and save \(saved)"
    }

    private var toolbarTrailingSymbol: String {
        stage == .selection ? "arrow.clockwise" : "xmark"
    }

    private var shouldShowFloatingSelectionButton: Bool {
        stage == .selection && !selectedAssets.isEmpty && appFlow.photoAuthorization.isReadable
    }

    var body: some View {
        FeatureScreen(
            title: "Compress",
            leadingSymbol: "chevron.left",
            trailingSymbol: toolbarTrailingSymbol,
            leadingAction: { handleLeadingAction() },
            trailingAction: { handleTrailingAction() }
        ) {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !appFlow.photoAuthorization.isReadable {
                            permissionCard
                        } else {
                            switch stage {
                            case .selection:
                                selectionContent
                            case .quality:
                                qualityContent
                            case .processing:
                                processingContent
                            case .success:
                                successContent
                            }
                        }
                    }
                    .padding(.bottom, shouldShowFloatingSelectionButton ? 136 : 24)
                }
                .scrollDisabled(dragSelect.isDragging)

                if showDeletePrompt {
                    deleteOriginalOverlay
                }
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) {
            if shouldShowFloatingSelectionButton {
                floatingSelectionButton
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
        }
        // Fullscreen preview when the user taps the expand icon on a
        // thumbnail. We reuse the same sheet the flat screenshot/video
        // gallery uses so selection, swipe-to-clean, and the filmstrip
        // all behave identically across the app.
        .sheet(item: Binding(
            get: { previewAssetID.map { VideoPreviewRoute(id: $0) } },
            set: { previewAssetID = $0?.id }
        )) { route in
            VideoZoomPreviewSheet(
                assets: visibleAssets,
                initialAssetID: route.id,
                selectedAssetIDs: $selectedAssetIDs,
                accent: CleanupTheme.electricBlue
            )
            .environmentObject(appFlow)
        }
        .onChange(of: selectedSection) { _, _ in
            selectedAssetIDs.removeAll()
            resetVisibleAssetWindow()
            previewAssetID = nil
            if stage != .selection {
                stage = .selection
            }
        }
        .onChange(of: stage) { _, newStage in
            if newStage != .selection {
                previewAssetID = nil
            }
        }
        .task {
            // Only kick off a scan if we have NOTHING cached yet.
            // `.firstLoad` is a hard no-op once the app has scanned
            // the library at least once, which prevents the "went
            // into Compress → everything re-indexed" footgun while
            // Duplicates refinement is still running.
            if appFlow.photoAuthorization.isReadable,
               appFlow.mediaAssets(for: .videos).isEmpty,
               appFlow.compressiblePhotoAssets().isEmpty {
                await appFlow.scanLibrary(trigger: .firstLoad)
            }
            resetVisibleAssetWindow()
        }
        // Re-check permission state on return from background so the
        // "Open Settings" card resolves itself after the user flips the
        // toggle and comes back.
        //
        // IMPORTANT: we intentionally do NOT call `scanLibrary()` here
        // anymore. `didBecomeActive` fires on every sheet/preview/
        // system-dialog dismissal (permission prompts, share sheets,
        // the PHAsset preview sheet, even just swiping down the
        // Control Center). Wiring a scan to it meant every one of
        // those innocuous events wiped the in-flight refinement state
        // and re-ran the whole 30k-asset Vision pipeline. The photo
        // library change observer picks up real library edits via
        // `applyIncrementalPhotoLibraryChange`, so we don't need to
        // rescan just because the app foregrounded.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            appFlow.refreshPermissions()
        }
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryCard
            sectionPicker
            selectionSummaryCard

            if visibleAssets.isEmpty {
                emptyCard
            } else {
                assetsGrid
            }
        }
    }

    private var qualityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            previewCard
            qualityPanel
            qualityActionButton
        }
    }

    private var processingContent: some View {
        GlassCard(cornerRadius: 30) {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(CleanupTheme.electricBlue.opacity(0.12))
                        .frame(width: 112, height: 112)

                    Circle()
                        .trim(from: 0.08, to: 0.82)
                        .stroke(
                            LinearGradient(colors: [CleanupTheme.electricBlue, CleanupTheme.accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 94, height: 94)
                        .rotationEffect(.degrees(isRunningBatch ? 360 : 0))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: isRunningBatch)

                    Image(systemName: selectedSection == .photos ? "photo.stack.fill" : "film.stack.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Compressing your \(selectedSection.title.lowercased())")
                        .font(CleanupFont.sectionTitle(26))
                        .foregroundStyle(.white)
                    Text("We are creating optimized copies, calculating saved space, and finishing the cleanup flow.")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Text(ByteCountFormatter.cleanupString(fromByteCount: estimatedSavedBytes))
                    .font(CleanupFont.hero(34))
                    .foregroundStyle(CleanupTheme.electricBlue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    private var successContent: some View {
        GlassCard(cornerRadius: 30) {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(CleanupTheme.accentGreen.opacity(0.14))
                        .frame(width: 118, height: 118)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(CleanupTheme.accentGreen)
                }

                VStack(spacing: 6) {
                    Text("Congratulations!")
                        .font(CleanupFont.hero(34))
                        .foregroundStyle(.white)
                    Text(successSubtitle)
                        .font(CleanupFont.body(16))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    statRow(
                        title: "Compressed",
                        subtitle: "\(runSummary?.compressedCount ?? 0) item(s)",
                        value: ByteCountFormatter.cleanupString(fromByteCount: runSummary?.compressedBytes ?? 0),
                        tint: CleanupTheme.electricBlue
                    )
                    statRow(
                        title: "Freed Up",
                        subtitle: successFreedSubtitle,
                        value: ByteCountFormatter.cleanupString(fromByteCount: runSummary?.savedBytes ?? 0),
                        tint: CleanupTheme.accentGreen
                    )
                }

                GlassProminentCTA {
                    resetFlowAfterSuccess()
                } label: {
                    Text("Great!")
                        .font(CleanupFont.body(18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(visibleAssets.count) \(selectedSection.title.lowercased()) · \(ByteCountFormatter.cleanupString(fromByteCount: totalVisibleBytes))")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.electricBlue)
                    Text("Save up to \(ByteCountFormatter.cleanupString(fromByteCount: totalVisibleEstimatedSavedBytes))")
                        .font(CleanupFont.badge(12))
                        .foregroundStyle(CleanupTheme.accentGreen)
                }
                Spacer(minLength: 0)
                if let message = appFlow.compressionMessage {
                    Text(message)
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
        }
    }

    private var permissionCard: some View {
        // See DashboardView.permissionCard for why we branch on
        // `needsSettingsRedirect`: iOS won't re-show the system prompt
        // after a user has denied access, so the "Allow Photos Access"
        // button silently no-ops until we route to Settings instead.
        let deniedPath = appFlow.photoAuthorization.needsSettingsRedirect

        return GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(deniedPath
                    ? "Photo access was turned off. Open Settings to turn it back on so we can compress your files."
                    : "Photo access is required to compress files.")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(.white)

                PrimaryCTAButton(title: deniedPath ? "Open Settings" : "Allow Photos Access") {
                    if deniedPath {
                        appFlow.openSystemSettings()
                    } else {
                        Task { _ = await appFlow.requestPhotoAccessIfNeeded() }
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("No \(selectedSection.title.lowercased()) found yet")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                Text("Refresh the library scan or switch sections to review other compressible files.")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Compression Section", selection: $selectedSection) {
            ForEach(CompressionMediaSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    private var selectionSummaryCard: some View {
        GlassCard(cornerRadius: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedAssets.isEmpty ? "Choose your \(selectedSection.title.lowercased())" : "\(selectedAssets.count) \(selectionUnitLabel()) selected")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(.white)
                    if !selectedAssets.isEmpty {
                        Text(ByteCountFormatter.cleanupString(fromByteCount: selectedAssets.reduce(0) { $0 + $1.sizeInBytes }))
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }
                }

                Spacer()

                Text(ByteCountFormatter.cleanupString(fromByteCount: estimatedSavedBytes))
                    .font(CleanupFont.sectionTitle(17))
                    .foregroundStyle(CleanupTheme.electricBlue)
            }
        }
    }

    private static let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var assetsGrid: some View {
        let paged = pagedVisibleAssets

        return VStack(spacing: 14) {
            LazyVGrid(columns: Self.gridColumns, spacing: 12) {
                ForEach(paged) { asset in
                    compressAssetCell(asset)
                        .modifier(DragSelectCellModifier(id: asset.id, coordinateSpace: "compressGrid"))
                        .onAppear {
                            loadMoreAssetsIfNeeded(currentAssetID: asset.id)
                        }
                }
            }
            .coordinateSpace(name: "compressGrid")
            .onPreferenceChange(DragSelectCellFrameKey.self) { frames in
                dragSelect.cellFrames = frames
            }
            .simultaneousGesture(
                // Higher minimumDistance so light touches/vertical scrolls don't
                // fire drag-select. 40pt matches Photos.app's drag threshold.
                DragGesture(minimumDistance: 40, coordinateSpace: .named("compressGrid"))
                    .onChanged { value in
                        // Only engage drag-select when the gesture is clearly
                        // horizontal/diagonal — vertical-dominant drags belong
                        // to the ScrollView.
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        if !dragSelect.isDragging {
                            guard dx > dy * 0.6 else { return }
                            dragSelect.orderedIDs = paged.map(\.id)
                            dragSelect.dragBegan(at: value.startLocation, currentSelection: selectedAssetIDs)
                        }
                        if let newSelection = dragSelect.dragMoved(to: value.location) {
                            selectedAssetIDs = newSelection
                        }
                    }
                    .onEnded { _ in
                        if let finalSelection = dragSelect.dragEnded() {
                            selectedAssetIDs = finalSelection
                        }
                    }
            )

            if hasMoreVisibleAssets {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CleanupTheme.electricBlue)
                    Text("Loading more \(selectedSection.title.lowercased())")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func compressAssetCell(_ asset: MediaAssetRecord) -> some View {
        let isSelected = selectedAssetIDs.contains(asset.id)
        // Use a ZStack + tap gesture on the card body so we can layer a
        // separate "expand" button on top without the two fighting the
        // hit-testing rules of nested SwiftUI Buttons. The card itself
        // still toggles selection; the overlay button opens the
        // fullscreen preview sheet.
        ZStack(alignment: .topLeading) {
            compressAssetCardContent(asset, isSelected: isSelected)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(for: asset.id)
                }

            Button {
                previewAssetID = asset.id
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Preview")
        }
    }

    private var floatingSelectionButton: some View {
        GlassProminentCTA {
            stage = .quality
        } label: {
            Text(selectionButtonTitle)
                .font(CleanupFont.body(18))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
    }

    private var previewCard: some View {
        GlassCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .bottomLeading) {
                    if let leadAsset {
                        PhotoThumbnailView(localIdentifier: leadAsset.id)
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                    }

                    ResultBadge(
                        title: selectedQualityPreviewTitle,
                        tint: CleanupTheme.electricBlue
                    )
                    .padding(16)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Select \(selectedSection.singularTitle) quality after compression")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)
                    Text("You selected \(selectedAssets.count) \(selectionUnitLabel()) to compress.")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }
        }
    }

    private var qualityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(CompressionQualityChoice.allCases) { choice in
                Button {
                    selectedQuality = choice
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choice.title)
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                            Text(description(for: choice))
                                .font(CleanupFont.caption(12))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: selectedQuality == choice ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selectedQuality == choice ? CleanupTheme.electricBlue : CleanupTheme.textSecondary)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if selectedQuality == .percentage {
                GlassCard(cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Target size")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(Int(customPercentage))% of original")
                                .font(CleanupFont.badge(13))
                                .foregroundStyle(CleanupTheme.electricBlue)
                        }

                        Slider(value: $customPercentage, in: 20...90, step: 5)
                            .tint(CleanupTheme.electricBlue)

                        Text("Lower percentages save more space but reduce quality further.")
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var qualityActionButton: some View {
        GlassProminentCTA {
            if !EntitlementStore.shared.isPremium,
               EntitlementStore.shared.remaining(.videoCompress) == 0 {
                appFlow.requestUpgrade(for: .videoCompress)
                return
            }
            showDeletePrompt = true
        } label: {
            Text(qualityButtonTitle)
                .font(CleanupFont.body(18))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .disabled(selectedAssets.isEmpty)
        .opacity(selectedAssets.isEmpty ? 0.55 : 1)
    }

    private var deleteOriginalOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showDeletePrompt = false }

            GlassCard(cornerRadius: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Do you want to delete the original \(selectedSection.singularTitle) from Photos?")
                        .font(CleanupFont.sectionTitle(24))
                        .foregroundStyle(.white)

                    Text("Compressed copies will be saved to your library. Deleting originals frees real storage on the device.")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)

                    HStack(spacing: 12) {
                        Button {
                            startCompression(deleteOriginals: false)
                        } label: {
                            Text("No")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        Button {
                            startCompression(deleteOriginals: true)
                        } label: {
                            Text("Yes, Delete")
                                .font(CleanupFont.body(16))
                                .foregroundStyle(Color(hex: "#FF8B7B"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "#FF8B7B").opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(6)
            }
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
    }

    private func statRow(title: String, subtitle: String, value: String, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CleanupFont.body(15))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }

            Spacer()

            Text(value)
                .font(CleanupFont.badge(13))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func compressAssetCardContent(_ asset: MediaAssetRecord, isSelected: Bool) -> some View {
        let estimate = max(0, asset.sizeInBytes - estimatedCompressedBytes(for: asset))

        return GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    PhotoThumbnailView(localIdentifier: asset.id)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(isSelected ? CleanupTheme.electricBlue : .white.opacity(0.82))
                        .padding(8)
                }

                HStack(spacing: 6) {
                    Text(asset.formattedSize)
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Text(appFlow.compressionResults[asset.id].map { ByteCountFormatter.cleanupString(fromByteCount: $0.compressedBytes) } ?? ByteCountFormatter.cleanupString(fromByteCount: estimatedCompressedBytes(for: asset)))
                        .font(CleanupFont.caption(11))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                    if let result = appFlow.compressionResults[asset.id] {
                        Text("−\(ByteCountFormatter.cleanupString(fromByteCount: result.savedBytes))")
                            .font(CleanupFont.badge(11))
                            .foregroundStyle(CleanupTheme.accentGreen)
                    } else {
                        Text("−\(ByteCountFormatter.cleanupString(fromByteCount: estimate))")
                            .font(CleanupFont.badge(11))
                            .foregroundStyle(CleanupTheme.electricBlue)
                    }
                }
            }
        }
    }

    private var successSubtitle: String {
        guard let runSummary else { return "Your storage cleanup is complete." }
        if runSummary.originalsDeleted && runSummary.deleteSucceeded {
            return "You compressed your files and freed up storage on this device."
        }
        return "Compressed copies were created successfully. Your originals stayed in Photos."
    }

    private var successFreedSubtitle: String {
        guard let runSummary else { return "0 more space" }
        if runSummary.originalsDeleted && runSummary.deleteSucceeded {
            return "Originals removed after compression"
        }
        return "Originals kept in Photos"
    }

    private var compressedOutputBytes: Int64 {
        selectedAssets.reduce(0) { partial, asset in
            partial + (appFlow.compressionResults[asset.id]?.compressedBytes ?? estimatedCompressedBytes(for: asset))
        }
    }

    private var selectedQualityPreviewTitle: String {
        switch selectedQuality {
        case .high:
            return "High quality"
        case .medium:
            return "Medium quality"
        case .percentage:
            return "\(Int(customPercentage))% size"
        }
    }

    private func handleLeadingAction() {
        switch stage {
        case .selection, .success:
            dismiss()
            appFlow.closeFeature()
        case .quality:
            stage = .selection
        case .processing:
            break
        }
    }

    private func handleTrailingAction() {
        switch stage {
        case .selection:
            // Top-right refresh button — user-initiated, always runs.
            Task { await appFlow.scanLibrary(trigger: .manual) }
        case .quality, .success:
            stage = .selection
        case .processing:
            break
        }
    }

    private func toggleSelection(for assetID: String) {
        if selectedAssetIDs.contains(assetID) {
            selectedAssetIDs.remove(assetID)
        } else {
            selectedAssetIDs.insert(assetID)
        }
    }

    private func description(for choice: CompressionQualityChoice) -> String {
        switch choice {
        case .high:
            return "Keep about 80% of the original size."
        case .medium:
            return "Keep about 55% of the original size."
        case .percentage:
            return "Target \(Int(customPercentage))% of the original size."
        }
    }

    private func resetVisibleAssetWindow() {
        displayedAssetLimit = Self.assetPageSize
    }

    private func loadMoreAssetsIfNeeded(currentAssetID: String) {
        guard visibleAssets.count > displayedAssetLimit else { return }
        let pagedCount = min(displayedAssetLimit, visibleAssets.count)
        let triggerIndex = max(pagedCount - Self.assetPrefetchThreshold, 0)

        // Use the paged slice directly to find the index without creating a new array
        guard let currentIndex = visibleAssets.prefix(pagedCount).firstIndex(where: { $0.id == currentAssetID }) else { return }
        guard currentIndex >= triggerIndex else { return }

        displayedAssetLimit = min(displayedAssetLimit + Self.assetPageSize, visibleAssets.count)
    }

    private func targetRatio(for asset: MediaAssetRecord) -> Double {
        switch selectedQuality {
        case .high:
            return asset.mediaType == .video ? 0.8 : 0.82
        case .medium:
            return asset.mediaType == .video ? 0.55 : 0.6
        case .percentage:
            return customPercentage / 100
        }
    }

    private func estimatedCompressedBytes(for asset: MediaAssetRecord) -> Int64 {
        Int64(Double(asset.sizeInBytes) * targetRatio(for: asset))
    }

    private func videoPreset(for ratio: Double) -> VideoCompressionPreset {
        if ratio >= 0.75 {
            return .high
        } else if ratio >= 0.5 {
            return .medium
        } else {
            return .low
        }
    }

    private func qualityLabel() -> String {
        switch selectedQuality {
        case .high:
            return "High Quality"
        case .medium:
            return "Medium Quality"
        case .percentage:
            return "\(Int(customPercentage))% Size"
        }
    }

    private func photoCompressionQuality() -> CGFloat {
        switch selectedQuality {
        case .high:
            return 0.82
        case .medium:
            return 0.62
        case .percentage:
            return CGFloat(customPercentage / 100)
        }
    }

    private func startCompression(deleteOriginals: Bool) {
        showDeletePrompt = false
        stage = .processing
        Task {
            await runCompression(deleteOriginals: deleteOriginals)
        }
    }

    private func runCompression(deleteOriginals: Bool) async {
        guard !selectedAssets.isEmpty else { return }

        let requested = selectedAssets.count
        let allowed = await MainActor.run { () -> Int in
            appFlow.consumeFreeAllowance(.videoCompress, requested: requested)
        }
        guard allowed > 0 else {
            stage = .selection
            return
        }

        isRunningBatch = true

        let assetsToCompress = Array(selectedAssets.prefix(allowed))
        var successfulIDs: [String] = []
        var savedBytes: Int64 = 0
        var compressedBytes: Int64 = 0

        for asset in assetsToCompress {
            let success: Bool
            if asset.mediaType == .video {
                let ratio = targetRatio(for: asset)
                let preset = videoPreset(for: ratio)
                success = await appFlow.compressVideo(
                    assetID: asset.id,
                    preset: preset,
                    label: qualityLabel(),
                    targetSizeRatio: ratio
                )
            } else {
                success = await appFlow.compressPhoto(
                    assetID: asset.id,
                    quality: photoCompressionQuality(),
                    label: qualityLabel()
                )
            }

            if success, let result = appFlow.compressionResults[asset.id] {
                successfulIDs.append(asset.id)
                savedBytes += result.savedBytes
                compressedBytes += result.compressedBytes
            }
        }

        var deleteSucceeded = false
        if deleteOriginals, !successfulIDs.isEmpty {
            deleteSucceeded = await appFlow.deleteAssets(with: successfulIDs)
        }

        runSummary = CompressionRunSummary(
            compressedCount: successfulIDs.count,
            compressedBytes: compressedBytes,
            savedBytes: deleteOriginals && deleteSucceeded ? savedBytes : 0,
            originalsDeleted: deleteOriginals,
            deleteSucceeded: deleteSucceeded
        )

        isRunningBatch = false
        stage = .success
    }

    private func resetFlowAfterSuccess() {
        selectedAssetIDs.removeAll()
        runSummary = nil
        stage = .selection
    }

    private func selectionUnitLabel() -> String {
        selectedAssets.count == 1 ? selectedSection.singularTitle : selectedSection.title.lowercased()
    }
}

private struct ResultBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(CleanupFont.badge(12))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

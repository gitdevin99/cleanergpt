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
    let savedBytes: Int64
    let originalsDeleted: Bool
    let deleteSucceeded: Bool
}

struct CompressView: View {
    @EnvironmentObject private var appFlow: AppFlow

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

    private var visibleAssets: [MediaAssetRecord] {
        switch selectedSection {
        case .photos:
            appFlow.compressiblePhotoAssets()
        case .videos:
            appFlow.compressibleVideoAssets()
        }
    }

    private var pagedVisibleAssets: [MediaAssetRecord] {
        Array(visibleAssets.prefix(displayedAssetLimit))
    }

    private var hasMoreVisibleAssets: Bool {
        pagedVisibleAssets.count < visibleAssets.count
    }

    private var selectedAssets: [MediaAssetRecord] {
        visibleAssets.filter { selectedAssetIDs.contains($0.id) }
    }

    private var leadAsset: MediaAssetRecord? {
        selectedAssets.first
    }

    private var estimatedSavedBytes: Int64 {
        selectedAssets.reduce(0) { partial, asset in
            partial + max(0, asset.sizeInBytes - estimatedCompressedBytes(for: asset))
        }
    }

    private var totalVisibleBytes: Int64 {
        visibleAssets.reduce(0) { $0 + $1.sizeInBytes }
    }

    private var totalVisibleEstimatedSavedBytes: Int64 {
        visibleAssets.reduce(0) { partial, asset in
            partial + max(0, asset.sizeInBytes - estimatedCompressedBytes(for: asset))
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
        NavigationStack {
            FeatureScreen(
                title: "Compress",
                leadingSymbol: "chevron.left",
                trailingSymbol: toolbarTrailingSymbol,
                leadingAction: { handleLeadingAction() },
                trailingAction: { handleTrailingAction() }
            ) {
                ZStack {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
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
        }
        .onChange(of: selectedSection) { _, _ in
            selectedAssetIDs.removeAll()
            resetVisibleAssetWindow()
            if stage != .selection {
                stage = .selection
            }
        }
        .task {
            if appFlow.photoAuthorization.isReadable, appFlow.mediaAssets(for: .videos).isEmpty, appFlow.compressiblePhotoAssets().isEmpty {
                await appFlow.scanLibrary()
            }
            resetVisibleAssetWindow()
        }
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        value: ByteCountFormatter.cleanupString(fromByteCount: compressedOutputBytes),
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
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Compress your media files")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)

                Text("\(visibleAssets.count) \(selectedSection.title.lowercased()) • \(ByteCountFormatter.cleanupString(fromByteCount: totalVisibleBytes))")
                    .font(CleanupFont.body(18))
                    .foregroundStyle(CleanupTheme.electricBlue)

                Text("Potential savings: \(ByteCountFormatter.cleanupString(fromByteCount: totalVisibleEstimatedSavedBytes))")
                    .font(CleanupFont.badge(13))
                    .foregroundStyle(CleanupTheme.accentGreen)

                if let message = appFlow.compressionMessage {
                    Text(message)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }
        }
    }

    private var permissionCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Photo access is required to compress files.")
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
        GlassCard(cornerRadius: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedAssets.isEmpty ? "Choose your \(selectedSection.title.lowercased())" : "\(selectedAssets.count) \(selectionUnitLabel()) selected")
                        .font(CleanupFont.body(16))
                        .foregroundStyle(.white)
                    Text(selectedAssets.isEmpty ? "Select one or multiple items first." : "Selected size \(ByteCountFormatter.cleanupString(fromByteCount: selectedAssets.reduce(0) { $0 + $1.sizeInBytes }))")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }

                Spacer()

                Text(ByteCountFormatter.cleanupString(fromByteCount: estimatedSavedBytes))
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(CleanupTheme.electricBlue)
            }
        }
    }

    private var assetsGrid: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(pagedVisibleAssets) { asset in
                    Button {
                        toggleSelection(for: asset.id)
                    } label: {
                        assetCard(asset)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        loadMoreAssetsIfNeeded(currentAssetID: asset.id)
                    }
                }
            }

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

    private func assetCard(_ asset: MediaAssetRecord) -> some View {
        let estimate = max(0, asset.sizeInBytes - estimatedCompressedBytes(for: asset))

        return GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    PhotoThumbnailView(localIdentifier: asset.id)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Image(systemName: selectedAssetIDs.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(selectedAssetIDs.contains(asset.id) ? CleanupTheme.electricBlue : .white.opacity(0.82))
                        .padding(10)
                }

                if let result = appFlow.compressionResults[asset.id] {
                    ResultBadge(title: "Saved \(ByteCountFormatter.cleanupString(fromByteCount: result.savedBytes))", tint: CleanupTheme.accentGreen)
                } else {
                    ResultBadge(title: "Save \(ByteCountFormatter.cleanupString(fromByteCount: estimate))", tint: CleanupTheme.electricBlue)
                }

                Text(asset.title)
                    .font(CleanupFont.body(15))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(asset.detailLine)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)

                HStack {
                    Text("Original \(asset.formattedSize)")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    Spacer()
                    Text(appFlow.compressionResults[asset.id].map { "Now \(ByteCountFormatter.cleanupString(fromByteCount: $0.compressedBytes))" } ?? "After \(ByteCountFormatter.cleanupString(fromByteCount: estimatedCompressedBytes(for: asset)))")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(.white.opacity(0.72))
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
            Task { await appFlow.scanLibrary() }
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
        guard hasMoreVisibleAssets else { return }
        guard let currentIndex = pagedVisibleAssets.firstIndex(where: { $0.id == currentAssetID }) else { return }

        let triggerIndex = max(pagedVisibleAssets.count - Self.assetPrefetchThreshold, 0)
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
        isRunningBatch = true

        let assetsToCompress = selectedAssets
        var successfulIDs: [String] = []
        var savedBytes: Int64 = 0

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
            }
        }

        var deleteSucceeded = false
        if deleteOriginals, !successfulIDs.isEmpty {
            deleteSucceeded = await appFlow.deleteAssets(with: successfulIDs)
        }

        runSummary = CompressionRunSummary(
            compressedCount: successfulIDs.count,
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

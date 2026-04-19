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

struct CompressView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    @State private var selectedSection: CompressionMediaSection = .photos
    @State private var selectedQuality: CompressionQualityChoice = .medium
    @State private var customPercentage: Double = 60
    @State private var selectedAssetIDs: Set<String> = []
    @State private var isRunningBatch = false

    private var visibleAssets: [MediaAssetRecord] {
        switch selectedSection {
        case .photos:
            appFlow.compressiblePhotoAssets()
        case .videos:
            appFlow.compressibleVideoAssets()
        }
    }

    private var selectedAssets: [MediaAssetRecord] {
        visibleAssets.filter { selectedAssetIDs.contains($0.id) }
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

    private var estimatedButtonTitle: String {
        let saved = ByteCountFormatter.cleanupString(fromByteCount: estimatedSavedBytes)
        return selectedAssets.isEmpty ? "Select files to compress" : "Compress and save \(saved)"
    }

    var body: some View {
        NavigationStack {
            FeatureScreen(
                title: "Compress",
                leadingSymbol: "chevron.left",
                trailingSymbol: "arrow.clockwise",
                leadingAction: { dismiss() },
                trailingAction: { Task { await appFlow.scanLibrary() } }
            ) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard

                        if !appFlow.photoAuthorization.isReadable {
                            permissionCard
                        } else {
                            sectionPicker
                            qualityPanel
                            selectionSummary

                            if visibleAssets.isEmpty {
                                emptyCard
                            } else {
                                assetsGrid
                                actionButton
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
        .onChange(of: selectedSection) { _, _ in
            selectedAssetIDs.removeAll()
        }
        .task {
            if appFlow.photoAuthorization.isReadable, appFlow.mediaAssets(for: .videos).isEmpty, appFlow.compressiblePhotoAssets().isEmpty {
                await appFlow.scanLibrary()
            }
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Native Apple compression")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)
                Text("\(visibleAssets.count) \(selectedSection.title.lowercased()) • \(ByteCountFormatter.cleanupString(fromByteCount: totalVisibleBytes))")
                    .font(CleanupFont.body(18))
                    .foregroundStyle(CleanupTheme.electricBlue)
                Text("Potential savings: \(ByteCountFormatter.cleanupString(fromByteCount: totalVisibleEstimatedSavedBytes))")
                    .font(CleanupFont.badge(13))
                    .foregroundStyle(CleanupTheme.accentGreen)
                Text("Videos use AVFoundation export presets and file-size limits. Photos use native image re-encoding and save a compressed copy back into the library.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
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

    private var qualityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose compression amount")
                .font(CleanupFont.sectionTitle(20))
                .foregroundStyle(.white)

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

    private var selectionSummary: some View {
        GlassCard(cornerRadius: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedAssets.isEmpty ? "No files selected" : "\(selectedAssets.count) \(selectedSection.title.lowercased()) selected")
                        .font(CleanupFont.body(16))
                        .foregroundStyle(.white)
                    Text(selectedAssets.isEmpty ? "Tap cards below to choose files." : "Selected size \(ByteCountFormatter.cleanupString(fromByteCount: selectedAssets.reduce(0) { $0 + $1.sizeInBytes })) • live savings estimate below.")
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(visibleAssets) { asset in
                Button {
                    toggleSelection(for: asset.id)
                } label: {
                    assetCard(asset)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionButton: some View {
        GlassProminentCTA {
            Task {
                await runCompression()
            }
        } label: {
            HStack {
                if isRunningBatch {
                    ProgressView()
                        .tint(.white)
                }
                Text(estimatedButtonTitle)
                    .font(CleanupFont.body(18))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 18)
        }
        .disabled(selectedAssets.isEmpty || isRunningBatch)
        .opacity(selectedAssets.isEmpty ? 0.55 : 1)
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
                        .foregroundStyle(selectedAssetIDs.contains(asset.id) ? CleanupTheme.electricBlue : .white.opacity(0.8))
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

    private func runCompression() async {
        guard !selectedAssets.isEmpty else { return }
        isRunningBatch = true

        let assetsToCompress = selectedAssets
        for asset in assetsToCompress {
            if asset.mediaType == .video {
                let ratio = targetRatio(for: asset)
                let preset = videoPreset(for: ratio)
                _ = await appFlow.compressVideo(
                    assetID: asset.id,
                    preset: preset,
                    label: qualityLabel(),
                    targetSizeRatio: ratio
                )
            } else {
                _ = await appFlow.compressPhoto(
                    assetID: asset.id,
                    quality: photoCompressionQuality(),
                    label: qualityLabel()
                )
            }
        }

        isRunningBatch = false
        selectedAssetIDs.removeAll()
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

import SwiftUI

struct CompressView: View {
    @EnvironmentObject private var appFlow: AppFlow

    @State private var selectedPreset: VideoCompressionPreset = .medium

    private var videos: [MediaAssetRecord] {
        Array(appFlow.mediaAssets(for: .videos).prefix(12))
    }

    var body: some View {
        NavigationStack {
            FeatureScreen(
                title: "Compress",
                leadingSymbol: "chevron.left",
                trailingSymbol: "arrow.clockwise",
                leadingAction: { appFlow.closeFeature() },
                trailingAction: { Task { await appFlow.scanLibrary() } }
            ) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard

                        if !appFlow.photoAuthorization.isReadable {
                            permissionCard
                        } else if videos.isEmpty {
                            emptyCard
                        } else {
                            presetPicker
                            videosList
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Largest videos ready")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)
                Text(ByteCountFormatter.cleanupString(fromByteCount: videos.reduce(0) { $0 + $1.sizeInBytes }))
                    .font(CleanupFont.body(18))
                    .foregroundStyle(CleanupTheme.electricBlue)
                Text("Tap any video to export a compressed copy back into your library.")
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
                Text("Photo access is required to compress videos.")
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
            Text("No videos were found in the current library scan.")
                .font(CleanupFont.body(16))
                .foregroundStyle(CleanupTheme.textSecondary)
        }
    }

    private var presetPicker: some View {
        Picker("Compression Preset", selection: $selectedPreset) {
            ForEach(VideoCompressionPreset.allCases) { preset in
                Text(preset.title).tag(preset)
            }
        }
        .pickerStyle(.segmented)
    }

    private var videosList: some View {
        VStack(spacing: 12) {
            ForEach(videos) { video in
                GlassCard(cornerRadius: 24) {
                    HStack(spacing: 14) {
                        PhotoThumbnailView(localIdentifier: video.id)
                            .frame(width: 92, height: 92)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(video.title)
                                .font(CleanupFont.body(16))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(video.detailLine)
                                .font(CleanupFont.caption(12))
                                .foregroundStyle(CleanupTheme.textSecondary)

                            if let result = appFlow.compressionResults[video.id] {
                                Text("Saved \(ByteCountFormatter.cleanupString(fromByteCount: result.savedBytes)) with \(result.preset.title)")
                                    .font(CleanupFont.caption(12))
                                    .foregroundStyle(CleanupTheme.accentGreen)
                            }
                        }

                        Spacer()

                        if appFlow.isCompressingAssetID == video.id {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Button("Compress") {
                                Task {
                                    _ = await appFlow.compressVideo(assetID: video.id, preset: selectedPreset)
                                }
                            }
                            .font(CleanupFont.badge(12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(CleanupTheme.cta, in: Capsule(style: .continuous))
                        }
                    }
                }
            }
        }
    }
}

import SwiftUI

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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                quickActions
                tiles
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .refreshable {
            await appFlow.scanLibrary()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cleanup")
                        .font(CleanupFont.hero(40))
                        .foregroundStyle(.white)

                    Text(appFlow.currentStorageLine)
                        .font(CleanupFont.body(16))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }

                Spacer()

                VStack(spacing: 10) {
                    PremiumPill()

                    NavigationLink {
                        AppStatusView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            UsageBar(
                progress: max(0.04, min(appFlow.storageSnapshot.progress, 1)),
                palette: LinearGradient(
                    colors: [CleanupTheme.electricBlue, Color(hex: "#6FE2FF")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 6)

            Text(appFlow.scanStatusText)
                .font(CleanupFont.body(15))
                .foregroundStyle(CleanupTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickActionCard(
                title: "Storage",
                value: ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.usedBytes),
                subtitle: "Used on this iPhone",
                symbol: "internaldrive.fill"
            )
            quickActionCard(
                title: "Photos",
                value: "\(appFlow.photoCount)",
                subtitle: "Images indexed",
                symbol: "photo.stack.fill"
            )
            quickActionCard(
                title: "Videos",
                value: "\(appFlow.videoCount)",
                subtitle: "Ready for review",
                symbol: "video.fill"
            )
        }
    }

    private func quickActionCard(title: String, value: String, subtitle: String, symbol: String) -> some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CleanupTheme.electricBlue)
                Text(title)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textTertiary)
                Text(value)
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(appFlow.dashboardCategories) { item in
                NavigationLink {
                    MediaCategoryReviewView(category: item.kind)
                } label: {
                    GlassCard(cornerRadius: 26) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.kind.title)
                                .font(CleanupFont.sectionTitle())
                                .foregroundStyle(.white)

                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(LinearGradient(colors: item.kind.palette, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(height: item.kind.tileHeight)
                                .overlay(alignment: .topLeading) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.count == 0 ? "Ready" : "\(item.count)")
                                            .font(CleanupFont.hero(24))
                                            .foregroundStyle(.white)
                                        Text(item.count == 0 ? "Scan again" : "items found")
                                            .font(CleanupFont.caption(12))
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                    .padding(14)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    CounterBadge(title: item.badgeTitle, subtitle: item.badgeSubtitle)
                                        .padding(12)
                                }
                        }
                    }
                    .padding(.horizontal, -4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MediaCategoryReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appFlow: AppFlow

    let category: DashboardCategoryKind

    @State private var selectedAssetIDs: Set<String> = []
    @State private var isDeleting = false
    @State private var statusMessage: String?

    private var assets: [MediaAssetRecord] {
        appFlow.mediaAssets(for: category)
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
                summaryCard

                if !appFlow.photoAuthorization.isReadable {
                    permissionCard
                } else if assets.isEmpty {
                    emptyState
                } else {
                    selectionBar
                    assetGrid
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedAssetIDs)
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(assets.count) items")
                        .font(CleanupFont.sectionTitle(22))
                        .foregroundStyle(.white)
                    Text(ByteCountFormatter.cleanupString(fromByteCount: assets.reduce(0) { $0 + $1.sizeInBytes }))
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(category.accent)
                    }
                }
                Spacer()
                Circle()
                    .fill(category.accent.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(category.accent)
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
                Text("Pull to refresh after adding more photos or videos.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            Button(selectedAssetIDs.count == assets.count ? "Clear Selection" : "Select All") {
                if selectedAssetIDs.count == assets.count {
                    selectedAssetIDs.removeAll()
                } else {
                    selectedAssetIDs = Set(assets.map(\.id))
                }
            }
            .font(CleanupFont.body(15))
            .foregroundStyle(category.accent)

            Spacer()

            if isDeleting {
                ProgressView()
                    .tint(.white)
            } else {
                PrimaryCTAButton(title: selectedAssetIDs.isEmpty ? "Select items to delete" : "Delete \(selectedAssetIDs.count) Selected") {
                    Task {
                        isDeleting = true
                        let success = await appFlow.deleteAssets(with: Array(selectedAssetIDs))
                        isDeleting = false
                        if success {
                            statusMessage = "Deleted \(selectedAssetIDs.count) item(s)."
                            selectedAssetIDs.removeAll()
                        } else {
                            statusMessage = "Delete failed. Please try again."
                        }
                    }
                }
                .disabled(selectedAssetIDs.isEmpty)
                .opacity(selectedAssetIDs.isEmpty ? 0.5 : 1)
                .frame(maxWidth: 220)
            }
        }
    }

    private var assetGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(assets) { asset in
                    Button {
                        if selectedAssetIDs.contains(asset.id) {
                            selectedAssetIDs.remove(asset.id)
                        } else {
                            selectedAssetIDs.insert(asset.id)
                        }
                    } label: {
                        AssetSelectableTile(asset: asset, isSelected: selectedAssetIDs.contains(asset.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
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

private struct AssetSelectableTile: View {
    let asset: MediaAssetRecord
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnailView(localIdentifier: asset.id)
                .frame(height: 142)
                .overlay(alignment: .bottomLeading) {
                    LinearGradient(colors: [.clear, Color.black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.title)
                                    .font(CleanupFont.caption(10))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(asset.detailLine)
                                    .font(CleanupFont.caption(10))
                                    .foregroundStyle(.white.opacity(0.76))
                            }
                            .padding(10)
                        }
                }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isSelected ? CleanupTheme.electricBlue : .white.opacity(0.74))
                .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? CleanupTheme.electricBlue : .white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
        )
    }
}

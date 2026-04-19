import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SecretSpaceView: View {
    private enum ImportAction {
        case keepOriginals
        case deleteOriginals

        var shouldDeleteOriginals: Bool {
            self == .deleteOriginals
        }
    }

    @EnvironmentObject private var appFlow: AppFlow

    @State private var newPIN = ""
    @State private var unlockPIN = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingImportItems: [PhotosPickerItem] = []
    @State private var showImportOptions = false
    @State private var statusMessage: String?

    var body: some View {
        FeatureScreen(
            title: "Secret Library",
            leadingSymbol: "chevron.left",
            trailingSymbol: appFlow.isSecretSpaceUnlocked ? "lock.fill" : "lock.open.fill",
            leadingAction: { appFlow.closeFeature() },
            trailingAction: { appFlow.lockSecretSpace() }
        ) {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        hero

                        if !appFlow.hasSecretPIN {
                            pinCreationCard
                        } else if !appFlow.isSecretSpaceUnlocked {
                            unlockCard
                        } else {
                            unlockedVault
                        }
                    }
                    .padding(.bottom, 24)
                }

                if let importStatus = appFlow.secretVaultImportStatus {
                    importOverlay(importStatus)
                }
            }
        }
        .onChange(of: pickerItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            pendingImportItems = newValue
            showImportOptions = true
        }
        .confirmationDialog("After importing, what should happen to the originals?", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button(importOnlyLabel) {
                startImport(.keepOriginals)
            }

            Button(importAndDeleteLabel, role: .destructive) {
                startImport(.deleteOriginals)
            }

            Button("Cancel", role: .cancel) {
                resetImportSelection()
            }
        } message: {
            Text(importDialogMessage)
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CleanupTheme.electricBlue.opacity(0.12))
                    .frame(width: 156, height: 156)

                GeneratedArtworkView(
                    assetName: "SecretLibraryArt",
                    fallbackSymbol: appFlow.isSecretSpaceUnlocked ? "lock.open.fill" : "lock.square.stack.fill",
                    tint: appFlow.isSecretSpaceUnlocked ? CleanupTheme.accentGreen : .white,
                    size: 86
                )
                .frame(width: 118, height: 118)
            }

            Text(appFlow.isSecretSpaceUnlocked ? "Secret Space Unlocked" : "Keep personal media private")
                .font(CleanupFont.hero(26))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(appFlow.isSecretSpaceUnlocked ? "Imported files stay inside the app until you remove them." : "Create a 4-digit PIN, then move private photos or videos into a locked local vault.")
                .font(CleanupFont.body(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(CleanupTheme.textSecondary)
        }
    }

    private var pinCreationCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create a 4-digit PIN")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)

                SecureField("PIN", text: $newPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding()
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let statusMessage {
                    Text(statusMessage)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }

                PrimaryCTAButton(title: "Create PIN") {
                    if appFlow.createSecretPIN(newPIN) {
                        statusMessage = "PIN created. You can import media now."
                        newPIN = ""
                    } else {
                        statusMessage = "Use exactly 4 digits."
                    }
                }
            }
        }
    }

    private var unlockCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Unlock Secret Space")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)

                SecureField("Enter PIN", text: $unlockPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding()
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                PrimaryCTAButton(title: "Unlock") {
                    if appFlow.unlockSecretSpace(with: unlockPIN) {
                        statusMessage = "Secret Space unlocked."
                        unlockPIN = ""
                    } else {
                        statusMessage = "That PIN didn't match."
                    }
                }
            }
        }
    }

    private var unlockedVault: some View {
        VStack(alignment: .leading, spacing: 16) {
            storageCard

            HStack {
                Text("\(appFlow.secretVaultItems.count) hidden file(s)")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                Spacer()
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                    Text("+ Add Files")
                        .font(CleanupFont.badge(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(CleanupTheme.cta, in: Capsule(style: .continuous))
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.accentGreen)
            }

            if appFlow.secretVaultItems.isEmpty {
                GlassCard(cornerRadius: 24) {
                    Text("Add files from your photo library to start using the vault.")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(appFlow.secretVaultItems) { item in
                        SecretVaultItemCard(item: item) {
                            appFlow.deleteSecretVaultItem(item)
                        }
                    }
                }
            }
        }
    }

    private var storageCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vault Storage")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)

                Text(ByteCountFormatter.cleanupString(fromByteCount: appFlow.secretVaultStorageBytes))
                    .font(CleanupFont.body(18))
                    .foregroundStyle(CleanupTheme.electricBlue)

                Text("Import copies stay in the private local vault. You can minimize the app while import continues, but keep the app open until it finishes.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private func importOverlay(_ status: SecretVaultImportStatus) -> some View {
        let completed = status.importedCount + status.failedCount
        let progress = Double(completed) / Double(max(status.totalCount, 1))

        return ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            GlassCard(cornerRadius: 28) {
                VStack(spacing: 18) {
                    ProgressView(value: progress)
                        .tint(CleanupTheme.electricBlue)
                        .scaleEffect(x: 1, y: 1.4, anchor: .center)

                    VStack(spacing: 6) {
                        Text("Securing your media")
                            .font(CleanupFont.sectionTitle(24))
                            .foregroundStyle(.white)
                        Text("\(status.importedCount) of \(status.totalCount) imported • \(ByteCountFormatter.cleanupString(fromByteCount: status.processedBytes)) protected")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(CleanupTheme.electricBlue)
                        Text("You can minimize the app and do something else, but don’t close it until the import finishes.")
                            .font(CleanupFont.body(14))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    if let currentFilename = status.currentFilename {
                        Text(currentFilename)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, 24)
        }
    }

    private var selectedImportCount: Int {
        pendingImportItems.isEmpty ? pickerItems.count : pendingImportItems.count
    }

    private var importOnlyLabel: String {
        let noun = selectedImportCount == 1 ? "File" : "\(selectedImportCount) Files"
        return "Import \(noun)"
    }

    private var importAndDeleteLabel: String {
        if selectedImportCount == 1 {
            return "Import and Delete Original"
        }
        return "Import and Delete \(selectedImportCount) Originals"
    }

    private var importDialogMessage: String {
        if selectedImportCount == 1 {
            return "We’ll move a protected copy into Secret Space. You can keep the original in Photos or delete it after import finishes."
        }
        return "We’ll move protected copies into Secret Space. You can keep the originals in Photos or delete them after import finishes."
    }

    private func startImport(_ action: ImportAction) {
        let items = pendingImportItems
        guard !items.isEmpty else {
            resetImportSelection()
            return
        }

        Task {
            let result = await appFlow.addSecretVaultItems(from: items, deleteOriginals: action.shouldDeleteOriginals)
            statusMessage = importStatusMessage(for: result)
            resetImportSelection()
        }
    }

    private func resetImportSelection() {
        pickerItems.removeAll()
        pendingImportItems.removeAll()
    }

    private func importStatusMessage(for result: SecretVaultImportResult) -> String {
        guard result.importedCount > 0 else {
            return "Nothing was imported."
        }

        if result.requestedOriginalDeletion {
            if result.eligibleOriginalCount == 0 {
                return "Imported \(result.importedCount) file(s) into Secret Space. The originals couldn’t be matched for deletion."
            }

            if result.deletedAllEligibleOriginals {
                return "Imported \(result.importedCount) file(s) and deleted \(result.deletedOriginalCount) original(s) from Photos."
            }

            return "Imported \(result.importedCount) file(s), but the originals could not be deleted."
        }

        return "Imported \(result.importedCount) file(s) into Secret Space."
    }
}

private struct SecretVaultItemCard: View {
    let item: SecretVaultItem
    let onDelete: () -> Void

    @State private var previewImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#111728"), Color(hex: "#0B1020")], startPoint: .topLeading, endPoint: .bottomTrailing))

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: item.isVideo ? "video.fill" : "photo.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(item.filename)
                .font(CleanupFont.body(14))
                .foregroundStyle(.white)
                .lineLimit(1)

            Button("Remove") {
                onDelete()
            }
            .font(CleanupFont.caption(12))
            .foregroundStyle(CleanupTheme.accentRed)
        }
        .task {
            loadPreview()
        }
    }

    private func loadPreview() {
        guard !item.isVideo, previewImage == nil else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let url = documents?.appendingPathComponent(item.relativePath)
        guard let path = url?.path else { return }
        previewImage = UIImage(contentsOfFile: path)
    }
}

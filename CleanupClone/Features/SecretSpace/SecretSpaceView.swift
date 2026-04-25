import AVFoundation
import AVKit
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Main view

struct SecretSpaceView: View {
    private enum ImportAction {
        case keepOriginals
        case deleteOriginals

        var shouldDeleteOriginals: Bool { self == .deleteOriginals }
    }

    @EnvironmentObject private var appFlow: AppFlow

    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var creationPhase: PINCreationPhase = .enter
    @State private var enableBiometricsOnCreate = true
    @State private var unlockPIN = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingImportItems: [PhotosPickerItem] = []
    @State private var showImportOptions = false
    /// True once Face ID has confirmed the user is the device owner
    /// during the "I forgot my PIN" recovery flow. While true the
    /// unlock screen swaps the PIN entry pad for a NEW-PIN entry pad
    /// (using the same `pinCreationCard` we already have, primed for
    /// replacement instead of first-time setup). Vault contents are
    /// not touched at any point in this path.
    @State private var isResettingPINViaBiometrics = false
    /// Last-resort wipe path: only offered when Face ID isn't
    /// available / the user disabled it during creation. This is the
    /// old destructive "Reset & Wipe Vault" alert that already
    /// existed — kept as a fallback because there's no other identity
    /// proof we can ask for.
    @State private var showWipeFallbackConfirm = false
    @State private var statusMessage: String?
    @State private var previewStartIndex: Int?
    @State private var didAttemptBiometric = false
    @State private var selectionMode = false
    @State private var selectedIDs: Set<String> = []
    @State private var showRemoveConfirm = false
    @State private var shareURLs: [URL] = []
    @State private var showShareSheet = false

    private enum PINCreationPhase {
        case enter, confirm
    }

    var body: some View {
        FeatureScreen(
            title: "Secret Library",
            leadingSymbol: "chevron.left",
            leadingAction: { appFlow.closeFeature() },
            trailingContent: {
                HStack(spacing: 8) {
                    // "Select" / "Done" toggle — only when unlocked and we
                    // have something to act on. Mirrors the competitor's
                    // multi-select gesture for bulk Share / Remove.
                    if appFlow.hasSecretPIN,
                       appFlow.isSecretSpaceUnlocked,
                       !appFlow.secretVaultItems.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selectionMode.toggle()
                                if !selectionMode { selectedIDs.removeAll() }
                            }
                        } label: {
                            Text(selectionMode ? "Done" : "Select")
                                .font(CleanupFont.body(13).weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // Top-right lock/unlock chip — green open when unlocked,
                    // amber closed when locked. One-tap re-lock.
                    if appFlow.hasSecretPIN {
                        Button {
                            if appFlow.isSecretSpaceUnlocked {
                                // Bail out of selection mode on lock.
                                selectionMode = false
                                selectedIDs.removeAll()
                                appFlow.lockSecretSpace()
                            }
                        } label: {
                            Image(systemName: appFlow.isSecretSpaceUnlocked ? "lock.open.fill" : "lock.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(appFlow.isSecretSpaceUnlocked
                                                 ? CleanupTheme.accentGreen
                                                 : Color(hex: "#FFB445"))
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle().fill(Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        ) {
            ZStack {
                if !appFlow.hasSecretPIN {
                    pinCreationCard
                } else if isResettingPINViaBiometrics {
                    // Face-ID recovery: same creation pad, primed to
                    // replace the existing hash. `handlePINCreationStep`
                    // routes through `replaceSecretPIN(_:)` while this
                    // flag is set, so vault contents stay intact.
                    pinCreationCard
                } else if !appFlow.isSecretSpaceUnlocked {
                    unlockCard
                } else {
                    ZStack(alignment: .bottom) {
                        unlockedVault
                            .padding(.bottom, selectionMode ? 96 : 0)
                        if selectionMode {
                            selectionActionBar
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }

                if let importStatus = appFlow.secretVaultImportStatus {
                    importOverlay(importStatus)
                }
            }
        }
        .task(id: appFlow.isSecretSpaceUnlocked) {
            // Only try Face ID once per lock gate — not every SwiftUI refresh.
            guard appFlow.hasSecretPIN,
                  !appFlow.isSecretSpaceUnlocked,
                  !didAttemptBiometric else { return }
            didAttemptBiometric = true
            _ = await appFlow.attemptBiometricUnlock()
        }
        .onChange(of: appFlow.isSecretSpaceUnlocked) { _, unlocked in
            if unlocked {
                // Reset one-shot so the next lock can re-prompt biometrics.
                didAttemptBiometric = false
                unlockPIN = ""
                statusMessage = nil
            }
        }
        .onChange(of: pickerItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            pendingImportItems = newValue
            showImportOptions = true
        }
        .confirmationDialog(
            "After importing, what should happen to the originals?",
            isPresented: $showImportOptions,
            titleVisibility: .visible
        ) {
            Button(importOnlyLabel) { startImport(.keepOriginals) }
            Button(importAndDeleteLabel, role: .destructive) { startImport(.deleteOriginals) }
            Button("Cancel", role: .cancel) { resetImportSelection() }
        } message: {
            Text(importDialogMessage)
        }
        .fullScreenCover(item: Binding(
            get: { previewStartIndex.map { PreviewStart(index: $0) } },
            set: { newValue in previewStartIndex = newValue?.index }
        )) { start in
            SecretVaultPreview(
                items: appFlow.secretVaultItems,
                startIndex: start.index,
                vaultURL: { appFlow.vaultURL(for: $0) },
                onDelete: { item in
                    appFlow.deleteSecretVaultItem(item)
                }
            )
        }
        .alert(
            "Are you sure you want to remove these media files from the Secret Space?",
            isPresented: $showRemoveConfirm
        ) {
            Button("No, Back", role: .cancel) {}
            Button("Yes, Remove", role: .destructive) {
                performRemoveSelected()
            }
        } message: {
            Text("This action cannot be undone, make sure you've restored the files you want to keep to your device.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareURLs)
        }
    }

    // MARK: - Unlocked vault

    /// Compact hero row — tiny lock icon + single info line. Replaces the
    /// 156pt circle + long paragraph that wasted the top third of the screen.
    private var compactHero: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CleanupTheme.accentGreen.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CleanupTheme.accentGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Secret Space Unlocked")
                    .font(CleanupFont.sectionTitle(17))
                    .foregroundStyle(.white)
                Text("\(appFlow.secretVaultItems.count) files · \(ByteCountFormatter.cleanupString(fromByteCount: appFlow.secretVaultStorageBytes))")
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
            Spacer()
            // `photoLibrary: .shared()` is REQUIRED so PhotosPickerItem
            // carries a real `itemIdentifier`. Without it, the picker runs
            // in anonymous mode and we can't match originals back to the
            // Photos library to delete them — which is why "Import and
            // Delete Originals" appeared to do nothing.
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 20,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add")
                        .font(CleanupFont.badge(13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(CleanupTheme.cta, in: Capsule(style: .continuous))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CleanupTheme.card.opacity(0.55))
        )
    }

    private var unlockedVault: some View {
        VStack(alignment: .leading, spacing: 14) {
            compactHero

            if let statusMessage {
                Text(statusMessage)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.accentGreen)
            }

            if appFlow.secretVaultItems.isEmpty {
                emptyVaultCard
                Spacer(minLength: 0)
            } else {
                galleryGrid
            }
        }
    }

    private var emptyVaultCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(CleanupTheme.textSecondary)
            Text("Your vault is empty")
                .font(CleanupFont.sectionTitle(17))
                .foregroundStyle(.white)
            Text("Tap Add to move private photos or videos here.")
                .font(CleanupFont.body(13))
                .foregroundStyle(CleanupTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CleanupTheme.card.opacity(0.45))
        )
    }

    /// Native gallery: 3 equal square tiles per row, edge-to-edge, tiny
    /// gutters. Each tile uses `aspectRatio(1, contentMode: .fill)` so the
    /// tile is a square whose side is dictated by the grid column width —
    /// this avoids `GeometryReader` returning zero height when nested in
    /// a VStack, which is what caused the 10pt tall strips.
    private var galleryGrid: some View {
        let spacing: CGFloat = 3
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: 3
        )
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(appFlow.secretVaultItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        if selectionMode {
                            toggleSelection(item.id)
                        } else {
                            previewStartIndex = index
                        }
                    } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                SecretVaultThumbnail(
                                    item: item,
                                    url: appFlow.vaultURL(for: item)
                                )
                            )
                            .overlay(selectionOverlay(for: item.id))
                            .clipped()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            appFlow.deleteSecretVaultItem(item)
                        } label: {
                            Label("Remove from vault", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Selection mode

    private func toggleSelection(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    @ViewBuilder
    private func selectionOverlay(for id: String) -> some View {
        if selectionMode {
            let isSelected = selectedIDs.contains(id)
            ZStack {
                if isSelected {
                    Color.black.opacity(0.35)
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(CleanupTheme.electricBlue, lineWidth: 3)
                }
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                isSelected ? Color.white : Color.white.opacity(0.9),
                                isSelected ? CleanupTheme.electricBlue : Color.black.opacity(0.35)
                            )
                            .background(
                                Circle().fill(Color.black.opacity(0.25))
                                    .frame(width: 24, height: 24)
                                    .opacity(isSelected ? 0 : 1)
                            )
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
    }

    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Text(selectionCountLabel)
                .font(CleanupFont.body(13))
                .foregroundStyle(CleanupTheme.textSecondary)
                .padding(.top, 10)
                .padding(.bottom, 6)
            HStack(spacing: 0) {
                Button {
                    prepareShare()
                } label: {
                    actionBarLabel(icon: "square.and.arrow.up", title: "Share", tint: CleanupTheme.electricBlue)
                }
                .buttonStyle(.plain)
                .disabled(selectedIDs.isEmpty)
                .opacity(selectedIDs.isEmpty ? 0.4 : 1)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 28)

                Button {
                    showRemoveConfirm = true
                } label: {
                    actionBarLabel(icon: "trash", title: "Remove", tint: CleanupTheme.accentRed)
                }
                .buttonStyle(.plain)
                .disabled(selectedIDs.isEmpty)
                .opacity(selectedIDs.isEmpty ? 0.4 : 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func actionBarLabel(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(CleanupFont.sectionTitle(16))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var selectionCountLabel: String {
        let n = selectedIDs.count
        if n == 0 { return "Select items" }
        if n == 1 { return "1 secret media file selected" }
        return "\(n) secret media files selected"
    }

    private func selectedItems() -> [SecretVaultItem] {
        appFlow.secretVaultItems.filter { selectedIDs.contains($0.id) }
    }

    private func prepareShare() {
        let urls = selectedItems().map { appFlow.vaultURL(for: $0) }
        guard !urls.isEmpty else { return }
        shareURLs = urls
        showShareSheet = true
    }

    private func performRemoveSelected() {
        let items = selectedItems()
        for item in items {
            appFlow.deleteSecretVaultItem(item)
        }
        selectedIDs.removeAll()
        withAnimation(.easeOut(duration: 0.18)) {
            selectionMode = false
        }
    }

    // MARK: - PIN gates
    //
    // Layout matches the reference screenshots: hero icon + prompt + 4 dots
    // vertically centered, numeric keypad pinned to the bottom. The keypad
    // is our own — NOT the iOS on-screen keyboard — so there's no screen-
    // recording leak surface and no system-keyboard lag. Biometric fallback
    // is offered if the user opted in during creation.

    /// Two-step create: enter → confirm. Uses the system numeric keypad
    /// (matches the competitor screenshot exactly — iOS `.numberPad`) via a
    /// hidden auto-focused text field. The visible dots show progress; the
    /// actual digits never render anywhere on screen.
    private var pinCreationCard: some View {
        SystemPINPadContainer(
            value: creationPhase == .enter ? $newPIN : $confirmPIN,
            maxLength: 4,
            onComplete: handlePINCreationStep
        ) {
            VStack(spacing: 18) {
                Spacer(minLength: 24)

                keyHero

                Text(pinCreationPromptText)
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                PINDotsRow(length: 4, value: creationPhase == .enter ? newPIN : confirmPIN)

                if let statusMessage {
                    Text(statusMessage)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(statusMessage.contains("match") ? CleanupTheme.accentRed : CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if !isResettingPINViaBiometrics, let biometric = appFlow.biometricDisplayName {
                    Toggle(isOn: $enableBiometricsOnCreate) {
                        HStack(spacing: 8) {
                            Image(systemName: biometric == "Face ID" ? "faceid" : "touchid")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CleanupTheme.electricBlue)
                            Text("Unlock with \(biometric)")
                                .font(CleanupFont.body(14))
                                .foregroundStyle(.white)
                        }
                    }
                    .tint(CleanupTheme.electricBlue)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                }

                // "Forgot PIN?" escape hatch on the creation/confirm
                // screen. Two cases this rescues:
                //   1. User is stuck in the "PINs didn't match. Try
                //      again." loop because they typed a PIN, blanked
                //      out, typed something different on confirm, and
                //      now can't remember the first one. Tap clears
                //      the entry and starts over.
                //   2. A PIN was set previously but storage got
                //      cleared / reset (TestFlight reinstall, etc.)
                //      and the user is seeing the creation screen by
                //      mistake. Tap triggers the same Face-ID-backed
                //      recovery used on the unlock screen.
                Button {
                    handleForgotPINTap()
                } label: {
                    Text("Forgot PIN?")
                        .font(CleanupFont.body(13))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .underline()
                }
                .padding(.top, 6)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handlePINCreationStep() {
        // The pin pad fires this via a 0.1s `DispatchQueue` hop after
        // the 4th digit lands. If the user tapped "Forgot PIN?" inside
        // that 0.1s window the form will already be cleared — both
        // `newPIN` and `confirmPIN` empty — by the time this fires.
        // Without this guard the confirm branch below would compare
        // "" == "" → look like a successful match → call createPIN
        // with an empty string (which fails) → we'd land on the
        // generic "Use exactly 4 digits" error AND keep the prior red
        // "PINs didn't match" text on screen depending on phase. Drop
        // stale calls on the floor: if the relevant field is empty,
        // there's nothing to do.
        let activeField = creationPhase == .enter ? newPIN : confirmPIN
        guard !activeField.isEmpty else { return }
        switch creationPhase {
        case .enter:
            // Basic validation: must be 4 digits.
            guard newPIN.count == 4 else {
                statusMessage = "Use exactly 4 digits."
                newPIN = ""
                return
            }
            statusMessage = nil
            creationPhase = .confirm
        case .confirm:
            print("[PIN-VIEW] confirm step — newPIN=\"\(newPIN)\" confirmPIN=\"\(confirmPIN)\" match=\(confirmPIN == newPIN) recoveryMode=\(isResettingPINViaBiometrics)")
            if confirmPIN == newPIN {
                // During Face-ID-backed recovery we REPLACE the hash
                // without touching the vault directory or the items
                // index. First-time creation still goes through
                // `createSecretPIN(_:)` which is functionally identical
                // for the hash but sets `isSecretSpaceUnlocked` and
                // initialises a fresh vault state.
                let saved = isResettingPINViaBiometrics
                    ? appFlow.replaceSecretPIN(with: newPIN)
                    : appFlow.createSecretPIN(newPIN)
                if saved {
                    if !isResettingPINViaBiometrics {
                        appFlow.isBiometricUnlockEnabled = enableBiometricsOnCreate && appFlow.biometricDisplayName != nil
                    }
                    newPIN = ""
                    confirmPIN = ""
                    creationPhase = .enter
                    statusMessage = nil
                    isResettingPINViaBiometrics = false
                } else {
                    statusMessage = "Use exactly 4 digits."
                    resetCreationState()
                }
            } else {
                statusMessage = "PINs didn't match. Try again."
                resetCreationState()
            }
        }
    }

    /// Prompt copy for the 4-digit pad. Three states:
    ///   • first-time setup, entering the PIN → "Create a 4-digit PIN"
    ///   • first-time setup, confirming       → "Re-enter PIN to confirm"
    ///   • recovery via Face ID, entering     → "Choose a new 4-digit PIN"
    ///   • recovery via Face ID, confirming   → "Re-enter new PIN to confirm"
    /// The vault contents are preserved through the recovery path; the
    /// copy makes that distinction explicit so the user doesn't think
    /// they're starting over from scratch.
    private var pinCreationPromptText: String {
        switch (isResettingPINViaBiometrics, creationPhase) {
        case (false, .enter):   return "Create a 4-digit PIN"
        case (false, .confirm): return "Re-enter PIN to confirm"
        case (true,  .enter):   return "Choose a new 4-digit PIN"
        case (true,  .confirm): return "Re-enter new PIN to confirm"
        }
    }

    private func resetCreationState() {
        newPIN = ""
        confirmPIN = ""
        creationPhase = .enter
    }

    private var unlockCard: some View {
        SystemPINPadContainer(
            value: $unlockPIN,
            maxLength: 4,
            onComplete: {
                let attempted = unlockPIN
                print("[PIN-VIEW] unlock onComplete fired — unlockPIN=\"\(attempted)\" len=\(attempted.count)")
                if appFlow.unlockSecretSpace(with: unlockPIN) {
                    statusMessage = nil
                    unlockPIN = ""
                } else {
                    statusMessage = "That PIN didn't match."
                    unlockPIN = ""
                }
            }
        ) {
            VStack(spacing: 18) {
                Spacer(minLength: 24)

                keyHero

                Text("Enter PIN")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)

                PINDotsRow(length: 4, value: unlockPIN)

                if let statusMessage {
                    Text(statusMessage)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(statusMessage.contains("didn") ? CleanupTheme.accentRed : CleanupTheme.textSecondary)
                }

                // Biometric re-prompt + Forgot PIN escape hatch. Both are
                // secondary — the primary path is typing the PIN.
                HStack(spacing: 18) {
                    if let biometric = appFlow.biometricDisplayName,
                       appFlow.isBiometricUnlockEnabled {
                        Button {
                            Task {
                                _ = await appFlow.attemptBiometricUnlock()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: biometric == "Face ID" ? "faceid" : "touchid")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Use \(biometric)")
                                    .font(CleanupFont.body(13))
                            }
                            .foregroundStyle(CleanupTheme.electricBlue)
                        }
                    }

                    Button {
                        handleForgotPINTap()
                    } label: {
                        Text("Forgot PIN?")
                            .font(CleanupFont.body(13))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .underline()
                    }
                }
                .padding(.top, 2)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            "Reset Secret Space?",
            isPresented: $showWipeFallbackConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Wipe Vault", role: .destructive) {
                appFlow.resetSecretPIN()
                unlockPIN = ""
                statusMessage = nil
            }
        } message: {
            Text("Face ID isn't available on this device, so we can't verify it's you any other way. Resetting will permanently delete every photo and video inside Secret Space and let you set a new PIN. This can't be undone.")
        }
    }

    /// Branches the "Forgot PIN?" tap based on what state the screen
    /// is in:
    ///   • No PIN saved yet AND the user is mid-creation → just clear
    ///     the form and let them start over. There's nothing to
    ///     "recover" because nothing's saved.
    ///   • PIN saved + biometrics available → Face ID / Touch ID as
    ///     identity proof, then let the user pick a new PIN. Vault
    ///     contents preserved.
    ///   • PIN saved + no biometrics → fall back to the destructive
    ///     wipe alert (the only safe option without identity proof).
    private func handleForgotPINTap() {
        // Mid-creation rescue: user got stuck in the "PINs didn't
        // match" loop with no prior PIN saved. Clear the form so
        // they're back at "Create a 4-digit PIN" with empty dots.
        guard appFlow.hasSecretPIN else {
            newPIN = ""
            confirmPIN = ""
            creationPhase = .enter
            statusMessage = nil
            return
        }
        guard appFlow.biometricDisplayName != nil else {
            showWipeFallbackConfirm = true
            return
        }
        Task {
            let approved = await appFlow.attemptBiometricPINReset()
            await MainActor.run {
                if approved {
                    unlockPIN = ""
                    newPIN = ""
                    confirmPIN = ""
                    creationPhase = .enter
                    statusMessage = nil
                    isResettingPINViaBiometrics = true
                }
                // On user-cancel / failure we just stay on the unlock
                // screen. We don't auto-fall-back to the wipe alert —
                // that would punish the user for tapping the button by
                // accident.
            }
        }
    }

    /// Small key glyph on an amber disc — matches the competitor's visual
    /// language without stealing half the screen.
    private var keyHero: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#F2B23B"))
                .frame(width: 92, height: 92)
                .shadow(color: Color(hex: "#F2B23B").opacity(0.35), radius: 20, y: 6)
            Image(systemName: "key.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-45))
        }
    }

    // MARK: - Import overlay

    private func importOverlay(_ status: SecretVaultImportStatus) -> some View {
        let completed = status.importedCount + status.failedCount
        let progress = Double(completed) / Double(max(status.totalCount, 1))

        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            GlassCard(cornerRadius: 24) {
                VStack(spacing: 14) {
                    ProgressView(value: progress)
                        .tint(CleanupTheme.electricBlue)
                        .scaleEffect(x: 1, y: 1.3, anchor: .center)

                    Text("Securing your media")
                        .font(CleanupFont.sectionTitle(20))
                        .foregroundStyle(.white)

                    Text("\(status.importedCount) of \(status.totalCount) · \(ByteCountFormatter.cleanupString(fromByteCount: status.processedBytes))")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.electricBlue)

                    if let currentFilename = status.currentFilename {
                        Text(currentFilename)
                            .font(CleanupFont.caption(11))
                            .foregroundStyle(CleanupTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 30)
        }
    }

    // MARK: - Labels / import flow

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
            return "We'll move a protected copy into Secret Space. You can keep the original in Photos or delete it after import finishes."
        }
        return "We'll move protected copies into Secret Space. You can keep the originals in Photos or delete them after import finishes."
    }

    private func startImport(_ action: ImportAction) {
        let items = pendingImportItems
        guard !items.isEmpty else {
            resetImportSelection()
            return
        }
        guard appFlow.gateSingleAction(.vaultAdd) else {
            resetImportSelection()
            return
        }

        Task {
            // If the user asked us to delete the originals, make sure the
            // Photos library is actually authorized for write access first.
            // Without readWrite auth, `PHAssetChangeRequest.deleteAssets`
            // never shows the iOS system delete confirmation — it silently
            // no-ops, which is exactly the bug the user reported.
            if action.shouldDeleteOriginals {
                let ok = await appFlow.requestPhotoAuthorizationOnly()
                if !ok {
                    statusMessage = "Grant Photos access in Settings to delete originals."
                    resetImportSelection()
                    return
                }
            }
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
                return "Imported \(result.importedCount) file(s) into Secret Space. The originals couldn't be matched for deletion."
            }

            if result.deletedAllEligibleOriginals {
                return "Imported \(result.importedCount) file(s) and deleted \(result.deletedOriginalCount) original(s) from Photos."
            }

            return "Imported \(result.importedCount) file(s), but the originals could not be deleted."
        }

        return "Imported \(result.importedCount) file(s) into Secret Space."
    }
}

// MARK: - Fullscreen cover payload

private struct PreviewStart: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Thumbnail (grid)

/// Displays a downsampled thumbnail for a vault item. Decoding happens off
/// the main thread via an actor-backed cache; the view only ever blits the
/// result. Cancels work if the view disappears so scrolling stays fluid.
private struct SecretVaultThumbnail: View {
    let item: SecretVaultItem
    let url: URL

    @State private var thumb: UIImage?

    var body: some View {
        ZStack {
            Color(hex: "#0E1424")

            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: item.isVideo ? "video.fill" : "photo.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CleanupTheme.textTertiary)
            }

            if item.isVideo {
                // Corner badge so you can tell videos apart in the grid.
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
        .task(id: item.id) {
            if let cached = SecretThumbnailCache.shared.cached(for: item.id) {
                self.thumb = cached
                return
            }
            let loaded = await SecretThumbnailCache.shared.thumbnail(
                for: item,
                at: url,
                maxPixel: 320
            )
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.thumb = loaded
                }
            }
        }
    }
}

// MARK: - Thumbnail cache

/// Off-main thumbnail generator for vault items. Uses `CGImageSource` for
/// images so we never decode the whole file into memory on the main thread,
/// and `AVAssetImageGenerator` for videos. An in-memory `NSCache` means
/// redraws after a scroll-and-back don't touch disk.
final class SecretThumbnailCache: @unchecked Sendable {
    static let shared = SecretThumbnailCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()
    private let queue = DispatchQueue(label: "cleanup.secret.thumbs", qos: .userInitiated, attributes: .concurrent)

    func cached(for id: String) -> UIImage? {
        cache.object(forKey: id as NSString)
    }

    func thumbnail(for item: SecretVaultItem, at url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cached(for: item.id) { return hit }

        let isVideo = item.isVideo
        let key = item.id as NSString
        let cache = self.cache
        let queue = self.queue

        return await withCheckedContinuation { continuation in
            queue.async {
                let image: UIImage?
                if isVideo {
                    image = Self.makeVideoThumbnail(url: url, maxPixel: maxPixel)
                } else {
                    image = Self.makeImageThumbnail(url: url, maxPixel: maxPixel)
                }
                if let image {
                    cache.setObject(image, forKey: key)
                }
                continuation.resume(returning: image)
            }
        }
    }

    func purge(_ id: String) {
        cache.removeObject(forKey: id as NSString)
    }

    /// Bigger video poster for the preview page — same downsample path
    /// as photos but using AVAssetImageGenerator. Cached separately.
    func videoPoster(for item: SecretVaultItem, at url: URL) async -> UIImage? {
        let key = "poster-\(item.id)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let queue = self.queue
        let cache = self.cache
        return await withCheckedContinuation { continuation in
            queue.async {
                let image = Self.makeVideoThumbnail(url: url, maxPixel: 1600)
                if let image {
                    cache.setObject(image, forKey: key)
                }
                continuation.resume(returning: image)
            }
        }
    }

    // Full-resolution loader for the preview sheet — also cached (separate
    // key suffix) so swiping back to an already-seen item is instant.
    func fullImage(for item: SecretVaultItem, at url: URL) async -> UIImage? {
        let key = "full-\(item.id)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let queue = self.queue
        let cache = self.cache
        return await withCheckedContinuation { continuation in
            queue.async {
                // Downsample to screen-ish size (1600 pixel) — perfect for
                // zoom-in-by-pinch without eating 50MB per photo.
                let image = Self.makeImageThumbnail(url: url, maxPixel: 1600)
                if let image {
                    cache.setObject(image, forKey: key)
                }
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Private decoders

    private static func makeImageThumbnail(url: URL, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * UIScreen.main.scale
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func makeVideoThumbnail(url: URL, maxPixel: CGFloat) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let side = maxPixel * UIScreen.main.scale
        generator.maximumSize = CGSize(width: side, height: side)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cg = try? generator.copyCGImage(at: time, actualTime: nil) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}

// MARK: - PIN keypad + dots

/// Compact dot indicator that mirrors the system passcode row.
private struct PINDotsRow: View {
    let length: Int
    let value: String

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<length, id: \.self) { index in
                Circle()
                    .fill(index < value.count ? CleanupTheme.electricBlue : Color.white.opacity(0.18))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: value.count)
            }
        }
    }
}

/// Wraps PIN content with a hidden auto-focused `TextField` that summons
/// the iOS system numeric keypad (`.numberPad` — the phone-dialer style
/// with "ABC / DEF" letters under digits). This matches the competitor
/// screenshot and eliminates the screen-recording risk of a custom on-
/// screen keypad: no digits are ever painted into our view hierarchy.
///
/// The visible content (hero + dots + prompt) renders normally above.
/// A transparent 1pt `TextField` stays focused; every keystroke updates
/// the bound value, and once `maxLength` is reached we fire `onComplete`.
/// Tapping anywhere on the content re-focuses the field in case the
/// keyboard was dismissed.
private struct SystemPINPadContainer<Content: View>: View {
    @Binding var value: String
    let maxLength: Int
    let onComplete: () -> Void
    @ViewBuilder let content: () -> Content

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hidden input — drives the system .numberPad keyboard. We
            // still own the visible dots; this field is never shown.
            TextField("", text: Binding(
                get: { value },
                set: { newValue in
                    let digits = newValue.filter(\.isNumber)
                    let trimmed = String(digits.prefix(maxLength))
                    if trimmed != value {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    value = trimmed
                    if value.count == maxLength {
                        // Let the last dot animate, then fire.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onComplete()
                        }
                    }
                }
            ))
            .keyboardType(.numberPad)
            // Intentionally NOT `.textContentType(.oneTimeCode)`. That
            // hint causes iOS to surface 4-digit codes from Messages /
            // Mail / AutoFill above the keypad, and a misread tap
            // there silently replaces the user's typed PIN with
            // something they never intended to save. For a vault PIN
            // we want exactly the digits the user pressed, nothing
            // else.
            .textContentType(.none)
            .autocorrectionDisabled(true)
            .focused($focused)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)

            content()
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
        }
        .onAppear {
            // Tiny delay so SwiftUI has mounted the field before focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focused = true
            }
        }
    }
}

// MARK: - Quick preview sheet

/// Full-screen swipe+zoom preview. Pages horizontally through the vault,
/// pinch to zoom on photos, play button for videos, delete from toolbar.
private struct SecretVaultPreview: View {
    let items: [SecretVaultItem]
    let startIndex: Int
    let vaultURL: (SecretVaultItem) -> URL
    let onDelete: (SecretVaultItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showDeleteConfirm = false

    init(
        items: [SecretVaultItem],
        startIndex: Int,
        vaultURL: @escaping (SecretVaultItem) -> URL,
        onDelete: @escaping (SecretVaultItem) -> Void
    ) {
        self.items = items
        self.startIndex = startIndex
        self.vaultURL = vaultURL
        self.onDelete = onDelete
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if items.isEmpty {
                emptyView
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        SecretVaultPreviewPage(
                            item: item,
                            url: vaultURL(item)
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            // Toolbar overlay
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.55), in: Circle())
                    }
                    Spacer()
                    Text(safeCounter)
                        .font(CleanupFont.body(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                    Spacer()
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CleanupTheme.accentRed)
                            .padding(10)
                            .background(Color.black.opacity(0.55), in: Circle())
                    }
                    .disabled(items.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                Spacer()
            }
        }
        .alert("Remove from vault?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                guard let current = currentItem else { return }
                onDelete(current)
                if items.count <= 1 {
                    dismiss()
                } else {
                    currentIndex = min(currentIndex, items.count - 2)
                }
            }
        } message: {
            Text("The file will be permanently deleted from Secret Space.")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("No items")
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var currentItem: SecretVaultItem? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    private var safeCounter: String {
        guard !items.isEmpty else { return "" }
        let shown = min(currentIndex + 1, items.count)
        return "\(shown) of \(items.count)"
    }
}

/// Single page in the preview. Two key things make this smooth:
///  1. No `GeometryReader` — that caused TabView paging to stall on the
///     last item (the proxy size flickers as pages mount, breaking the
///     pan offset internal to TabView).
///  2. Pan / zoom gestures are only attached when the image is actually
///     zoomed in. Otherwise SwiftUI's `DragGesture` would steal every
///     horizontal swipe from the parent `TabView` — that's why the user
///     could get to page 2 then get "stuck": the gesture system gave the
///     drag to the page, not the pager.
private struct SecretVaultPreviewPage: View {
    let item: SecretVaultItem
    let url: URL

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black

            if item.isVideo {
                SecretVideoPlayerView(item: item, url: url)
            } else {
                photoBody
            }
        }
        .task(id: item.id) {
            await loadImage()
        }
        .onDisappear {
            // Reset zoom state so re-entering doesn't show a stale crop.
            scale = 1; lastScale = 1
            offset = .zero; lastOffset = .zero
        }
    }

    @ViewBuilder
    private var photoBody: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(zoomGesture)
        // Only attach pan when zoomed in — otherwise this would consume
        // the horizontal swipe TabView needs to page between items.
        .simultaneousGesture(scale > 1.02 ? panGesture : nil)
        .onTapGesture(count: 2) { toggleZoom() }
    }

    private func loadImage() async {
        if item.isVideo { return }
        // Instant: use the grid thumb if we already have it.
        if let warm = SecretThumbnailCache.shared.cached(for: item.id) {
            self.image = warm
        }
        // Then swap in the higher-res version.
        if let full = await SecretThumbnailCache.shared.fullImage(for: item, at: url) {
            withAnimation(.easeOut(duration: 0.15)) { self.image = full }
        }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            if scale > 1.01 {
                scale = 1; lastScale = 1
                offset = .zero; lastOffset = .zero
            } else {
                scale = 2.2; lastScale = 2.2
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.02 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = .zero; lastOffset = .zero
                        scale = 1; lastScale = 1
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}

/// Video page with poster + tap-to-play. We don't mount AVPlayer until
/// the user actually taps Play — mounting AVPlayer for every page in a
/// pager is what makes swiping janky and what stalls memory after a few
/// videos. Once the user taps, we swap in the player.
private struct SecretVideoPlayerView: View {
    let item: SecretVaultItem
    let url: URL

    @State private var poster: UIImage?
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            // Poster behind everything so the page never looks empty
            // mid-swipe (this is why scrolling now feels instant — we
            // never wait for AVPlayer to be ready before showing pixels).
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black
            }

            if isPlaying {
                VideoPlayerHost(url: url)
                    .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isPlaying = true
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 78, height: 78)
                        Image(systemName: "play.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 3) // visually center the triangle
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: item.id) {
            if let cached = SecretThumbnailCache.shared.cached(for: item.id) {
                self.poster = cached
            }
            if let big = await SecretThumbnailCache.shared.videoPoster(for: item, at: url) {
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.15)) { self.poster = big }
                }
            }
        }
        .onDisappear {
            // Tear down the player when leaving the page — this is the
            // single most important thing for smooth swiping through a
            // mix of photos and videos.
            isPlaying = false
        }
    }
}

/// Wraps AVPlayerViewController. Created fresh per page; the parent
/// only mounts it when the user taps Play, and tears it down on
/// `onDisappear` so memory stays flat.
private struct VideoPlayerHost: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewControllerWrapped {
        let vc = AVPlayerViewControllerWrapped()
        let player = AVPlayer(url: url)
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        // Auto-start once mounted so the user doesn't have to tap twice.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            player.play()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewControllerWrapped, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewControllerWrapped, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}

/// Alias so we can tweak later without the SwiftUI site changing.
final class AVPlayerViewControllerWrapped: AVPlayerViewController {}

// MARK: - Share sheet

/// Bridges UIActivityViewController to SwiftUI for sharing vault file URLs
/// from selection mode. We pass file URLs directly so AirDrop / Save to
/// Files preserve the original media instead of re-encoding screenshots.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

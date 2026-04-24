import SwiftUI
import UIKit

// MARK: - Preferences

/// Per-preview toggle. Lives inline in the preview header (next to the back
/// chevron) so users discover it where they'd use it. UserDefaults-backed so
/// the choice sticks across sessions.
enum SwipeCleanPreferences {
    static let toggleKey = "pref.swipeCleanEnabled"
}

// MARK: - Decisions

enum SwipeDecision {
    case keep
    case delete
}

// MARK: - SwipeCleanDeck
//
// Design notes — what changed and why
// ------------------------------------
//
// The earlier implementation rendered a 3-card depth stack, which created
// the "ghost image peeking from behind" effect the user called out. The
// competitor (WaveGuard / ScanGuru-style swipe apps) does NOT stack cards.
// They show a single full-bleed card and lean on the filmstrip at the
// bottom + the progress bar at top to give a sense of position. That reads
// as dramatically more solid.
//
// This rewrite adopts that pattern:
//   - Single card, full-bleed, centered. No depth, no peek, no ghosts.
//   - Swipe fling animates the outgoing card off-screen and fades the next
//     one in under it (two z-layers, not three). Fast + clean.
//   - A filmstrip at the bottom lets the user scroll through the whole
//     set without committing. Tapping a thumbnail jumps to it. The current
//     index is always visually centered.
//   - Progress counter "N / Total" in the header.
//   - Pending-delete trash counter on the right of the action bar.
//
// The deck takes `assets` + a `$currentIndex` binding so the host can
// reflect the same index in a paged-mode view (we share the filmstrip).
struct SwipeCleanDeck: View {
    let assets: [MediaAssetRecord]
    @Binding var selectedAssetIDs: Set<String>
    @Binding var currentIndex: Int
    let accent: Color
    var onFinished: (() -> Void)? = nil
    /// Tapping the trash counter opens the Trash Bin sheet so the user
    /// can review, restore, or bulk-delete. Host owns the sheet; deck
    /// just signals.
    var onTrashTap: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var isCommitting: Bool = false
    @State private var outgoingAsset: MediaAssetRecord?
    @State private var outgoingDirection: CGFloat = 0
    @State private var lastDecision: (index: Int, decision: SwipeDecision)?
    @State private var cardSize: CGSize = .zero

    private let swipeThreshold: CGFloat = 110
    private let flingVelocity: CGFloat = 520

    var body: some View {
        VStack(spacing: 14) {
            cardArea

            actionBar

            FilmstripView(
                assets: assets,
                currentIndex: $currentIndex,
                selectedAssetIDs: selectedAssetIDs,
                accent: accent
            )
            .frame(height: 64)
        }
    }

    // MARK: - Card area

    private var cardArea: some View {
        GeometryReader { geo in
            ZStack {
                // Outgoing card (the one the user just swiped). Drawn
                // BELOW the incoming so the new image looks like it rose
                // up from underneath — gives a real sense of motion even
                // though there's no depth stack.
                if let outgoing = outgoingAsset {
                    SwipeCard(asset: outgoing, accent: accent)
                        .offset(x: outgoingDirection * (geo.size.width + 200))
                        .rotationEffect(.degrees(Double(outgoingDirection) * 18), anchor: .bottom)
                        .opacity(0.9)
                        .allowsHitTesting(false)
                        .zIndex(0)
                }

                // Incoming card (current).
                if let current = currentAsset {
                    SwipeCard(
                        asset: current,
                        accent: accent,
                        dragOffset: dragOffset,
                        rotation: rotationFor(offset: dragOffset, width: geo.size.width),
                        overlay: overlayFor(offset: dragOffset)
                    )
                    .zIndex(1)
                    .id(current.id) // forces the PhotoPreviewView to key on this asset
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onAppear { cardSize = geo.size }
            .onChange(of: geo.size) { _, new in cardSize = new }
            .simultaneousGesture(dragGesture(width: geo.size.width))
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            undoButton

            Button {
                commit(.delete)
            } label: {
                actionLabel(icon: "hand.thumbsdown.fill", title: "Delete", color: Color(hex: "#E63946"))
            }
            .buttonStyle(.plain)
            .disabled(currentAsset == nil || isCommitting)

            Button {
                commit(.keep)
            } label: {
                actionLabel(icon: "hand.thumbsup.fill", title: "Keep", color: Color(hex: "#2BB673"))
            }
            .buttonStyle(.plain)
            .disabled(currentAsset == nil || isCommitting)

            trashCounter
        }
    }

    private func actionLabel(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
            Text(title)
                .font(CleanupFont.body(15))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(color, in: Capsule(style: .continuous))
    }

    private var undoButton: some View {
        Button {
            undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(lastDecision == nil)
        .opacity(lastDecision == nil ? 0.35 : 1)
    }

    /// Pending-delete count — tap to open the Trash Bin sheet, where the
    /// user can review, tap-to-restore, or commit the bulk delete. The
    /// actual `PHPhotoLibrary.performChanges` call (which triggers Apple's
    /// native delete confirmation) lives in the host.
    private var trashCounter: some View {
        Button {
            guard selectedAssetIDs.count > 0 else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTrashTap?()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())

                if selectedAssetIDs.count > 0 {
                    Text("\(selectedAssetIDs.count)")
                        .font(CleanupFont.badge(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#E63946"), in: Capsule(style: .continuous))
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(selectedAssetIDs.count == 0)
        .opacity(selectedAssetIDs.count == 0 ? 0.45 : 1)
    }

    // MARK: - Derived

    private var currentAsset: MediaAssetRecord? {
        assets.indices.contains(currentIndex) ? assets[currentIndex] : nil
    }

    // MARK: - Gesture

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !isCommitting else { return }
                // Lock vertical — card travels left/right only. Prevents the
                // "pull-to-dismiss" misread the user reported.
                dragOffset = CGSize(width: value.translation.width, height: 0)
            }
            .onEnded { value in
                guard !isCommitting else { return }
                let horizontal = value.translation.width
                let velocity = value.predictedEndTranslation.width - value.translation.width

                if horizontal < -swipeThreshold || velocity < -flingVelocity {
                    fling(.delete, width: width)
                } else if horizontal > swipeThreshold || velocity > flingVelocity {
                    fling(.keep, width: width)
                } else {
                    withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.78)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func fling(_ decision: SwipeDecision, width: CGFloat) {
        guard !isCommitting, let current = currentAsset else { return }
        isCommitting = true

        UIImpactFeedbackGenerator(style: decision == .delete ? .rigid : .light).impactOccurred()

        switch decision {
        case .delete:
            selectedAssetIDs.insert(current.id)
        case .keep:
            selectedAssetIDs.remove(current.id)
        }
        lastDecision = (currentIndex, decision)

        // Hand the current asset off to the outgoing slot, reset drag,
        // advance the index. The outgoing card then flies off in a second
        // animation tick. This avoids the "both cards moving together"
        // look the old 3-stack had.
        outgoingAsset = current
        outgoingDirection = decision == .delete ? -1 : 1

        withAnimation(.easeOut(duration: 0.26)) {
            dragOffset = .zero
            currentIndex += 1
        }

        // Clear the outgoing card after its fly-out animation has visibly
        // completed. 320ms covers the 260ms animation + a beat of buffer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            outgoingAsset = nil
            outgoingDirection = 0
            isCommitting = false
            if currentIndex >= assets.count {
                onFinished?()
            }
        }
    }

    private func commit(_ decision: SwipeDecision) {
        fling(decision, width: max(cardSize.width, 360))
    }

    private func undo() {
        guard !isCommitting, let last = lastDecision else { return }
        let asset = assets[last.index]
        if last.decision == .delete {
            selectedAssetIDs.remove(asset.id)
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            currentIndex = last.index
        }
        lastDecision = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: - Layout math

    private func rotationFor(offset: CGSize, width: CGFloat) -> Double {
        let clamped = max(-1, min(1, offset.width / max(width, 1)))
        return Double(clamped) * 12
    }

    private func overlayFor(offset: CGSize) -> SwipeCardOverlay? {
        let dx = offset.width
        if dx < -40 {
            return .delete(strength: min(1, -dx / 160))
        } else if dx > 40 {
            return .keep(strength: min(1, dx / 160))
        }
        return nil
    }
}

// MARK: - SwipeCard

enum SwipeCardOverlay {
    case keep(strength: Double)
    case delete(strength: Double)
}

private struct SwipeCard: View {
    let asset: MediaAssetRecord
    let accent: Color
    var dragOffset: CGSize = .zero
    var rotation: Double = 0
    var overlay: SwipeCardOverlay? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.35))

            Group {
                if asset.mediaType == .video {
                    // For swipe mode the video doesn't need autoplay — the
                    // user is making a keep/delete judgement call on a
                    // thumbnail. Keeps memory flat.
                    PhotoThumbnailView(localIdentifier: asset.id, targetPointSize: 900)
                } else {
                    PhotoPreviewView(localIdentifier: asset.id)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if asset.mediaType == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            }

            if let overlay {
                overlayStamp(for: overlay)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
        .offset(dragOffset)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
    }

    @ViewBuilder
    private func overlayStamp(for overlay: SwipeCardOverlay) -> some View {
        switch overlay {
        case .keep(let strength):
            stamp(text: "KEEP", color: Color(hex: "#2BB673"), strength: strength, alignment: .topLeading, rotation: -14)
        case .delete(let strength):
            stamp(text: "DELETE", color: Color(hex: "#E63946"), strength: strength, alignment: .topTrailing, rotation: 14)
        }
    }

    private func stamp(text: String, color: Color, strength: Double, alignment: Alignment, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .heavy))
            .kerning(2)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color, lineWidth: 3)
            )
            .rotationEffect(.degrees(rotation))
            .opacity(strength)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - FilmstripView

/// Bottom thumbnail strip. Scrolls horizontally, auto-centers the current
/// index, and lets the user tap any thumbnail to jump. This is what makes
/// the UI feel native — users aren't locked into one-at-a-time navigation.
///
/// Uses `LazyHStack` so only on-screen thumbnails allocate memory, and the
/// shared `PhotoThumbnailView` uses `PHCachingImageManager` — so a 9k-asset
/// cluster doesn't explode.
struct FilmstripView: View {
    let assets: [MediaAssetRecord]
    @Binding var currentIndex: Int
    let selectedAssetIDs: Set<String>
    let accent: Color

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        FilmstripThumb(
                            asset: asset,
                            isCurrent: index == currentIndex,
                            isMarkedForDelete: selectedAssetIDs.contains(asset.id),
                            accent: accent
                        )
                        .id(index)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                currentIndex = index
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
            .onChange(of: currentIndex) { _, new in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }
}

private struct FilmstripThumb: View {
    let asset: MediaAssetRecord
    let isCurrent: Bool
    let isMarkedForDelete: Bool
    let accent: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnailView(localIdentifier: asset.id, targetPointSize: 140)
                .frame(width: 52, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isCurrent ? 2 : 1)
                )
                .scaleEffect(isCurrent ? 1.08 : 1.0)
                .opacity(isMarkedForDelete ? 0.45 : 1)

            if isMarkedForDelete {
                // Small red dot so the user can scan the strip and see
                // which ones they've already flagged. Much faster than
                // having to swipe back through to check.
                Circle()
                    .fill(Color(hex: "#E63946"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .offset(x: 4, y: -4)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isCurrent)
        .animation(.easeOut(duration: 0.18), value: isMarkedForDelete)
    }

    private var borderColor: Color {
        if isMarkedForDelete { return Color(hex: "#E63946").opacity(0.8) }
        if isCurrent { return accent }
        return Color.white.opacity(0.1)
    }
}

// MARK: - TrashBinSheet

/// Competitor-style trash bin. Shows every asset the user has marked
/// for deletion as a 3-column thumbnail grid. Tap a thumbnail to restore
/// it. "Empty Trash" runs the actual `PHPhotoLibrary.performChanges`
/// (which triggers Apple's native bulk-delete confirmation); "Restore
/// All" clears the pending set without touching Photos.
///
/// This is a *pending* trash — it mirrors the behavior of competitors'
/// apps and does not keep deleted assets after the native prompt is
/// accepted. iOS's own Recently Deleted album is what handles true
/// recovery.
struct TrashBinSheet: View {
    @Environment(\.dismiss) private var dismiss

    let assets: [MediaAssetRecord]
    @Binding var selectedAssetIDs: Set<String>
    let accent: Color
    /// Closure that actually performs the delete. Host wires this to
    /// `appFlow.deleteAssets` with the correct `FreeAction` kind for
    /// whichever preview surface opened the sheet.
    let onEmptyTrash: ([String]) async -> Bool

    @State private var isDeleting = false
    @State private var statusMessage: String?

    /// Only show items that are actually pending deletion AND still
    /// present in the source collection. This keeps the grid accurate
    /// if an asset gets removed from upstream between renders.
    private var pendingAssets: [MediaAssetRecord] {
        assets.filter { selectedAssetIDs.contains($0.id) }
    }

    private var totalBytes: Int64 {
        pendingAssets.reduce(0) { $0 + $1.sizeInBytes }
    }

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 16) {
                header

                hintPill

                if pendingAssets.isEmpty {
                    emptyState
                } else {
                    grid
                }

                Spacer(minLength: 8)

                if !pendingAssets.isEmpty {
                    emptyTrashButton
                    restoreAllButton
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Trash Bin (\(ByteCountFormatter.cleanupString(fromByteCount: totalBytes)))")
                .font(CleanupFont.sectionTitle(18))
                .foregroundStyle(.white)

            Spacer()

            // Visual weight counter-balance so the title stays centered.
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private var hintPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#FFD36E"))
            Text("Tap on Photo to Restore")
                .font(CleanupFont.body(14))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05), in: Capsule(style: .continuous))
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(pendingAssets, id: \.id) { asset in
                    TrashBinCell(asset: asset, accent: accent) {
                        restore(asset)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 36))
                .foregroundStyle(CleanupTheme.textTertiary)
            Text("Trash is empty")
                .font(CleanupFont.sectionTitle(16))
                .foregroundStyle(.white)
            Text("Mark items for deletion and they'll show up here.")
                .font(CleanupFont.caption(12))
                .foregroundStyle(CleanupTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyTrashButton: some View {
        Button {
            Task { await emptyTrash() }
        } label: {
            HStack(spacing: 10) {
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(isDeleting ? "Deleting…" : "Empty Trash")
                    .font(CleanupFont.body(16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#3B5BFF"))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    private var restoreAllButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.2)) {
                for asset in pendingAssets {
                    selectedAssetIDs.remove(asset.id)
                }
            }
        } label: {
            Text("Restore All")
                .font(CleanupFont.body(15))
                .foregroundStyle(Color(hex: "#4F8BFF"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    // MARK: - Actions

    private func restore(_ asset: MediaAssetRecord) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) {
            selectedAssetIDs.remove(asset.id)
        }
    }

    private func emptyTrash() async {
        let ids = pendingAssets.map(\.id)
        guard !ids.isEmpty, !isDeleting else { return }
        isDeleting = true
        statusMessage = nil
        // This call internally hits PHPhotoLibrary.performChanges, which
        // triggers iOS's native delete confirmation prompt automatically.
        // We don't need to show our own — Apple's is the loud/official one.
        let success = await onEmptyTrash(ids)
        isDeleting = false
        if success {
            // Remove from the pending set — the assets no longer exist.
            for id in ids { selectedAssetIDs.remove(id) }
            dismiss()
        } else {
            statusMessage = "Delete cancelled or failed. Nothing was removed."
        }
    }
}

private struct TrashBinCell: View {
    let asset: MediaAssetRecord
    let accent: Color
    let onTapToRestore: () -> Void

    var body: some View {
        Button(action: onTapToRestore) {
            ZStack(alignment: .topTrailing) {
                PhotoThumbnailView(localIdentifier: asset.id, targetPointSize: 240)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, Color(hex: "#3B5BFF"))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SwipeModeTogglePill

struct SwipeModeTogglePill: View {
    @Binding var isOn: Bool
    let accent: Color

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "hand.draw.fill" : "hand.draw")
                    .font(.system(size: 13, weight: .bold))
                Text("Swipe")
                    .font(CleanupFont.body(13))
            }
            .foregroundStyle(isOn ? .white : accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? accent.opacity(0.92) : accent.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

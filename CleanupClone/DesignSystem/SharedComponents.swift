import AVFoundation
import AVKit
import Photos
import SwiftUI
import UIKit

struct ScreenContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            CleanupTheme.background
                .overlay(alignment: .top) {
                    RadialGradient(
                        colors: [CleanupTheme.electricBlue.opacity(0.18), .clear],
                        center: .top,
                        startRadius: 20,
                        endRadius: 380
                    )
                    .frame(height: 280)
                }
                .ignoresSafeArea()

            content
        }
    }
}

struct PrimaryCTAButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        let label = Text(title)
            .font(CleanupFont.body(16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)

        Button(action: action) {
            label
        }
        .modifier(PrimaryCTAChrome())
    }
}

private struct PrimaryCTAChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(CleanupTheme.electricBlue)
        } else {
            content
                .background(CleanupTheme.cta)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: CleanupTheme.electricBlue.opacity(0.24), radius: 14, y: 8)
                .buttonStyle(.plain)
        }
    }
}

struct GlassIconLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
    }
}

struct GlassIconButton: View {
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassIconLabel(symbol: symbol)
        }
        .modifier(GlassActionChrome())
    }
}

struct GlassActionChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .tint(.white)
        } else {
            content
                .background(Color.white.opacity(0.05), in: Circle())
                .buttonStyle(.plain)
        }
    }
}

struct GlassCapsuleBadge<Label: View>: View {
    let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: {}) {
                label
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
            .disabled(true)
        } else {
            label
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
        }
    }
}

struct GlassProminentCTA<Label: View>: View {
    let action: () -> Void
    let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .modifier(GlassProminentCTAChrome())
    }
}

private struct GlassProminentCTAChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(CleanupTheme.electricBlue)
        } else {
            content
                .background(CleanupTheme.cta)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: CleanupTheme.electricBlue.opacity(0.22), radius: 12, y: 7)
                .buttonStyle(.plain)
        }
    }
}

struct PremiumPill: View {
    var body: some View {
        GlassCapsuleBadge {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                Text("PRO")
                    .font(CleanupFont.badge(12))
            }
            .foregroundStyle(.white)
        }
    }
}

struct UsageBar: View {
    let progress: CGFloat
    let palette: LinearGradient

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Capsule(style: .continuous)
                    .fill(palette)
                    .frame(width: max(18, proxy.size.width * progress))
            }
        }
        .frame(height: 18)
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    let content: Content

    init(cornerRadius: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CleanupTheme.card.opacity(0.95), CleanupTheme.cardAlt.opacity(0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.05))
                    )
            )
    }
}

struct CounterBadge: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(CleanupFont.badge(14))
                Text(subtitle)
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CleanupTheme.badgeBlue, in: Capsule(style: .continuous))
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(CleanupFont.sectionTitle())
            .foregroundStyle(CleanupTheme.textPrimary)
    }
}

struct HeaderIconTile: View {
    let symbol: String
    let title: String
    var palette: [Color]

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.white)
                )
                .frame(width: 98, height: 98)

            Text(title)
                .font(CleanupFont.body(18))
                .foregroundStyle(CleanupTheme.textPrimary)
        }
    }
}

struct PosterTile: View {
    let title: String
    let subtitle: String
    let palette: [Color]
    var locked: Bool = false
    var assetName: String? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let assetName, UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(CleanupFont.sectionTitle(18))
                        Text(subtitle)
                            .font(CleanupFont.caption(12))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(18)
                }
            }

            if locked {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, CleanupTheme.electricBlue)
                    .padding(12)
            }
        }
    }
}

struct GeneratedArtworkView: View {
    let assetName: String
    let fallbackSymbol: String
    var tint: Color = CleanupTheme.electricBlue
    var size: CGFloat = 88

    var body: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
        }
    }
}

struct PhotoThumbnailView: View {
    let localIdentifier: String
    var targetPointSize: CGFloat = 220

    private static let thumbnailManager = PHCachingImageManager()

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(CleanupTheme.textTertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task(id: localIdentifier) {
            image = nil
            await loadThumbnail(for: localIdentifier)
        }
        .onDisappear {
            cancelThumbnailRequest()
        }
    }

    private func loadThumbnail(for identifier: String) async {
        cancelThumbnailRequest()

        guard let asset = await MainActor.run(body: { PhotoAssetLookup.shared.asset(for: identifier) ?? fallbackAsset(for: identifier) }) else {
            image = nil
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.version = .current

        await withCheckedContinuation { continuation in
            var didResume = false
            let targetSize = Self.targetSize(for: targetPointSize)
            MediaWorkQueues.thumbnailQueue.async {
                let nextRequestID = Self.thumbnailManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                ) { uiImage, info in
                    guard identifier == localIdentifier else {
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume()
                        return
                    }

                    if let uiImage {
                        Task { @MainActor in
                            image = uiImage
                        }
                    }

                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

                    guard !didResume, isCancelled || !isDegraded else { return }
                    didResume = true
                    Task { @MainActor in
                        requestID = nil
                    }
                    continuation.resume()
                }

                Task { @MainActor in
                    requestID = nextRequestID
                }
            }
        }
    }

    private func cancelThumbnailRequest() {
        guard let requestID else { return }
        Self.thumbnailManager.cancelImageRequest(requestID)
        self.requestID = nil
    }

    static func startCaching(localIdentifiers: [String], targetPointSize: CGFloat = 220) {
        guard !localIdentifiers.isEmpty else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.version = .current

        Task { @MainActor in
            let assets = PhotoAssetLookup.shared.assets(for: localIdentifiers)
            guard !assets.isEmpty else { return }
            let targetSize = targetSize(for: targetPointSize)
            MediaWorkQueues.thumbnailQueue.async {
                Self.thumbnailManager.startCachingImages(
                    for: assets,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                )
            }
        }
    }

    static func stopCaching(localIdentifiers: [String], targetPointSize: CGFloat = 220) {
        guard !localIdentifiers.isEmpty else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.version = .current

        Task { @MainActor in
            let assets = PhotoAssetLookup.shared.assets(for: localIdentifiers)
            guard !assets.isEmpty else { return }
            let targetSize = targetSize(for: targetPointSize)
            MediaWorkQueues.thumbnailQueue.async {
                Self.thumbnailManager.stopCachingImages(
                    for: assets,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                )
            }
        }
    }

    private static func targetSize(for targetPointSize: CGFloat) -> CGSize {
        let scale = UIScreen.main.scale
        let dimension = max(120, min(targetPointSize * scale, 360))
        return CGSize(width: dimension, height: dimension)
    }

    @MainActor
    private func fallbackAsset(for identifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        PhotoAssetLookup.shared.upsert(asset)
        return asset
    }
}

struct PhotoPreviewView: View {
    let localIdentifier: String

    private static let previewManager = PHCachingImageManager()

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))

            if let image {
                ZoomablePhotoContainer(image: image)
            } else {
                ProgressView()
                    .tint(.white.opacity(0.8))
            }
        }
        .task(id: localIdentifier) {
            image = nil
            await loadPreview(for: localIdentifier)
        }
        .onDisappear {
            cancelPreviewRequest()
        }
    }

    private func loadPreview(for identifier: String) async {
        cancelPreviewRequest()

        guard let asset = await MainActor.run(body: { PhotoAssetLookup.shared.asset(for: identifier) ?? fallbackAsset(for: identifier) }) else {
            image = nil
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.version = .current

        await withCheckedContinuation { continuation in
            var didResume = false
            requestID = Self.previewManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data, let uiImage = UIImage(data: data) {
                    image = uiImage
                }

                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

                guard !didResume, isCancelled || !isDegraded else { return }
                didResume = true
                requestID = nil
                continuation.resume()
            }
        }
    }

    private func cancelPreviewRequest() {
        guard let requestID else { return }
        Self.previewManager.cancelImageRequest(requestID)
        self.requestID = nil
    }

    @MainActor
    private func fallbackAsset(for identifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        PhotoAssetLookup.shared.upsert(asset)
        return asset
    }
}

// MARK: - Video Player

struct VideoPlayerView: View {
    let localIdentifier: String
    let autoPlay: Bool

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var controlTimer: Task<Void, Never>?

    init(localIdentifier: String, autoPlay: Bool = true) {
        self.localIdentifier = localIdentifier
        self.autoPlay = autoPlay
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))

            if let player {
                VideoPlayerLayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture { toggleControls() }

                // Play/Pause overlay
                if showControls {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            } else if isLoading {
                ProgressView()
                    .tint(.white.opacity(0.8))
            }
        }
        .task(id: localIdentifier) {
            await loadVideo(for: localIdentifier)
        }
        .onDisappear {
            controlTimer?.cancel()
            player?.pause()
            player = nil
        }
    }

    private func loadVideo(for identifier: String) async {
        isLoading = true
        player?.pause()
        player = nil

        guard let phAsset = await MainActor.run(body: {
            PhotoAssetLookup.shared.asset(for: identifier) ?? fallbackAsset(for: identifier)
        }) else {
            isLoading = false
            return
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        await withCheckedContinuation { continuation in
            var didResume = false
            PHCachingImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                Task { @MainActor in
                    if let avAsset {
                        let playerItem = AVPlayerItem(asset: avAsset)
                        let newPlayer = AVPlayer(playerItem: playerItem)
                        newPlayer.isMuted = true
                        self.player = newPlayer
                        self.isLoading = false

                        // Loop playback
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: playerItem,
                            queue: .main
                        ) { _ in
                            newPlayer.seek(to: .zero)
                            newPlayer.play()
                        }

                        if autoPlay {
                            newPlayer.play()
                            isPlaying = true
                            scheduleControlHide()
                        }
                    } else {
                        self.isLoading = false
                    }

                    if !didResume {
                        didResume = true
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            controlTimer?.cancel()
        } else {
            player.play()
            isPlaying = true
            scheduleControlHide()
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls && isPlaying {
            scheduleControlHide()
        }
    }

    private func scheduleControlHide() {
        controlTimer?.cancel()
        controlTimer = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }

    @MainActor
    private func fallbackAsset(for identifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        PhotoAssetLookup.shared.upsert(asset)
        return asset
    }
}

/// UIViewRepresentable wrapper for AVPlayerLayer to get proper video rendering
private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Zoomable Photo

private struct ZoomablePhotoContainer: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomablePhotoScrollView {
        let view = ZoomablePhotoScrollView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ uiView: ZoomablePhotoScrollView, context: Context) {
        uiView.setImage(image)
    }
}

private final class ZoomablePhotoScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastImageIdentifier: ObjectIdentifier?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image else { return }
        layoutImage(image)
        centerImageIfNeeded()
    }

    func setImage(_ image: UIImage) {
        let identifier = ObjectIdentifier(image)
        if lastImageIdentifier != identifier {
            imageView.image = image
            lastImageIdentifier = identifier
            zoomScale = 1
        }

        layoutImage(image)
        centerImageIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageIfNeeded()
    }

    private func layoutImage(_ image: UIImage) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let imageSize = image.size
        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let fittedScale = min(widthScale, heightScale)

        let fittedSize = CGSize(
            width: imageSize.width * fittedScale,
            height: imageSize.height * fittedScale
        )

        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        contentSize = fittedSize
        minimumZoomScale = 1
        maximumZoomScale = 5
    }

    private func centerImageIfNeeded() {
        let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(
            x: contentSize.width * 0.5 + offsetX,
            y: contentSize.height * 0.5 + offsetY
        )
    }
}

// MARK: - Drag-to-Select Grid Support

/// PreferenceKey that collects cell frames keyed by item ID.
struct DragSelectCellFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Modifier that reports a cell's frame in the given coordinate space.
struct DragSelectCellModifier: ViewModifier {
    let id: String
    let coordinateSpace: String

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DragSelectCellFrameKey.self,
                        value: [id: geo.frame(in: .named(coordinateSpace))]
                    )
                }
            )
    }
}

/// Observable state for drag-to-select gesture.
@MainActor
final class DragSelectState: ObservableObject {
    @Published var isDragging = false

    /// IDs of items the finger has passed over during this drag.
    @Published var dragSelectedIDs: Set<String> = []

    /// The ordered list of item IDs in the grid (row-major order).
    var orderedIDs: [String] = []

    /// Cell frames keyed by ID, updated from preference changes.
    var cellFrames: [String: CGRect] = [:]

    /// Index of the first cell the drag started on.
    private var anchorIndex: Int?

    /// Whether the anchor cell was already selected (drag to deselect).
    private var isDeselecting = false

    /// The pre-drag selection state, so we can compute the delta.
    private var baseSelection: Set<String> = []

    func dragBegan(at point: CGPoint, currentSelection: Set<String>) {
        guard let hitID = cellID(at: point),
              let hitIndex = orderedIDs.firstIndex(of: hitID) else { return }

        isDragging = true
        anchorIndex = hitIndex
        baseSelection = currentSelection
        isDeselecting = currentSelection.contains(hitID)

        // Immediately include the anchor cell
        dragSelectedIDs = [hitID]
    }

    func dragMoved(to point: CGPoint) -> Set<String>? {
        guard isDragging, let anchorIndex else { return nil }

        // Find the cell closest to the current point
        guard let currentID = cellID(at: point),
              let currentIndex = orderedIDs.firstIndex(of: currentID) else { return nil }

        // Select all cells between anchor and current position (inclusive)
        let lo = min(anchorIndex, currentIndex)
        let hi = max(anchorIndex, currentIndex)
        let swept = Set(orderedIDs[lo...hi])

        dragSelectedIDs = swept

        // Compute the resulting selection
        if isDeselecting {
            return baseSelection.subtracting(swept)
        } else {
            return baseSelection.union(swept)
        }
    }

    func dragEnded() -> Set<String>? {
        guard isDragging else { return nil }
        isDragging = false

        let result: Set<String>
        if isDeselecting {
            result = baseSelection.subtracting(dragSelectedIDs)
        } else {
            result = baseSelection.union(dragSelectedIDs)
        }

        dragSelectedIDs.removeAll()
        anchorIndex = nil
        baseSelection.removeAll()
        return result
    }

    func cancelDrag() {
        isDragging = false
        dragSelectedIDs.removeAll()
        anchorIndex = nil
        baseSelection.removeAll()
    }

    /// Find which cell contains the given point.
    private func cellID(at point: CGPoint) -> String? {
        // First try exact hit test
        for (id, frame) in cellFrames {
            if frame.contains(point) { return id }
        }

        // If no exact hit, find the closest cell (allows dragging between cells)
        var bestID: String?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (id, frame) in cellFrames {
            let cx = frame.midX
            let cy = frame.midY
            let dx = point.x - cx
            let dy = point.y - cy
            let dist = dx * dx + dy * dy
            if dist < bestDist {
                bestDist = dist
                bestID = id
            }
        }

        // Only snap to closest cell if within reasonable distance (1.5x cell size)
        if let bestID, let frame = cellFrames[bestID] {
            let maxSnapDist = max(frame.width, frame.height) * 1.5
            if bestDist < maxSnapDist * maxSnapDist {
                return bestID
            }
        }

        return nil
    }
}

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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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

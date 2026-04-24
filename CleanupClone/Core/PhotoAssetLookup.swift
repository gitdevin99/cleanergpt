import Photos

@MainActor
final class PhotoAssetLookup {
    static let shared = PhotoAssetLookup()

    private var assetsByIdentifier: [String: PHAsset] = [:]

    private init() {}

    func reset() {
        assetsByIdentifier.removeAll(keepingCapacity: false)
    }

    func upsert(_ asset: PHAsset) {
        assetsByIdentifier[asset.localIdentifier] = asset
    }

    func upsert(contentsOf fetchResult: PHFetchResult<PHAsset>) {
        for index in 0..<fetchResult.count {
            let asset = fetchResult.object(at: index)
            assetsByIdentifier[asset.localIdentifier] = asset
        }
    }

    func remove(localIdentifiers: some Sequence<String>) {
        for identifier in localIdentifiers {
            assetsByIdentifier.removeValue(forKey: identifier)
        }
    }

    func asset(for localIdentifier: String) -> PHAsset? {
        assetsByIdentifier[localIdentifier]
    }

    func assets(for localIdentifiers: [String]) -> [PHAsset] {
        localIdentifiers.compactMap { assetsByIdentifier[$0] }
    }

    /// Rehydrates `PHAsset` references for a set of local identifiers
    /// on a background queue. Used on cold-launch after we restore the
    /// scan snapshot from disk: the snapshot carries asset IDs, but the
    /// thumbnail image manager needs the actual `PHAsset` object. Runs
    /// the `PHAsset.fetchAssets(withLocalIdentifiers:)` call off-main
    /// so it never blocks the first frame, then hops back to the main
    /// actor to upsert.
    nonisolated func prime(localIdentifiers: [String]) {
        guard !localIdentifiers.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let fetch = PHAsset.fetchAssets(
                withLocalIdentifiers: localIdentifiers,
                options: nil
            )
            var collected: [PHAsset] = []
            collected.reserveCapacity(fetch.count)
            for index in 0..<fetch.count {
                collected.append(fetch.object(at: index))
            }
            let assets = collected
            Task { @MainActor in
                for asset in assets {
                    PhotoAssetLookup.shared.upsert(asset)
                }
            }
        }
    }
}


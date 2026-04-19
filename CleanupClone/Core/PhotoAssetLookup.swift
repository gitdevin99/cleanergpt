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
}


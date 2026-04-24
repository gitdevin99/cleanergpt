import Foundation
import Photos

/// On-disk cache of the most recent library scan's *output* (what the
/// dashboard and cluster views read). Persisting this across launches
/// is how we avoid the "close the app, reopen it, and wait for a full
/// rescan before anything shows up" experience.
///
/// We deliberately do NOT persist the Vision / feature-print / face
/// caches or the `LibraryBucketsCache` routing map. Those are rebuilt
/// lazily by the scan pipeline, live only in memory during a session,
/// and staking anything on their on-disk shape would couple the cache
/// to the (still-evolving) scan internals. The snapshot here is just
/// the final, user-visible list of records per category — bit-for-bit
/// what `applyLibrarySnapshot` hands to the UI.
///
/// Schema is versioned. A mismatch means the previous app version wrote
/// something this build can't trust, so we drop the cache and fall
/// through to a full rescan. Better to scan once than ship wrong data.
enum ScanSnapshotStore {

    /// Bump this whenever the on-disk shape changes (fields added /
    /// removed / renamed in `Persisted*` below). Old snapshots will be
    /// ignored — the user pays one full rescan, then they're back on
    /// the fast path.
    private static let schemaVersion = 1

    // MARK: - Persisted shapes

    private struct PersistedAsset: Codable {
        let id: String
        let title: String
        let subtitle: String
        let sizeInBytes: Int64
        let duration: TimeInterval
        let createdAt: Date?
        let modificationAt: Date?
        let mediaTypeRaw: Int
        let isScreenshot: Bool
        let pixelWidth: Int
        let pixelHeight: Int

        init(_ record: MediaAssetRecord) {
            self.id = record.id
            self.title = record.title
            self.subtitle = record.subtitle
            self.sizeInBytes = record.sizeInBytes
            self.duration = record.duration
            self.createdAt = record.createdAt
            self.modificationAt = record.modificationAt
            self.mediaTypeRaw = record.mediaType.rawValue
            self.isScreenshot = record.isScreenshot
            self.pixelWidth = record.pixelWidth
            self.pixelHeight = record.pixelHeight
        }

        func toRecord() -> MediaAssetRecord {
            MediaAssetRecord(
                id: id,
                title: title,
                subtitle: subtitle,
                sizeInBytes: sizeInBytes,
                duration: duration,
                createdAt: createdAt,
                modificationAt: modificationAt,
                mediaType: PHAssetMediaType(rawValue: mediaTypeRaw) ?? .unknown,
                isScreenshot: isScreenshot,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        }
    }

    private struct PersistedCluster: Codable {
        let id: String
        let categoryRaw: String
        let assetIDs: [String]
        let subtitle: String?
    }

    private struct PersistedSnapshot: Codable {
        let schemaVersion: Int
        let capturedAt: Date
        let totalLibraryItems: Int
        let photoCount: Int
        let videoCount: Int
        let confirmedScreenRecordingIDs: [String]
        let assetsByCategory: [String: [PersistedAsset]]
        /// Map category raw → ordered list of clusters. Each cluster
        /// just references asset IDs; we rehydrate full records by
        /// looking up into `assetsByCategory` on load.
        let clustersByCategory: [String: [PersistedCluster]]
    }

    /// What callers get back on a successful load. Already in the same
    /// shape that `AppFlow` stores in-memory — no further massaging
    /// required.
    struct Loaded {
        let capturedAt: Date
        let totalLibraryItems: Int
        let photoCount: Int
        let videoCount: Int
        let confirmedScreenRecordingIDs: Set<String>
        let mediaAssetsByCategory: [DashboardCategoryKind: [MediaAssetRecord]]
        let mediaClustersByCategory: [DashboardCategoryKind: [MediaCluster]]
    }

    // MARK: - File location

    /// `~/Library/Application Support/CleanupClone/ScanSnapshot.json`.
    /// Same directory `MediaAnalysisStore` writes its SQLite into, so a
    /// wipe of Application Support clears both together.
    private static func snapshotURL() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("CleanupClone", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("ScanSnapshot.json", isDirectory: false)
    }

    // MARK: - Public API

    /// Loads the previously-saved snapshot. Any failure — file missing,
    /// schema mismatch, decode error — returns `nil` and the caller is
    /// expected to fall through to a full rescan. Never throws.
    static func load() -> Loaded? {
        guard let url = snapshotURL(), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(PersistedSnapshot.self, from: data)
            guard snapshot.schemaVersion == schemaVersion else {
                // Schema drifted. Don't try to coerce old data — we'd
                // rather eat one rescan than mis-categorize something.
                try? FileManager.default.removeItem(at: url)
                return nil
            }

            var assets: [DashboardCategoryKind: [MediaAssetRecord]] = [:]
            for (rawKind, rawAssets) in snapshot.assetsByCategory {
                guard let kind = DashboardCategoryKind(rawValue: rawKind) else { continue }
                assets[kind] = rawAssets.map { $0.toRecord() }
            }
            // Ensure every category key exists (downstream code reads
            // with `default: []` but we keep the shape uniform).
            for kind in DashboardCategoryKind.allCases where assets[kind] == nil {
                assets[kind] = []
            }

            var clusters: [DashboardCategoryKind: [MediaCluster]] = [:]
            for (rawKind, rawClusters) in snapshot.clustersByCategory {
                guard let kind = DashboardCategoryKind(rawValue: rawKind) else { continue }
                let assetLookup: [String: MediaAssetRecord] = Dictionary(
                    (assets[kind] ?? []).map { ($0.id, $0) },
                    uniquingKeysWith: { lhs, _ in lhs }
                )
                clusters[kind] = rawClusters.compactMap { persistedCluster in
                    let hydrated = persistedCluster.assetIDs.compactMap { assetLookup[$0] }
                    guard !hydrated.isEmpty else { return nil }
                    return MediaCluster(
                        id: persistedCluster.id,
                        category: kind,
                        assets: hydrated,
                        totalBytes: hydrated.reduce(0) { $0 + $1.sizeInBytes },
                        subtitle: persistedCluster.subtitle
                    )
                }
            }
            for kind in DashboardCategoryKind.allCases where clusters[kind] == nil {
                clusters[kind] = []
            }

            return Loaded(
                capturedAt: snapshot.capturedAt,
                totalLibraryItems: snapshot.totalLibraryItems,
                photoCount: snapshot.photoCount,
                videoCount: snapshot.videoCount,
                confirmedScreenRecordingIDs: Set(snapshot.confirmedScreenRecordingIDs),
                mediaAssetsByCategory: assets,
                mediaClustersByCategory: clusters
            )
        } catch {
            // Corrupt file — nuke it so we don't keep tripping over it
            // on every launch.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Writes the snapshot atomically. Called after a full scan, after
    /// pixel-verified duplicates are in place, and after an incremental
    /// library change is applied. Safe to call from any thread; the
    /// file write itself happens on a background queue so the caller
    /// never blocks the main thread on disk I/O.
    static func save(
        totalLibraryItems: Int,
        photoCount: Int,
        videoCount: Int,
        confirmedScreenRecordingIDs: Set<String>,
        assetsByCategory: [DashboardCategoryKind: [MediaAssetRecord]],
        clustersByCategory: [DashboardCategoryKind: [MediaCluster]]
    ) {
        var persistedAssets: [String: [PersistedAsset]] = [:]
        for (kind, records) in assetsByCategory {
            persistedAssets[kind.rawValue] = records.map(PersistedAsset.init)
        }
        var persistedClusters: [String: [PersistedCluster]] = [:]
        for (kind, clusters) in clustersByCategory {
            persistedClusters[kind.rawValue] = clusters.map { cluster in
                PersistedCluster(
                    id: cluster.id,
                    categoryRaw: kind.rawValue,
                    assetIDs: cluster.assets.map(\.id),
                    subtitle: cluster.subtitle
                )
            }
        }
        let snapshot = PersistedSnapshot(
            schemaVersion: schemaVersion,
            capturedAt: Date(),
            totalLibraryItems: totalLibraryItems,
            photoCount: photoCount,
            videoCount: videoCount,
            confirmedScreenRecordingIDs: Array(confirmedScreenRecordingIDs),
            assetsByCategory: persistedAssets,
            clustersByCategory: persistedClusters
        )

        DispatchQueue.global(qos: .utility).async {
            guard let url = snapshotURL() else { return }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                // Snapshot save is best-effort. Failing here just means
                // the next launch pays a rescan — not a user-visible
                // bug, no need to surface.
            }
        }
    }

    /// Deletes the on-disk snapshot. Called when the user signs out or
    /// the app's data is otherwise reset. Not wired up yet, but handy.
    static func clear() {
        guard let url = snapshotURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

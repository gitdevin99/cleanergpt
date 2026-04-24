import Foundation
import Photos
import SQLite3
import Vision

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct PersistedMediaAnalysis: Sendable {
    let faceCount: Int?
    let featurePrintArchive: Data?
    let visualSignature: MediaVisualSignature?
}

actor MediaAnalysisStore {
    static let schemaVersion = 1
    static let analysisVersion = 1

    private var database: OpaquePointer?

    func upsertMetadataBatch(_ records: [MediaAssetRecord]) {
        guard !records.isEmpty else { return }

        do {
            let database = try openDatabaseIfNeeded()
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            defer {
                sqlite3_exec(database, "COMMIT", nil, nil, nil)
            }

            let sql = """
            INSERT INTO assets_analysis (
                local_identifier,
                creation_date,
                modification_date,
                pixel_width,
                pixel_height,
                media_type,
                is_screenshot,
                file_size_estimate,
                face_count,
                feature_print,
                visual_dhash,
                visual_mean_luma,
                visual_spread,
                analysis_version,
                indexed_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, 0, ?)
            ON CONFLICT(local_identifier) DO UPDATE SET
                creation_date = excluded.creation_date,
                modification_date = excluded.modification_date,
                pixel_width = excluded.pixel_width,
                pixel_height = excluded.pixel_height,
                media_type = excluded.media_type,
                is_screenshot = excluded.is_screenshot,
                file_size_estimate = excluded.file_size_estimate,
                indexed_at = excluded.indexed_at,
                face_count = CASE
                    WHEN \(metadataMatchesCurrentVersionSQL) THEN assets_analysis.face_count
                    ELSE NULL
                END,
                feature_print = CASE
                    WHEN \(metadataMatchesCurrentVersionSQL) THEN assets_analysis.feature_print
                    ELSE NULL
                END,
                visual_dhash = CASE
                    WHEN \(metadataMatchesCurrentVersionSQL) THEN assets_analysis.visual_dhash
                    ELSE NULL
                END,
                visual_mean_luma = CASE
                    WHEN \(metadataMatchesCurrentVersionSQL) THEN assets_analysis.visual_mean_luma
                    ELSE NULL
                END,
                visual_spread = CASE
                    WHEN \(metadataMatchesCurrentVersionSQL) THEN assets_analysis.visual_spread
                    ELSE NULL
                END,
                analysis_version = CASE
                    WHEN \(metadataMatchesCurrentVersionSQL) THEN assets_analysis.analysis_version
                    ELSE 0
                END
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message: lastErrorMessage(in: database))
            }
            defer { sqlite3_finalize(statement) }

            for record in records {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)

                bindText(record.id, to: 1, in: statement)
                bindInt64(record.createdAt.map(Self.epochSeconds(from:)) ?? 0, to: 2, in: statement)
                bindOptionalInt64(record.modificationAt.map(Self.epochSeconds(from:)), to: 3, in: statement)
                sqlite3_bind_int(statement, 4, Int32(record.pixelWidth))
                sqlite3_bind_int(statement, 5, Int32(record.pixelHeight))
                sqlite3_bind_int(statement, 6, Int32(record.mediaType.rawValue))
                sqlite3_bind_int(statement, 7, record.isScreenshot ? 1 : 0)
                bindInt64(record.sizeInBytes, to: 8, in: statement)
                bindInt64(Self.currentTimestamp(), to: 9, in: statement)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw StoreError.step(message: lastErrorMessage(in: database))
                }
            }
        } catch {
            debugPrint("MediaAnalysisStore upsertMetadataBatch failed:", error.localizedDescription)
        }
    }

    /// Loads every asset's persisted metadata in a single query and
    /// rebuilds a `MediaAssetRecord` for each row. This is the function
    /// that turns the SQLite database into the source of truth for
    /// "what have we already scanned" — a cold-launch `performLibraryScan`
    /// pulls this once, looks up by `localIdentifier`, and skips the
    /// expensive `makeMediaRecord` + `PHAssetResource` size lookup for
    /// anything already in the DB. Only genuinely-new assets pay the
    /// full scan pipeline. Everything else = ~microseconds per asset.
    ///
    /// Title and subtitle are derived from the stored media_type,
    /// is_screenshot, and creation_date — same formatting that
    /// `makeMediaRecord` / `mediaDisplayTitle` produce when building a
    /// record from a live `PHAsset`. Matching those strings exactly
    /// matters because the UI keys off them in a few places (sort
    /// stability across rescans, etc.).
    func loadAllRecords() -> [String: MediaAssetRecord] {
        do {
            let database = try openDatabaseIfNeeded()
            let sql = """
            SELECT
                local_identifier,
                creation_date,
                modification_date,
                pixel_width,
                pixel_height,
                media_type,
                is_screenshot,
                file_size_estimate
            FROM assets_analysis
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message: lastErrorMessage(in: database))
            }
            defer { sqlite3_finalize(statement) }

            var records: [String: MediaAssetRecord] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idPointer = sqlite3_column_text(statement, 0) else { continue }
                let localIdentifier = String(cString: idPointer)
                let creationEpoch = sqlite3_column_int64(statement, 1)
                let createdAt: Date? = creationEpoch == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(creationEpoch))
                let modificationAt: Date?
                if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                    modificationAt = nil
                } else {
                    modificationAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2)))
                }
                let pixelWidth = Int(sqlite3_column_int(statement, 3))
                let pixelHeight = Int(sqlite3_column_int(statement, 4))
                let mediaType = PHAssetMediaType(rawValue: Int(sqlite3_column_int(statement, 5))) ?? .unknown
                let isScreenshot = sqlite3_column_int(statement, 6) != 0
                let sizeInBytes = sqlite3_column_int64(statement, 7)

                let title = Self.displayTitle(
                    mediaType: mediaType,
                    isScreenshot: isScreenshot,
                    createdAt: createdAt
                )
                let subtitle = Self.shortDate(createdAt)

                // duration isn't persisted (it was never needed by the
                // downstream code — videos get a fresh duration via
                // PHAsset when they get played), so we default to 0
                // here and the scan-time pipeline will fill it in when
                // the asset gets routed from a live PHAsset.
                records[localIdentifier] = MediaAssetRecord(
                    id: localIdentifier,
                    title: title,
                    subtitle: subtitle,
                    sizeInBytes: sizeInBytes,
                    duration: 0,
                    createdAt: createdAt,
                    modificationAt: modificationAt,
                    mediaType: mediaType,
                    isScreenshot: isScreenshot,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight
                )
            }
            return records
        } catch {
            debugPrint("MediaAnalysisStore loadAllRecords failed:", error.localizedDescription)
            return [:]
        }
    }

    /// Loads just the set of known `localIdentifier`s — much cheaper
    /// than `loadAllRecords()` when the caller only needs to do set
    /// arithmetic (e.g. "which IDs in the current PHFetchResult are new?").
    func loadAllIdentifiers() -> Set<String> {
        do {
            let database = try openDatabaseIfNeeded()
            let sql = "SELECT local_identifier FROM assets_analysis"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message: lastErrorMessage(in: database))
            }
            defer { sqlite3_finalize(statement) }
            var ids: Set<String> = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pointer = sqlite3_column_text(statement, 0) else { continue }
                ids.insert(String(cString: pointer))
            }
            return ids
        } catch {
            debugPrint("MediaAnalysisStore loadAllIdentifiers failed:", error.localizedDescription)
            return []
        }
    }

    func cachedAnalysis(for asset: MediaAssetRecord) -> PersistedMediaAnalysis? {
        do {
            let database = try openDatabaseIfNeeded()
            let sql = """
            SELECT face_count, feature_print, visual_dhash, visual_mean_luma, visual_spread
            FROM assets_analysis
            WHERE local_identifier = ?
              AND analysis_version = ?
            LIMIT 1
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message: lastErrorMessage(in: database))
            }
            defer { sqlite3_finalize(statement) }

            bindText(asset.id, to: 1, in: statement)
            sqlite3_bind_int(statement, 2, Int32(Self.analysisVersion))

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            let faceCount: Int?
            if sqlite3_column_type(statement, 0) == SQLITE_NULL {
                faceCount = nil
            } else {
                faceCount = Int(sqlite3_column_int(statement, 0))
            }

            let featurePrintArchive = blob(at: 1, in: statement)

            let visualSignature: MediaVisualSignature?
            if let dHashHex = text(at: 2, in: statement),
               let dHash = UInt64(dHashHex, radix: 16),
               sqlite3_column_type(statement, 3) != SQLITE_NULL,
               sqlite3_column_type(statement, 4) != SQLITE_NULL
            {
                visualSignature = MediaVisualSignature(
                    dHash: dHash,
                    meanLuma: Int(sqlite3_column_int(statement, 3)),
                    spread: Int(sqlite3_column_int(statement, 4))
                )
            } else {
                visualSignature = nil
            }

            return PersistedMediaAnalysis(
                faceCount: faceCount,
                featurePrintArchive: featurePrintArchive,
                visualSignature: visualSignature
            )
        } catch {
            debugPrint("MediaAnalysisStore cachedAnalysis failed:", error.localizedDescription)
            return nil
        }
    }

    func saveDerivedSignals(
        for asset: MediaAssetRecord,
        faceCount: Int?,
        featurePrintArchive: Data?,
        visualSignature: MediaVisualSignature?
    ) {
        guard faceCount != nil || featurePrintArchive != nil || visualSignature != nil else { return }

        do {
            let database = try openDatabaseIfNeeded()
            let sql = """
            UPDATE assets_analysis
            SET face_count = COALESCE(?, face_count),
                feature_print = COALESCE(?, feature_print),
                visual_dhash = COALESCE(?, visual_dhash),
                visual_mean_luma = COALESCE(?, visual_mean_luma),
                visual_spread = COALESCE(?, visual_spread),
                analysis_version = ?,
                indexed_at = ?
            WHERE local_identifier = ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message: lastErrorMessage(in: database))
            }
            defer { sqlite3_finalize(statement) }

            if let faceCount {
                sqlite3_bind_int(statement, 1, Int32(faceCount))
            } else {
                sqlite3_bind_null(statement, 1)
            }

            if let featurePrintArchive {
                bindBlob(featurePrintArchive, to: 2, in: statement)
            } else {
                sqlite3_bind_null(statement, 2)
            }

            if let visualSignature {
                bindText(String(visualSignature.dHash, radix: 16), to: 3, in: statement)
                sqlite3_bind_int(statement, 4, Int32(visualSignature.meanLuma))
                sqlite3_bind_int(statement, 5, Int32(visualSignature.spread))
            } else {
                sqlite3_bind_null(statement, 3)
                sqlite3_bind_null(statement, 4)
                sqlite3_bind_null(statement, 5)
            }

            sqlite3_bind_int(statement, 6, Int32(Self.analysisVersion))
            bindInt64(Self.currentTimestamp(), to: 7, in: statement)
            bindText(asset.id, to: 8, in: statement)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(message: lastErrorMessage(in: database))
            }
        } catch {
            debugPrint("MediaAnalysisStore saveDerivedSignals failed:", error.localizedDescription)
        }
    }

    func deleteAnalyses(for identifiers: [String]) {
        let uniqueIdentifiers = Array(Set(identifiers)).filter { !$0.isEmpty }
        guard !uniqueIdentifiers.isEmpty else { return }

        do {
            let database = try openDatabaseIfNeeded()
            let placeholders = Array(repeating: "?", count: uniqueIdentifiers.count).joined(separator: ",")
            let sql = "DELETE FROM assets_analysis WHERE local_identifier IN (\(placeholders))"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message: lastErrorMessage(in: database))
            }
            defer { sqlite3_finalize(statement) }

            for (index, identifier) in uniqueIdentifiers.enumerated() {
                bindText(identifier, to: Int32(index + 1), in: statement)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(message: lastErrorMessage(in: database))
            }
        } catch {
            debugPrint("MediaAnalysisStore deleteAnalyses failed:", error.localizedDescription)
        }
    }

    private func openDatabaseIfNeeded() throws -> OpaquePointer {
        if let database {
            return database
        }

        let url = try Self.databaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database
        else {
            throw StoreError.open(message: database.flatMap(lastErrorMessage(in:)) ?? "Unable to open database")
        }

        sqlite3_busy_timeout(database, 3_000)

        try execute("PRAGMA journal_mode = WAL", on: database)
        try execute("PRAGMA synchronous = NORMAL", on: database)
        try prepareSchema(in: database)

        self.database = database
        return database
    }

    private func prepareSchema(in database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS analysis_metadata (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                schema_version INTEGER NOT NULL
            )
            """,
            on: database
        )

        let existingVersion = try loadSchemaVersion(in: database)
        if existingVersion != 0, existingVersion != Self.schemaVersion {
            try execute("DROP TABLE IF EXISTS assets_analysis", on: database)
            try execute("DELETE FROM analysis_metadata WHERE id = 1", on: database)
        }

        try execute(
            """
            INSERT OR REPLACE INTO analysis_metadata (id, schema_version)
            VALUES (1, \(Self.schemaVersion))
            """,
            on: database
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS assets_analysis (
                local_identifier TEXT PRIMARY KEY,
                creation_date INTEGER,
                modification_date INTEGER,
                pixel_width INTEGER NOT NULL,
                pixel_height INTEGER NOT NULL,
                media_type INTEGER NOT NULL,
                is_screenshot INTEGER NOT NULL,
                file_size_estimate INTEGER NOT NULL,
                face_count INTEGER,
                feature_print BLOB,
                visual_dhash TEXT,
                visual_mean_luma INTEGER,
                visual_spread INTEGER,
                analysis_version INTEGER NOT NULL DEFAULT 0,
                indexed_at INTEGER NOT NULL
            )
            """,
            on: database
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_assets_analysis_creation_date ON assets_analysis (creation_date)",
            on: database
        )
        try execute(
            """
            UPDATE assets_analysis
            SET face_count = NULL,
                feature_print = NULL,
                visual_dhash = NULL,
                visual_mean_luma = NULL,
                visual_spread = NULL,
                analysis_version = 0
            WHERE analysis_version NOT IN (0, \(Self.analysisVersion))
            """,
            on: database
        )
    }

    private func loadSchemaVersion(in database: OpaquePointer) throws -> Int {
        let sql = "SELECT schema_version FROM analysis_metadata WHERE id = 1 LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message: lastErrorMessage(in: database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.exec(message: lastErrorMessage(in: database))
        }
    }

    private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindInt64(_ value: Int64, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_int64(statement, index, value)
    }

    private func bindOptionalInt64(_ value: Int64?, to index: Int32, in statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindBlob(_ value: Data, to index: Int32, in statement: OpaquePointer?) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
    }

    private func blob(at index: Int32, in statement: OpaquePointer?) -> Data? {
        guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, index))
        guard length > 0 else { return nil }
        return Data(bytes: pointer, count: length)
    }

    private func text(at index: Int32, in statement: OpaquePointer?) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func lastErrorMessage(in database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }

    /// Inline copy of `cleanupLabel` from AppFlow — "MMM d".
    /// `AppFlow`'s extension is `fileprivate`, so we can't reach it
    /// from this file. Duplicating the three lines here is simpler
    /// than exporting the extension.
    private static let labelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Inline copy of `cleanupShort` — medium date style, no time.
    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Mirrors `AppFlow.mediaDisplayTitle(for:)` — same format so that
    /// a record rebuilt from the DB is string-for-string identical to
    /// one built from a live `PHAsset`.
    static func displayTitle(
        mediaType: PHAssetMediaType,
        isScreenshot: Bool,
        createdAt: Date?
    ) -> String {
        let base: String
        if mediaType == .video {
            base = "Video"
        } else if isScreenshot {
            base = "Screenshot"
        } else {
            base = "Photo"
        }
        guard let createdAt else { return base }
        return "\(base) \(labelFormatter.string(from: createdAt))"
    }

    /// Mirrors the one-liner `DateFormatter.cleanupShort.string(from:)`
    /// the scan-time `makeMediaRecord` uses for the subtitle field.
    static func shortDate(_ createdAt: Date?) -> String {
        shortFormatter.string(from: createdAt ?? .now)
    }

    private static func databaseURL() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.open(message: "Application Support directory unavailable")
        }
        return baseURL
            .appendingPathComponent("CleanupClone", isDirectory: true)
            .appendingPathComponent("MediaAnalysis.sqlite", isDirectory: false)
    }

    private static func epochSeconds(from date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded())
    }

    private static func currentTimestamp() -> Int64 {
        epochSeconds(from: Date())
    }

    private var metadataMatchesCurrentVersionSQL: String {
        """
        assets_analysis.creation_date = excluded.creation_date
        AND IFNULL(assets_analysis.modification_date, -1) = IFNULL(excluded.modification_date, -1)
        AND assets_analysis.pixel_width = excluded.pixel_width
        AND assets_analysis.pixel_height = excluded.pixel_height
        AND assets_analysis.media_type = excluded.media_type
        AND assets_analysis.is_screenshot = excluded.is_screenshot
        AND assets_analysis.file_size_estimate = excluded.file_size_estimate
        AND assets_analysis.analysis_version = \(Self.analysisVersion)
        """
    }

    private enum StoreError: LocalizedError {
        case open(message: String)
        case prepare(message: String)
        case step(message: String)
        case exec(message: String)

        var errorDescription: String? {
            switch self {
            case .open(let message), .prepare(let message), .step(let message), .exec(let message):
                return message
            }
        }
    }
}

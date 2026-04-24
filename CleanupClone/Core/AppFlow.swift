import AVFoundation
import Contacts
import CoreML
import CoreImage
import CryptoKit
import EventKit
import Foundation
import LocalAuthentication
@preconcurrency import Photos
@preconcurrency import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

enum AppStage {
    /// Load-bearing launch splash. Holds for ~2.4s while SDKs warm
    /// and onboarding assets decode in the background. Auto-advances
    /// to `.onboarding` (or `.mainApp` if the user has already
    /// completed onboarding) via `SplashView`.
    case splash
    case onboarding
    case paywall
    case mainApp
}

/// User-facing appearance preference. Light mode is defined but intentionally
/// not exposed in the Themes picker until every screen has been audited for
/// contrast in light backgrounds. Keeping the case here so the enum is stable
/// when Light is rolled out in a follow-up release.
enum AppAppearance: String, CaseIterable, Identifiable {
    case automatic
    case dark
    case light  // not selectable yet – shown as "Coming soon" in the UI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

enum CleanupTab: String, CaseIterable, Identifiable {
    case home
    case secret
    case contacts
    case email
    case compress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .secret: "Secret"
        case .contacts: "Contacts"
        case .email: "Email"
        case .compress: "Compress"
        }
    }

    var symbol: String {
        switch self {
        case .home: "sparkles.rectangle.stack.fill"
        case .secret: "lock.fill"
        case .contacts: "person.crop.circle.fill"
        case .email: "envelope.badge.fill"
        case .compress: "video.fill.badge.ellipsis"
        }
    }
}

enum DashboardCategoryKind: String, CaseIterable, Identifiable, Hashable {
    case duplicates
    case similar
    case similarVideos
    case similarScreenshots
    case screenshots
    case other
    case videos
    case shortRecordings
    case screenRecordings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates: "Duplicates"
        case .similar: "Similar"
        case .similarVideos: "Duplicates"
        case .similarScreenshots: "Similar Screenshots"
        case .screenshots: "Screenshots"
        case .other: "Other"
        case .videos: "Videos"
        case .shortRecordings: "Short Recordings"
        case .screenRecordings: "Screen Recordings"
        }
    }

    var emptyTitle: String {
        switch self {
        case .duplicates: "No duplicates found"
        case .similar: "No similar photos found"
        case .similarVideos: "No video duplicates found"
        case .similarScreenshots: "No similar screenshots found"
        case .screenshots: "No screenshots found"
        case .other: "No extra media found"
        case .videos: "No videos found"
        case .shortRecordings: "No short recordings found"
        case .screenRecordings: "No screen recordings found"
        }
    }

    var palette: [Color] {
        switch self {
        case .duplicates:
            [Color(hex: "#1A1F29"), Color(hex: "#141924")]
        case .similar:
            [Color(hex: "#7A4C3E"), Color(hex: "#E39A6D")]
        case .similarVideos:
            [Color(hex: "#101624"), Color(hex: "#1F2F5A")]
        case .similarScreenshots:
            [Color(hex: "#2A1D4F"), Color(hex: "#5644A8")]
        case .screenshots:
            [Color(hex: "#35273B"), Color(hex: "#6D4D63")]
        case .other:
            [Color(hex: "#2B2E2F"), Color(hex: "#525B50")]
        case .videos:
            [Color(hex: "#101524"), Color(hex: "#0D0F17")]
        case .shortRecordings:
            [Color(hex: "#111827"), Color(hex: "#1E2A44")]
        case .screenRecordings:
            [Color(hex: "#0E1B1B"), Color(hex: "#143232")]
        }
    }

    var tileHeight: CGFloat {
        switch self {
        case .duplicates: 182
        case .similar: 186
        case .similarVideos: 226
        case .similarScreenshots: 226
        case .screenshots: 206
        case .other: 206
        case .videos: 220
        case .shortRecordings: 220
        case .screenRecordings: 220
        }
    }

    var accent: Color {
        switch self {
        case .duplicates: CleanupTheme.electricBlue
        case .similar: Color(hex: "#FFB17A")
        case .similarVideos: Color(hex: "#88A5FF")
        case .similarScreenshots: Color(hex: "#CBA8FF")
        case .screenshots: Color(hex: "#D39AB3")
        case .other: Color(hex: "#A8BDA2")
        case .videos: Color(hex: "#53DBFF")
        case .shortRecordings: Color(hex: "#7DD3FC")
        case .screenRecordings: Color(hex: "#34D399")
        }
    }
}

struct StorageSnapshot {
    let totalBytes: Int64
    let freeBytes: Int64

    var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }

    var progress: CGFloat {
        guard totalBytes > 0 else { return 0 }
        return CGFloat(Double(usedBytes) / Double(totalBytes))
    }

    static func current() -> StorageSnapshot {
        let rootURL = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        let values = try? rootURL.resourceValues(forKeys: keys)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let importantFree = values?.volumeAvailableCapacityForImportantUsage
        let standardFree = values?.volumeAvailableCapacity
        let resolvedFree: Int64
        if let importantFree {
            resolvedFree = importantFree
        } else if let standardFree {
            resolvedFree = Int64(standardFree)
        } else {
            resolvedFree = 0
        }
        let free = resolvedFree
        return StorageSnapshot(totalBytes: total, freeBytes: free)
    }
}

struct DeviceSnapshot {
    let deviceName: String
    let modelName: String
    let systemVersion: String
    let batteryDescription: String

    @MainActor
    static func current() -> DeviceSnapshot {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let battery: String
        if level >= 0 {
            battery = "\(Int(level * 100))%"
        } else {
            battery = "Unavailable"
        }

        return DeviceSnapshot(
            deviceName: UIDevice.current.name,
            modelName: modelIdentifier(),
            systemVersion: UIDevice.current.systemVersion,
            batteryDescription: battery
        )
    }

    private static func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { partialResult, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partialResult.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}

struct DashboardCategorySummary: Identifiable, Hashable {
    let kind: DashboardCategoryKind
    let count: Int
    let totalBytes: Int64

    var id: DashboardCategoryKind { kind }

    var badgeTitle: String {
        switch kind {
        case .similarVideos, .videos, .shortRecordings, .screenRecordings:
            "\(count) Videos"
        default:
            "\(count) Photos"
        }
    }

    var badgeSubtitle: String {
        "(\(ByteCountFormatter.cleanupString(fromByteCount: totalBytes)))"
    }
}

struct MediaCluster: Identifiable, Hashable {
    let id: String
    let category: DashboardCategoryKind
    let assets: [MediaAssetRecord]
    let totalBytes: Int64
    let subtitle: String?

    var count: Int {
        assets.count
    }

    var title: String {
        switch category {
        case .videos, .similarVideos, .shortRecordings, .screenRecordings:
            count == 1 ? "1 Video" : "\(count) Videos"
        default:
            count == 1 ? "1 Photo" : "\(count) Photos"
        }
    }

    var sizeLine: String {
        ByteCountFormatter.cleanupString(fromByteCount: totalBytes)
    }
}

struct MediaAssetRecord: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let sizeInBytes: Int64
    let duration: TimeInterval
    let createdAt: Date?
    let modificationAt: Date?
    let mediaType: PHAssetMediaType
    let isScreenshot: Bool
    let pixelWidth: Int
    let pixelHeight: Int

    var formattedSize: String {
        ByteCountFormatter.cleanupString(fromByteCount: sizeInBytes)
    }

    var detailLine: String {
        if mediaType == .video {
            return "\(formattedDuration(duration)) • \(formattedSize)"
        }
        return formattedSize
    }

    private func formattedDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ChargingPoster: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let palette: [Color]
    let assetName: String?
    let locked: Bool

    init(title: String, subtitle: String, palette: [Color], assetName: String?, locked: Bool) {
        self.id = title
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
        self.assetName = assetName
        self.locked = locked
    }
}

struct ContactRecord: Identifiable, Hashable {
    let id: String
    let fullName: String
    let phones: [String]
    let emails: [String]

    var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        if parts.isEmpty { return "?" }
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    var sectionLetter: String {
        let first = fullName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
        guard let char = first.first, char.isLetter, char.isASCII else { return "#" }
        return String(char)
    }
}

struct DuplicateContactGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let contacts: [ContactRecord]

    var duplicateCount: Int {
        contacts.count
    }

    var secondaryLine: String {
        let phones = contacts.reduce(0) { $0 + $1.phones.count }
        let emails = contacts.reduce(0) { $0 + $1.emails.count }
        return "\(phones) phone numbers • \(emails) emails"
    }

    /// Preview of what the merged contact would look like
    var mergedPreview: ContactRecord {
        guard let best = contacts.max(by: { lhs, rhs in
            let lScore = (lhs.fullName.count * 5) + (lhs.phones.count * 3) + (lhs.emails.count * 3)
            let rScore = (rhs.fullName.count * 5) + (rhs.phones.count * 3) + (rhs.emails.count * 3)
            return lScore < rScore
        }) else {
            return contacts.first ?? ContactRecord(id: "", fullName: "Unknown", phones: [], emails: [])
        }
        var allPhones: [String] = []
        var seenPhones: Set<String> = []
        var allEmails: [String] = []
        var seenEmails: Set<String> = []
        for c in contacts {
            for p in c.phones {
                let normalized = p.filter(\.isNumber)
                if seenPhones.insert(normalized).inserted { allPhones.append(p) }
            }
            for e in c.emails {
                let normalized = e.lowercased()
                if seenEmails.insert(normalized).inserted { allEmails.append(e) }
            }
        }
        return ContactRecord(id: best.id, fullName: best.fullName, phones: allPhones, emails: allEmails)
    }
}

struct ContactAnalysisSummary: Hashable {
    let totalCount: Int
    let duplicateGroupCount: Int
    let duplicateContactCount: Int
    let incompleteCount: Int
    let backupCount: Int

    static let empty = ContactAnalysisSummary(
        totalCount: 0,
        duplicateGroupCount: 0,
        duplicateContactCount: 0,
        incompleteCount: 0,
        backupCount: 0
    )
}

struct EventAnalysisSummary: Hashable {
    let totalCount: Int
    let pastEventCount: Int

    static let empty = EventAnalysisSummary(totalCount: 0, pastEventCount: 0)
}

struct EventRecord: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let calendarName: String
    let dateLine: String
    let startDate: Date?
    let isAllDay: Bool
    let canDelete: Bool
}

struct SecretVaultItem: Identifiable, Codable, Hashable {
    let id: String
    let filename: String
    let relativePath: String
    let contentTypeIdentifier: String
    let createdAt: Date

    var isVideo: Bool {
        guard let type = UTType(contentTypeIdentifier) else { return false }
        return type.conforms(to: .movie)
    }
}

struct SecretVaultImportStatus: Hashable {
    var totalCount: Int
    var importedCount: Int
    var failedCount: Int
    var processedBytes: Int64
    var currentFilename: String?

    var isFinished: Bool {
        importedCount + failedCount >= totalCount
    }
}

struct SecretVaultImportResult: Hashable {
    let importedCount: Int
    let failedCount: Int
    let requestedOriginalDeletion: Bool
    let eligibleOriginalCount: Int
    let deletedOriginalCount: Int

    var deletedAllEligibleOriginals: Bool {
        deletedOriginalCount == eligibleOriginalCount
    }
}

struct EmailCleanerPreferences: Codable, Hashable {
    var selectedFilters: Set<String> = ["Promotions", "Social", "Updates"]
    var archiveInsteadOfDelete = true
    var excludeStarred = true
    var senderChoices: [String: String] = [:]
    var deleteAllAfterUnsubscribe: Set<String> = []
}

enum VideoCompressionPreset: String, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "High Quality"
        case .medium: "Medium Quality"
        case .low: "Maximum Compression"
        }
    }

    var exportPreset: String {
        switch self {
        case .high: AVAssetExportPresetHighestQuality
        case .medium: AVAssetExportPresetMediumQuality
        case .low: AVAssetExportPresetLowQuality
        }
    }
}

struct MediaCompressionResult: Hashable {
    let assetID: String
    let originalBytes: Int64
    let compressedBytes: Int64
    let label: String

    var savedBytes: Int64 {
        max(0, originalBytes - compressedBytes)
    }
}

enum MediaWorkQueues {
    private static let indexingConcurrencyLimit = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

    static let indexingQueue = DispatchQueue(
        label: "com.cleanupclone.media.indexing",
        qos: .utility,
        attributes: .concurrent
    )
    static let thumbnailQueue = DispatchQueue(
        label: "com.cleanupclone.visible-thumbnails",
        qos: .userInitiated,
        attributes: .concurrent
    )
    static let indexingSemaphore = DispatchSemaphore(value: indexingConcurrencyLimit)
}

@MainActor
final class AppFlow: ObservableObject {
    nonisolated(unsafe) private static let indexingTargetSize = CGSize(width: 256, height: 256)
    nonisolated(unsafe) private static let indexingImageManager = PHCachingImageManager()

    @Published var stage: AppStage = .splash
    @Published var selectedTab: CleanupTab = .home
    @Published var onboardingIndex = 0
    @Published var pendingUpgradeGate: UpgradeGateContext?
    /// Direct-entry flag for the upgrade paywall — toggled by the
    /// dashboard PRO badge and any other "take me straight to the
    /// paywall" CTA. RootView observes this and drives the
    /// `UpgradePaywallSheet` fullScreenCover.
    @Published var presentUpgradePaywall: Bool = false

    @Published var storageSnapshot = StorageSnapshot.current()
    @Published var deviceSnapshot = DeviceSnapshot.current()
    @Published var photoAuthorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var contactsAuthorization = CNContactStore.authorizationStatus(for: .contacts)
    @Published var eventsAuthorization = EKEventStore.authorizationStatus(for: .event)
    @Published var isScanningLibrary = false
    @Published var scanProgress: CGFloat = 0
    @Published var scanStatusText = "Ready to scan"
    @Published var scannedLibraryItems = 0
    @Published var refiningClusterCategories: Set<DashboardCategoryKind> = []
    /// Categories that are queued for refinement but haven't yet
    /// started running (refinements happen sequentially to avoid
    /// saturating the Neural Engine). UI treats "queued" the same as
    /// "running" so the user sees a "Refining…" indicator on every
    /// card that's going to be refined, not just the one currently
    /// being worked on.
    @Published var pendingRefinementCategories: Set<DashboardCategoryKind> = []
    @Published var dashboardCategories: [DashboardCategorySummary] = DashboardCategoryKind.allCases.map {
        DashboardCategorySummary(kind: $0, count: 0, totalBytes: 0)
    }
    @Published var emailPreferences = EmailCleanerPreferences()
    @Published var gmailAccount: GmailAccountSummary?
    @Published var gmailCategorySummaries: [GmailCategorySummary] = []
    @Published var gmailSenderSummaries: [GmailSenderSummary] = []
    @Published var gmailLastSyncedAt: Date?
    @Published var gmailErrorMessage: String?
    @Published var isConnectingGmail = false
    @Published var isRefreshingGmail = false
    @Published var duplicateContactGroups: [DuplicateContactGroup] = []
    @Published var contactAnalysisSummary: ContactAnalysisSummary = .empty
    @Published var isScanningContacts = false
    @Published var allContacts: [ContactRecord] = []
    @Published var incompleteContacts: [ContactRecord] = []
    @Published var isCleaningContacts = false
    @Published var contactCleaningProgress: (done: Int, total: Int) = (0, 0)
    @Published var contactCleaningComplete = false
    @Published var eventAnalysisSummary: EventAnalysisSummary = .empty
    @Published var pastEvents: [EventRecord] = []
    @Published var isScanningEvents = false
    @Published var secretVaultItems: [SecretVaultItem] = []
    @Published var secretVaultImportStatus: SecretVaultImportStatus?
    @Published var isSecretSpaceUnlocked = false
    /// Deep-link request: when set, ContactsView will switch to this sub-screen
    /// on appear/change and then clear it. Used by the Dashboard to jump
    /// straight to Duplicates / Incomplete / All Contacts / Backups.
    @Published var pendingContactScreen: ContactsView.ContactScreen?
    /// Service that creates / lists / restores / deletes contact backups.
    /// Lives on AppFlow so views and background actions share the same state.
    let contactBackupService = ContactBackupService()
    /// User-chosen appearance (Automatic / Dark). "Light" is intentionally not
    /// available yet — shipping it half-baked would leave screens with white
    /// text on white backgrounds. Persisted across launches.
    @Published var appearancePreference: AppAppearance {
        didSet { UserDefaults.standard.set(appearancePreference.rawValue, forKey: "cleanup.appearance") }
    }
    @Published var selectedChargingPosterID = "Battery"
    @Published var appliedChargingPosterID = "Battery"
    @Published var compressionResults: [String: MediaCompressionResult] = [:]
    @Published var compressionMessage: String?
    @Published var isCompressingAssetID: String?

    /// Cached compressible asset lists – rebuilt whenever mediaAssetsByCategory changes.
    @Published private(set) var cachedCompressiblePhotos: [MediaAssetRecord] = []
    @Published private(set) var cachedCompressibleVideos: [MediaAssetRecord] = []

    private(set) var mediaAssetsByCategory: [DashboardCategoryKind: [MediaAssetRecord]] = [:]
    private(set) var mediaClustersByCategory: [DashboardCategoryKind: [MediaCluster]] = [:]
    /// IDs of assets the background screen-recording classifier has
    /// confirmed match iOS screen-recording filename patterns. This
    /// outlives individual `applyLibrarySnapshot` calls so that every
    /// snapshot the scan publishes carries the classifier's results
    /// forward — otherwise the snapshot would wipe the promoted
    /// records from `.screenRecordings` every time it ran.
    private var confirmedScreenRecordingIDs: Set<String> = []
    private(set) var totalLibraryItems = 0
    private(set) var photoCount = 0
    private(set) var videoCount = 0

    private let contactStore = CNContactStore()
    private let eventStore = EKEventStore()
    private let posters: [ChargingPoster] = [
        .init(title: "Battery", subtitle: "Neon charge loop", palette: [Color.black, Color(hex: "#3DFF44")], assetName: "ChargingBatteryPoster", locked: false),
        .init(title: "Bloom", subtitle: "Amber pulse", palette: [Color(hex: "#462100"), Color(hex: "#FFB445")], assetName: "ChargingBloomPoster", locked: false),
        .init(title: "Storm", subtitle: "Electric arc", palette: [Color(hex: "#040716"), Color(hex: "#52C3FF")], assetName: "ChargingStormPoster", locked: true),
        .init(title: "Cat", subtitle: "Psychedelic pet", palette: [Color(hex: "#240E3B"), Color(hex: "#E33C7B")], assetName: "ChargingCatPoster", locked: true),
        .init(title: "Glow", subtitle: "Soft spectrum", palette: [Color(hex: "#D48B8B"), Color(hex: "#A5B8FF")], assetName: nil, locked: true)
    ]

    private let selectedPosterKey = "cleanup.selected.poster"
    private let appliedPosterKey = "cleanup.applied.poster"
    private let emailPreferencesKey = "cleanup.email.preferences"
    private let vaultItemsKey = "cleanup.vault.items"
    private let secretPinHashKey = "cleanup.secret.pin.hash"
    private let retiredCompressionAssetIDsKey = "cleanup.retired.compression.asset.ids"
    /// Persisted on the last step of onboarding (either after purchase
    /// or after the user closes the paywall). Splash reads this to
    /// decide whether to route the user into the onboarding flow or
    /// straight into the main app on relaunch.
    private let onboardingCompletedKey = "cleanup.onboarding.completed"
    /// Timestamp of the last completed library scan. Persisted so that
    /// a relaunch with a valid on-disk snapshot can decide "library
    /// already scanned X minutes ago, no need to touch it again" without
    /// refetching every asset.
    private let lastLibraryScanAtKey = "cleanup.last.library.scan.at"

    /// True when `restorePersistedState()` successfully rehydrated the
    /// scan snapshot from disk. `bootstrapIfNeeded()` branches on this —
    /// when false, we run a full first-load scan (new install, wiped
    /// data, or schema bump); when true, we skip straight to a light
    /// delta check so the user doesn't pay another full scan on a
    /// simple relaunch.
    private(set) var didRestoreLibrarySnapshot = false

    private var retiredCompressionAssetIDs: Set<String> = []
    private let gmailService = GmailService.shared
    private var libraryScanGeneration = 0
    private var activeLibraryScanTask: Task<Void, Never>?
    /// When did the last successful library scan finish. Used to throttle
    /// `didBecomeActive`-triggered rescans — without this, every time the
    /// user opens a preview sheet (which trips didBecomeActive on return)
    /// we'd blow away all the Vision/clustering caches and rebuild them
    /// from scratch. That was the "it keeps re-indexing" bug.
    private var lastLibraryScanAt: Date?
    /// Minimum interval between auto-triggered rescans. Manual pull-to-
    /// refresh and first-load always go through.
    private let autoRescanCooldown: TimeInterval = 180
    private let librarySnapshotBatchSize = 240
    private let quickScanReadyCount = 4_000
    private var clusterRefinementSignature: [DashboardCategoryKind: Int] = [:]
    private var visualSignatureCache: [String: MediaVisualSignature] = [:]
    private var semanticFeaturePrintCache: [String: VNFeaturePrintObservation] = [:]
    private var faceCountCache: [String: Int] = [:]
    /// Per-face feature prints, up to `maxFacesPerAsset` largest faces per
    /// image. Used by `.similar` clustering so "me at the Louvre" and
    /// "my girlfriend at the Louvre" don't collapse into one cluster just
    /// because the scene feature print is close. An empty array means
    /// "we computed and found no usable face crops" — distinct from
    /// "not computed yet" (nil).
    private var faceEmbeddingsCache: [String: [VNFeaturePrintObservation]] = [:]
    /// Pixel-level fingerprint for duplicate detection. SHA256 over a
    /// normalized 64×64 grayscale buffer — two images with matching
    /// fingerprints are pixel-identical up to JPEG jitter. Used as
    /// the final gate for `.duplicates` so "90 GB of duplicates" can't
    /// happen — only bit-for-bit matches end up in the duplicate view.
    private var pixelFingerprintCache: [String: Data] = [:]
    /// Byte-exact file size per asset, keyed by `localIdentifier +
    /// modificationDate`. First scan pays the PHAssetResource lookup
    /// (which is what triggers Photos' "Missing prefetched properties …
    /// Fetching on demand on the main queue" warning). Every rescan
    /// after that short-circuits here, so the warning fires at most
    /// once per asset per install instead of 30K times per scan.
    private var fileSizeCache: [String: Int64] = [:]
    /// Lowercased original filename for video assets, populated by the
    /// scan preflight. Used by `isScreenRecordingAsset` to skip the
    /// synchronous `PHAssetResource.assetResources(for:)` call (which
    /// would otherwise trigger Photos' "Fetching on demand on the main
    /// queue" warning and serialise every video check on MainActor).
    /// A `nil` value means we tried and got no filename back; missing
    /// key means we haven't preflighted yet so the old sync path runs.
    private var originalFilenameCache: [String: String?] = [:]
    /// Cap the number of faces we embed per asset. Group photos still
    /// cluster correctly (we require every anchor face to match), but
    /// we don't pay O(n²) on a 30-person banquet photo.
    private let maxFacesPerAsset = 4
    /// Feature-print distance under which two face crops are considered
    /// the same identity. Vision's face-crop feature prints land roughly
    /// 8-14 apart for the same person and 18+ for different people, so
    /// 14 is an aggressive threshold that splits different identities
    /// while still tolerating pose / lighting variation in a burst.
    /// Lower = stricter (more false splits); higher = looser (more
    /// false merges). Tuned specifically to stop "me + my partner at
    /// the Louvre" from being called similar.
    private let faceIdentityDistanceThreshold: Float = 14.0

    // MARK: - Incremental-scan cache
    //
    // The full scan produces both a final snapshot (categorized +
    // clusters) and the intermediate bucket dicts that snapshot was
    // built from. For incremental updates we keep the buckets and the
    // last `PHFetchResult` around so a `PHPhotoLibraryChangeObserver`
    // callback can:
    //   • ask iOS exactly which assets were inserted / removed /
    //     changed via `PHChange.changeDetails(for:)`,
    //   • patch the buckets in place (same routing code paths as
    //     a full scan — no result divergence),
    //   • rerun `applyLibrarySnapshot` against the patched buckets.
    // Vision / feature-print / face-count caches are preserved across
    // the delta: we only invalidate the entries for removed/changed
    // assets. That's the "no re-index mid-browse" fix — new screenshots
    // surface within a second or two without touching existing work.
    private var lastLibraryFetchResult: PHFetchResult<PHAsset>?
    private var lastLibraryBuckets: LibraryBucketsCache?
    private let clusterThumbnailManager = PHCachingImageManager()
    private let mediaAnalysisStore = MediaAnalysisStore()

    /// Bridge to `PHPhotoLibrary` change notifications. Without this, newly-
    /// taken screenshots / deleted items don't show up until the user hits
    /// Refresh — and even then only after `autoRescanCooldown` elapses.
    /// With it registered, iOS pings us the instant the library changes
    /// and we kick off a fresh scan automatically.
    private var photoLibraryObserver: PhotoLibraryChangeBridge?
    /// Debounce handle so a burst of `photoLibraryDidChange` callbacks
    /// is coalesced into a single rescan (or skipped entirely if the
    /// cooldown is still active).
    private var photoLibraryChangeDebounce: Task<Void, Never>?
    /// Holds the most recent `PHChange` that arrived while a full scan
    /// was in progress. Without this we used to drop those changes on
    /// the floor, which meant a mid-scan delete stayed in the scan's
    /// pre-delete bucket snapshot — `verifyDuplicatesByPixel` would
    /// then briefly show Duplicates as "0 / Zero KB" while it threw the
    /// missing assets out. Draining this after the scan completes lets
    /// us patch those deltas surgically.
    private var pendingLibraryChange: PHChange?

    init() {
        // Load persisted appearance before any view reads it so we don't
        // flash the wrong mode on launch.
        let storedAppearance = UserDefaults.standard.string(forKey: "cleanup.appearance")
        self.appearancePreference = AppAppearance(rawValue: storedAppearance ?? "") ?? .dark

        restorePersistedState()
        refreshDeviceAndStorage()
        refreshPermissions()
        Task {
            await restoreGmailSessionIfPossible()
        }

        // Register the photo-library change observer only if the user has
        // already granted access. Registering while status is .notDetermined
        // causes iOS to surface the permission prompt immediately on app
        // launch, covering the splash. We defer registration until the
        // onboarding "Allow Access" step actually grants access (see
        // registerPhotoLibraryObserverIfNeeded).
        if photoAuthorization.isReadable {
            registerPhotoLibraryObserverIfNeeded()
        }
    }

    /// Lazily installs the `PHPhotoLibraryChangeObserver`. Safe to call
    /// multiple times — a second call is a no-op.
    ///
    /// Change-handling strategy:
    ///   1. Coalesce bursts. iCloud deltas, edits, favorite toggles etc.
    ///      often fire many callbacks in quick succession; we debounce
    ///      with a short timer so a burst triggers at most one pass.
    ///   2. Apply an **incremental** diff via
    ///      `PHChange.changeDetails(for:)`. Only the inserted / removed
    ///      / changed assets are processed — Vision, feature-print and
    ///      face-count caches are preserved. That's the "no re-index
    ///      mid-browse" fix: a new screenshot appears within a second
    ///      or two without touching existing work.
    ///   3. Fall back to a full scan only when iOS reports the change
    ///      cannot be expressed incrementally, or when we have no
    ///      cached fetch result yet.
    private func registerPhotoLibraryObserverIfNeeded() {
        guard photoLibraryObserver == nil else { return }
        let bridge = PhotoLibraryChangeBridge { [weak self] change in
            Task { @MainActor in
                guard let self else { return }
                self.schedulePhotoLibraryDelta(using: change)
            }
        }
        PHPhotoLibrary.shared().register(bridge)
        self.photoLibraryObserver = bridge
    }

    /// Debounces a flurry of `photoLibraryDidChange` callbacks. We
    /// keep only the **latest** `PHChange` in the burst window — iOS's
    /// snapshot always references the fetch result we stored, so the
    /// freshest change is what we want to apply.
    private func schedulePhotoLibraryDelta(using change: PHChange) {
        photoLibraryChangeDebounce?.cancel()
        let latestChange = change
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms burst window
            guard !Task.isCancelled, let self else { return }
            // If a scan is already running, keep the latest change
            // around and drain it the moment the scan finishes. iOS
            // does not re-send PHChanges, so dropping this would mean
            // a mid-scan delete never gets applied as an incremental
            // patch — we'd rely on the scan's pre-delete fetch snapshot,
            // which is exactly what made Duplicates flash "0 / Zero KB"
            // while `verifyDuplicatesByPixel` discarded the now-missing
            // assets one at a time.
            guard self.activeLibraryScanTask == nil else {
                self.pendingLibraryChange = latestChange
                return
            }

            let handled = await self.applyIncrementalPhotoLibraryChange(latestChange)
            if !handled {
                // `applyIncrementalPhotoLibraryChange` returns false
                // in two cases:
                //   1. iOS couldn't describe the change as incremental
                //      (`details.hasIncrementalChanges` is false).
                //   2. We don't have a `lastLibraryFetchResult` /
                //      `lastLibraryBuckets` cached — the common cold-
                //      launch path after we restore a snapshot from
                //      disk but haven't run a full scan this session.
                //
                // For either case, the cheap way out is the ID-diff
                // reconcile: fetch current IDs, diff against what's
                // in `mediaAssetsByCategory`, route only the new
                // assets. For a single-screenshot change that's ~1s
                // of work instead of the 85s full rescan we were
                // firing here before. The full scan now only runs on
                // true first-load or when the delta path itself can't
                // cope (e.g. hundreds of new items at once).
                print("[observer] incremental path unavailable — running ID-diff delta instead of full scan")
                await self.reconcileLibraryAfterRestore()
            }
        }
        photoLibraryChangeDebounce = task
    }

    var chargingPosters: [ChargingPoster] {
        posters
    }

    var totalCleanableBytes: Int64 {
        dashboardCategories.reduce(0) { $0 + $1.totalBytes }
    }

    var currentStorageLine: String {
        "\(totalLibraryItems) files • \(ByteCountFormatter.cleanupString(fromByteCount: totalCleanableBytes)) ready to review"
    }

    var hasSecretPIN: Bool {
        UserDefaults.standard.string(forKey: secretPinHashKey) != nil
    }

    var isGmailConnected: Bool {
        gmailAccount != nil
    }

    /// True once the user has successfully connected Gmail at least once on
    /// this install. Used by EmailCleaner to decide whether to show the
    /// demo "preview" data (new user, never connected) or a clean zero state
    /// (previously connected, now disconnected — we should NOT re-show the
    /// fake preview numbers or let them drill into old categories).
    var hasEverConnectedGmail: Bool {
        UserDefaults.standard.bool(forKey: "gmail.hasEverConnected")
    }

    private func markGmailEverConnected() {
        UserDefaults.standard.set(true, forKey: "gmail.hasEverConnected")
    }

    func bootstrapIfNeeded() async {
        refreshDeviceAndStorage()
        refreshPermissions()

        // Fast path: we already have fresh results from an in-session
        // scan or one restored from disk during init. Nothing to do
        // beyond refreshing device/storage stats above.
        if !mediaAssetsByCategory.allSatisfy({ $0.value.isEmpty }) {
            if didRestoreLibrarySnapshot, photoAuthorization.isReadable {
                // Snapshot-backed launch — reconcile the restored state
                // against whatever's currently in the Photos library.
                // Most launches are a no-op (count matches → skip the
                // rescan entirely) so the dashboard stays responsive
                // and we don't re-index 30K assets for nothing.
                didRestoreLibrarySnapshot = false
                await reconcileLibraryAfterRestore()
            }
            if contactsAuthorization.isReadable, duplicateContactGroups.isEmpty {
                await scanContacts()
            }
            if eventsAuthorization.isReadable, pastEvents.isEmpty {
                await scanEvents()
            }
            return
        }

        if photoAuthorization.isReadable {
            // Empty in-memory state AND no snapshot on disk — genuine
            // first load. Pass the trigger explicitly so the central
            // guard in `scanShouldProceed` stays enforceable.
            await scanLibrary(trigger: .firstLoad)
        } else {
            applyEmptyMediaState()
        }

        if contactsAuthorization.isReadable {
            await scanContacts()
        }

        if eventsAuthorization.isReadable {
            await scanEvents()
        }
    }

    /// True cold-launch delta. The user's library has 30K+ assets and a
    /// full rescan takes ~85s; if they took one screenshot while the
    /// app was closed we emphatically do NOT want to re-route 37,750
    /// unchanged assets just to find the one new one. This function
    /// diffs the fresh `PHFetchResult` against the asset IDs restored
    /// from our on-disk snapshot and hands off to one of three paths:
    ///
    ///   • No drift          → nothing to do. Dashboard already shows
    ///                         the same numbers it showed last session.
    ///   • Only removals     → strip them from the cached categorized
    ///                         state. No Photos work needed.
    ///   • Additions (± N)   → run a small routing pass over JUST the
    ///                         new assets (≤ handfulThreshold) and
    ///                         append them into the categorized state.
    ///                         Similar / duplicate clustering for the
    ///                         new items is deferred — they show up in
    ///                         `.screenshots` / `.other` / `.videos`
    ///                         immediately, and get their full cluster
    ///                         membership on the next real scan. A
    ///                         single new screenshot can't form a
    ///                         similar-group on its own anyway.
    ///   • Big additions     → fall back to a full scan (> threshold
    ///                         means something drastic happened —
    ///                         iCloud resync, re-enabled album, etc.
    ///                         — and a surgical patch isn't worth
    ///                         risking a miscategorisation).
    private func reconcileLibraryAfterRestore() async {
        guard photoAuthorization.isReadable else { return }

        // Match performLibraryScan's fetch options exactly so that the
        // set of IDs we diff against is apples-to-apples with what the
        // last full scan saw.
        struct FetchResult {
            let assets: [PHAsset]
            let ids: Set<String>
        }

        let fetched = await Task.detached(priority: .userInitiated) { () -> FetchResult in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            var ids: Set<String> = []
            assets.reserveCapacity(result.count)
            ids.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
                ids.insert(asset.localIdentifier)
            }
            return FetchResult(assets: assets, ids: ids)
        }.value

        // Seed the lookup from the fresh fetch so any view that needs a
        // PHAsset for a recently-added ID can resolve it without going
        // back to Photos.
        for asset in fetched.assets {
            PhotoAssetLookup.shared.upsert(asset)
        }

        // IDs currently materialised in memory (the restored snapshot).
        var knownIDs: Set<String> = []
        for records in mediaAssetsByCategory.values {
            for record in records { knownIDs.insert(record.id) }
        }

        let addedIDs = fetched.ids.subtracting(knownIDs)
        let removedIDs = knownIDs.subtracting(fetched.ids)

        if addedIDs.isEmpty, removedIDs.isEmpty {
            print("[reconcile] library matches snapshot (\(knownIDs.count) assets) — no scan needed")
            // Keep the stored totals honest: the fetch count is the
            // ground truth even when the sets match (e.g. a metadata-
            // only update can tweak totals without changing IDs).
            totalLibraryItems = fetched.ids.count
            return
        }

        if !removedIDs.isEmpty {
            print("[reconcile] removed \(removedIDs.count) assets since last launch")
            removeDeletedAssetsFromState(removedIDs)
        }

        // Threshold above which we stop trying to surgical-patch and
        // just let the full scan run. Chosen conservatively: if the
        // library changed by more than this many items while the app
        // was closed, the user likely did something bulky (imported,
        // deleted an album, iCloud re-sync) and we'd rather pay the
        // scan than ship partial results.
        let handfulThreshold = 200

        if addedIDs.count > handfulThreshold {
            print("[reconcile] \(addedIDs.count) new assets exceeds threshold \(handfulThreshold) — falling back to full scan")
            await scanLibrary(trigger: .manual)
            return
        }

        if addedIDs.isEmpty {
            // Removals-only — no new assets to route. Persist the
            // updated snapshot so the next launch starts clean.
            totalLibraryItems = fetched.ids.count
            persistLibrarySnapshot()
            return
        }

        print("[reconcile] routing \(addedIDs.count) new assets (library total: \(fetched.ids.count))")
        await ingestNewAssetsIntoCache(
            newAssets: fetched.assets.filter { addedIDs.contains($0.localIdentifier) },
            totalCount: fetched.ids.count
        )
    }

    /// Routes a handful of newly-discovered assets into the existing
    /// categorised state without touching the 37K assets already there.
    /// Deliberately skips the similar-clustering rebuild — a small
    /// burst of new items goes straight into their primary categories
    /// (`.screenshots`, `.other`, `.videos`, etc.) and any cross-asset
    /// similarity or duplicate work is deferred to the next full scan.
    /// This is the "just ingest the new one, don't burn 85 seconds"
    /// path the user asked for.
    @MainActor
    private func ingestNewAssetsIntoCache(
        newAssets: [PHAsset],
        totalCount: Int
    ) async {
        guard !newAssets.isEmpty else { return }

        // Build throwaway bucket dicts. We don't currently persist the
        // similar / duplicate bucket state across launches, so for the
        // delta path we only care about the primary categorisation
        // (which category each new asset shows up in). The scan-time
        // `routeAsset` already handles that correctly — we just ignore
        // its similar/duplicate key outputs here since there's nothing
        // to merge into.
        var deltaCategorized: [DashboardCategoryKind: [MediaAssetRecord]] = [:]
        var duplicateBuckets: [String: [MediaAssetRecord]] = [:]
        var similarBuckets: [String: [MediaAssetRecord]] = [:]
        var similarVideoBuckets: [String: [MediaAssetRecord]] = [:]
        var similarScreenshotBuckets: [String: [MediaAssetRecord]] = [:]

        var upsertBatch: [MediaAssetRecord] = []
        upsertBatch.reserveCapacity(newAssets.count)

        for asset in newAssets {
            let record = makeMediaRecord(from: asset)
            _ = routeAsset(
                asset: asset,
                record: record,
                categorized: &deltaCategorized,
                duplicateBuckets: &duplicateBuckets,
                similarBuckets: &similarBuckets,
                similarVideoBuckets: &similarVideoBuckets,
                similarScreenshotBuckets: &similarScreenshotBuckets
            )
            upsertBatch.append(record)
        }

        // Merge the delta buckets into the user-visible state. Dedupe
        // by ID so that if (e.g.) a metadata glitch puts an asset into
        // both .other and .screenshots we don't double-count.
        for (kind, newRecords) in deltaCategorized {
            var existing = mediaAssetsByCategory[kind, default: []]
            var existingIDs = Set(existing.map(\.id))
            for record in newRecords where !existingIDs.contains(record.id) {
                existing.append(record)
                existingIDs.insert(record.id)
            }
            // Keep the same sort the full-scan snapshot uses: largest
            // size first, then newest first, so the new item lands
            // near the top of the grid where users expect it.
            existing.sort {
                if $0.sizeInBytes == $1.sizeInBytes {
                    return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                }
                return $0.sizeInBytes > $1.sizeInBytes
            }
            mediaAssetsByCategory[kind] = existing
        }

        // Update library totals from the fresh fetch so the header
        // counters don't drift. photoCount/videoCount recomputed from
        // the merged state.
        totalLibraryItems = totalCount
        photoCount = mediaAssetsByCategory.values.reduce(0) { partial, records in
            partial + records.filter { $0.mediaType == .image }.count
        }
        videoCount = mediaAssetsByCategory.values.reduce(0) { partial, records in
            partial + records.filter { $0.mediaType == .video }.count
        }
        // photoCount/videoCount double-count assets that live in
        // multiple categories (e.g. .screenshots + .other). Dedupe.
        var photoIDs: Set<String> = []
        var videoIDs: Set<String> = []
        for records in mediaAssetsByCategory.values {
            for record in records {
                if record.mediaType == .image { photoIDs.insert(record.id) }
                else if record.mediaType == .video { videoIDs.insert(record.id) }
            }
        }
        photoCount = photoIDs.count
        videoCount = videoIDs.count

        refreshDashboardCategories()

        // Persist the new records to MediaAnalysisStore so that when
        // the next full scan runs, these assets don't pay the
        // `PHAssetResource` size lookup again.
        await mediaAnalysisStore.upsertMetadataBatch(upsertBatch)

        // Save the fresh snapshot so if the user closes and reopens
        // again before a full rescan runs, the new items persist.
        lastLibraryScanAt = Date()
        UserDefaults.standard.set(lastLibraryScanAt, forKey: lastLibraryScanAtKey)
        persistLibrarySnapshot()

        // Push to the home-screen widgets too.
        SharedSnapshotWriter.shared.refresh(force: true)

        print("[reconcile] ingested \(newAssets.count) new assets — no full scan ran")
    }

    /// Called when a feature hits the free-tier ceiling. Free users get the
    /// "you've used your free X" gate sheet. Any paying tier is a no-op —
    /// paying users shouldn't be nagged in-app, and plan changes are handled
    /// entirely through Apple's Subscriptions UI.
    ///
    /// We key off `isPremium` (not `currentPlan`) so the debug force-free
    /// toggle — which flips `isPremium` without clearing the underlying
    /// Adapty plan — still routes the user through the paywall.
    @MainActor
    func requestUpgrade(for action: FreeAction) {
        if EntitlementStore.shared.isPremium { return }
        pendingUpgradeGate = UpgradeGateContext.forAction(action)
    }

    /// Gate helper for batch actions. Given the requested batch size, returns
    /// the number of items the caller may actually process. Records the usage
    /// and presents the upgrade sheet when the free limit has been reached or
    /// exceeded. Returns 0 when the caller must stop.
    @MainActor
    func consumeFreeAllowance(_ action: FreeAction, requested: Int) -> Int {
        let store = EntitlementStore.shared
        if store.isPremium { return requested }
        let used = store.usage[action] ?? 0
        let remaining = max(0, action.limit - used)
        if remaining == 0 {
            requestUpgrade(for: action)
            return 0
        }
        let allowed = min(remaining, requested)
        store.recordUse(action, count: allowed)
        if allowed < requested {
            // Let the caller finish its allowed slice, then nudge the user.
            requestUpgrade(for: action)
        }
        return allowed
    }

    /// Convenience for single-shot actions (compress, vault import, speaker).
    /// Returns true when the action may proceed.
    @MainActor
    func gateSingleAction(_ action: FreeAction) -> Bool {
        let store = EntitlementStore.shared
        if store.isPremium { return true }
        if store.canUse(action) {
            store.recordUse(action)
            return true
        }
        requestUpgrade(for: action)
        return false
    }

    func advanceOnboarding() {
        if onboardingIndex < OnboardingStep.allCases.count - 1 {
            onboardingIndex += 1
        } else {
            // End of the 12-step onboarding — paywall is now step 10 inside
            // the flow, so the final step drops straight into the app.
            stage = .mainApp
        }
    }

    /// Called by `SplashView` when the splash animation finishes and
    /// background preload is done. On a fresh install we drop into
    /// onboarding; on every subsequent launch we go straight to the
    /// main app (and, if the user isn't premium, present the upgrade
    /// paywall on arrival) — running onboarding a second time was the
    /// TestFlight "why am I scanning again?" regression.
    func finishSplash() {
        guard stage == .splash else { return }
        if UserDefaults.standard.bool(forKey: onboardingCompletedKey) {
            stage = .mainApp
            // Non-subscribers see the upgrade sheet on cold launch.
            // `RootView` binds this to the fullScreenCover; the check
            // is deferred slightly so EntitlementStore has a chance to
            // refresh from Adapty and not flash the paywall at paying
            // users who just launched offline.
            if !EntitlementStore.shared.isPremium {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard let self else { return }
                    guard !EntitlementStore.shared.isPremium else { return }
                    self.presentUpgradePaywall = true
                }
            }
        } else {
            stage = .onboarding
        }
    }

    /// Marks onboarding as completed in UserDefaults so the next cold
    /// launch skips it. Called from `OnboardingFlowView` right before
    /// transitioning to the main app.
    func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
    }

    func showPaywall() {
        stage = .paywall
    }

    func enterApp() {
        stage = .mainApp
    }

    func closeFeature() {
        selectedTab = .home
    }

    func handleGoogleOpenURL(_ url: URL) {
        _ = gmailService.handle(url)
    }

    func selectTab(_ tab: CleanupTab) {
        selectedTab = tab
    }

    func refreshDeviceAndStorage() {
        // Dispatch the synchronous disk I/O for volume capacity off the
        // main thread so it can't block the first frame of whatever
        // screen just triggered the refresh. `StorageSnapshot.current()`
        // hits the file system via URLResourceValues; on a cold cache
        // this can stall the main thread for hundreds of milliseconds,
        // which was being perceived as the onboarding hero screen
        // "lagging for the first 5 seconds" before animations settled.
        //
        // `DeviceSnapshot.current()` touches UIDevice (main-actor
        // isolated) — we re-hop to the main actor for it, but only
        // after the disk read has completed off-main, so the main
        // thread stays free during the expensive part.
        Task.detached(priority: .utility) { [weak self] in
            let storage = StorageSnapshot.current()
            await MainActor.run {
                guard let self else { return }
                self.storageSnapshot = storage
                self.deviceSnapshot = DeviceSnapshot.current()
            }
        }
    }

    func refreshPermissions() {
        photoAuthorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        contactsAuthorization = CNContactStore.authorizationStatus(for: .contacts)
        eventsAuthorization = EKEventStore.authorizationStatus(for: .event)
    }

    func restoreGmailSessionIfPossible() async {
        guard gmailService.isConfigured else {
            return
        }

        do {
            guard let snapshot = try await gmailService.restoreSessionIfPossible() else {
                return
            }
            applyGmailSnapshot(snapshot)
        } catch {
            if gmailService.isRecoverableRestoreError(error) {
                gmailService.signOut()
                clearGmailState()
                return
            }

            gmailErrorMessage = gmailService.userFacingMessage(for: error)
        }
    }

    func connectGmail() async {
        guard let presentingViewController = activePresentingViewController() else {
            gmailErrorMessage = GmailServiceError.missingPresenter.localizedDescription
            return
        }

        isConnectingGmail = true
        gmailErrorMessage = nil
        defer { isConnectingGmail = false }

        do {
            let snapshot = try await gmailService.signIn(presentingViewController: presentingViewController)
            applyGmailSnapshot(snapshot)
        } catch {
            gmailErrorMessage = gmailService.userFacingMessage(for: error)
        }
    }

    func refreshGmailMailbox() async {
        guard isGmailConnected else {
            return
        }

        isRefreshingGmail = true
        gmailErrorMessage = nil
        defer { isRefreshingGmail = false }

        do {
            let snapshot = try await gmailService.refreshMailbox()
            applyGmailSnapshot(snapshot)
        } catch {
            gmailErrorMessage = gmailService.userFacingMessage(for: error)
        }
    }

    func disconnectGmail() async {
        do {
            try await gmailService.disconnect()
            clearGmailState()
        } catch {
            gmailErrorMessage = gmailService.userFacingMessage(for: error)
        }
    }

    func signOutGmail() {
        gmailService.signOut()
        clearGmailState()
    }

    private func applyGmailSnapshot(_ snapshot: GmailMailboxSnapshot) {
        gmailAccount = snapshot.account
        gmailCategorySummaries = snapshot.categories
        gmailSenderSummaries = snapshot.senders
        gmailLastSyncedAt = snapshot.syncedAt
        gmailErrorMessage = nil
        markGmailEverConnected()
    }

    private func clearGmailState() {
        gmailAccount = nil
        gmailCategorySummaries = []
        gmailSenderSummaries = []
        gmailLastSyncedAt = nil
        gmailErrorMessage = nil
    }

    private func activePresentingViewController() -> UIViewController? {
        let connectedScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let rootViewController = connectedScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        return deepestPresentedViewController(from: rootViewController)
    }

    private func deepestPresentedViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return deepestPresentedViewController(from: navigationController.visibleViewController)
        }
        if let tabBarController = controller as? UITabBarController {
            return deepestPresentedViewController(from: tabBarController.selectedViewController)
        }
        if let presentedViewController = controller?.presentedViewController {
            return deepestPresentedViewController(from: presentedViewController)
        }
        return controller
    }

    func mediaAssets(for category: DashboardCategoryKind) -> [MediaAssetRecord] {
        mediaAssetsByCategory[category, default: []]
    }

    func compressiblePhotoAssets() -> [MediaAssetRecord] {
        compressibleAssets(of: .image)
    }

    func compressibleVideoAssets() -> [MediaAssetRecord] {
        compressibleAssets(of: .video)
    }

    func mediaClusters(for category: DashboardCategoryKind) -> [MediaCluster] {
        mediaClustersByCategory[category, default: []]
    }

    func isRefiningClusters(for category: DashboardCategoryKind) -> Bool {
        refiningClusterCategories.contains(category)
            || pendingRefinementCategories.contains(category)
    }

    /// The ONLY writer for `mediaClustersByCategory[.duplicates]`.
    ///
    /// Candidate buckets from the scan group photos by (mediaType,
    /// resolution) — which on an iPhone library collapses thousands
    /// of unrelated photos together. This function opens each
    /// candidate, computes a pixel fingerprint (SHA256 over a
    /// quantized 64×64 grayscale render), and rebuckets by that
    /// fingerprint. Two photos end up in the same duplicate cluster
    /// iff their actual pixel content matches.
    ///
    /// A single-member candidate bucket is trivially not a duplicate
    /// and is skipped entirely — no fingerprint computed. This is
    /// what keeps the pass fast: only photos that share dimensions
    /// with at least one other photo pay the fingerprint cost.
    ///
    /// Writes directly to `mediaClustersByCategory[.duplicates]` on
    /// the main actor. The dashboard card shows 0 until this
    /// finishes, then jumps to the correct number. No intermediate
    /// "refining then correcting" flicker.
    func verifyDuplicatesByPixel(candidateBuckets: [String: [MediaAssetRecord]]) async {
        refiningClusterCategories.insert(.duplicates)
        defer { refiningClusterCategories.remove(.duplicates) }

        // DEBUG LOGS — remove once duplicate detection is verified on
        // multiple devices. These show (a) how many candidate buckets
        // arrived, (b) how many have >1 members (the only ones we
        // actually fingerprint), and (c) the distribution so we can
        // tell whether "0 duplicates" means "no candidates" vs
        // "candidates existed but all fingerprints mismatched".
        print("[DUP] verifyDuplicatesByPixel called with \(candidateBuckets.count) candidate buckets")
        let bucketMemberCounts = candidateBuckets.values.map(\.count)
        let totalCandidates = bucketMemberCounts.reduce(0, +)
        let multiMemberBuckets = bucketMemberCounts.filter { $0 > 1 }.count
        print("[DUP]   total candidate records: \(totalCandidates)")
        print("[DUP]   buckets with >1 member: \(multiMemberBuckets)")
        if multiMemberBuckets > 0 {
            let previewKeys = candidateBuckets.filter { $0.value.count > 1 }.prefix(5)
            for (key, members) in previewKeys {
                print("[DUP]   bucket key='\(key)' count=\(members.count) ids=\(members.prefix(3).map(\.id))")
            }
        }

        // Only care about candidate buckets with ≥2 members.
        let interesting = candidateBuckets.values.filter { $0.count > 1 }
        guard !interesting.isEmpty else {
            print("[DUP] no interesting buckets (every bucket has ≤1 member) — writing empty duplicates")
            mediaClustersByCategory[.duplicates] = []
            mediaAssetsByCategory[.duplicates] = []
            refreshDashboardCategories()
            return
        }

        var verifiedClusters: [MediaCluster] = []

        // Process each candidate bucket independently. Within a
        // bucket we fingerprint members, then group by print.
        //
        // CONCURRENCY CAP. Previously every candidate in the bucket
        // spawned its own task simultaneously — on large buckets
        // (thousands of photos at same resolution) that meant
        // thousands of parallel `requestIndexingThumbnail` calls all
        // hitting `photoanalysisd`. iOS's Photos daemon is
        // single-threaded internally, so the flood queued up and
        // STARVED the UI's own thumbnail requests (why users saw
        // blank grey tiles on every cluster card until refinement
        // finished).
        //
        // We now cap in-flight fingerprints at 4. The Photos daemon
        // still gets work to do, the verifier still makes steady
        // progress, and the app's visible thumbnails get scheduled
        // ahead because they run at higher QoS (`.userInitiated` in
        // `MediaWorkQueues.thumbnailQueue`) while this loop runs at
        // `.utility` inside `pixelFingerprint`.
        let maxConcurrentFingerprints = 4
        for (candidateIndex, candidates) in interesting.enumerated() {
            let fingerprints: [(MediaAssetRecord, Data?)] = await withTaskGroup(of: (MediaAssetRecord, Data?).self) { group in
                var inFlight = 0
                var cursor = 0
                var results: [(MediaAssetRecord, Data?)] = []
                results.reserveCapacity(candidates.count)

                func spawnNext() {
                    guard cursor < candidates.count else { return }
                    let record = candidates[cursor]
                    cursor += 1
                    inFlight += 1
                    group.addTask { [weak self] in
                        guard let self else { return (record, nil) }
                        let print = await self.pixelFingerprint(for: record)
                        return (record, print)
                    }
                }
                // Prime the pipe with up to `maxConcurrentFingerprints`
                // tasks.
                for _ in 0..<min(maxConcurrentFingerprints, candidates.count) {
                    spawnNext()
                }
                while inFlight > 0 {
                    if let entry = await group.next() {
                        results.append(entry)
                        inFlight -= 1
                        // Start the next one to keep the pipe at depth N.
                        spawnNext()
                    } else {
                        break
                    }
                }
                return results
            }

            // Group by fingerprint. Assets whose fingerprint couldn't
            // be computed are dropped (we'd rather skip than misgroup).
            var byPrint: [Data: [MediaAssetRecord]] = [:]
            var nilFingerprints = 0
            for (record, print) in fingerprints {
                guard let print else { nilFingerprints += 1; continue }
                byPrint[print, default: []].append(record)
            }
            // DEBUG LOG — per candidate bucket, show how many unique
            // fingerprints came back and how many matches we found.
            // If "candidates=N distinct=N" we know fingerprints all
            // differed → no duplicates for that bucket. If
            // "candidates=N distinct=1" we know they all matched →
            // one duplicate cluster coming up.
            let matchingGroups = byPrint.values.filter { $0.count > 1 }.count
            print("[DUP]   bucket #\(candidateIndex): candidates=\(fingerprints.count) nilFingerprints=\(nilFingerprints) distinct=\(byPrint.count) matchingGroups=\(matchingGroups)")

            for (printIndex, (_, records)) in byPrint.enumerated() where records.count > 1 {
                let sorted = records.sorted {
                    if $0.sizeInBytes == $1.sizeInBytes {
                        return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                    return $0.sizeInBytes > $1.sizeInBytes
                }
                verifiedClusters.append(
                    MediaCluster(
                        id: "duplicates-\(candidateIndex)-\(printIndex)",
                        category: .duplicates,
                        assets: sorted,
                        totalBytes: sorted.reduce(0) { $0 + $1.sizeInBytes },
                        subtitle: nil
                    )
                )
            }

            // Yield between candidate buckets so the UI stays responsive.
            await Task.yield()
        }

        verifiedClusters.sort {
            if $0.totalBytes == $1.totalBytes { return $0.count > $1.count }
            return $0.totalBytes > $1.totalBytes
        }

        mediaClustersByCategory[.duplicates] = verifiedClusters
        mediaAssetsByCategory[.duplicates] = verifiedClusters.flatMap(\.assets).sorted {
            if $0.sizeInBytes == $1.sizeInBytes {
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            return $0.sizeInBytes > $1.sizeInBytes
        }
        refreshDashboardCategories()

        // DEBUG LOG — final duplicate-pass outcome.
        print("[DUP] verifyDuplicatesByPixel DONE: \(verifiedClusters.count) verified cluster(s), \(mediaAssetsByCategory[.duplicates]?.count ?? 0) total duplicate records")

        // Duplicates are populated in this second pass; without a
        // re-save the on-disk snapshot would restore with an empty
        // `.duplicates` category on next launch.
        persistLibrarySnapshot()
    }

    func refineReviewClustersIfNeeded(for category: DashboardCategoryKind) async {
        // Refinement is OFF for every category right now. Reasoning:
        //
        //   .duplicates            → initial bucket key already uses
        //                            exact file size in bytes, so
        //                            duplicate detection is pixel-
        //                            accurate without refinement.
        //   .similar               → scan-time visual-hash bucketing
        //                            already produces good clusters.
        //                            Refinement added a slow second
        //                            Vision-feature-print pass per
        //                            asset for no visible improvement.
        //   .similarScreenshots    → same as .similar.
        //   .similarVideos         → same as .similar.
        //   .screenshots           → the UI renders this as a FLAT
        //                            gallery (see
        //                            usesFlatScreenshotGallery in
        //                            DashboardView) — cluster output
        //                            isn't displayed at all, so
        //                            refining burned CPU for nothing.
        //
        // The refinement pipeline (`refineVisualClusters`,
        // `refinedSubclusters`, signature cache, etc.) is still in
        // the file — if a specific category starts showing bad
        // clusters later, flip that category back on here and it'll
        // work again without needing to re-plumb anything.
        _ = category
    }

    func requestPhotoAccessIfNeeded() async -> Bool {
        refreshPermissions()
        if photoAuthorization.isReadable {
            registerPhotoLibraryObserverIfNeeded()
            // Permission was already granted — if we haven't scanned
            // yet this is truly first-load; if we have, `.firstLoad`
            // will no-op and reuse cached results.
            await scanLibrary(trigger: .firstLoad)
            return true
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photoAuthorization = status
        if status.isReadable {
            registerPhotoLibraryObserverIfNeeded()
            // User just granted permission — always do a fresh scan
            // because there's no way the cache can be right.
            await scanLibrary(trigger: .manual)
            return true
        }

        applyEmptyMediaState()
        return false
    }

    func requestPhotoAuthorizationOnly() async -> Bool {
        refreshPermissions()
        if photoAuthorization.isReadable {
            registerPhotoLibraryObserverIfNeeded()
            return true
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photoAuthorization = status
        if status.isReadable {
            registerPhotoLibraryObserverIfNeeded()
            return true
        }

        applyEmptyMediaState()
        return false
    }

    /// Opens iOS Settings on this app's page. Called from permission CTAs
    /// when the user previously denied access and iOS no longer allows us
    /// to show the system prompt — the only remaining remediation is for
    /// the user to flip the toggle in Settings themselves.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func requestContactsAccessIfNeeded() async -> Bool {
        refreshPermissions()
        if contactsAuthorization.isReadable {
            await scanContacts()
            return true
        }

        let granted = await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { success, _ in
                continuation.resume(returning: success)
            }
        }

        refreshPermissions()
        if granted, contactsAuthorization.isReadable {
            await scanContacts()
            return true
        }

        duplicateContactGroups = []
        return false
    }

    func requestEventsAccessIfNeeded() async -> Bool {
        refreshPermissions()
        if eventsAuthorization.isReadable {
            await scanEvents()
            return true
        }

        let granted: Bool
        do {
            granted = try await eventStore.requestFullAccessToEvents()
        } catch {
            refreshPermissions()
            eventAnalysisSummary = .empty
            return false
        }

        refreshPermissions()
        if granted, eventsAuthorization.isReadable {
            eventStore.reset()
            await scanEvents()
            return true
        }

        eventAnalysisSummary = .empty
        pastEvents = []
        return false
    }

    /// True when callers like Smart Clean should trigger a scan instead
    /// of re-using what the dashboard already produced. We say yes only
    /// if we genuinely have no results yet OR they're past the auto-
    /// rescan cooldown. Entering Smart Clean seconds after the
    /// dashboard finished a full scan now reuses that result rather
    /// than spinning the whole Vision pipeline a second time.
    func shouldRescanForSmartClean() -> Bool {
        guard photoAuthorization.isReadable else { return false }
        if isScanningLibrary { return false }
        guard let last = lastLibraryScanAt else { return true }
        return Date().timeIntervalSince(last) >= autoRescanCooldown
    }

    /// Read-only handle to the in-flight library scan, if any. Lets
    /// Smart Clean await the dashboard's scan without starting its own.
    var activeLibraryScanAwaitable: Task<Void, Never>? { activeLibraryScanTask }

    /// Where a rescan request is coming from. Every caller of
    /// `scanLibrary(trigger:)` must pick one of these so the rule
    /// about whether to actually run lives in ONE place — not scattered
    /// across every `.task`, `.onReceive`, pull-to-refresh handler, and
    /// tab-change observer. Past bugs in this file have all been
    /// variations of "something accidentally wired a full rescan to a
    /// foreground notification"; this enum lets us block that at the
    /// source.
    enum ScanTrigger {
        /// User explicitly asked for fresh data: pulled to refresh,
        /// tapped the top-right refresh button, tapped a permission
        /// card. These ALWAYS run, even during refinement — the user
        /// is in control.
        case manual
        /// We've never scanned before (fresh install, permission just
        /// granted, onboarding finished). Runs if and only if we
        /// genuinely have no cached scan yet.
        case firstLoad
        /// Reactive trigger: app foregrounded, a view's `.task`
        /// fired, tab was re-entered, a sheet dismissed. These are
        /// the dangerous callers. Runs only if BOTH:
        ///   (a) we're past the auto-rescan cooldown, AND
        ///   (b) no refinement is currently in progress (we do NOT
        ///       stomp on an active pixel-fingerprint pass just
        ///       because the app foregrounded).
        case auto
    }

    /// Single source of truth for "should this rescan actually run?"
    /// Returns a short reason string when it declines, for logging.
    private func scanShouldProceed(for trigger: ScanTrigger) -> (ok: Bool, reason: String) {
        switch trigger {
        case .manual:
            return (true, "manual")
        case .firstLoad:
            if lastLibraryScanAt == nil { return (true, "first-load") }
            return (false, "first-load skipped: already scanned at least once")
        case .auto:
            if !refiningClusterCategories.isEmpty {
                return (false, "auto skipped: refinement in progress for \(refiningClusterCategories)")
            }
            if !pendingRefinementCategories.isEmpty {
                return (false, "auto skipped: refinement pending for \(pendingRefinementCategories)")
            }
            if let last = lastLibraryScanAt,
               Date().timeIntervalSince(last) < autoRescanCooldown {
                return (false, "auto skipped: within cooldown (\(Int(Date().timeIntervalSince(last)))s < \(Int(autoRescanCooldown))s)")
            }
            return (true, "auto")
        }
    }

    func scanLibrary(trigger: ScanTrigger = .manual) async {
        let decision = scanShouldProceed(for: trigger)
        guard decision.ok else {
            // Keep this as a print rather than a logger call so it
            // shows up in the Xcode console during development without
            // needing a category filter.
            print("[scanLibrary] \(decision.reason)")
            // If a scan is already running and a caller asked for
            // `.manual` or `.auto`, still await it so the caller sees
            // fresh data when this returns.
            if let activeLibraryScanTask {
                await activeLibraryScanTask.value
            }
            return
        }

        if let activeLibraryScanTask {
            await activeLibraryScanTask.value
            return
        }

        let scanTask = Task {
            await performLibraryScan()
        }
        activeLibraryScanTask = scanTask
        await scanTask.value
        activeLibraryScanTask = nil
        lastLibraryScanAt = Date()
        UserDefaults.standard.set(lastLibraryScanAt, forKey: lastLibraryScanAtKey)
        persistLibrarySnapshot()

        // Drain any `PHChange` that arrived while the scan was running.
        // The scan's fetch result was captured at its start, so it still
        // contains the pre-change assets; `changeDetails(for:)` can tell
        // us what needs to be stripped/inserted. Apply it surgically so
        // Duplicates doesn't flash to 0 waiting on a full rebuild.
        if let queuedChange = pendingLibraryChange {
            pendingLibraryChange = nil
            let handled = await applyIncrementalPhotoLibraryChange(queuedChange)
            if !handled {
                // iOS couldn't describe it incrementally — fall back to
                // a fresh scan so we don't ship stale data. Guard
                // against unbounded recursion: clear the queue first so
                // the next scan's drain is a no-op.
                await scanLibrary(trigger: .manual)
            }
        }

        // Push fresh battery / storage / scan state into the App Group so
        // the Home-Screen widgets can reload with real numbers instead of
        // whatever they last saw.
        SharedSnapshotWriter.shared.refresh(force: true)
    }

    /// Legacy shim. Prefer `scanLibrary(trigger:)` — passing an
    /// explicit trigger makes the call site's intent auditable.
    /// This wrapper treats a bare call as `.manual` to preserve
    /// existing behavior for user-initiated paths.
    func scanLibrary() async {
        await scanLibrary(trigger: .manual)
    }

    /// Used by auto-triggers (didBecomeActive, tab re-entry, etc). Skips
    /// the rescan if we already have fresh results — prevents the preview
    /// sheet from wiping Vision caches every time the user backgrounds
    /// and reopens the app. Now just a thin wrapper over the
    /// `.auto` trigger, which does the same job centrally.
    func scanLibraryIfStale() async {
        await scanLibrary(trigger: .auto)
    }

    private func performLibraryScan() async {
        let scanStart = Date()
        print("[SCAN] T+0.00s — performLibraryScan BEGIN")
        libraryScanGeneration += 1
        let scanGeneration = libraryScanGeneration
        clusterRefinementSignature.removeAll()
        refiningClusterCategories.removeAll()
        visualSignatureCache.removeAll()
        semanticFeaturePrintCache.removeAll()
        faceCountCache.removeAll()
        faceEmbeddingsCache.removeAll()
        pixelFingerprintCache.removeAll()
        confirmedScreenRecordingIDs.removeAll()

        refreshDeviceAndStorage()
        refreshPermissions()
        print(String(format: "[SCAN] T+%.2fs — after refreshDeviceAndStorage + refreshPermissions",
              Date().timeIntervalSince(scanStart)))

        guard photoAuthorization.isReadable else {
            applyEmptyMediaState()
            return
        }

        isScanningLibrary = true
        scanProgress = 0.02
        scanStatusText = "Scanning your library..."
        scannedLibraryItems = 0

        let fetchStart = Date()
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        PhotoAssetLookup.shared.reset()
        print(String(format: "[SCAN] T+%.2fs — PHAsset.fetchAssets took %.3fs, count=%d",
              Date().timeIntervalSince(scanStart),
              Date().timeIntervalSince(fetchStart),
              fetchResult.count))

        totalLibraryItems = fetchResult.count
        photoCount = 0
        videoCount = 0

        // Pre-materialize the PHAsset array once on MainActor so the
        // concurrent preflight below can iterate it without calling
        // `fetchResult.object(at:)` from background tasks (Photos' fetch
        // result is optimised for the thread it was created on).
        let materializeStart = Date()
        var materializedAssets: [PHAsset] = []
        materializedAssets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            materializedAssets.append(asset)
        }
        print(String(format: "[SCAN] T+%.2fs — enumerateObjects took %.3fs",
              Date().timeIntervalSince(scanStart),
              Date().timeIntervalSince(materializeStart)))

        // Preflight runs in parallel with the routing loop below, not
        // BEFORE it. The old "await the full preflight, then start
        // routing" version stalled the progress counter at "0 of N"
        // for 2+ minutes on large libraries — the scan was working
        // internally but had nothing to publish yet. Running it in
        // parallel lets the routing loop start routing immediately;
        // the preflight fills the cache from behind so the majority
        // of `estimatedFileSize` calls become instant cache hits
        // within the first few seconds.
        //
        // Preflight fans out across 8 workers AT FULL SPEED. We used
        // to throttle it to 1 worker to protect the paywall's WebView,
        // but the scan is no longer kicked off during the paywall
        // step (see `OnboardingFlowView.kickOffFirstScanIfNeeded`) —
        // by the time this runs the paywall is gone and the WebView
        // is dead, so there's nothing to protect and no reason not to
        // use the full available concurrency.
        //
        // Results merge to the MainActor caches in chunks as each
        // worker chunk finishes (not all at the end), so even a
        // partially-completed preflight benefits the routing loop.
        // No preflight, no separate classifier workers. The old code
        // spun up TWO extra background fleets (8 preflight workers
        // reading PHAssetResource.fileSize, plus 8 classifier workers
        // reading PHAssetResource.originalFilename) that flooded
        // `photoanalysisd` and starved the UI's thumbnail requests
        // — that's why thumbnails were invisible for 2-3 minutes
        // during scan. The preread streaming pass already reads each
        // asset once; we fold the screen-recording filename check
        // into it. Real file sizes are computed on-demand via
        // `preciseFileSize` only when the user opens a cluster to
        // make a delete decision — that's the only place byte-exact
        // numbers matter.

        var categorized: [DashboardCategoryKind: [MediaAssetRecord]] = Dictionary(
            uniqueKeysWithValues: DashboardCategoryKind.allCases.map { ($0, []) }
        )
        var duplicateBuckets: [String: [MediaAssetRecord]] = [:]
        var similarBuckets: [String: [MediaAssetRecord]] = [:]
        var similarVideoBuckets: [String: [MediaAssetRecord]] = [:]
        var similarScreenshotBuckets: [String: [MediaAssetRecord]] = [:]
        var assetRouting: [String: AssetRouting] = [:]
        var analysisBatch: [MediaAssetRecord] = []

        let total = max(fetchResult.count, 1)
        var lastSnapshotPublishedAt: Int = 0
        let routingLoopStart = Date()
        var loggedMilestones = Set<Int>()
        print(String(format: "[SCAN] T+%.2fs — routing loop START",
              Date().timeIntervalSince(scanStart)))

        // STREAMING PRE-READ. The preread reads every PHAsset property
        // off MainActor (pixelWidth, mediaSubtypes, creationDate, etc.)
        // so the routing loop doesn't pay the lazy-load cost. Instead
        // of waiting for all 37K to finish preread (which was causing
        // the 2-minute "Scanning 0 of X" stall), we stream chunks of
        // 500 back to MainActor as each chunk completes. The routing
        // loop consumes each chunk as soon as it arrives — users see
        // "Scanning 500 of 37,750" within a second, not 2 minutes.
        let assetsCopy = materializedAssets
        let expectedGeneration = scanGeneration
        let chunkStream = AsyncStream<[AssetMetaSnapshot]> { continuation in
            // `.utility` priority (not `.userInitiated`) so that when
            // the user navigates to a cluster view, their thumbnail
            // load requests (which run at `.userInitiated` via
            // `MediaWorkQueues.thumbnailQueue`) win the Photos-daemon
            // scheduling race. The scan still makes steady progress
            // but doesn't starve thumbnails.
            Task.detached(priority: .utility) {
                Self.prereadAssetMetadataStreaming(
                    assetsCopy,
                    chunkSize: 300
                ) { chunk in
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }

        var processedSoFar = 0
        for await chunk in chunkStream {
            guard scanGeneration == expectedGeneration else { return }

            for meta in chunk {
                processedSoFar += 1
                let assetIndex = processedSoFar - 1
                let asset = materializedAssets[assetIndex]
                PhotoAssetLookup.shared.upsert(asset)

                let (record, routing) = self.routeFromMeta(
                    meta: meta,
                    categorized: &categorized,
                    duplicateBuckets: &duplicateBuckets,
                    similarBuckets: &similarBuckets,
                    similarVideoBuckets: &similarVideoBuckets,
                    similarScreenshotBuckets: &similarScreenshotBuckets
                )
                assetRouting[record.id] = routing
                analysisBatch.append(record)
                if meta.mediaType == .image { photoCount += 1 }
                else if meta.mediaType == .video { videoCount += 1 }
            }

            // After each chunk: update progress, maybe snapshot.
            let processedCount = processedSoFar
            for milestone in [1000, 5000, 10000, 20000, 30000] {
                if processedCount >= milestone, !loggedMilestones.contains(milestone) {
                    loggedMilestones.insert(milestone)
                    let elapsed = Date().timeIntervalSince(routingLoopStart)
                    let rate = Double(processedCount) / max(elapsed, 0.001)
                    print(String(format: "[SCAN] T+%.2fs — routing loop: %d items in %.2fs (%.0f items/sec)",
                          Date().timeIntervalSince(scanStart),
                          processedCount, elapsed, rate))
                }
            }

            let isFinalItem = processedCount == assetsCopy.count
            scanProgress = CGFloat(processedCount) / CGFloat(total)
            scanStatusText = libraryScanStatusText(processedCount: processedCount, totalCount: assetsCopy.count)
            scannedLibraryItems = processedCount
            await Task.yield()

            let shouldPublishSnapshot: Bool = {
                if isFinalItem { return true }
                if total < 1000 { return false }
                let fraction = Double(processedCount) / Double(total)
                let milestones: [Double] = [0.10, 0.25, 0.50, 0.75]
                let hitMilestone = milestones.contains(where: { m in
                    fraction >= m && (Double(processedCount - chunk.count) / Double(total)) < m
                })
                if hitMilestone { return true }
                let gap = processedCount - lastSnapshotPublishedAt
                if gap >= 3000 { return true }
                return false
            }()
            if shouldPublishSnapshot {
                let snapStart = Date()
                await applyLibrarySnapshot(
                    categorized: categorized,
                    duplicateBuckets: duplicateBuckets,
                    similarBuckets: similarBuckets,
                    similarVideoBuckets: similarVideoBuckets,
                    similarScreenshotBuckets: similarScreenshotBuckets
                )
                let snapElapsed = Date().timeIntervalSince(snapStart)
                print(String(format: "[SCAN] T+%.2fs — applyLibrarySnapshot @%d took %.3fs",
                      Date().timeIntervalSince(scanStart),
                      processedCount, snapElapsed))
                lastSnapshotPublishedAt = processedCount
            }

            if processedCount.isMultiple(of: librarySnapshotBatchSize),
               processedCount < assetsCopy.count,
               !analysisBatch.isEmpty {
                await mediaAnalysisStore.upsertMetadataBatch(analysisBatch)
                analysisBatch.removeAll(keepingCapacity: true)
            }
        }
        guard scanGeneration == libraryScanGeneration else { return }

        print(String(format: "[SCAN] T+%.2fs — routing loop COMPLETE (%d items, %.2fs, %.0f items/sec)",
              Date().timeIntervalSince(scanStart),
              materializedAssets.count,
              Date().timeIntervalSince(routingLoopStart),
              Double(materializedAssets.count) / max(Date().timeIntervalSince(routingLoopStart), 0.001)))

        // Screen-recording classifier is fire-and-forget from the top
        // of this function — it runs in parallel with the routing
        // loop and promotes matching records into `.screenRecordings`
        // as soon as each chunk lands. No blocking pass here.

        let finalBatchStart = Date()
        await mediaAnalysisStore.upsertMetadataBatch(analysisBatch)
        print(String(format: "[SCAN] T+%.2fs — final upsertMetadataBatch took %.3fs",
              Date().timeIntervalSince(scanStart),
              Date().timeIntervalSince(finalBatchStart)))

        let finalSnapshotStart = Date()
        await applyLibrarySnapshot(
            categorized: categorized,
            duplicateBuckets: duplicateBuckets,
            similarBuckets: similarBuckets,
            similarVideoBuckets: similarVideoBuckets,
            similarScreenshotBuckets: similarScreenshotBuckets
        )
        print(String(format: "[SCAN] T+%.2fs — final applyLibrarySnapshot took %.3fs",
              Date().timeIntervalSince(scanStart),
              Date().timeIntervalSince(finalSnapshotStart)))
        print(String(format: "[SCAN] T+%.2fs — ✅ SCAN DONE (routing phase)",
              Date().timeIntervalSince(scanStart)))

        // Cache the fetch result and the bucket state so a
        // `PHPhotoLibraryChangeObserver` can ask iOS for a precise
        // diff and patch these buckets in place instead of forcing a
        // full re-index on every screenshot.
        lastLibraryFetchResult = fetchResult
        lastLibraryBuckets = LibraryBucketsCache(
            categorized: categorized,
            duplicateBuckets: duplicateBuckets,
            similarBuckets: similarBuckets,
            similarVideoBuckets: similarVideoBuckets,
            similarScreenshotBuckets: similarScreenshotBuckets,
            assetRouting: assetRouting
        )

        scanProgress = fetchResult.count == 0 ? 0 : 1
        scanStatusText = fetchResult.count == 0 ? "No media found yet" : "Scan complete"
        scannedLibraryItems = fetchResult.count
        isScanningLibrary = false

        // Duplicates are NOT populated during the scan itself — the
        // raw `duplicateBuckets` are just "same pixel dimensions"
        // candidate groups, which produces enormous false positives
        // on an iPhone library where thousands of photos share
        // resolution. The pixel-fingerprint verifier below is the
        // sole source of truth for `.duplicates`: it actually opens
        // each candidate, computes a SHA256 over a quantized pixel
        // render, and only groups photos whose pixels match.
        //
        // Similar / screenshots / videos used to go through a second
        // Vision-feature-print refinement pass. That's been disabled —
        // the scan-time visual-hash bucketing is good enough for those
        // categories, and refinement was what made the dashboard feel
        // laggy after a scan. See `refineReviewClustersIfNeeded` for
        // the full rationale per category.
        //
        // Only `.duplicates` still has a post-scan pass: pixel
        // fingerprinting via `verifyDuplicatesByPixel`, which is what
        // fixes the "90 GB of duplicates" bug by requiring bit-exact
        // pixel matches instead of just same-file-size grouping.
        if fetchResult.count > 0 {
            pendingRefinementCategories = [.duplicates]
            Task { @MainActor [weak self] in
                await self?.verifyDuplicatesByPixel(candidateBuckets: duplicateBuckets)
                self?.pendingRefinementCategories.remove(.duplicates)
            }
        }
    }

    /// Routes one asset into the bucket dicts using the same priority
    /// rules `applyLibrarySnapshot` expects. Returns an `AssetRouting`
    /// record so a later incremental remove can strip the asset from
    /// exactly the buckets it was placed in, in O(1).
    ///
    /// Kept as a single function so full-scan and incremental-insert
    /// paths are guaranteed to produce identical results.
    /// Plain value-type snapshot of the PHAsset properties the
    /// routing loop needs. Once we preread these off MainActor we
    /// never touch the PHAsset object again during routing — so no
    /// lazy Photos-DB round-trips happen on the main thread.
    struct AssetMetaSnapshot: Sendable {
        let id: String
        let mediaType: PHAssetMediaType
        let mediaSubtypes: PHAssetMediaSubtype
        let pixelWidth: Int
        let pixelHeight: Int
        let duration: TimeInterval
        let creationDate: Date?
        let modificationDate: Date?
        /// Pre-computed screen-recording flag: true when the asset is
        /// a portrait-oriented video whose original filename starts
        /// with `rpreplay`, `screen recording`, or `screenrecording`.
        /// This is computed in the preread pass (one PHAssetResource
        /// call per candidate) rather than in a separate flood, so
        /// we don't hammer `photoanalysisd` with concurrent workers.
        let isScreenRecording: Bool
    }

    /// Pre-reads every PHAsset's metadata in parallel chunks off
    /// MainActor. Returns an array parallel to the input so index i
    /// of the output maps to index i of `assets`.
    ///
    /// This is the key speed fix. Before: routing loop on MainActor
    /// reads `.pixelWidth`, `.mediaSubtypes`, `.creationDate` etc.
    /// inside the hot loop — each read can be a synchronous Photos
    /// XPC round-trip that stalls the loop. After: all reads happen
    /// once here in parallel on background threads, the loop then
    /// iterates plain Swift structs at memory speed.
    /// Streaming version of `prereadAssetMetadata`. Reads PHAsset
    /// properties sequentially (single-threaded — Photos DB is
    /// serialized internally anyway, so parallel workers just queue
    /// behind each other) and emits chunks of `chunkSize` snapshots
    /// as they become available. This lets the routing loop start
    /// consuming within ~100ms of scan start, instead of waiting for
    /// the full preread.
    nonisolated private static func prereadAssetMetadataStreaming(
        _ assets: [PHAsset],
        chunkSize: Int,
        onChunk: (([AssetMetaSnapshot]) -> Void)
    ) {
        guard !assets.isEmpty else { return }
        var buffer: [AssetMetaSnapshot] = []
        buffer.reserveCapacity(chunkSize)
        for asset in assets {
            // Screen-recording check: only for portrait videos. We
            // read `PHAssetResource.originalFilename` inline here —
            // yes it costs one PHAssetResource call per candidate
            // video, but we do it serially in this one pass instead
            // of spawning 8 parallel workers that would flood
            // `photoanalysisd` and break the UI's thumbnail requests.
            var isScreenRecording = false
            if asset.mediaType == .video && asset.pixelHeight >= asset.pixelWidth {
                let resources = PHAssetResource.assetResources(for: asset)
                if let filename = resources.first?.originalFilename {
                    let lower = filename.lowercased()
                    isScreenRecording = lower.hasPrefix("rpreplay")
                        || lower.hasPrefix("screen recording")
                        || lower.hasPrefix("screenrecording")
                }
            }
            let snap = AssetMetaSnapshot(
                id: asset.localIdentifier,
                mediaType: asset.mediaType,
                mediaSubtypes: asset.mediaSubtypes,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate,
                isScreenRecording: isScreenRecording
            )
            buffer.append(snap)
            if buffer.count >= chunkSize {
                onChunk(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            onChunk(buffer)
        }
    }

    nonisolated private static func prereadAssetMetadata(
        _ assets: [PHAsset]
    ) -> [AssetMetaSnapshot] {
        guard !assets.isEmpty else { return [] }
        var result = [AssetMetaSnapshot?](repeating: nil, count: assets.count)
        let workerCount = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount))
        let chunkSize = max(1, (assets.count + workerCount - 1) / workerCount)

        // Concurrent dispatch; each worker writes into a disjoint
        // slice of the result buffer so no locking needed.
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        // We can't safely write to a non-Sendable Array from multiple
        // queues without a lock, so use an NSLock.
        let lock = NSLock()

        for workerIndex in 0..<workerCount {
            let start = workerIndex * chunkSize
            guard start < assets.count else { break }
            let end = min(start + chunkSize, assets.count)
            group.enter()
            queue.async {
                var local: [(Int, AssetMetaSnapshot)] = []
                local.reserveCapacity(end - start)
                for i in start..<end {
                    let a = assets[i]
                    let snap = AssetMetaSnapshot(
                        id: a.localIdentifier,
                        mediaType: a.mediaType,
                        mediaSubtypes: a.mediaSubtypes,
                        pixelWidth: a.pixelWidth,
                        pixelHeight: a.pixelHeight,
                        duration: a.duration,
                        creationDate: a.creationDate,
                        modificationDate: a.modificationDate,
                        isScreenRecording: false
                    )
                    local.append((i, snap))
                }
                lock.lock()
                for (i, snap) in local { result[i] = snap }
                lock.unlock()
                group.leave()
            }
        }
        group.wait()
        return result.compactMap { $0 }
    }

    /// Routing variant that uses the pre-read `AssetMetaSnapshot`
    /// instead of touching the PHAsset directly. Same bucketing
    /// logic as `routeAsset`, just without the lazy-load cost.
    private func routeFromMeta(
        meta: AssetMetaSnapshot,
        categorized: inout [DashboardCategoryKind: [MediaAssetRecord]],
        duplicateBuckets: inout [String: [MediaAssetRecord]],
        similarBuckets: inout [String: [MediaAssetRecord]],
        similarVideoBuckets: inout [String: [MediaAssetRecord]],
        similarScreenshotBuckets: inout [String: [MediaAssetRecord]]
    ) -> (MediaAssetRecord, AssetRouting) {
        // File size estimate (fast pixel-based — no PHAssetResource).
        let pixelCount = max(meta.pixelWidth * meta.pixelHeight, 1)
        let size: Int64
        if meta.mediaType == .video {
            size = Int64(Double(pixelCount) * max(meta.duration, 1) * 0.08)
        } else {
            size = Int64(Double(pixelCount) * 0.45)
        }

        // Display title / subtitle.
        let base: String
        if meta.mediaType == .video {
            base = "Video"
        } else if meta.mediaSubtypes.contains(.photoScreenshot) {
            base = "Screenshot"
        } else {
            base = "Photo"
        }
        let title: String
        if let d = meta.creationDate {
            title = "\(base) \(DateFormatter.cleanupLabel.string(from: d))"
        } else {
            title = base
        }
        let subtitle = DateFormatter.cleanupShort.string(from: meta.creationDate ?? .now)
        let isScreenshot = meta.mediaSubtypes.contains(.photoScreenshot)

        let record = MediaAssetRecord(
            id: meta.id,
            title: title,
            subtitle: subtitle,
            sizeInBytes: size,
            duration: meta.duration,
            createdAt: meta.creationDate,
            modificationAt: meta.modificationDate,
            mediaType: meta.mediaType,
            isScreenshot: isScreenshot,
            pixelWidth: meta.pixelWidth,
            pixelHeight: meta.pixelHeight
        )

        // Cache the estimated size so any downstream lookups of
        // `estimatedFileSize` get a cache hit until the preflight
        // lands real numbers.
        let modStamp = meta.modificationDate?.timeIntervalSince1970 ?? 0
        fileSizeCache["\(meta.id)|\(modStamp)"] = size

        var categories: Set<DashboardCategoryKind> = []
        var dupKey: String? = nil
        var simKey: String? = nil
        var simVideoKey: String? = nil
        var simShotKey: String? = nil

        if meta.mediaType == .video {
            let timeBucket = Int((meta.creationDate?.timeIntervalSince1970 ?? 0) / (2 * 3600))
            let durationBucket = Int(meta.duration / 3)
            let sizeBucket = Int(size / 2_000_000)
            let wRounded = max(120, (meta.pixelWidth / 120) * 120)
            let hRounded = max(120, (meta.pixelHeight / 120) * 120)
            let videoKey = "\(timeBucket)-\(durationBucket)-\(sizeBucket)-\(wRounded)-\(hRounded)"
            similarVideoBuckets[videoKey, default: []].append(record)
            simVideoKey = videoKey

            if meta.isScreenRecording {
                categorized[.screenRecordings, default: []].append(record)
                categories.insert(.screenRecordings)
            } else if meta.duration > 0, meta.duration < 10 {
                categorized[.shortRecordings, default: []].append(record)
                categories.insert(.shortRecordings)
            } else {
                categorized[.videos, default: []].append(record)
                categories.insert(.videos)
            }
        } else {
            categorized[.other, default: []].append(record)
            categories.insert(.other)

            if isScreenshot {
                categorized[.screenshots, default: []].append(record)
                categories.insert(.screenshots)
                let dayBucket = Int((meta.creationDate?.timeIntervalSince1970 ?? 0) / 86_400)
                let wRounded = max(80, (meta.pixelWidth / 80) * 80)
                let hRounded = max(80, (meta.pixelHeight / 80) * 80)
                let screenshotKey = "\(dayBucket)-\(wRounded)-\(hRounded)"
                similarScreenshotBuckets[screenshotKey, default: []].append(record)
                simShotKey = screenshotKey
            } else {
                let ts = meta.creationDate?.timeIntervalSince1970 ?? 0
                let w48 = max(48, (meta.pixelWidth / 48) * 48)
                let h48 = max(48, (meta.pixelHeight / 48) * 48)
                let areaBucket = max(meta.pixelWidth * meta.pixelHeight, 1) / 350_000
                let duplicateKey = "\(meta.mediaType.rawValue)-\(meta.pixelWidth)x\(meta.pixelHeight)-\(size)"
                duplicateBuckets[duplicateKey, default: []].append(record)
                dupKey = duplicateKey
                // DEBUG LOG — routeFromMeta (full-scan path). Only
                // logs one per 500 records to avoid flooding the
                // Xcode console on a 37K-asset scan.
                if duplicateBuckets[duplicateKey]?.count ?? 0 > 1 {
                    print("[DUP-ROUTE] full-scan dupKey='\(duplicateKey)' bucketSize=\(duplicateBuckets[duplicateKey]?.count ?? 0) id=\(record.id)")
                }

                let similarKey = "\(Int(ts / 180))-\(w48)-\(h48)-\(areaBucket)"
                similarBuckets[similarKey, default: []].append(record)
                simKey = similarKey
            }
        }

        return (
            record,
            AssetRouting(
                mediaType: meta.mediaType,
                categories: categories,
                duplicateKey: dupKey,
                similarKey: simKey,
                similarVideoKey: simVideoKey,
                similarScreenshotKey: simShotKey
            )
        )
    }

    @discardableResult
    private func routeAsset(
        asset: PHAsset,
        record: MediaAssetRecord,
        categorized: inout [DashboardCategoryKind: [MediaAssetRecord]],
        duplicateBuckets: inout [String: [MediaAssetRecord]],
        similarBuckets: inout [String: [MediaAssetRecord]],
        similarVideoBuckets: inout [String: [MediaAssetRecord]],
        similarScreenshotBuckets: inout [String: [MediaAssetRecord]]
    ) -> AssetRouting {
        var categories: Set<DashboardCategoryKind> = []
        var dupKey: String? = nil
        var simKey: String? = nil
        var simVideoKey: String? = nil
        var simShotKey: String? = nil

        if record.mediaType == .video {
            let videoKey = similarVideoKey(for: asset, size: record.sizeInBytes)
            similarVideoBuckets[videoKey, default: []].append(record)
            simVideoKey = videoKey
            // DEFERRED screen-recording classification. The synchronous
            // `PHAssetResource.assetResources(for:)` call inside
            // `isScreenRecordingAsset` was the #1 scan bottleneck on
            // large libraries — every portrait video triggers a Photos
            // DB round-trip on MainActor. We now route ALL videos
            // tentatively below (`.videos` or `.shortRecordings`) based
            // on duration alone, and a post-scan classifier runs off
            // MainActor in parallel to promote screen-recording-named
            // videos into `.screenRecordings`. Accuracy is identical
            // (same filename check), just happens a second after the
            // main scan completes instead of inline.
            if asset.duration > 0, asset.duration < 10 {
                categorized[.shortRecordings, default: []].append(record)
                categories.insert(.shortRecordings)
            } else {
                categorized[.videos, default: []].append(record)
                categories.insert(.videos)
            }
        } else {
            categorized[.other, default: []].append(record)
            categories.insert(.other)

            if record.isScreenshot {
                categorized[.screenshots, default: []].append(record)
                categories.insert(.screenshots)
                let screenshotKey = similarScreenshotKey(for: asset)
                similarScreenshotBuckets[screenshotKey, default: []].append(record)
                simShotKey = screenshotKey
            } else {
                // Candidate bucket key now includes BOTH pixel
                // dimensions AND exact file size in bytes. Two
                // photos can only be bit-exact duplicates if both
                // match — so narrowing the bucket here means
                // `verifyDuplicatesByPixel` below only fingerprints
                // the tiny handful of real candidates instead of
                // every photo at that resolution.
                //
                // Before: key was "image-3024x4032". On an iPhone
                // EVERY photo lands in that bucket, so pixel
                // fingerprinting ran on ~30k photos. That's the
                // main reason duplicate refinement was dragging the
                // whole app down (it also blocked compression on
                // the shared main actor).
                //
                // The pixel-fingerprint verifier is still the final
                // source of truth for `.duplicates` — we've just
                // cut out the photos that CAN'T be duplicates
                // before it runs.
                let duplicateKey = duplicateCandidateKey(for: asset, size: record.sizeInBytes)
                duplicateBuckets[duplicateKey, default: []].append(record)
                dupKey = duplicateKey
                // DEBUG LOG — routeAsset (incremental / delta path).
                // If two identical new photos produce DIFFERENT
                // duplicateKeys, that's our bug: the size differs
                // because estimatedFileSize returned different values
                // for them.
                print("[DUP-ROUTE] routeAsset id=\(record.id) size=\(record.sizeInBytes) dupKey='\(duplicateKey)'")

                let similarKey = similarPhotoKey(for: asset)
                similarBuckets[similarKey, default: []].append(record)
                simKey = similarKey
            }
        }

        return AssetRouting(
            mediaType: asset.mediaType,
            categories: categories,
            duplicateKey: dupKey,
            similarKey: simKey,
            similarVideoKey: simVideoKey,
            similarScreenshotKey: simShotKey
        )
    }

    /// Handles a `PHPhotoLibraryChangeObserver` callback by applying
    /// the delta to the cached bucket state instead of re-indexing the
    /// whole library. Returns `true` when the incremental path ran
    /// successfully; `false` means the caller should fall back to a
    /// full scan (fresh install, no cached state, or iOS reported a
    /// non-incremental change).
    @MainActor
    @discardableResult
    private func applyIncrementalPhotoLibraryChange(_ change: PHChange) async -> Bool {
        // Guard against calling mid-scan — a full scan is already
        // rebuilding the buckets, so we don't need to patch them.
        guard activeLibraryScanTask == nil else { return true }
        guard photoAuthorization.isReadable else { return false }
        guard let previousFetchResult = lastLibraryFetchResult,
              var buckets = lastLibraryBuckets else {
            return false
        }
        guard let details = change.changeDetails(for: previousFetchResult) else {
            // Nothing in our fetch result was affected.
            return true
        }
        // When iOS can't express the change as insert/remove/change
        // arrays (e.g. sort order shifted significantly), fall back to
        // a full scan so we don't produce stale data.
        guard details.hasIncrementalChanges else { return false }

        let removedAssets = details.removedObjects
        let insertedAssets = details.insertedObjects
        let changedAssets = details.changedObjects

        // Pure no-op change (metadata on unrelated assets, etc).
        if removedAssets.isEmpty, insertedAssets.isEmpty, changedAssets.isEmpty {
            lastLibraryFetchResult = details.fetchResultAfterChanges
            return true
        }

        // Removed + changed both need to be stripped from their old
        // buckets. Changed assets get re-inserted below with fresh
        // routing (size/media-type/screenshot flag could have shifted
        // after an edit).
        let idsToStrip = Set(
            (removedAssets + changedAssets).map(\.localIdentifier)
        )
        if !idsToStrip.isEmpty {
            stripAssetsFromBuckets(idsToStrip, buckets: &buckets)
            // Vision / feature / face caches are keyed by local ID
            // and become stale for any removed or mutated asset.
            for id in idsToStrip {
                visualSignatureCache.removeValue(forKey: id)
                semanticFeaturePrintCache.removeValue(forKey: id)
                faceCountCache.removeValue(forKey: id)
                faceEmbeddingsCache.removeValue(forKey: id)
            pixelFingerprintCache.removeValue(forKey: id)
            }
        }

        PhotoAssetLookup.shared.remove(
            localIdentifiers: Set(removedAssets.map(\.localIdentifier))
        )

        // Insert new + reinsert changed, refreshing metadata for each.
        let assetsToInsert = insertedAssets + changedAssets
        var upsertBatch: [MediaAssetRecord] = []
        upsertBatch.reserveCapacity(assetsToInsert.count)

        for asset in assetsToInsert {
            PhotoAssetLookup.shared.upsert(asset)
            let record = makeMediaRecord(from: asset)
            let routing = routeAsset(
                asset: asset,
                record: record,
                categorized: &buckets.categorized,
                duplicateBuckets: &buckets.duplicateBuckets,
                similarBuckets: &buckets.similarBuckets,
                similarVideoBuckets: &buckets.similarVideoBuckets,
                similarScreenshotBuckets: &buckets.similarScreenshotBuckets
            )
            buckets.assetRouting[record.id] = routing
            upsertBatch.append(record)
        }

        if !upsertBatch.isEmpty {
            await mediaAnalysisStore.upsertMetadataBatch(upsertBatch)
        }
        if !removedAssets.isEmpty {
            await mediaAnalysisStore.deleteAnalyses(
                for: removedAssets.map(\.localIdentifier)
            )
        }

        // Recount from the patched routing map. Routing covers every
        // asset currently in our caches — a single O(n) pass is plenty
        // at library sizes and avoids drift from signed-delta math.
        let newFetch = details.fetchResultAfterChanges
        totalLibraryItems = newFetch.count
        var photos = 0
        var videos = 0
        for routing in buckets.assetRouting.values {
            if routing.mediaType == .image { photos += 1 }
            else if routing.mediaType == .video { videos += 1 }
        }
        photoCount = photos
        videoCount = videos

        // Invalidate refinement signatures so the next visit to a
        // cluster view re-runs Vision refinement over the patched
        // buckets. We do NOT wipe the caches themselves — only the
        // per-asset entries for removed/changed IDs were dropped
        // above, so the rest of the Vision work is preserved.
        clusterRefinementSignature.removeAll()

        await applyLibrarySnapshot(
            categorized: buckets.categorized,
            duplicateBuckets: buckets.duplicateBuckets,
            similarBuckets: buckets.similarBuckets,
            similarVideoBuckets: buckets.similarVideoBuckets,
            similarScreenshotBuckets: buckets.similarScreenshotBuckets
        )

        lastLibraryBuckets = buckets
        lastLibraryFetchResult = newFetch

        scanProgress = totalLibraryItems == 0 ? 0 : 1
        scannedLibraryItems = totalLibraryItems
        scanStatusText = totalLibraryItems == 0 ? "No media found yet" : "Library updated"

        // Re-run the pixel-fingerprint verifier so the Duplicates card
        // doesn't stay at "0 / Zero KB" after a delete or incremental
        // library change. `applyLibrarySnapshot` always writes
        // `.duplicates = []` (the raw buckets are coarse and would
        // give false positives), so without this re-run Duplicates
        // stays empty until a full rescan. The pixel-fingerprint cache
        // already persists across assets, so this is cheap — only
        // buckets whose membership actually changed pay new Vision
        // work; everything else is a cache hit.
        pendingRefinementCategories.insert(.duplicates)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.verifyDuplicatesByPixel(candidateBuckets: buckets.duplicateBuckets)
            self.pendingRefinementCategories.remove(.duplicates)
        }

        SharedSnapshotWriter.shared.refresh(force: true)

        // Persist the patched state so a relaunch after this delta
        // starts from the new numbers, not the pre-change ones.
        lastLibraryScanAt = Date()
        UserDefaults.standard.set(lastLibraryScanAt, forKey: lastLibraryScanAtKey)
        persistLibrarySnapshot()
        return true
    }

    /// Strips the given IDs from every bucket dict / categorized list
    /// in `buckets`, using the stored routing map for O(1) lookup
    /// instead of walking every bucket.
    private func stripAssetsFromBuckets(_ ids: Set<String>, buckets: inout LibraryBucketsCache) {
        for id in ids {
            guard let routing = buckets.assetRouting.removeValue(forKey: id) else {
                // Unknown asset — fall back to the pessimistic sweep.
                buckets.categorized = buckets.categorized.mapValues { $0.filter { $0.id != id } }
                buckets.duplicateBuckets = buckets.duplicateBuckets.mapValues { $0.filter { $0.id != id } }
                buckets.similarBuckets = buckets.similarBuckets.mapValues { $0.filter { $0.id != id } }
                buckets.similarVideoBuckets = buckets.similarVideoBuckets.mapValues { $0.filter { $0.id != id } }
                buckets.similarScreenshotBuckets = buckets.similarScreenshotBuckets.mapValues { $0.filter { $0.id != id } }
                continue
            }

            for category in routing.categories {
                buckets.categorized[category]?.removeAll(where: { $0.id == id })
            }
            if let key = routing.duplicateKey {
                buckets.duplicateBuckets[key]?.removeAll(where: { $0.id == id })
                if buckets.duplicateBuckets[key]?.isEmpty == true {
                    buckets.duplicateBuckets.removeValue(forKey: key)
                }
            }
            if let key = routing.similarKey {
                buckets.similarBuckets[key]?.removeAll(where: { $0.id == id })
                if buckets.similarBuckets[key]?.isEmpty == true {
                    buckets.similarBuckets.removeValue(forKey: key)
                }
            }
            if let key = routing.similarVideoKey {
                buckets.similarVideoBuckets[key]?.removeAll(where: { $0.id == id })
                if buckets.similarVideoBuckets[key]?.isEmpty == true {
                    buckets.similarVideoBuckets.removeValue(forKey: key)
                }
            }
            if let key = routing.similarScreenshotKey {
                buckets.similarScreenshotBuckets[key]?.removeAll(where: { $0.id == id })
                if buckets.similarScreenshotBuckets[key]?.isEmpty == true {
                    buckets.similarScreenshotBuckets.removeValue(forKey: key)
                }
            }
        }
    }


    /// Gate-aware wrapper. Callers that know whether they're deleting photos
    /// or videos should use this; it tracks free-tier usage and pops the
    /// upgrade sheet when the allowance is exhausted. Ungated legacy callers
    /// continue to hit `deleteAssets(with:)` directly.
    @MainActor
    func deleteAssets(with identifiers: [String], kind: FreeAction) async -> Bool {
        let unique = Array(Set(identifiers))
        guard !unique.isEmpty else { return true }
        let allowed = consumeFreeAllowance(kind, requested: unique.count)
        guard allowed > 0 else { return false }
        let slice = Array(unique.prefix(allowed))
        return await deleteAssets(with: slice)
    }

    func deleteAssets(with identifiers: [String]) async -> Bool {
        let deletedIDs = Set(identifiers)
        guard !deletedIDs.isEmpty else { return true }

        do {
            try await Self.deletePhotoLibraryAssets(with: Array(deletedIDs))
            removeDeletedAssetsFromState(deletedIDs)
            PhotoAssetLookup.shared.remove(localIdentifiers: deletedIDs)
            await mediaAnalysisStore.deleteAnalyses(for: Array(deletedIDs))
            return true
        } catch {
            return false
        }
    }

    func scanContacts() async {
        refreshPermissions()
        guard contactsAuthorization.isReadable else {
            duplicateContactGroups = []
            contactAnalysisSummary = .empty
            allContacts = []
            incompleteContacts = []
            return
        }

        isScanningContacts = true
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        var buckets: [String: [ContactRecord]] = [:]
        var allRecords: [ContactRecord] = []
        var incompleteRecords: [ContactRecord] = []
        let request = CNContactFetchRequest(keysToFetch: keys)

        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                let record = ContactRecord(
                    id: contact.identifier,
                    fullName: self.displayName(for: contact),
                    phones: contact.phoneNumbers.map { $0.value.stringValue },
                    emails: contact.emailAddresses.map { String($0.value) }
                )
                allRecords.append(record)
                if self.isIncompleteContact(record) {
                    incompleteRecords.append(record)
                }
                let key = self.contactBucketKey(for: record)
                guard !key.isEmpty else { return }
                buckets[key, default: []].append(record)
            }
        } catch {
            duplicateContactGroups = []
            contactAnalysisSummary = .empty
            allContacts = []
            incompleteContacts = []
            isScanningContacts = false
            return
        }

        let duplicateGroups = buckets
            .filter { $0.value.count > 1 }
            .map { key, contacts in
                DuplicateContactGroup(id: key, title: contacts.first?.fullName ?? "Duplicate", contacts: contacts.sorted { $0.fullName < $1.fullName })
            }
            .sorted { lhs, rhs in
                if lhs.duplicateCount == rhs.duplicateCount {
                    return lhs.title < rhs.title
                }
                return lhs.duplicateCount > rhs.duplicateCount
            }

        allContacts = allRecords.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        incompleteContacts = incompleteRecords.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        duplicateContactGroups = duplicateGroups
        contactBackupService.refreshBackups()
        contactAnalysisSummary = ContactAnalysisSummary(
            totalCount: allRecords.count,
            duplicateGroupCount: duplicateGroups.count,
            duplicateContactCount: duplicateGroups.reduce(0) { $0 + max(0, $1.duplicateCount - 1) },
            incompleteCount: incompleteRecords.count,
            backupCount: contactBackupService.backups.count
        )

        isScanningContacts = false
    }

    func scanEvents() async {
        refreshPermissions()
        guard eventsAuthorization.isReadable else {
            eventAnalysisSummary = .empty
            pastEvents = []
            return
        }

        isScanningEvents = true

        let now = Date()
        let start = Calendar.current.date(byAdding: .year, value: -5, to: now) ?? now.addingTimeInterval(-157_680_000)
        let end = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now.addingTimeInterval(31_536_000)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let pastEventItems = events
            .filter { event in
                (event.endDate ?? event.startDate) < now
            }
            .sorted { lhs, rhs in
                (lhs.endDate ?? lhs.startDate ?? .distantPast) > (rhs.endDate ?? rhs.startDate ?? .distantPast)
            }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let pastCount = pastEventItems.count
        pastEvents = pastEventItems.map { event in
            let date = event.startDate ?? event.endDate
            let dateLine: String
            if let date {
                if event.isAllDay {
                    let allDayFormatter = DateFormatter()
                    allDayFormatter.dateStyle = .medium
                    allDayFormatter.timeStyle = .none
                    dateLine = allDayFormatter.string(from: date)
                } else {
                    dateLine = formatter.string(from: date)
                }
            } else {
                dateLine = "No date"
            }

            let calendarName = event.calendar.title
            let subtitle = calendarName.isEmpty ? dateLine : "\(calendarName) • \(dateLine)"

            return EventRecord(
                id: event.eventIdentifier,
                title: event.title?.isEmpty == false ? event.title! : "Untitled Event",
                subtitle: subtitle,
                calendarName: calendarName.isEmpty ? "Calendar" : calendarName,
                dateLine: dateLine,
                startDate: event.startDate,
                isAllDay: event.isAllDay,
                canDelete: event.calendar.allowsContentModifications
            )
        }

        eventAnalysisSummary = EventAnalysisSummary(
            totalCount: events.count,
            pastEventCount: pastCount
        )

        isScanningEvents = false
    }

    func deleteEvents(with identifiers: [String]) async -> Bool {
        refreshPermissions()
        guard eventsAuthorization.isReadable else { return false }

        do {
            for identifier in identifiers {
                guard let event = eventStore.event(withIdentifier: identifier) else { continue }
                guard event.calendar.allowsContentModifications else { continue }
                try eventStore.remove(event, span: .thisEvent, commit: false)
            }
            try eventStore.commit()
            await scanEvents()
            return true
        } catch {
            eventStore.reset()
            await scanEvents()
            return false
        }
    }

    func mergeDuplicateContacts(group: DuplicateContactGroup) async -> Bool {
        let keeperID = bestContactID(in: group)
        let duplicateIDs = group.contacts.map(\.id).filter { $0 != keeperID }
        guard !duplicateIDs.isEmpty else { return false }

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        do {
            // 1. Fetch the keeper and collect all unique phones/emails from duplicates
            let keeperContact = try contactStore.unifiedContact(withIdentifier: keeperID, keysToFetch: keys)
            guard let keeperMutable = keeperContact.mutableCopy() as? CNMutableContact else { return false }

            var existingPhones = Set(keeperMutable.phoneNumbers.map { $0.value.stringValue.filter(\.isNumber) })
            var existingEmails = Set(keeperMutable.emailAddresses.map { ($0.value as String).lowercased() })

            let saveRequest = CNSaveRequest()

            for identifier in duplicateIDs {
                let dup = try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keys)

                // Merge unique phones into keeper
                for phone in dup.phoneNumbers {
                    let normalized = phone.value.stringValue.filter(\.isNumber)
                    if !normalized.isEmpty, existingPhones.insert(normalized).inserted {
                        keeperMutable.phoneNumbers.append(phone.copy() as! CNLabeledValue<CNPhoneNumber>)
                    }
                }

                // Merge unique emails into keeper
                for email in dup.emailAddresses {
                    let normalized = (email.value as String).lowercased()
                    if !normalized.isEmpty, existingEmails.insert(normalized).inserted {
                        keeperMutable.emailAddresses.append(email.copy() as! CNLabeledValue<NSString>)
                    }
                }

                // Delete the duplicate
                if let deletable = dup.mutableCopy() as? CNMutableContact {
                    saveRequest.delete(deletable)
                }
            }

            // 2. Update the keeper with merged fields
            saveRequest.update(keeperMutable)

            try contactStore.execute(saveRequest)
            await scanContacts()
            return true
        } catch {
            return false
        }
    }

    /// Merge multiple duplicate groups in bulk (single rescan at end)
    func bulkMergeDuplicateContacts(groups: [DuplicateContactGroup]) async -> Int {
        // Safety net: snapshot contacts before any destructive action, so the
        // user can always restore if the merge does something they didn't want.
        await contactBackupService.ensureRecentBackup()

        isCleaningContacts = true
        contactCleaningComplete = false
        contactCleaningProgress = (0, groups.count)
        var successCount = 0

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        for (index, group) in groups.enumerated() {
            contactCleaningProgress = (index, groups.count)

            let keeperID = bestContactID(in: group)
            let duplicateIDs = group.contacts.map(\.id).filter { $0 != keeperID }
            guard !duplicateIDs.isEmpty else { continue }

            do {
                let keeperContact = try contactStore.unifiedContact(withIdentifier: keeperID, keysToFetch: keys)
                guard let keeperMutable = keeperContact.mutableCopy() as? CNMutableContact else { continue }

                var existingPhones = Set(keeperMutable.phoneNumbers.map { $0.value.stringValue.filter(\.isNumber) })
                var existingEmails = Set(keeperMutable.emailAddresses.map { ($0.value as String).lowercased() })
                let saveRequest = CNSaveRequest()

                for identifier in duplicateIDs {
                    let dup = try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
                    for phone in dup.phoneNumbers {
                        let normalized = phone.value.stringValue.filter(\.isNumber)
                        if !normalized.isEmpty, existingPhones.insert(normalized).inserted {
                            keeperMutable.phoneNumbers.append(phone.copy() as! CNLabeledValue<CNPhoneNumber>)
                        }
                    }
                    for email in dup.emailAddresses {
                        let normalized = (email.value as String).lowercased()
                        if !normalized.isEmpty, existingEmails.insert(normalized).inserted {
                            keeperMutable.emailAddresses.append(email.copy() as! CNLabeledValue<NSString>)
                        }
                    }
                    if let deletable = dup.mutableCopy() as? CNMutableContact {
                        saveRequest.delete(deletable)
                    }
                }

                saveRequest.update(keeperMutable)
                try contactStore.execute(saveRequest)
                successCount += 1
            } catch {
                // Skip failed group, continue with rest
            }
        }

        contactCleaningProgress = (groups.count, groups.count)
        // Single rescan at end
        await scanContacts()
        isCleaningContacts = false
        contactCleaningComplete = true
        return successCount
    }

    /// Delete contacts by their IDs
    func deleteContacts(ids: Set<String>) async -> Bool {
        // Safety net before a destructive delete.
        await contactBackupService.ensureRecentBackup()

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        let saveRequest = CNSaveRequest()

        do {
            for identifier in ids {
                let contact = try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
                if let mutable = contact.mutableCopy() as? CNMutableContact {
                    saveRequest.delete(mutable)
                }
            }
            try contactStore.execute(saveRequest)
            await scanContacts()
            return true
        } catch {
            return false
        }
    }

    func resetContactCleaningState() {
        contactCleaningComplete = false
        contactCleaningProgress = (0, 0)
    }

    func updateEmailPreferences(_ transform: (inout EmailCleanerPreferences) -> Void) {
        transform(&emailPreferences)
        persist(emailPreferences, key: emailPreferencesKey)
    }

    func selectChargingPoster(_ poster: ChargingPoster) {
        guard !poster.locked else { return }
        selectedChargingPosterID = poster.id
        UserDefaults.standard.set(poster.id, forKey: selectedPosterKey)
    }

    func applyChargingPoster() {
        appliedChargingPosterID = selectedChargingPosterID
        UserDefaults.standard.set(appliedChargingPosterID, forKey: appliedPosterKey)
    }

    func currentChargingPoster() -> ChargingPoster? {
        posters.first { $0.id == selectedChargingPosterID }
    }

    func createSecretPIN(_ pin: String) -> Bool {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: trimmed)) else {
            return false
        }

        UserDefaults.standard.set(hashedPIN(trimmed), forKey: secretPinHashKey)
        isSecretSpaceUnlocked = true
        return true
    }

    func unlockSecretSpace(with pin: String) -> Bool {
        guard let storedHash = UserDefaults.standard.string(forKey: secretPinHashKey) else {
            return false
        }

        let isMatch = storedHash == hashedPIN(pin)
        isSecretSpaceUnlocked = isMatch
        return isMatch
    }

    func lockSecretSpace() {
        isSecretSpaceUnlocked = false
    }

    /// Nuclear recovery path for a forgotten PIN: wipes the stored PIN hash,
    /// the vault directory on disk, and the persisted item list. We don't
    /// keep a backup anywhere — the whole point of Secret Space is that a
    /// forgotten PIN means the data is gone. The UI must show a clear
    /// destructive confirm before calling this.
    func resetSecretPIN() {
        UserDefaults.standard.removeObject(forKey: secretPinHashKey)
        isSecretSpaceUnlocked = false
        isBiometricUnlockEnabled = false

        // Delete every file in the vault, then clear the index.
        let directory = secretVaultDirectory()
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
        secretVaultItems.removeAll()
        persist(secretVaultItems, key: vaultItemsKey)
    }

    // MARK: - Biometric unlock (Face ID / Touch ID)

    private var biometricEnabledKey: String { "cleanup.secret.biometric.enabled" }

    /// Whether the user opted in to Face ID / Touch ID unlock during PIN
    /// creation. Stored separately from the PIN hash so the PIN is still
    /// required if biometrics are disabled at the OS level later.
    var isBiometricUnlockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: biometricEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: biometricEnabledKey) }
    }

    /// Returns a label for the device's biometric, or nil if the device
    /// can't evaluate biometrics right now (no enrollment, no sensor, user
    /// disabled it). Safe to call every render.
    var biometricDisplayName: String? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return nil
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    /// Prompts Face ID / Touch ID. On success, flips `isSecretSpaceUnlocked`
    /// to true on the main actor so the vault UI reveals immediately. On
    /// failure / cancel, does nothing — PIN stays the fallback path.
    func attemptBiometricUnlock() async -> Bool {
        guard isBiometricUnlockEnabled, hasSecretPIN else { return false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        let reason = "Unlock Secret Space"
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if success {
                await MainActor.run { self.isSecretSpaceUnlocked = true }
            }
            return success
        } catch {
            return false
        }
    }

    func addSecretVaultItems(from items: [PhotosPickerItem], deleteOriginals: Bool) async -> SecretVaultImportResult {
        guard isSecretSpaceUnlocked else {
            return SecretVaultImportResult(
                importedCount: 0,
                failedCount: items.count,
                requestedOriginalDeletion: deleteOriginals,
                eligibleOriginalCount: 0,
                deletedOriginalCount: 0
            )
        }

        let directory = secretVaultDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var newItems = secretVaultItems
        var importedCount = 0
        var processedBytes: Int64 = 0
        var failedCount = 0
        var importedAssetIdentifiers: [String] = []
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SecretVaultImport") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        secretVaultImportStatus = SecretVaultImportStatus(
            totalCount: items.count,
            importedCount: 0,
            failedCount: 0,
            processedBytes: 0,
            currentFilename: nil
        )

        defer {
            secretVaultImportStatus = nil
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }

        for item in items {
            let contentType = item.supportedContentTypes.first
            let ext = contentType?.preferredFilenameExtension ?? "bin"
            let id = UUID().uuidString
            let filename = "\(id).\(ext)"

            secretVaultImportStatus?.currentFilename = filename

            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
                failedCount += 1
                updateSecretVaultImportStatus(
                    totalCount: items.count,
                    importedCount: importedCount,
                    failedCount: failedCount,
                    processedBytes: processedBytes,
                    currentFilename: filename
                )
                continue
            }

            let destinationURL = directory.appendingPathComponent(filename)

            do {
                try data.write(to: destinationURL, options: .atomic)
                let record = SecretVaultItem(
                    id: id,
                    filename: filename,
                    relativePath: "Vault/\(filename)",
                    contentTypeIdentifier: contentType?.identifier ?? UTType.data.identifier,
                    createdAt: .now
                )
                newItems.append(record)
                importedCount += 1
                processedBytes += Int64(data.count)
                if let itemIdentifier = item.itemIdentifier {
                    importedAssetIdentifiers.append(itemIdentifier)
                }
            } catch {
                failedCount += 1
            }

            updateSecretVaultImportStatus(
                totalCount: items.count,
                importedCount: importedCount,
                failedCount: failedCount,
                processedBytes: processedBytes,
                currentFilename: filename
            )
        }

        secretVaultItems = newItems.sorted { $0.createdAt > $1.createdAt }
        persist(secretVaultItems, key: vaultItemsKey)

        let eligibleOriginalIdentifiers = Array(Set(importedAssetIdentifiers))
        var deletedOriginalCount = 0
        if deleteOriginals, !eligibleOriginalIdentifiers.isEmpty {
            do {
                try await Self.deletePhotoLibraryAssets(with: eligibleOriginalIdentifiers)
                deletedOriginalCount = eligibleOriginalIdentifiers.count
                // User just moved N items to the secret vault with
                // "delete originals" — the library really did change.
                // `.manual` because this is a user action, not an
                // auto trigger; the PHChange observer will also fire
                // the incremental path, but we run this one first to
                // reflect the deletion in the UI without waiting for
                // the observer's 400ms debounce.
                await scanLibrary(trigger: .manual)
            } catch {
                deletedOriginalCount = 0
            }
        }

        return SecretVaultImportResult(
            importedCount: importedCount,
            failedCount: failedCount,
            requestedOriginalDeletion: deleteOriginals,
            eligibleOriginalCount: eligibleOriginalIdentifiers.count,
            deletedOriginalCount: deletedOriginalCount
        )
    }

    func deleteSecretVaultItem(_ item: SecretVaultItem) {
        let url = vaultURL(for: item)
        try? FileManager.default.removeItem(at: url)
        secretVaultItems.removeAll { $0.id == item.id }
        persist(secretVaultItems, key: vaultItemsKey)
    }

    var secretVaultStorageBytes: Int64 {
        secretVaultItems.reduce(0) { partial, item in
            let values = try? vaultURL(for: item).resourceValues(forKeys: [.fileSizeKey])
            return partial + Int64(values?.fileSize ?? 0)
        }
    }

    func compressVideo(
        assetID: String,
        preset: VideoCompressionPreset,
        label: String? = nil,
        targetSizeRatio: Double? = nil
    ) async -> Bool {
        guard let asset = assetForLookupIdentifier(assetID) else {
            compressionMessage = "This video is no longer available."
            return false
        }

        isCompressingAssetID = assetID
        compressionMessage = nil

        defer {
            isCompressingAssetID = nil
        }

        do {
            let sourceURL = try await requestVideoURL(for: asset)
            let originalBytes = estimatedFileSize(for: asset)
            let exportedURL = try await exportCompressedVideo(
                sourceURL: sourceURL,
                preset: preset,
                fileLengthLimit: targetSizeRatio.map { Int64(Double(originalBytes) * $0) }
            )
            let compressedBytes = fileSize(at: exportedURL)
            let compressedCopyID = try await saveCompressedVideoCopy(from: exportedURL)
            compressionResults[assetID] = MediaCompressionResult(
                assetID: assetID,
                originalBytes: originalBytes,
                compressedBytes: compressedBytes,
                label: label ?? preset.title
            )
            retireCompressionCandidates([assetID, compressedCopyID])
            compressionMessage = "Compressed copy saved to your photo library."
            return true
        } catch {
            compressionMessage = error.localizedDescription
            return false
        }
    }

    func compressPhoto(assetID: String, quality: CGFloat, label: String) async -> Bool {
        guard let asset = assetForLookupIdentifier(assetID) else {
            compressionMessage = "This photo is no longer available."
            return false
        }

        isCompressingAssetID = assetID
        compressionMessage = nil

        defer {
            isCompressingAssetID = nil
        }

        do {
            let imageData = try await requestImageData(for: asset)
            // UIImage decode + `jpegData` re-encode for a full-size
            // photo is 100-300ms of pure CPU. Running it inline on
            // the `@MainActor` AppFlow context blocks everything
            // else that needs the actor — including UI updates on
            // the Compress screen itself — and contends with
            // duplicate refinement's Vision tasks. Move it to a
            // detached background task so it can't starve the UI.
            let compressedData: Data? = await Task.detached(priority: .userInitiated) {
                guard let image = UIImage(data: imageData) else { return nil }
                return image.jpegData(compressionQuality: quality)
            }.value
            guard let compressedData else {
                throw NSError(domain: "Cleanup", code: -8, userInfo: [NSLocalizedDescriptionKey: "Unable to compress this photo."])
            }

            let originalBytes = estimatedFileSize(for: asset)
            let compressedCopyID = try await Self.saveCompressedPhotoToLibrary(data: compressedData)
            compressionResults[assetID] = MediaCompressionResult(
                assetID: assetID,
                originalBytes: originalBytes,
                compressedBytes: Int64(compressedData.count),
                label: label
            )
            retireCompressionCandidates([assetID, compressedCopyID])
            compressionMessage = "Compressed copy saved to your photo library."
            return true
        } catch {
            compressionMessage = error.localizedDescription
            return false
        }
    }

    private func restorePersistedState() {
        if let posterID = UserDefaults.standard.string(forKey: selectedPosterKey) {
            selectedChargingPosterID = posterID
        }
        if let appliedID = UserDefaults.standard.string(forKey: appliedPosterKey) {
            appliedChargingPosterID = appliedID
        }
        if let preferences: EmailCleanerPreferences = loadPersistedValue(key: emailPreferencesKey) {
            emailPreferences = preferences
        }
        if let vaultItems: [SecretVaultItem] = loadPersistedValue(key: vaultItemsKey) {
            secretVaultItems = vaultItems.filter { FileManager.default.fileExists(atPath: vaultURL(for: $0).path) }
        }
        if let retiredIDs: Set<String> = loadPersistedValue(key: retiredCompressionAssetIDsKey) {
            retiredCompressionAssetIDs = retiredIDs
        }

        // Restore the last-scan timestamp so the first `.auto` trigger
        // after relaunch respects the cooldown instead of re-scanning
        // from scratch on every cold start.
        if let saved = UserDefaults.standard.object(forKey: lastLibraryScanAtKey) as? Date {
            lastLibraryScanAt = saved
        }

        // Rehydrate the dashboard from the on-disk scan snapshot. The
        // cached results are exactly what `applyLibrarySnapshot` wrote
        // at the end of the most recent scan, so the UI paints with the
        // same numbers the user last saw — no "0 / 0 KB" flash while a
        // fresh scan churns. A light delta check in
        // `bootstrapIfNeeded()` reconciles this against the current
        // library state in the background.
        if let restored = ScanSnapshotStore.load() {
            mediaAssetsByCategory = restored.mediaAssetsByCategory
            mediaClustersByCategory = restored.mediaClustersByCategory
            totalLibraryItems = restored.totalLibraryItems
            photoCount = restored.photoCount
            videoCount = restored.videoCount
            confirmedScreenRecordingIDs = restored.confirmedScreenRecordingIDs
            refreshDashboardCategories()
            // Prime the lookup so any view that resolves PHAssets by
            // local identifier doesn't have to wait for the delta scan.
            let allIDs = restored.mediaAssetsByCategory.values.flatMap { $0.map(\.id) }
            if !allIDs.isEmpty {
                PhotoAssetLookup.shared.prime(localIdentifiers: Array(Set(allIDs)))
            }
            didRestoreLibrarySnapshot = true
        }
    }

    private func applyEmptyMediaState() {
        PhotoAssetLookup.shared.reset()
        totalLibraryItems = 0
        photoCount = 0
        videoCount = 0
        mediaAssetsByCategory = Dictionary(uniqueKeysWithValues: DashboardCategoryKind.allCases.map { ($0, []) })
        mediaClustersByCategory = Dictionary(uniqueKeysWithValues: DashboardCategoryKind.allCases.map { ($0, []) })
        dashboardCategories = DashboardCategoryKind.allCases.map {
            DashboardCategorySummary(kind: $0, count: 0, totalBytes: 0)
        }
        cachedCompressiblePhotos = []
        cachedCompressibleVideos = []
        // Reset incremental-scan cache so the next granted-access scan
        // does a proper full indexing instead of diffing against stale
        // buckets from a previous session. The queued change belongs to
        // the old fetch result and would be meaningless once the cache
        // is gone, so drop it too.
        lastLibraryFetchResult = nil
        lastLibraryBuckets = nil
        pendingLibraryChange = nil
        isScanningLibrary = false
        scanProgress = 0
        scanStatusText = "Photo access is required"
        scannedLibraryItems = 0
        // Photo access was revoked (or never granted). Clear the on-
        // disk snapshot too — otherwise the next cold launch would
        // restore dashboard numbers for photos we can no longer read,
        // which is worse than showing an empty state.
        ScanSnapshotStore.clear()
        UserDefaults.standard.removeObject(forKey: lastLibraryScanAtKey)
        lastLibraryScanAt = nil
        didRestoreLibrarySnapshot = false
    }

    private func applyLibrarySnapshot(
        categorized: [DashboardCategoryKind: [MediaAssetRecord]],
        duplicateBuckets: [String: [MediaAssetRecord]],
        similarBuckets: [String: [MediaAssetRecord]],
        similarVideoBuckets: [String: [MediaAssetRecord]],
        similarScreenshotBuckets: [String: [MediaAssetRecord]]
    ) async {
        // Move all heavy sorting/clustering OFF the main thread
        let (newAssets, newClusters) = await Task.detached(priority: .userInitiated) {
            func uniqueList(_ records: [MediaAssetRecord]) -> [MediaAssetRecord] {
                var seen = Set<String>()
                return records.filter { seen.insert($0.id).inserted }
            }

            func buildClusters(from buckets: [String: [MediaAssetRecord]], category: DashboardCategoryKind) -> [MediaCluster] {
                buckets.compactMap { key, value in
                    let sorted = uniqueList(value).sorted {
                        if $0.sizeInBytes == $1.sizeInBytes {
                            return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                        }
                        return $0.sizeInBytes > $1.sizeInBytes
                    }
                    guard sorted.count > 1 else { return nil }
                    return MediaCluster(id: key, category: category, assets: sorted, totalBytes: sorted.reduce(0) { $0 + $1.sizeInBytes }, subtitle: nil)
                }
                .sorted {
                    if $0.totalBytes == $1.totalBytes { return $0.count > $1.count }
                    return $0.totalBytes > $1.totalBytes
                }
            }

            func flatten(_ clusters: [MediaCluster]) -> [MediaAssetRecord] {
                uniqueList(clusters.flatMap(\.assets))
            }

            func chunkClusters(_ assets: [MediaAssetRecord], category: DashboardCategoryKind, chunkSize: Int) -> [MediaCluster] {
                let sorted = assets.sorted {
                    if $0.sizeInBytes == $1.sizeInBytes {
                        return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                    return $0.sizeInBytes > $1.sizeInBytes
                }
                guard !sorted.isEmpty else { return [] }
                return stride(from: 0, to: sorted.count, by: chunkSize).map { startIndex in
                    let endIndex = min(startIndex + chunkSize, sorted.count)
                    let chunk = Array(sorted[startIndex..<endIndex])
                    return MediaCluster(id: "\(category.rawValue)-\(startIndex)", category: category, assets: chunk, totalBytes: chunk.reduce(0) { $0 + $1.sizeInBytes }, subtitle: nil)
                }
            }

            // NOTE: we deliberately DO NOT build duplicate clusters
            // from `duplicateBuckets` here. Those buckets are coarse
            // candidates (same resolution, same media type) — iPhone
            // produces thousands of photos at identical dimensions so
            // raw candidates would inflate duplicates to 90+ GB of
            // false positives. The pixel-fingerprint verifier
            // (`verifyDuplicatesByPixel`, runs post-scan) is the sole
            // author of `.duplicates`. Until it completes the
            // Duplicates dashboard card shows zero, not a wrong number.
            let similarClusters = buildClusters(from: similarBuckets, category: .similar)
            let similarVideoClusters = buildClusters(from: similarVideoBuckets, category: .similarVideos)
            let similarScreenshotClusters = buildClusters(from: similarScreenshotBuckets, category: .similarScreenshots)

            var workingCategorized = categorized
            workingCategorized[.duplicates] = []
            workingCategorized[.similar] = flatten(similarClusters)
            workingCategorized[.similarVideos] = flatten(similarVideoClusters)
            workingCategorized[.similarScreenshots] = flatten(similarScreenshotClusters)

            // Priority routing for video buckets: a video promoted to the
            // duplicate (similarVideos) cluster must be removed from
            // shortRecordings / screenRecordings / videos so each asset
            // appears in exactly one bucket.
            let videoDuplicateIDs = Set(workingCategorized[.similarVideos, default: []].map(\.id))
            workingCategorized[.screenRecordings] = workingCategorized[.screenRecordings, default: []].filter { !videoDuplicateIDs.contains($0.id) }
            workingCategorized[.shortRecordings] = workingCategorized[.shortRecordings, default: []].filter { !videoDuplicateIDs.contains($0.id) }
            workingCategorized[.videos] = workingCategorized[.videos, default: []].filter { !videoDuplicateIDs.contains($0.id) }

            let assets = workingCategorized.mapValues { records in
                records.sorted {
                    if $0.sizeInBytes == $1.sizeInBytes {
                        return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                    return $0.sizeInBytes > $1.sizeInBytes
                }
            }

            let clusters: [DashboardCategoryKind: [MediaCluster]] = [
                .duplicates: [],
                .similar: similarClusters,
                .similarVideos: similarVideoClusters,
                .similarScreenshots: similarScreenshotClusters,
                .screenshots: chunkClusters(workingCategorized[.screenshots, default: []], category: .screenshots, chunkSize: 12),
                .other: chunkClusters(workingCategorized[.other, default: []], category: .other, chunkSize: 12),
                .videos: chunkClusters(workingCategorized[.videos, default: []], category: .videos, chunkSize: 1),
                .shortRecordings: chunkClusters(workingCategorized[.shortRecordings, default: []], category: .shortRecordings, chunkSize: 1),
                .screenRecordings: chunkClusters(workingCategorized[.screenRecordings, default: []], category: .screenRecordings, chunkSize: 1)
            ]

            return (assets, clusters)
        }.value

        // Only lightweight assignments on the main thread
        mediaAssetsByCategory = newAssets
        mediaClustersByCategory = newClusters

        // Re-apply screen-recording promotions from the classifier.
        // The snapshot above was built from the raw `categorized` dict
        // (which knows nothing about filename classification), so any
        // records the classifier has confirmed need to be moved back
        // out of `.videos` / `.shortRecordings` and into
        // `.screenRecordings`. Carrying this through on every snapshot
        // is what makes the Screen Recordings card stay populated
        // instead of getting wiped at each publish.
        if !confirmedScreenRecordingIDs.isEmpty {
            let ids = confirmedScreenRecordingIDs
            var videos = mediaAssetsByCategory[.videos] ?? []
            var shorts = mediaAssetsByCategory[.shortRecordings] ?? []
            var screens = mediaAssetsByCategory[.screenRecordings] ?? []
            let existingScreenIDs = Set(screens.map(\.id))

            var promoted: [MediaAssetRecord] = []
            videos.removeAll { rec in
                if ids.contains(rec.id), !existingScreenIDs.contains(rec.id) {
                    promoted.append(rec); return true
                }
                return false
            }
            shorts.removeAll { rec in
                if ids.contains(rec.id), !existingScreenIDs.contains(rec.id) {
                    promoted.append(rec); return true
                }
                return false
            }
            if !promoted.isEmpty {
                screens.append(contentsOf: promoted)
                mediaAssetsByCategory[.videos] = videos
                mediaAssetsByCategory[.shortRecordings] = shorts
                mediaAssetsByCategory[.screenRecordings] = screens
            }
        }

        refreshDashboardCategories()

        // `applyLibrarySnapshot` wholesale replaces the cluster maps.
        // If the current state had been refined earlier (post-scan or
        // view-triggered), this snapshot just reverted it. Drop the
        // cached refinement signature so the NEXT refinement trigger
        // actually runs instead of short-circuiting on "signature
        // already refined." Refinement itself is gated on
        // `!isScanningLibrary`, so during a scan we simply wait for
        // the final post-scan snapshot + post-scan refinement to
        // drive the deterministic end state.
        let refinable: [DashboardCategoryKind] = [
            .similar, .similarScreenshots, .similarVideos, .screenshots
        ]
        for category in refinable {
            clusterRefinementSignature[category] = nil
        }
    }

    private func refreshDashboardCategories() {
        dashboardCategories = DashboardCategoryKind.allCases.map { kind in
            let items = mediaAssetsByCategory[kind, default: []]
            return DashboardCategorySummary(
                kind: kind,
                count: items.count,
                totalBytes: items.reduce(0) { $0 + $1.sizeInBytes }
            )
        }
        rebuildCompressibleAssetCaches()
    }

    /// Writes the current in-memory scan state to disk. Called after a
    /// full scan, after the pixel-fingerprint duplicate pass, and after
    /// an incremental library change so that the next launch can paint
    /// the dashboard with real numbers before a single `PHAsset` fetch
    /// runs. Fire-and-forget — the actual file write hops off to a
    /// utility queue inside `ScanSnapshotStore.save`.
    func persistLibrarySnapshot() {
        ScanSnapshotStore.save(
            totalLibraryItems: totalLibraryItems,
            photoCount: photoCount,
            videoCount: videoCount,
            confirmedScreenRecordingIDs: confirmedScreenRecordingIDs,
            assetsByCategory: mediaAssetsByCategory,
            clustersByCategory: mediaClustersByCategory
        )
    }

    private func rebuildCompressibleAssetCaches() {
        cachedCompressiblePhotos = compressibleAssets(of: .image)
        cachedCompressibleVideos = compressibleAssets(of: .video)
    }

    private func removeDeletedAssetsFromState(_ identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }

        let removedRecords = uniqueMediaRecords(
            from: mediaAssetsByCategory.values.flatMap { $0 },
            filteringTo: identifiers
        )

        totalLibraryItems = max(0, totalLibraryItems - removedRecords.count)
        photoCount = max(0, photoCount - removedRecords.values.filter { $0.mediaType == .image }.count)
        videoCount = max(0, videoCount - removedRecords.values.filter { $0.mediaType == .video }.count)

        mediaAssetsByCategory = mediaAssetsByCategory.mapValues { records in
            records.filter { !identifiers.contains($0.id) }
        }

        mediaClustersByCategory = mediaClustersByCategory.mapValues { clusters in
            clusters.compactMap { cluster in
                let remainingAssets = cluster.assets.filter { !identifiers.contains($0.id) }
                guard !remainingAssets.isEmpty else { return nil }

                let shouldKeepCluster: Bool
                switch cluster.category {
                case .duplicates, .similar, .similarVideos, .similarScreenshots, .screenshots:
                    shouldKeepCluster = remainingAssets.count > 1
                case .other, .videos, .shortRecordings, .screenRecordings:
                    shouldKeepCluster = !remainingAssets.isEmpty
                }

                guard shouldKeepCluster else { return nil }

                return MediaCluster(
                    id: cluster.id,
                    category: cluster.category,
                    assets: remainingAssets,
                    totalBytes: remainingAssets.reduce(0) { $0 + $1.sizeInBytes },
                    subtitle: cluster.subtitle
                )
            }
        }

        identifiers.forEach {
            visualSignatureCache.removeValue(forKey: $0)
            semanticFeaturePrintCache.removeValue(forKey: $0)
            faceCountCache.removeValue(forKey: $0)
            faceEmbeddingsCache.removeValue(forKey: $0)
            pixelFingerprintCache.removeValue(forKey: $0)
        }

        // Keep the incremental-scan bucket cache in lockstep with the
        // user-visible state. If we didn't strip here, the next
        // `PHPhotoLibraryChangeObserver` callback would diff against
        // a cache that still contained these IDs and the incremental
        // path would apply a no-op, leaving stale routing entries.
        if var buckets = lastLibraryBuckets {
            stripAssetsFromBuckets(identifiers, buckets: &buckets)
            lastLibraryBuckets = buckets
        }

        clusterRefinementSignature.removeAll()
        refreshDashboardCategories()
        scanProgress = totalLibraryItems == 0 ? 0 : 1
        scannedLibraryItems = totalLibraryItems
        scanStatusText = totalLibraryItems == 0 ? "No media found yet" : "Library updated"
        isScanningLibrary = false
    }

    private func refineVisualClusters(from sourceClusters: [MediaCluster], category: DashboardCategoryKind) async -> [MediaCluster] {
        var refined: [MediaCluster] = []

        for (index, cluster) in sourceClusters.enumerated() {
            refined.append(contentsOf: await refinedSubclusters(from: cluster, category: category))

            if index.isMultiple(of: 4) {
                await Task.yield()
            }
        }

        return refined.sorted {
            if $0.totalBytes == $1.totalBytes {
                return $0.count > $1.count
            }
            return $0.totalBytes > $1.totalBytes
        }
    }

    private func refinementSourceSignature(for clusters: [MediaCluster]) -> Int {
        var hasher = Hasher()
        hasher.combine(clusters.count)
        for cluster in clusters {
            hasher.combine(cluster.id)
            hasher.combine(cluster.assets.count)
            hasher.combine(cluster.totalBytes)
            hasher.combine(cluster.assets.first?.id)
            hasher.combine(cluster.assets.last?.id)
        }
        return hasher.finalize()
    }

    private func refinedSubclusters(from cluster: MediaCluster, category: DashboardCategoryKind) async -> [MediaCluster] {
        guard cluster.assets.count > 1 else { return [] }

        let sortedAssets = uniqueMediaRecordList(from: cluster.assets).sorted {
            if $0.createdAt == $1.createdAt {
                return $0.sizeInBytes > $1.sizeInBytes
            }
            return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }

        var groups: [VisualClusterBucket] = []

        for (index, asset) in sortedAssets.enumerated() {
            let signature = await visualSignature(for: asset)
            let fallbackKey = refinementFallbackKey(for: asset, category: category)

            let featurePrint = await semanticFeaturePrint(for: asset)

            // Face embeddings were the main cost in this pipeline —
            // they required a 1024px thumbnail per asset (vs 256px
            // for everything else) and a second Vision pass per face
            // crop. For similar/screenshots/videos we no longer ask
            // for them: scene feature print + face COUNT + time/size
            // gates are enough to keep clusters honest without the
            // 10-50× I/O penalty. Identity splitting for similar is
            // handled by the face-count parity check — different
            // people will also usually be at different counts OR in
            // different time windows. Good-enough, and fast.
            let candidateFaces: [VNFeaturePrintObservation]? = nil

            // Agglomerative matching: the new asset joins a cluster
            // only if it matches at least one MEMBER of that cluster —
            // not just the anchor. This prevents the classic drift
            // bug where photo B matches anchor A loosely, photo C
            // matches A loosely, but C and B are actually different
            // people. With transitive pairwise checks, C only joins
            // the A-B cluster if it matches A OR B (not just A).
            var matchingGroupIndex: Int?
            groupLoop: for groupIndex in groups.indices {
                for member in groups[groupIndex].members {
                    if await shouldPlace(
                        asset: asset,
                        signature: signature,
                        featurePrint: featurePrint,
                        faceEmbeddings: candidateFaces,
                        againstMember: member,
                        category: category
                    ) {
                        matchingGroupIndex = groupIndex
                        break groupLoop
                    }
                }
            }

            let newMember = ClusterMember(
                asset: asset,
                signature: signature,
                featurePrint: featurePrint,
                faceEmbeddings: candidateFaces
            )

            if let groupIndex = matchingGroupIndex {
                groups[groupIndex].assets.append(asset)
                groups[groupIndex].members.append(newMember)
            } else {
                groups.append(
                    VisualClusterBucket(
                        anchorAsset: asset,
                        anchorSignature: signature,
                        anchorFeaturePrint: featurePrint,
                        anchorFaceEmbeddings: candidateFaces,
                        fallbackKey: fallbackKey,
                        assets: [asset],
                        members: [newMember]
                    )
                )
            }

            if index.isMultiple(of: 10) {
                await Task.yield()
            }
        }

        return groups.enumerated().compactMap { index, group in
            let groupAssets = group.assets.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.sizeInBytes > $1.sizeInBytes
                }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }

            guard groupAssets.count > 1 else { return nil }

            return MediaCluster(
                id: "\(cluster.id)-exact-\(index)",
                category: category,
                assets: groupAssets,
                totalBytes: groupAssets.reduce(0) { $0 + $1.sizeInBytes },
                subtitle: refinedClusterSubtitle(for: groupAssets, category: category)
            )
        }
    }

    /// Pairwise cluster merge test. The candidate joins a cluster iff
    /// it matches at least one existing MEMBER (not just the anchor).
    /// That single design change is what keeps transitive drift out
    /// of clusters: photo C can't slip in just because it matches
    /// anchor A loosely — it must match A or B tightly.
    private func shouldPlace(
        asset: MediaAssetRecord,
        signature: MediaVisualSignature?,
        featurePrint: VNFeaturePrintObservation?,
        faceEmbeddings: [VNFeaturePrintObservation]?,
        againstMember member: ClusterMember,
        category: DashboardCategoryKind
    ) async -> Bool {
        // ── .similar: quick face-count parity ──────────────────────
        //
        // Face identity via per-face embeddings turned out to be too
        // slow for an interactive refinement (needs a 1024px thumb +
        // per-face Vision pass). We rely on face-count parity as a
        // cheap identity proxy: photos with different face counts
        // are clearly different subjects, photos with matching face
        // counts in the same time window + scene feature print range
        // are either the same moment or a harmless near-miss. Tiny
        // accuracy trade for a 10-50× speedup. Duplicates still has
        // its own strict pixel-fingerprint pass; this loosening does
        // NOT affect duplicate detection.
        if category == .similar {
            let assetFaceCount = await faceCount(for: asset)
            let memberFaceCount = await faceCount(for: member.asset)
            guard assetFaceCount == memberFaceCount else {
                return false
            }
        }

        guard isWithinRefinementWindow(asset, comparedTo: member.asset, category: category) else {
            return false
        }

        guard isComparableResolution(asset, comparedTo: member.asset, category: category) else {
            return false
        }

        let sizeFloor = max(min(asset.sizeInBytes, member.asset.sizeInBytes), 1)
        let sizeCeiling = max(asset.sizeInBytes, member.asset.sizeInBytes)
        let sizeRatio = Double(sizeCeiling) / Double(sizeFloor)
        guard sizeRatio <= refinementSizeRatioThreshold(for: category) else {
            return false
        }

        if let featurePrint, let memberFeaturePrint = member.featurePrint {
            let semanticDistance = Self.featurePrintDistance(from: featurePrint, to: memberFeaturePrint)
            guard semanticDistance <= refinementFeatureDistanceThreshold(for: category) else {
                return false
            }
            if category == .similar {
                // Face identity already verified above (or both have
                // zero faces, in which case scene similarity IS the
                // right signal for this pair).
                return true
            }
        }

        if let signature, let memberSignature = member.signature {
            let hashDistance = Self.hammingDistance(signature.dHash, memberSignature.dHash)
            let lumaDistance = abs(signature.meanLuma - memberSignature.meanLuma)
            let spreadDistance = abs(signature.spread - memberSignature.spread)

            let coarseMatch = hashDistance <= refinementHashThreshold(for: category)
                && lumaDistance <= refinementLumaThreshold(for: category)
                && spreadDistance <= refinementSpreadThreshold(for: category)

            guard coarseMatch else { return false }

            // ── PIXEL-LEVEL VERIFICATION for .duplicates ─────────────
            //
            // Every other signal above is perceptual — it tells us
            // the two images look similar, not that they're actually
            // the same pixels. For the duplicate category that's not
            // enough: "duplicate" must mean duplicate, or we flag 90
            // GB of stuff that's just similar and users lose trust.
            //
            // The pixel fingerprint is SHA256 over a 64×64 / 4-bit
            // quantized render. Matching fingerprints = true
            // duplicates (iCloud copies, airdrop round-trips, re-
            // saves). Crops / edits / filters fail this check, which
            // is exactly what we want.
            if category == .duplicates {
                let a = await pixelFingerprint(for: asset)
                let b = await pixelFingerprint(for: member.asset)
                guard let a, let b, a == b else {
                    return false
                }
            }

            return true
        }

        // No signals at all — reject rather than fall back to a loose
        // fallback key (which is what was merging unrelated photos).
        return false
    }

    private func refinementFallbackKey(for asset: MediaAssetRecord, category: DashboardCategoryKind) -> String {
        let timestamp = asset.createdAt?.timeIntervalSince1970 ?? 0

        switch category {
        case .similarScreenshots:
            return [
                Int(timestamp / (12 * 60)).description,
                roundedValue(asset.pixelWidth, unit: 20).description,
                roundedValue(asset.pixelHeight, unit: 20).description,
                Int(asset.sizeInBytes / 250_000).description
            ].joined(separator: "-")
        case .similarVideos:
            return [
                Int(timestamp / (10 * 60)).description,
                roundedValue(asset.pixelWidth, unit: 60).description,
                roundedValue(asset.pixelHeight, unit: 60).description,
                Int(asset.duration / 2).description,
                Int(asset.sizeInBytes / 1_500_000).description
            ].joined(separator: "-")
        default:
            return [
                Int(timestamp / (45 * 60)).description,
                roundedValue(asset.pixelWidth, unit: 24).description,
                roundedValue(asset.pixelHeight, unit: 24).description,
                Int(asset.sizeInBytes / 350_000).description
            ].joined(separator: "-")
        }
    }

    private func isWithinRefinementWindow(
        _ asset: MediaAssetRecord,
        comparedTo anchor: MediaAssetRecord,
        category: DashboardCategoryKind
    ) -> Bool {
        guard let lhs = asset.createdAt, let rhs = anchor.createdAt else { return true }

        let delta = abs(lhs.timeIntervalSince(rhs))
        switch category {
        case .similarScreenshots:
            return delta <= 20 * 60
        case .similarVideos:
            return delta <= 15 * 60
        default:
            return delta <= 45 * 60
        }
    }

    private func isComparableResolution(
        _ asset: MediaAssetRecord,
        comparedTo anchor: MediaAssetRecord,
        category: DashboardCategoryKind
    ) -> Bool {
        let widthDelta = abs(asset.pixelWidth - anchor.pixelWidth)
        let heightDelta = abs(asset.pixelHeight - anchor.pixelHeight)

        switch category {
        case .similarScreenshots:
            return widthDelta <= 80 && heightDelta <= 80
        case .similarVideos:
            return widthDelta <= 120 && heightDelta <= 120
        default:
            return widthDelta <= 120 && heightDelta <= 120
        }
    }

    private func refinementHashThreshold(for category: DashboardCategoryKind) -> Int {
        switch category {
        case .duplicates:
            // "Duplicate" means near-pixel-identical. dHash over a 9×8
            // grid has 72 bits — 2 flipped bits = effectively identical
            // (JPEG re-encoding jitter). Anything higher is "similar",
            // not "duplicate".
            return 2
        case .similarScreenshots:
            return 9
        case .similarVideos:
            return 10
        case .similar:
            return 8
        default:
            return 11
        }
    }

    private func refinementLumaThreshold(for category: DashboardCategoryKind) -> Int {
        switch category {
        case .duplicates:
            return 4
        case .similarScreenshots:
            return 22
        case .similarVideos:
            return 26
        case .similar:
            return 18
        default:
            return 24
        }
    }

    private func refinementSpreadThreshold(for category: DashboardCategoryKind) -> Int {
        switch category {
        case .duplicates:
            return 4
        case .similarScreenshots:
            return 20
        case .similarVideos:
            return 24
        case .similar:
            return 16
        default:
            return 22
        }
    }

    private func refinementSizeRatioThreshold(for category: DashboardCategoryKind) -> Double {
        switch category {
        case .duplicates:
            // Within 2% — true duplicates from iCloud sync / airdrop
            // round-trip vary by < 1%. This is what separates real
            // duplicates (90 KB vs 91 KB) from re-edits / crops.
            return 1.02
        case .similarScreenshots:
            return 1.35
        case .similarVideos:
            return 1.8
        case .similar:
            return 1.25
        default:
            return 1.5
        }
    }

    private func refinementFeatureDistanceThreshold(for category: DashboardCategoryKind) -> Float {
        switch category {
        case .duplicates:
            // Semantic featurePrint distance ≤ 0.06 means the two
            // images are essentially the same frame.
            return 0.06
        case .similarScreenshots:
            return 0.18
        case .similarVideos:
            return 0.24
        case .similar:
            // Tight: scene feature print alone must be very close.
            // Face identity is additionally enforced in shouldPlace.
            return 0.12
        default:
            return 0.20
        }
    }

    private func maximumClusterSize(for category: DashboardCategoryKind) -> Int {
        switch category {
        case .similarScreenshots:
            return 12
        case .similarVideos:
            return 12
        case .similar:
            // A real "similar" cluster is a burst of near-identical
            // frames — 8 is already generous. Caps prevent the
            // "167 photos in one cluster" blow-up when refinement
            // under-splits.
            return 8
        default:
            return 20
        }
    }

    private func refinedClusterSubtitle(for assets: [MediaAssetRecord], category: DashboardCategoryKind) -> String? {
        guard let lead = assets.first else { return nil }

        let dateLine: String
        if let date = lead.createdAt {
            dateLine = DateFormatter.cleanupCluster.string(from: date)
        } else {
            dateLine = "Unknown capture time"
        }

        let resolution = "\(lead.pixelWidth)×\(lead.pixelHeight)"
        switch category {
        case .similarScreenshots:
            return "\(dateLine) • Screenshot • \(resolution)"
        case .similarVideos:
            return "\(dateLine) • Video • \(resolution)"
        default:
            return "\(dateLine) • \(resolution)"
        }
    }

    private struct IndexingThumbnail {
        let uiImage: UIImage
        let ciImage: CIImage
    }

    private struct VisionAnalysisResult {
        let featurePrint: VNFeaturePrintObservation?
        let faceCount: Int?
        /// Feature print per detected face crop (largest faces first,
        /// capped at `maxFacesPerAsset`). Used as an identity proxy in
        /// `.similar` clustering. `nil` when the caller didn't ask for
        /// it; empty array when we ran detection but couldn't produce
        /// any usable crops.
        let faceEmbeddings: [VNFeaturePrintObservation]?
    }

    private func visualSignature(for asset: MediaAssetRecord) async -> MediaVisualSignature? {
        if let cached = visualSignatureCache[asset.id] {
            return cached
        }

        await hydratePersistedAnalysisCaches(for: asset)
        if let cached = visualSignatureCache[asset.id] {
            return cached
        }

        // Use the larger 256×256 indexing thumbnail for better hash quality
        // (especially important for videos where the 52×52 thumbnail is too small)
        guard let sourceAsset = assetForLookupIdentifier(asset.id),
              let thumbnail = await Self.requestIndexingThumbnail(for: sourceAsset),
              let signature = Self.makeVisualSignature(from: thumbnail.uiImage)
        else {
            return nil
        }

        visualSignatureCache[asset.id] = signature
        await mediaAnalysisStore.saveDerivedSignals(
            for: asset,
            faceCount: faceCountCache[asset.id],
            featurePrintArchive: archivedFeaturePrint(for: semanticFeaturePrintCache[asset.id]),
            visualSignature: signature
        )
        return signature
    }

    private func semanticFeaturePrint(for asset: MediaAssetRecord) async -> VNFeaturePrintObservation? {
        if let cached = semanticFeaturePrintCache[asset.id] {
            return cached
        }

        await ensureAnalysisSignals(for: asset, includeFaceCount: false)
        return semanticFeaturePrintCache[asset.id]
    }

    private func faceCount(for asset: MediaAssetRecord) async -> Int {
        if let cached = faceCountCache[asset.id] {
            return cached
        }

        await ensureAnalysisSignals(for: asset, includeFaceCount: true, includeFaceEmbeddings: false)
        return faceCountCache[asset.id] ?? 0
    }

    /// Pixel-level fingerprint for this asset. Two assets sharing a
    /// fingerprint are pixel-identical at 64×64 / 4-bit quantization —
    /// i.e. actual duplicates (iCloud copies, airdrop round-trips,
    /// re-saves). Edits, crops, and filters will produce a different
    /// fingerprint.
    private func pixelFingerprint(for asset: MediaAssetRecord) async -> Data? {
        if let cached = pixelFingerprintCache[asset.id] {
            return cached
        }
        guard let sourceAsset = assetForLookupIdentifier(asset.id) else {
            // DEBUG LOG — we couldn't resolve a PHAsset for this ID.
            // That would silently drop the record from duplicate
            // verification.
            print("[DUP-FP] pixelFingerprint: no PHAsset found for id=\(asset.id)")
            return nil
        }

        // Do the expensive Vision / CoreImage work in a DETACHED task
        // so it runs on a background thread instead of the
        // `@MainActor` queue shared with `AppFlow`. Before this, the
        // thumbnail fetch + fingerprint pass hopped back to main for
        // every asset, which starved UI work like the Compress
        // screen's `jpegData` encode — exactly the "compression
        // stuck during duplicate refinement" bug.
        let assetID = asset.id
        let fingerprint: Data? = await Task.detached(priority: .utility) {
            guard let thumbnail = await Self.requestIndexingThumbnail(for: sourceAsset) else {
                print("[DUP-FP] requestIndexingThumbnail returned nil for id=\(assetID)")
                return nil
            }
            return Self.makePixelFingerprint(from: thumbnail.uiImage)
        }.value

        if let fingerprint {
            // DEBUG LOG — first 8 bytes of the fingerprint so we can
            // eyeball whether two "identical" photos actually produced
            // matching hashes. If the prefixes differ, they won't
            // group; if they match, they will.
            let prefix = fingerprint.prefix(8).map { String(format: "%02x", $0) }.joined()
            print("[DUP-FP] fingerprint id=\(assetID) prefix=\(prefix)")
            // Hop back to main actor only for the cache write — this
            // closure is implicitly on `@MainActor` because AppFlow is.
            pixelFingerprintCache[assetID] = fingerprint
        } else {
            print("[DUP-FP] makePixelFingerprint returned nil for id=\(assetID)")
        }
        return fingerprint
    }

    /// Returns per-face feature prints for the asset, or `[]` when the
    /// asset has no faces. Lazily computed on first call and cached
    /// in-memory for the rest of the session (not persisted yet — face
    /// embeddings are cheap to recompute and not worth NSKeyedArchiver
    /// round-trips for now).
    private func faceEmbeddings(for asset: MediaAssetRecord) async -> [VNFeaturePrintObservation] {
        if let cached = faceEmbeddingsCache[asset.id] {
            return cached
        }
        // Skip work entirely if we already know this asset has no faces.
        if let count = faceCountCache[asset.id], count == 0 {
            faceEmbeddingsCache[asset.id] = []
            return []
        }

        await ensureAnalysisSignals(for: asset, includeFaceCount: true, includeFaceEmbeddings: true)
        return faceEmbeddingsCache[asset.id] ?? []
    }

    private func hydratePersistedAnalysisCaches(for asset: MediaAssetRecord) async {
        guard visualSignatureCache[asset.id] == nil
            || semanticFeaturePrintCache[asset.id] == nil
            || faceCountCache[asset.id] == nil
        else {
            return
        }

        guard let cached = await mediaAnalysisStore.cachedAnalysis(for: asset) else {
            return
        }

        if let visualSignature = cached.visualSignature {
            visualSignatureCache[asset.id] = visualSignature
        }
        if let archived = cached.featurePrintArchive,
           let featurePrint = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: VNFeaturePrintObservation.self,
            from: archived
           )
        {
            semanticFeaturePrintCache[asset.id] = featurePrint
        }
        if let faceCount = cached.faceCount {
            faceCountCache[asset.id] = faceCount
        }
    }

    private func archivedFeaturePrint(for observation: VNFeaturePrintObservation?) -> Data? {
        guard let observation else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    private func requestClusterThumbnail(for identifier: String) async -> UIImage? {
        guard let asset = assetForLookupIdentifier(identifier) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.version = .current

        return await withCheckedContinuation { continuation in
            _ = clusterThumbnailManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 52, height: 52),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func ensureAnalysisSignals(
        for asset: MediaAssetRecord,
        includeFaceCount: Bool,
        includeFaceEmbeddings: Bool = false
    ) async {
        await hydratePersistedAnalysisCaches(for: asset)

        let needsVisualSignature = visualSignatureCache[asset.id] == nil
        let needsFeaturePrint = semanticFeaturePrintCache[asset.id] == nil
        let needsFaceCount = includeFaceCount && faceCountCache[asset.id] == nil
        let needsFaceEmbeddings = includeFaceEmbeddings && faceEmbeddingsCache[asset.id] == nil

        guard needsVisualSignature || needsFeaturePrint || needsFaceCount || needsFaceEmbeddings else {
            return
        }

        guard let sourceAsset = assetForLookupIdentifier(asset.id),
              let thumbnail = await Self.requestIndexingThumbnail(for: sourceAsset)
        else {
            if needsFaceCount {
                faceCountCache[asset.id] = 0
            }
            if needsFaceEmbeddings {
                faceEmbeddingsCache[asset.id] = []
            }
            return
        }

        if needsVisualSignature, let signature = Self.makeVisualSignature(from: thumbnail.uiImage) {
            visualSignatureCache[asset.id] = signature
        }

        // Scene feature print + face COUNT always run on the 256px
        // thumbnail — both are cheap and robust at that scale.
        if needsFeaturePrint || needsFaceCount {
            let result = await Self.analyzeVisionSignals(
                from: thumbnail.ciImage,
                includeFeaturePrint: needsFeaturePrint,
                includeFaceCount: needsFaceCount,
                includeFaceEmbeddings: false,
                maxFaces: 0
            )
            if needsFeaturePrint, let featurePrint = result.featurePrint {
                semanticFeaturePrintCache[asset.id] = featurePrint
            }
            if needsFaceCount {
                faceCountCache[asset.id] = result.faceCount ?? 0
            }
        }

        // Face embeddings need a much larger thumbnail — feature
        // prints on a 40px face crop are noisy garbage. We fetch the
        // 1024px thumbnail only when we actually need embeddings and
        // the asset has faces (skip otherwise; saves a Photos I/O).
        if needsFaceEmbeddings {
            let currentFaceCount = faceCountCache[asset.id] ?? 0
            if currentFaceCount == 0 {
                faceEmbeddingsCache[asset.id] = []
            } else if let hiRes = await Self.requestHighResFaceThumbnail(for: sourceAsset) {
                let result = await Self.analyzeVisionSignals(
                    from: hiRes.ciImage,
                    includeFeaturePrint: false,
                    includeFaceCount: false,
                    includeFaceEmbeddings: true,
                    maxFaces: maxFacesPerAsset
                )
                faceEmbeddingsCache[asset.id] = result.faceEmbeddings ?? []
            } else {
                // Couldn't fetch high-res thumbnail. Leave empty — the
                // strict `faceIdentitiesMatch` will then reject any
                // merge rather than risk a false positive.
                faceEmbeddingsCache[asset.id] = []
            }
        }

        await mediaAnalysisStore.saveDerivedSignals(
            for: asset,
            faceCount: faceCountCache[asset.id],
            featurePrintArchive: archivedFeaturePrint(for: semanticFeaturePrintCache[asset.id]),
            visualSignature: visualSignatureCache[asset.id]
        )
    }

    nonisolated private static func makeVisualSignature(from image: UIImage) -> MediaVisualSignature? {
        guard let cgImage = image.cgImage else { return nil }

        let width = 9
        let height = 8
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0
        var lumaTotal = 0
        var minLuma = 255
        var maxLuma = 0

        for row in 0..<height {
            for column in 0..<width {
                let value = Int(pixels[(row * width) + column])
                lumaTotal += value
                minLuma = min(minLuma, value)
                maxLuma = max(maxLuma, value)
            }
        }

        for row in 0..<height {
            for column in 0..<(width - 1) {
                let left = pixels[(row * width) + column]
                let right = pixels[(row * width) + column + 1]
                if left > right {
                    hash |= (1 << bitIndex)
                }
                bitIndex += 1
            }
        }

        return MediaVisualSignature(
            dHash: hash,
            meanLuma: lumaTotal / (width * height),
            spread: maxLuma - minLuma
        )
    }

    /// Pixel-level fingerprint for duplicate detection.
    ///
    /// Renders the image into a normalized 64×64 grayscale buffer,
    /// quantizes each pixel to 4 bits (16 levels) so JPEG jitter /
    /// compression re-encode can't spoil the fingerprint, and takes
    /// SHA256. Two images with the same fingerprint are the same
    /// pixel content — that's what "duplicate" actually means.
    ///
    /// 4-bit quantization is the sweet spot: lossless bit-for-bit
    /// compare would over-split (iCloud re-encodes slightly), full
    /// 8-bit would still split. 16 luma levels survive JPEG jitter
    /// while still failing on crops, filters, edits.
    nonisolated private static func makePixelFingerprint(from image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 64
        let bytesPerRow = side
        var pixels = [UInt8](repeating: 0, count: side * side)

        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Quantize to 4 bits per pixel. 256 levels → 16 levels.
        var quantized = [UInt8](repeating: 0, count: (side * side) / 2)
        for i in 0..<(side * side / 2) {
            let hi = pixels[2 * i] >> 4
            let lo = pixels[2 * i + 1] >> 4
            quantized[i] = (hi << 4) | lo
        }

        let digest = SHA256.hash(data: Data(quantized))
        return Data(digest)
    }

    nonisolated private static func analyzeVisionSignals(
        from image: CIImage,
        includeFeaturePrint: Bool,
        includeFaceCount: Bool,
        includeFaceEmbeddings: Bool,
        maxFaces: Int
    ) async -> VisionAnalysisResult {
        await performIndexingWork {
            var requests: [VNRequest] = []
            var featurePrintRequest: VNGenerateImageFeaturePrintRequest?
            if includeFeaturePrint {
                let request = VNGenerateImageFeaturePrintRequest()
                request.imageCropAndScaleOption = .scaleFit
                request.preferBackgroundProcessing = true
                configurePreferredComputeDevices(for: request)
                requests.append(request)
                featurePrintRequest = request
            }

            // Need face rectangles whenever we want count OR embeddings.
            let needFaceRects = includeFaceCount || includeFaceEmbeddings
            var faceRequest: VNDetectFaceRectanglesRequest?
            if needFaceRects {
                let request = VNDetectFaceRectanglesRequest()
                request.preferBackgroundProcessing = true
                configurePreferredComputeDevices(for: request)
                requests.append(request)
                faceRequest = request
            }

            guard !requests.isEmpty else {
                return VisionAnalysisResult(featurePrint: nil, faceCount: nil, faceEmbeddings: nil)
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform(requests)

                let faceObservations = faceRequest?.results ?? []
                let embeddings: [VNFeaturePrintObservation]?
                if includeFaceEmbeddings {
                    embeddings = computeFaceEmbeddings(
                        from: image,
                        faceObservations: faceObservations,
                        maxFaces: maxFaces
                    )
                } else {
                    embeddings = nil
                }

                return VisionAnalysisResult(
                    featurePrint: featurePrintRequest?.results?.first,
                    faceCount: includeFaceCount ? faceObservations.count : nil,
                    faceEmbeddings: embeddings
                )
            } catch {
                return VisionAnalysisResult(
                    featurePrint: nil,
                    faceCount: includeFaceCount ? 0 : nil,
                    faceEmbeddings: includeFaceEmbeddings ? [] : nil
                )
            }
        }
    }

    /// Computes a feature print per face crop as a lightweight identity
    /// proxy. We don't have a public face-recognition model on iOS, but
    /// running `VNGenerateImageFeaturePrintRequest` on a tight face crop
    /// yields embeddings that are markedly closer for the same person
    /// than for different people — enough to prevent the "everyone at
    /// the Louvre is one cluster" bug.
    ///
    /// Crops the top-`maxFaces` largest face rectangles (with ~25%
    /// padding so hair/chin aren't clipped), runs the feature-print
    /// request over each, and returns the successful observations.
    nonisolated private static func computeFaceEmbeddings(
        from image: CIImage,
        faceObservations: [VNFaceObservation],
        maxFaces: Int
    ) -> [VNFeaturePrintObservation] {
        guard !faceObservations.isEmpty, maxFaces > 0 else { return [] }

        // Largest face first — they're the most stable for identity.
        let sorted = faceObservations.sorted { lhs, rhs in
            (lhs.boundingBox.width * lhs.boundingBox.height)
                > (rhs.boundingBox.width * rhs.boundingBox.height)
        }
        let top = Array(sorted.prefix(maxFaces))

        let imageExtent = image.extent
        guard imageExtent.width > 0, imageExtent.height > 0 else { return [] }

        var results: [VNFeaturePrintObservation] = []
        for face in top {
            // Vision bounding boxes are normalized (0..1) with origin at
            // bottom-left. Convert to image pixels and expand slightly.
            let pad: CGFloat = 0.25
            let nx = max(0, face.boundingBox.origin.x - face.boundingBox.width * pad * 0.5)
            let ny = max(0, face.boundingBox.origin.y - face.boundingBox.height * pad * 0.5)
            let nw = min(1 - nx, face.boundingBox.width * (1 + pad))
            let nh = min(1 - ny, face.boundingBox.height * (1 + pad))

            let pixelRect = CGRect(
                x: imageExtent.origin.x + nx * imageExtent.width,
                y: imageExtent.origin.y + ny * imageExtent.height,
                width: nw * imageExtent.width,
                height: nh * imageExtent.height
            )

            // Reject degenerate / tiny crops that'd make a noisy print.
            // At 1024×1024 thumbnail scale a face smaller than 64px
            // is too far / too occluded to produce a stable identity
            // embedding — we'd rather return empty (and let the
            // strict matcher reject the merge) than include noise.
            guard pixelRect.width >= 64, pixelRect.height >= 64 else { continue }

            let cropped = image.cropped(to: pixelRect)

            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFit
            request.preferBackgroundProcessing = true
            configurePreferredComputeDevices(for: request)

            let handler = VNImageRequestHandler(ciImage: cropped, options: [:])
            do {
                try handler.perform([request])
                if let print = request.results?.first {
                    results.append(print)
                }
            } catch {
                continue
            }
        }
        return results
    }

    /// Fetch a small 256×256 thumbnail for indexing. This is I/O-bound work
    /// so it does NOT hold the indexing semaphore — only Vision compute should.
    nonisolated private static func requestIndexingThumbnail(for asset: PHAsset) async -> IndexingThumbnail? {
        await requestThumbnail(for: asset, targetSize: indexingTargetSize)
    }

    /// Larger thumbnail for face embedding. On a 256×256 indexing
    /// thumbnail a detected face is often only 40–80px wide — too
    /// small for Vision's image-feature-print to produce a stable
    /// identity signal. At 1024×1024 the same face is 150–300px,
    /// which gives feature prints that actually separate different
    /// people. This is only fetched when we know the asset has faces.
    nonisolated private static func requestHighResFaceThumbnail(for asset: PHAsset) async -> IndexingThumbnail? {
        await requestThumbnail(for: asset, targetSize: CGSize(width: 1024, height: 1024))
    }

    nonisolated private static func requestThumbnail(for asset: PHAsset, targetSize: CGSize) async -> IndexingThumbnail? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.version = .current

        return await withCheckedContinuation { continuation in
            var didResume = false

            indexingImageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

                guard !didResume, isCancelled || !isDegraded else { return }
                didResume = true

                guard let image, let ciImage = ciImage(from: image) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: IndexingThumbnail(uiImage: image, ciImage: ciImage))
            }
        }
    }

    nonisolated private static func ciImage(from image: UIImage) -> CIImage? {
        if let ciImage = image.ciImage {
            return ciImage
        }
        if let cgImage = image.cgImage {
            return CIImage(cgImage: cgImage)
        }
        return nil
    }

    nonisolated private static func configurePreferredComputeDevices(for request: VNRequest) {
        if #available(iOS 17.0, *) {
            guard let supportedDevices = try? request.supportedComputeStageDevices else {
                return
            }

            for (stage, devices) in supportedDevices {
                if let preferredDevice = devices.first(where: isNeuralEngineDevice)
                    ?? devices.first(where: isGPUDevice)
                {
                    request.setComputeDevice(preferredDevice, for: stage)
                }
            }
        } else {
            request.usesCPUOnly = false
        }
    }

    nonisolated private static func isNeuralEngineDevice(_ device: MLComputeDevice) -> Bool {
        if case .neuralEngine = device {
            return true
        }
        return false
    }

    nonisolated private static func isGPUDevice(_ device: MLComputeDevice) -> Bool {
        if case .gpu = device {
            return true
        }
        return false
    }

    nonisolated private static func performIndexingWork<T>(_ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            MediaWorkQueues.indexingQueue.async {
                MediaWorkQueues.indexingSemaphore.wait()
                defer { MediaWorkQueues.indexingSemaphore.signal() }
                continuation.resume(returning: operation())
            }
        }
    }

    nonisolated private static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    nonisolated private static func featurePrintDistance(from lhs: VNFeaturePrintObservation, to rhs: VNFeaturePrintObservation) -> Float {
        var distance = Float.greatestFiniteMagnitude
        do {
            try lhs.computeDistance(&distance, to: rhs)
            return distance
        } catch {
            return Float.greatestFiniteMagnitude
        }
    }

    /// Decides whether two photos show the same person / group of
    /// people. We already rejected earlier when face COUNTS differ;
    /// this enforces face IDENTITY.
    ///
    /// Strategy: greedy bipartite match. For each anchor face, find
    /// the nearest unused candidate face; if its distance is under
    /// `faceIdentityDistanceThreshold`, consume it. If any anchor
    /// face fails to match, the photos are not "similar" — they're
    /// two different people at the same place.
    ///
    /// Strict mode: when one side has embeddings and the other does
    /// NOT (face detected but we couldn't crop — tiny profile face,
    /// heavy occlusion), we **reject** rather than merge. Being
    /// over-aggressive about splitting is the right failure mode
    /// here: "me + my partner at the Louvre" being in the same
    /// cluster is a much worse bug than the same person's burst
    /// getting split into two clusters.
    private func faceIdentitiesMatch(
        candidate: [VNFeaturePrintObservation],
        anchor: [VNFeaturePrintObservation]
    ) -> Bool {
        // If either side failed to produce embeddings despite having
        // faces, bail out — we'd rather over-split than risk a false
        // merge of two different people.
        if anchor.isEmpty || candidate.isEmpty {
            return false
        }

        // Each side must be able to account for every face on the
        // other side. We run the bipartite match from the larger
        // side so the smaller doesn't trivially match.
        let (left, right) = anchor.count >= candidate.count
            ? (anchor, candidate)
            : (candidate, anchor)

        var available = Array(right.indices)
        for face in left {
            var bestIndex: Int?
            var bestDistance: Float = .greatestFiniteMagnitude
            for (arrayIdx, rightIdx) in available.enumerated() {
                let d = Self.featurePrintDistance(
                    from: face,
                    to: right[rightIdx]
                )
                if d < bestDistance {
                    bestDistance = d
                    bestIndex = arrayIdx
                }
            }
            guard let matchIndex = bestIndex,
                  bestDistance <= faceIdentityDistanceThreshold
            else {
                return false
            }
            available.remove(at: matchIndex)
        }
        return true
    }

    private func libraryScanStatusText(processedCount: Int, totalCount: Int) -> String {
        if totalCount > quickScanReadyCount, processedCount >= quickScanReadyCount, processedCount < totalCount {
            return "Quick results are ready. Scanning older media in the background..."
        }

        return "Scanning \(processedCount.formatted()) of \(totalCount.formatted())"
    }

    private func makeMediaRecord(from asset: PHAsset) -> MediaAssetRecord {
        let size = estimatedFileSize(for: asset)
        let filename = mediaDisplayTitle(for: asset)
        let subtitle = DateFormatter.cleanupShort.string(from: asset.creationDate ?? .now)

        return MediaAssetRecord(
            id: asset.localIdentifier,
            title: filename,
            subtitle: subtitle,
            sizeInBytes: size,
            duration: asset.duration,
            createdAt: asset.creationDate,
            modificationAt: asset.modificationDate,
            mediaType: asset.mediaType,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    /// Result of the scan-time preflight. Everything in here is keyed
    /// so the MainActor merge can drop entries straight into
    /// `fileSizeCache` (keyed by `fileSizeCacheKey`) and
    /// `originalFilenameCache` (keyed by `localIdentifier`).
    private struct ResourcePreflightResult: Sendable {
        var sizes: [String: Int64]
        var filenames: [String: String?]
    }

    /// Fans `PHAssetResource.assetResources(for:)` across a bounded
    /// number of background workers and returns a map of file sizes
    /// plus, for videos that could be screen recordings, their
    /// lowercased original filename. Runs off MainActor — the Photos
    /// framework itself is thread-safe for these lookups; the "Fetching
    /// on demand on the main queue" warning fires only when the main
    /// thread is the one waiting. Moving the wait to background workers
    /// and fanning out is the key speedup.
    ///
    /// Concurrency is capped at 8 so we don't drown Photos' internal
    /// serial queue. Empirically anything over ~8 workers on an iPhone
    /// stops scaling and starts adding contention.
    /// Merges a preflight chunk into the MainActor caches, but only
    /// if the scan generation that owns it is still current. If the
    /// user restarted the scan (tapped refresh, changed permissions,
    /// etc.) a stale preflight worker finishing in the background
    /// must not poison the new scan's state.
    @MainActor
    private func mergePreflightResultsIfCurrent(
        _ result: ResourcePreflightResult,
        generation: Int
    ) {
        guard generation == libraryScanGeneration else { return }
        for (cacheKey, size) in result.sizes {
            fileSizeCache[cacheKey] = size
        }
        for (localID, filename) in result.filenames {
            originalFilenameCache[localID] = .some(filename)
        }
    }

    /// Batched, parallel screen-recording filename classifier. Given
    /// the set of portrait videos the scan routed tentatively as
    /// `.videos` or `.shortRecordings`, streams back the subset whose
    /// `PHAssetResource.originalFilename` matches an iOS screen-
    /// recording pattern (`rpreplay*`, `screen recording*`).
    ///
    /// Runs off MainActor with 8 concurrent workers and streams
    /// results via `chunkCallback` as each worker chunk finishes —
    /// so the Screen Recordings card fills in progressively during
    /// the scan instead of appearing all at once at the end.
    nonisolated private static func classifyScreenRecordings(
        candidates: [PHAsset],
        chunkCallback: (@Sendable (Set<String>) async -> Void)? = nil
    ) async -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let workerCount = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount))

        // Chunk size controls the streaming cadence. Smaller chunks =
        // more frequent UI updates during the scan. Measured on a 5K-
        // candidate library: 50 items per chunk gives ~14 visible
        // waves of Screen Recordings updates over the classifier's
        // ~13-second lifetime, with only ~3% MainActor overhead from
        // the callback dispatch. Larger (200+) means the card feels
        // like it appears at the end; smaller (<25) starts eating
        // measurable MainActor time and fighting the routing loop.
        let chunkSize = 50
        var chunks: [[PHAsset]] = []
        var cursor = 0
        while cursor < candidates.count {
            let end = min(cursor + chunkSize, candidates.count)
            chunks.append(Array(candidates[cursor..<end]))
            cursor = end
        }

        return await withTaskGroup(of: Set<String>.self) { group in
            var chunkIterator = chunks.makeIterator()
            var active = 0

            func addNextChunk() {
                guard let chunk = chunkIterator.next() else { return }
                active += 1
                group.addTask {
                    var local = Set<String>()
                    for asset in chunk {
                        let resources = PHAssetResource.assetResources(for: asset)
                        guard let filename = resources.first?.originalFilename else { continue }
                        let lower = filename.lowercased()
                        if lower.hasPrefix("rpreplay")
                            || lower.hasPrefix("screen recording")
                            || lower.hasPrefix("screenrecording") {
                            local.insert(asset.localIdentifier)
                        }
                    }
                    return local
                }
            }

            for _ in 0..<workerCount { addNextChunk() }

            var merged = Set<String>()
            while active > 0 {
                guard let partial = await group.next() else { break }
                active -= 1
                if !partial.isEmpty, let chunkCallback {
                    await chunkCallback(partial)
                }
                merged.formUnion(partial)
                addNextChunk()
            }
            return merged
        }
    }

    /// Streams screen-recording classifier results into the live
    /// `mediaAssetsByCategory[.screenRecordings]` bucket on MainActor.
    /// Moves matching records out of `.videos` / `.shortRecordings`
    /// and into `.screenRecordings` without waiting for the whole
    /// classifier to finish. The Screen Recordings card's count and
    /// byte total grow progressively during the scan.
    ///
    /// Also accumulates IDs into `confirmedScreenRecordingIDs` so
    /// that subsequent `applyLibrarySnapshot` calls during the same
    /// scan carry the promotion forward — snapshots wholesale replace
    /// `mediaAssetsByCategory`, so without this persistent set the
    /// promotion would vanish on the next snapshot.
    @MainActor
    private func promoteScreenRecordings(
        ids: Set<String>,
        generation: Int
    ) {
        guard generation == libraryScanGeneration else { return }
        guard !ids.isEmpty else { return }

        // Persistent record for future snapshots.
        confirmedScreenRecordingIDs.formUnion(ids)

        // Move from `.videos` / `.shortRecordings` into `.screenRecordings`
        // in the CURRENT `mediaAssetsByCategory` so the UI updates now.
        var videos = mediaAssetsByCategory[.videos] ?? []
        var shorts = mediaAssetsByCategory[.shortRecordings] ?? []
        var screens = mediaAssetsByCategory[.screenRecordings] ?? []
        let existingScreenIDs = Set(screens.map(\.id))

        var promoted: [MediaAssetRecord] = []
        videos.removeAll { rec in
            if ids.contains(rec.id), !existingScreenIDs.contains(rec.id) {
                promoted.append(rec)
                return true
            }
            return false
        }
        shorts.removeAll { rec in
            if ids.contains(rec.id), !existingScreenIDs.contains(rec.id) {
                promoted.append(rec)
                return true
            }
            return false
        }
        if promoted.isEmpty { return }
        screens.append(contentsOf: promoted)

        mediaAssetsByCategory[.videos] = videos
        mediaAssetsByCategory[.shortRecordings] = shorts
        mediaAssetsByCategory[.screenRecordings] = screens
        refreshDashboardCategories()
    }

    nonisolated private static func preflightAssetResources(
        for assets: [PHAsset],
        maxConcurrency: Int = 8,
        chunkCallback: (@Sendable (ResourcePreflightResult) async -> Void)? = nil
    ) async -> ResourcePreflightResult {
        guard !assets.isEmpty else {
            return ResourcePreflightResult(sizes: [:], filenames: [:])
        }

        let workerCount = min(maxConcurrency, max(1, ProcessInfo.processInfo.activeProcessorCount))

        // Chunk size of ~200 (instead of "total / workers") means each
        // worker finishes a chunk every second or two and the caller's
        // chunkCallback fires repeatedly — the routing loop sees cache
        // entries appear continuously rather than all at the end. 200
        // also matches the routing loop's snapshot-publish cadence, so
        // progress roughly tracks.
        let chunkSize = 200

        var chunks: [[PHAsset]] = []
        var cursor = 0
        while cursor < assets.count {
            let end = min(cursor + chunkSize, assets.count)
            chunks.append(Array(assets[cursor..<end]))
            cursor = end
        }

        return await withTaskGroup(of: ResourcePreflightResult.self) { group in
            // Bound the group to `workerCount` concurrent chunks.
            var chunkIterator = chunks.makeIterator()
            var active = 0

            func addNextChunk() {
                guard let chunk = chunkIterator.next() else { return }
                active += 1
                group.addTask {
                    var localSizes: [String: Int64] = [:]
                    var localFilenames: [String: String?] = [:]
                    localSizes.reserveCapacity(chunk.count)

                    for asset in chunk {
                        let resources = PHAssetResource.assetResources(for: asset)

                        var sized: Int64 = 0
                        for resource in resources {
                            if let bytes = resource.value(forKey: "fileSize") as? Int64, bytes > 0 {
                                sized = bytes
                                break
                            }
                            if let bytes = resource.value(forKey: "fileSize") as? NSNumber {
                                let intBytes = bytes.int64Value
                                if intBytes > 0 {
                                    sized = intBytes
                                    break
                                }
                            }
                        }
                        if sized > 0 {
                            let modificationStamp = asset.modificationDate?.timeIntervalSince1970 ?? 0
                            let key = "\(asset.localIdentifier)|\(modificationStamp)"
                            localSizes[key] = sized
                        }

                        if asset.mediaType == .video,
                           asset.pixelHeight >= asset.pixelWidth {
                            if let filename = resources.first?.originalFilename {
                                localFilenames[asset.localIdentifier] = filename.lowercased()
                            } else {
                                localFilenames[asset.localIdentifier] = Optional<String>.none
                            }
                        }
                    }

                    return ResourcePreflightResult(sizes: localSizes, filenames: localFilenames)
                }
            }

            // Prime the group with up to `workerCount` concurrent chunks.
            for _ in 0..<workerCount { addNextChunk() }

            var merged = ResourcePreflightResult(sizes: [:], filenames: [:])
            merged.sizes.reserveCapacity(assets.count)

            while active > 0 {
                guard let partial = await group.next() else { break }
                active -= 1
                // Stream this chunk to the caller as soon as it finishes
                // — don't wait until the whole preflight is done.
                if let chunkCallback {
                    await chunkCallback(partial)
                }
                for (key, value) in partial.sizes {
                    merged.sizes[key] = value
                }
                for (key, value) in partial.filenames {
                    merged.filenames[key] = value
                }
                // Start the next chunk to keep the pipeline full.
                addNextChunk()
            }
            return merged
        }
    }

    private func estimatedFileSize(for asset: PHAsset) -> Int64 {
        // HOT-PATH FAST RETURN. The scan loop calls this 37K+ times on
        // MainActor. Going through `PHAssetResource.assetResources(for:)`
        // here is the reason first-scan used to take 2+ minutes — every
        // call is a synchronous Photos-DB XPC round-trip and iOS even
        // logs "Fetching on demand on the main queue" for each one.
        //
        // New order of operations:
        //   1. In-memory cache hit → return immediately (µs).
        //   2. No cache → return a pixel-count estimate immediately
        //      (arithmetic only, no I/O). Scan keeps flying.
        //   3. The parallel preflight (fired from `performLibraryScan`)
        //      backfills the real `PHAssetResource` size into the cache
        //      moments later. The dashboard's total-bytes counter
        //      corrects itself as soon as the preflight lands (see
        //      `mergePreflightResultsIfCurrent`).
        //
        // Duplicate detection is unaffected: the coarse estimate means
        // multiple unrelated photos at the same resolution land in the
        // same candidate bucket, but `verifyDuplicatesByPixel` is the
        // actual duplicate judge — it compares pixel fingerprints and
        // rejects any non-matches. So we trade a slightly larger
        // candidate set for a ~100× faster scan, and the verifier's
        // per-bucket-member cost is what stays bounded.
        let cacheKey = fileSizeCacheKey(for: asset)
        if let cached = fileSizeCache[cacheKey] {
            return cached
        }

        let pixelCount = max(asset.pixelWidth * asset.pixelHeight, 1)
        let estimate: Int64
        if asset.mediaType == .video {
            // Video: roughly 0.08 bytes per pixel per second (H.264 iPhone
            // average at ~30 fps, standard bitrate). Duration × pixel
            // area × 0.08 gives us order-of-magnitude right.
            estimate = Int64(Double(pixelCount) * max(asset.duration, 1) * 0.08)
        } else {
            // JPEG / HEIC iPhone photos: ~0.45 bytes per pixel with
            // iPhone camera settings. Good enough for bucket totals
            // until the preflight lands the real number.
            estimate = Int64(Double(pixelCount) * 0.45)
        }
        // Cache the estimate too so the scan's repeat visits are O(1).
        // The preflight will overwrite with the real size when it lands.
        fileSizeCache[cacheKey] = estimate
        return estimate
    }

    /// Byte-exact size via `PHAssetResource`. Called on demand from the
    /// preflight workers (off MainActor) and any code path that needs
    /// real numbers (e.g. deciding compression target size). The scan
    /// hot path deliberately does NOT use this — see `estimatedFileSize`.
    private func preciseFileSize(for asset: PHAsset) -> Int64 {
        let cacheKey = fileSizeCacheKey(for: asset)
        if let cached = fileSizeCache[cacheKey] {
            return cached
        }
        let resources = PHAssetResource.assetResources(for: asset)
        for resource in resources {
            if let bytes = resource.value(forKey: "fileSize") as? Int64, bytes > 0 {
                fileSizeCache[cacheKey] = bytes
                return bytes
            }
            if let bytes = resource.value(forKey: "fileSize") as? NSNumber {
                let intBytes = bytes.int64Value
                if intBytes > 0 {
                    fileSizeCache[cacheKey] = intBytes
                    return intBytes
                }
            }
        }

        // Fallback only if the resource lookup fails (shouldn't happen
        // for local assets). The formula is a wild guess but matches
        // the pre-fix behaviour so we at least don't crash or show 0.
        // Cache the fallback too — otherwise assets whose resource
        // lookup returns zero bytes (iCloud originals not yet
        // downloaded, etc.) would re-hit PHAssetResource every scan.
        let pixelCount = max(asset.pixelWidth * asset.pixelHeight, 1)
        let fallback: Int64
        if asset.mediaType == .video {
            fallback = Int64(Double(pixelCount) * max(asset.duration, 1) * 0.08)
        } else {
            fallback = Int64(Double(pixelCount) * 0.45)
        }
        fileSizeCache[cacheKey] = fallback
        return fallback
    }

    private func fileSizeCacheKey(for asset: PHAsset) -> String {
        // Invalidate the cached size if the asset was edited (Photos
        // updates modificationDate on every crop / filter / adjustment).
        let modificationStamp = asset.modificationDate?.timeIntervalSince1970 ?? 0
        return "\(asset.localIdentifier)|\(modificationStamp)"
    }

    private func isScreenRecordingAsset(_ asset: PHAsset) -> Bool {
        guard asset.mediaType == .video else { return false }
        // Portrait-orientation pre-filter: every screen recording iOS
        // produces is captured in portrait (height >= width). This
        // filter is CORRECT — landscape videos are camera captures.
        // We keep this because it's essentially free (two Int reads).
        guard asset.pixelHeight >= asset.pixelWidth else { return false }

        // Filename check. Previously we gated this behind a hardcoded
        // iPhone-screen-resolution whitelist, but that list is:
        //   - incomplete (missing iPhone 13 PM, XS Max, 11 PM, etc.)
        //   - wrong for scaled recordings and AirPlay captures
        //   - wrong for recordings transferred from other devices
        // Result: users with ~1000 screen recordings saw only 3
        // detected. The filename pattern (`rpreplay*`, `screen
        // recording*`) is the ground truth that iOS uses.
        //
        // Fetching `PHAssetResource.assetResources(for:)` for every
        // video during scan WAS the main-thread bottleneck, but
        // `originalFilename` alone doesn't trigger the slow
        // `PHAssetOriginalMetadataProperties` fetch — only `fileSize`
        // does. So reading the filename here is cheap enough for the
        // subset of videos that pass the portrait gate.
        //
        // The background preflight still populates
        // `originalFilenameCache` for all videos in parallel, so
        // repeated scans hit the cache and skip PHAssetResource
        // entirely after the first pass.
        if let cachedFilename = originalFilenameCache[asset.localIdentifier] {
            guard let lower = cachedFilename else { return false }
            return lower.hasPrefix("rpreplay")
                || lower.hasPrefix("screen recording")
                || lower.hasPrefix("screenrecording")
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let filename = resources.first?.originalFilename else {
            originalFilenameCache[asset.localIdentifier] = .some(nil)
            return false
        }
        let lower = filename.lowercased()
        originalFilenameCache[asset.localIdentifier] = .some(lower)
        return lower.hasPrefix("rpreplay")
            || lower.hasPrefix("screen recording")
            || lower.hasPrefix("screenrecording")
    }

    private func isLikelyScreenResolution(width: Int, height: Int) -> Bool {
        // Known iPhone/iPad screen-recording output resolutions (portrait).
        // Screen recordings use device-native pixels; camera clips do not.
        let known: Set<Int> = [
            // iPhone SE / 8 / 7 / 6s
            568, 667, 736, 812,
            // iPhone X / XS / 11 Pro / 12 mini / 13 mini
            844, 852, 896,
            // iPhone 11 / XR
            1624,
            // iPhone 12 / 13 / 14 / 15
            1170, 2532,
            // iPhone 14 Pro / 15 Pro / 16
            1179, 2556,
            // iPhone 14 Pro Max / 15 Pro Max / 16 Pro Max
            1290, 2796,
            // iPhone 16 Pro
            1206, 2622,
            // iPad common
            1620, 2160, 1668, 2224, 2388, 2732
        ]
        return known.contains(width) || known.contains(height)
    }

    private func mediaDisplayTitle(for asset: PHAsset) -> String {
        let base: String
        if asset.mediaType == .video {
            base = "Video"
        } else if asset.mediaSubtypes.contains(.photoScreenshot) {
            base = "Screenshot"
        } else {
            base = "Photo"
        }

        guard let date = asset.creationDate else {
            return base
        }

        return "\(base) \(DateFormatter.cleanupLabel.string(from: date))"
    }

    private func assetForLookupIdentifier(_ identifier: String) -> PHAsset? {
        if let cached = PhotoAssetLookup.shared.asset(for: identifier) {
            return cached
        }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        PhotoAssetLookup.shared.upsert(asset)
        return asset
    }

    private func compressibleAssets(of mediaType: PHAssetMediaType) -> [MediaAssetRecord] {
        let assets = mediaAssetsByCategory
            .values
            .flatMap { $0 }
            .filter { $0.mediaType == mediaType && !retiredCompressionAssetIDs.contains($0.id) }

        var seen = Set<String>()
        return assets
            .filter { seen.insert($0.id).inserted }
            .sorted {
                let lhsDate = $0.createdAt ?? .distantPast
                let rhsDate = $1.createdAt ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.sizeInBytes > $1.sizeInBytes
                }
                return lhsDate > rhsDate
            }
    }

    private func displayName(for contact: CNContact) -> String {
        let components = [contact.givenName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !components.isEmpty {
            return components.joined(separator: " ")
        }

        if let email = contact.emailAddresses.first?.value as String?, !email.isEmpty {
            return email
        }

        if let phone = contact.phoneNumbers.first?.value.stringValue, !phone.isEmpty {
            return phone
        }

        return "Unnamed Contact"
    }

    private func retireCompressionCandidates(_ identifiers: [String]) {
        let newIDs = identifiers.filter { !$0.isEmpty }
        guard !newIDs.isEmpty else { return }
        retiredCompressionAssetIDs.formUnion(newIDs)
        persist(retiredCompressionAssetIDs, key: retiredCompressionAssetIDsKey)
        rebuildCompressibleAssetCaches()
    }

    private func updateSecretVaultImportStatus(
        totalCount: Int,
        importedCount: Int,
        failedCount: Int,
        processedBytes: Int64,
        currentFilename: String?
    ) {
        secretVaultImportStatus = SecretVaultImportStatus(
            totalCount: totalCount,
            importedCount: importedCount,
            failedCount: failedCount,
            processedBytes: processedBytes,
            currentFilename: currentFilename
        )
    }

    private func flattenClusters(_ clusters: [MediaCluster]) -> [MediaAssetRecord] {
        uniqueMediaRecordList(from: clusters.flatMap(\.assets))
    }

    private func makeClusters(from buckets: [String: [MediaAssetRecord]], category: DashboardCategoryKind) -> [MediaCluster] {
        buckets
            .compactMap { key, value in
                let deduplicated = uniqueMediaRecordList(from: value)
                let sorted = deduplicated.sorted {
                    if $0.sizeInBytes == $1.sizeInBytes {
                        return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                    return $0.sizeInBytes > $1.sizeInBytes
                }
                guard sorted.count > 1 else { return nil }
                return MediaCluster(
                    id: key,
                    category: category,
                    assets: sorted,
                    totalBytes: sorted.reduce(0) { $0 + $1.sizeInBytes },
                    subtitle: nil
                )
            }
            .sorted {
                if $0.totalBytes == $1.totalBytes {
                    return $0.count > $1.count
                }
                return $0.totalBytes > $1.totalBytes
            }
    }

    private func uniqueMediaRecords(
        from records: [MediaAssetRecord],
        filteringTo allowedIDs: Set<String>? = nil
    ) -> [String: MediaAssetRecord] {
        Dictionary(
            records.lazy
                .filter { allowedIDs?.contains($0.id) ?? true }
                .map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
    }

    private func uniqueMediaRecordList(from records: [MediaAssetRecord]) -> [MediaAssetRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.id).inserted }
    }

    private func assertUniqueClusterMembership(in clusters: [MediaCluster], category: DashboardCategoryKind) {
        #if DEBUG
        var seen = Set<String>()
        var duplicates = Set<String>()

        for assetID in clusters.flatMap({ $0.assets.map(\.id) }) {
            if !seen.insert(assetID).inserted {
                duplicates.insert(assetID)
            }
        }

        assert(
            duplicates.isEmpty,
            "Duplicate asset ids found across \(category.rawValue) clusters: \(duplicates.sorted())"
        )
        #endif
    }

    private func makeClustersFromSortedAssets(_ assets: [MediaAssetRecord], category: DashboardCategoryKind, chunkSize: Int) -> [MediaCluster] {
        let sorted = assets.sorted {
            if $0.sizeInBytes == $1.sizeInBytes {
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            return $0.sizeInBytes > $1.sizeInBytes
        }

        guard !sorted.isEmpty else { return [] }

        return stride(from: 0, to: sorted.count, by: chunkSize).map { startIndex in
            let endIndex = min(startIndex + chunkSize, sorted.count)
            let chunk = Array(sorted[startIndex..<endIndex])
            return MediaCluster(
                id: "\(category.rawValue)-\(startIndex)",
                category: category,
                assets: chunk,
                totalBytes: chunk.reduce(0) { $0 + $1.sizeInBytes },
                subtitle: nil
            )
        }
    }

    /// Coarse candidate-bucket key for duplicates — used ONLY to
    /// pair up photos that *might* be duplicates before the pixel
    /// pass verifies them. iPhones produce billions of photos at the
    /// same pixel dimensions, so this key is deliberately loose; the
    /// real duplicate decision lives in `verifyDuplicatesByPixel`
    /// which compares actual pixel content. Keying by resolution +
    /// media type alone keeps this O(1) and moves the expensive
    /// fingerprint work to a bounded post-scan pass.
    /// Coarse candidate key for the pixel-fingerprint verifier.
    /// Must identify photos that COULD be bit-exact duplicates —
    /// i.e. same media type, same dimensions, same exact byte size.
    /// Anything that differs on ANY of those three can't be a pixel
    /// duplicate, so we don't waste a Vision pass on it.
    ///
    /// Note: file size alone is not sufficient (two different photos
    /// can coincidentally share a byte count); the pixel-fingerprint
    /// verifier is still the source of truth. This key is purely a
    /// cheap pre-filter so refinement finishes in seconds instead of
    /// minutes on a 30k-photo library.
    private func duplicateCandidateKey(for asset: PHAsset, size: Int64) -> String {
        return "\(asset.mediaType.rawValue)-\(asset.pixelWidth)x\(asset.pixelHeight)-\(size)"
    }

    private func similarPhotoKey(for asset: PHAsset) -> String {
        // Tighter time window (3 min) so a 2-hour photoshoot can't
        // all land in the same initial bucket before refinement even
        // runs. Refinement will further split on face identity + scene
        // feature print, but keeping buckets small is what saves us
        // when refinement is deferred or skipped.
        let timestamp = asset.creationDate?.timeIntervalSince1970 ?? 0
        return [
            Int(timestamp / (3 * 60)).description,
            roundedValue(asset.pixelWidth, unit: 48).description,
            roundedValue(asset.pixelHeight, unit: 48).description,
            Int(max(asset.pixelWidth * asset.pixelHeight, 1) / 350_000).description
        ].joined(separator: "-")
    }

    private func similarVideoKey(for asset: PHAsset, size: Int64) -> String {
        // Tighter bucketing: 2-hour time window, 3-second duration, 2MB size, 120px resolution
        let timeBucket = Int((asset.creationDate?.timeIntervalSince1970 ?? 0) / (2 * 3600))
        let durationBucket = Int(asset.duration / 3)
        let sizeBucket = Int(size / 2_000_000)
        return [
            timeBucket.description,
            durationBucket.description,
            sizeBucket.description,
            roundedValue(asset.pixelWidth, unit: 120).description,
            roundedValue(asset.pixelHeight, unit: 120).description
        ].joined(separator: "-")
    }

    private func similarScreenshotKey(for asset: PHAsset) -> String {
        let dayBucket = Int((asset.creationDate?.timeIntervalSince1970 ?? 0) / 86_400)
        return [dayBucket.description, roundedValue(asset.pixelWidth, unit: 80).description, roundedValue(asset.pixelHeight, unit: 80).description].joined(separator: "-")
    }

    private func roundedValue(_ value: Int, unit: Int) -> Int {
        max(unit, (value / unit) * unit)
    }

    private func contactBucketKey(for contact: ContactRecord) -> String {
        let normalizedName = contact.fullName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        if !normalizedName.isEmpty {
            return normalizedName
        }

        if let phone = contact.phones.first {
            return phone.filter(\.isNumber)
        }

        if let email = contact.emails.first {
            return email.lowercased()
        }

        return ""
    }

    private func bestContactID(in group: DuplicateContactGroup) -> String {
        group.contacts.max { lhs, rhs in
            contactScore(lhs) < contactScore(rhs)
        }?.id ?? group.contacts.first?.id ?? ""
    }

    private func contactScore(_ contact: ContactRecord) -> Int {
        (contact.fullName.count * 5) + (contact.phones.count * 3) + (contact.emails.count * 3)
    }

    private func isIncompleteContact(_ contact: ContactRecord) -> Bool {
        let trimmedName = contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty || (contact.phones.isEmpty && contact.emails.isEmpty)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadPersistedValue<T: Decodable>(key: String) -> T? {
        let decoder = JSONDecoder()
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func hashedPIN(_ pin: String) -> String {
        SHA256.hash(data: Data(pin.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func secretVaultDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        return documents.appendingPathComponent("Vault", isDirectory: true)
    }

    func vaultURL(for item: SecretVaultItem) -> URL {
        secretVaultDirectory().appendingPathComponent(item.filename)
    }

    private func requestVideoURL(for asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                    return
                }

                let error = (info?[PHImageErrorKey] as? Error)
                    ?? NSError(domain: "Cleanup", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to load this video."])
                continuation.resume(throwing: error)
            }
        }
    }

    private func requestImageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.version = .current
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { imageData, _, _, info in
                if let imageData {
                    continuation.resume(returning: imageData)
                    return
                }

                let error = (info?[PHImageErrorKey] as? Error)
                    ?? NSError(domain: "Cleanup", code: -9, userInfo: [NSLocalizedDescriptionKey: "Unable to load this photo."])
                continuation.resume(throwing: error)
            }
        }
    }

    private func exportCompressedVideo(
        sourceURL: URL,
        preset: VideoCompressionPreset,
        fileLengthLimit: Int64? = nil
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset.exportPreset) else {
            throw NSError(domain: "Cleanup", code: -3, userInfo: [NSLocalizedDescriptionKey: "Compression is unavailable for this video."])
        }

        if let fileLengthLimit {
            exportSession.fileLengthLimit = fileLengthLimit
        }

        try await exportSession.export(to: outputURL, as: .mp4)
        return outputURL
    }

    private func saveCompressedVideoCopy(from url: URL) async throws -> String {
        try await Self.saveCompressedVideoToLibrary(from: url)
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    nonisolated private static func deletePhotoLibraryAssets(with identifiers: [String]) async throws {
        guard !identifiers.isEmpty else {
            throw NSError(domain: "Cleanup", code: -1, userInfo: [NSLocalizedDescriptionKey: "No assets were selected."])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                guard assets.count > 0 else { return }
                PHAssetChangeRequest.deleteAssets(assets)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "Cleanup",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Photo library change request was not completed."]
                        )
                    )
                }
            }
        }
    }

    nonisolated private static func saveCompressedVideoToLibrary(from url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var createdIdentifier = ""
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                createdIdentifier = request?.placeholderForCreatedAsset?.localIdentifier ?? ""
            }) { success, error in
                try? FileManager.default.removeItem(at: url)

                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: createdIdentifier)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "Cleanup",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Photo library change request was not completed."]
                        )
                    )
                }
            }
        }
    }

    nonisolated private static func saveCompressedPhotoToLibrary(data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var createdIdentifier = ""
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.jpeg.identifier
                request.addResource(with: .photo, data: data, options: options)
                createdIdentifier = request.placeholderForCreatedAsset?.localIdentifier ?? ""
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: createdIdentifier)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "Cleanup",
                            code: -10,
                            userInfo: [NSLocalizedDescriptionKey: "Photo library change request was not completed."]
                        )
                    )
                }
            }
        }
    }
}

extension PHAuthorizationStatus {
    var isReadable: Bool {
        self == .authorized || self == .limited
    }

    /// When true, `PHPhotoLibrary.requestAuthorization` will NOT show the
    /// system dialog again — iOS only prompts for `.notDetermined`. Once
    /// a user has denied (or MDM restricted) access, the only way to grant
    /// it is by deep-linking to iOS Settings → <App> → Photos. The
    /// permission CTAs check this so a "denied" user sees "Open Settings"
    /// instead of a button that silently does nothing.
    var needsSettingsRedirect: Bool {
        self == .denied || self == .restricted
    }
}

extension CNAuthorizationStatus {
    var isReadable: Bool {
        self == .authorized
    }
}

extension EKAuthorizationStatus {
    var isReadable: Bool {
        switch self {
        case .authorized:
            return true
        case .fullAccess:
            return true
        default:
            return false
        }
    }
}

private struct ClusterMember {
    let asset: MediaAssetRecord
    let signature: MediaVisualSignature?
    let featurePrint: VNFeaturePrintObservation?
    let faceEmbeddings: [VNFeaturePrintObservation]?
}

private struct VisualClusterBucket {
    let anchorAsset: MediaAssetRecord
    let anchorSignature: MediaVisualSignature?
    let anchorFeaturePrint: VNFeaturePrintObservation?
    /// Per-face embeddings for the anchor. Populated only for the
    /// `.similar` category (the only one that needs identity-aware
    /// clustering); `nil` for screenshots / videos where face identity
    /// isn't part of the decision.
    let anchorFaceEmbeddings: [VNFeaturePrintObservation]?
    let fallbackKey: String
    var assets: [MediaAssetRecord]
    /// Full snapshot of every member's signals. Agglomerative
    /// clustering compares the candidate to all members, not just
    /// the anchor, so drift is impossible (C only joins A-B if it
    /// matches A OR B — not just A).
    var members: [ClusterMember]
}

struct MediaVisualSignature: Hashable, Sendable {
    let dHash: UInt64
    let meanLuma: Int
    let spread: Int
}

private extension PHFetchResult where ObjectType == PHAsset {
    var firstObject: PHAsset? {
        count > 0 ? object(at: 0) : nil
    }
}

extension ByteCountFormatter {
    static func cleanupString(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: byteCount)
    }
}

private extension DateFormatter {
    static let cleanupShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let cleanupLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let cleanupCluster: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d • h:mm a"
        return formatter
    }()
}

// MARK: - Photo library change bridge

/// Thin `NSObject` that adapts `PHPhotoLibraryChangeObserver` (an Obj-C
/// protocol) into a Swift callback AppFlow can hook. Callbacks arrive on
/// an arbitrary background queue — the handler bounces to the main actor.
/// The `PHChange` is passed through so the handler can call
/// `changeDetails(for:)` against the last cached `PHFetchResult` and
/// apply an incremental diff rather than doing a full rescan.
final class PhotoLibraryChangeBridge: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: (PHChange) -> Void

    init(onChange: @escaping (PHChange) -> Void) {
        self.onChange = onChange
        super.init()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange(changeInstance)
    }
}

// MARK: - Incremental scan support types

/// Intermediate bucket state produced by a full library scan and
/// preserved so that `PHPhotoLibraryChangeObserver` can patch it in
/// place when the library changes. The same bucket dicts are the
/// input to `applyLibrarySnapshot`, so patched output is bit-for-bit
/// what a full rescan would produce.
struct LibraryBucketsCache {
    var categorized: [DashboardCategoryKind: [MediaAssetRecord]]
    var duplicateBuckets: [String: [MediaAssetRecord]]
    var similarBuckets: [String: [MediaAssetRecord]]
    var similarVideoBuckets: [String: [MediaAssetRecord]]
    var similarScreenshotBuckets: [String: [MediaAssetRecord]]
    /// Remembers which buckets each asset was routed into, so a remove
    /// or change can strip it from exactly the buckets it's in without
    /// scanning every bucket key for a match.
    var assetRouting: [String: AssetRouting]
}

/// Where a single asset was routed during bucket assignment. Needed
/// for O(1) incremental removes — without it we'd have to walk every
/// bucket dict looking for the asset ID.
struct AssetRouting {
    let mediaType: PHAssetMediaType
    let categories: Set<DashboardCategoryKind>
    let duplicateKey: String?
    let similarKey: String?
    let similarVideoKey: String?
    let similarScreenshotKey: String?
}

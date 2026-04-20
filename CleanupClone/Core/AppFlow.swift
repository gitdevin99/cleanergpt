import AVFoundation
import Contacts
import CoreML
import CoreImage
import CryptoKit
import EventKit
import Foundation
@preconcurrency import Photos
@preconcurrency import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

enum AppStage {
    case onboarding
    case paywall
    case mainApp
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

    @Published var stage: AppStage = .onboarding
    @Published var selectedTab: CleanupTab = .home
    @Published var onboardingIndex = 0

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

    private var retiredCompressionAssetIDs: Set<String> = []
    private let gmailService = GmailService.shared
    private var libraryScanGeneration = 0
    private var activeLibraryScanTask: Task<Void, Never>?
    private let librarySnapshotBatchSize = 240
    private let quickScanReadyCount = 4_000
    private var clusterRefinementSignature: [DashboardCategoryKind: Int] = [:]
    private var visualSignatureCache: [String: MediaVisualSignature] = [:]
    private var semanticFeaturePrintCache: [String: VNFeaturePrintObservation] = [:]
    private var faceCountCache: [String: Int] = [:]
    private let clusterThumbnailManager = PHCachingImageManager()
    private let mediaAnalysisStore = MediaAnalysisStore()

    init() {
        restorePersistedState()
        refreshDeviceAndStorage()
        refreshPermissions()
        Task {
            await restoreGmailSessionIfPossible()
        }
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

    func bootstrapIfNeeded() async {
        guard mediaAssetsByCategory.isEmpty else {
            refreshDeviceAndStorage()
            refreshPermissions()
            return
        }

        refreshDeviceAndStorage()
        refreshPermissions()

        if photoAuthorization.isReadable {
            await scanLibrary()
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

    func advanceOnboarding() {
        if onboardingIndex < OnboardingStep.allCases.count - 1 {
            onboardingIndex += 1
        } else {
            stage = .paywall
        }
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
        storageSnapshot = StorageSnapshot.current()
        deviceSnapshot = DeviceSnapshot.current()
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
    }

    func refineReviewClustersIfNeeded(for category: DashboardCategoryKind) async {
        guard [.similar, .similarScreenshots, .similarVideos, .screenshots].contains(category) else { return }
        guard photoAuthorization.isReadable else { return }
        guard !refiningClusterCategories.contains(category) else { return }

        let sourceClusters = mediaClusters(for: category)
        let expectedSignature = refinementSourceSignature(for: sourceClusters)
        guard clusterRefinementSignature[category] != expectedSignature else { return }
        guard !sourceClusters.isEmpty else {
            clusterRefinementSignature[category] = expectedSignature
            return
        }

        refiningClusterCategories.insert(category)
        defer { refiningClusterCategories.remove(category) }

        let refinedClusters = await refineVisualClusters(from: sourceClusters, category: category)
        guard expectedSignature == refinementSourceSignature(for: mediaClusters(for: category)) else { return }

        clusterRefinementSignature[category] = expectedSignature

        let finalClusters = refinedClusters.isEmpty ? sourceClusters : refinedClusters
        assertUniqueClusterMembership(in: finalClusters, category: category)
        mediaClustersByCategory[category] = finalClusters
        mediaAssetsByCategory[category] = flattenClusters(finalClusters).sorted {
            if $0.sizeInBytes == $1.sizeInBytes {
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            return $0.sizeInBytes > $1.sizeInBytes
        }
        refreshDashboardCategories()
    }

    func requestPhotoAccessIfNeeded() async -> Bool {
        refreshPermissions()
        if photoAuthorization.isReadable {
            await scanLibrary()
            return true
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photoAuthorization = status
        if status.isReadable {
            await scanLibrary()
            return true
        }

        applyEmptyMediaState()
        return false
    }

    func requestPhotoAuthorizationOnly() async -> Bool {
        refreshPermissions()
        if photoAuthorization.isReadable {
            return true
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photoAuthorization = status
        if status.isReadable {
            return true
        }

        applyEmptyMediaState()
        return false
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

    func scanLibrary() async {
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
    }

    private func performLibraryScan() async {
        libraryScanGeneration += 1
        let scanGeneration = libraryScanGeneration
        clusterRefinementSignature.removeAll()
        refiningClusterCategories.removeAll()
        visualSignatureCache.removeAll()
        semanticFeaturePrintCache.removeAll()
        faceCountCache.removeAll()

        refreshDeviceAndStorage()
        refreshPermissions()

        guard photoAuthorization.isReadable else {
            applyEmptyMediaState()
            return
        }

        isScanningLibrary = true
        scanProgress = 0.02
        scanStatusText = "Scanning your library..."
        scannedLibraryItems = 0

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        PhotoAssetLookup.shared.reset()

        totalLibraryItems = fetchResult.count
        photoCount = 0
        videoCount = 0

        var categorized: [DashboardCategoryKind: [MediaAssetRecord]] = Dictionary(
            uniqueKeysWithValues: DashboardCategoryKind.allCases.map { ($0, []) }
        )
        var duplicateBuckets: [String: [MediaAssetRecord]] = [:]
        var similarBuckets: [String: [MediaAssetRecord]] = [:]
        var similarVideoBuckets: [String: [MediaAssetRecord]] = [:]
        var similarScreenshotBuckets: [String: [MediaAssetRecord]] = [:]
        var analysisBatch: [MediaAssetRecord] = []

        let total = max(fetchResult.count, 1)
        var lastSnapshotPublishAt = Date.distantPast

        for index in 0..<fetchResult.count {
            guard scanGeneration == libraryScanGeneration else { return }

            let asset = fetchResult.object(at: index)
            PhotoAssetLookup.shared.upsert(asset)
            let record = makeMediaRecord(from: asset)
            analysisBatch.append(record)

            if asset.mediaType == .image {
                photoCount += 1
            } else if asset.mediaType == .video {
                videoCount += 1
            }

            if record.mediaType == .video {
                let videoKey = similarVideoKey(for: asset, size: record.sizeInBytes)
                similarVideoBuckets[videoKey, default: []].append(record)
                // Stash preliminary bucket. `applyLibrarySnapshot` will
                // re-route to exactly one of: similarVideos, screenRecordings,
                // shortRecordings, videos using priority rules.
                if isScreenRecordingAsset(asset) {
                    categorized[.screenRecordings, default: []].append(record)
                } else if asset.duration > 0, asset.duration < 10 {
                    categorized[.shortRecordings, default: []].append(record)
                } else {
                    categorized[.videos, default: []].append(record)
                }
            } else {
                categorized[.other, default: []].append(record)

                if record.isScreenshot {
                    categorized[.screenshots, default: []].append(record)
                    let screenshotKey = similarScreenshotKey(for: asset)
                    similarScreenshotBuckets[screenshotKey, default: []].append(record)
                } else {
                    let duplicateKey = exactDuplicateKey(for: asset, size: record.sizeInBytes)
                    duplicateBuckets[duplicateKey, default: []].append(record)

                    let similarKey = similarPhotoKey(for: asset)
                    similarBuckets[similarKey, default: []].append(record)
                }
            }

            let processedCount = index + 1

            let isFinalItem = index == fetchResult.count - 1
            if index.isMultiple(of: 200) || isFinalItem {
                scanProgress = CGFloat(processedCount) / CGFloat(total)
                scanStatusText = libraryScanStatusText(processedCount: processedCount, totalCount: fetchResult.count)
                scannedLibraryItems = processedCount

                let shouldPublishSnapshot = isFinalItem
                    || index.isMultiple(of: librarySnapshotBatchSize)
                    || Date().timeIntervalSince(lastSnapshotPublishAt) >= 2.0
                if shouldPublishSnapshot {
                    await applyLibrarySnapshot(
                        categorized: categorized,
                        duplicateBuckets: duplicateBuckets,
                        similarBuckets: similarBuckets,
                        similarVideoBuckets: similarVideoBuckets,
                        similarScreenshotBuckets: similarScreenshotBuckets
                    )
                    lastSnapshotPublishAt = Date()
                }
                await Task.yield()
            }

            if processedCount.isMultiple(of: librarySnapshotBatchSize), processedCount < fetchResult.count {
                await mediaAnalysisStore.upsertMetadataBatch(analysisBatch)
                analysisBatch.removeAll(keepingCapacity: true)
            }
        }
        guard scanGeneration == libraryScanGeneration else { return }

        await mediaAnalysisStore.upsertMetadataBatch(analysisBatch)

        await applyLibrarySnapshot(
            categorized: categorized,
            duplicateBuckets: duplicateBuckets,
            similarBuckets: similarBuckets,
            similarVideoBuckets: similarVideoBuckets,
            similarScreenshotBuckets: similarScreenshotBuckets
        )

        scanProgress = fetchResult.count == 0 ? 0 : 1
        scanStatusText = fetchResult.count == 0 ? "No media found yet" : "Scan complete"
        scannedLibraryItems = fetchResult.count
        isScanningLibrary = false
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
        contactAnalysisSummary = ContactAnalysisSummary(
            totalCount: allRecords.count,
            duplicateGroupCount: duplicateGroups.count,
            duplicateContactCount: duplicateGroups.reduce(0) { $0 + max(0, $1.duplicateCount - 1) },
            incompleteCount: incompleteRecords.count,
            backupCount: 0
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
                await scanLibrary()
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
            guard let image = UIImage(data: imageData), let compressedData = image.jpegData(compressionQuality: quality) else {
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
        isScanningLibrary = false
        scanProgress = 0
        scanStatusText = "Photo access is required"
        scannedLibraryItems = 0
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

            let duplicateClusters = buildClusters(from: duplicateBuckets, category: .duplicates)
            let similarClusters = buildClusters(from: similarBuckets, category: .similar)
            let similarVideoClusters = buildClusters(from: similarVideoBuckets, category: .similarVideos)
            let similarScreenshotClusters = buildClusters(from: similarScreenshotBuckets, category: .similarScreenshots)

            var workingCategorized = categorized
            workingCategorized[.duplicates] = flatten(duplicateClusters)
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
                .duplicates: duplicateClusters,
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
        refreshDashboardCategories()
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

            var matchingGroupIndex: Int?
            for groupIndex in groups.indices {
                if await shouldPlace(
                    asset: asset,
                    signature: signature,
                    featurePrint: featurePrint,
                    into: groups[groupIndex],
                    category: category
                ) {
                    matchingGroupIndex = groupIndex
                    break
                }
            }

            if let groupIndex = matchingGroupIndex {
                groups[groupIndex].assets.append(asset)
            } else {
                groups.append(
                    VisualClusterBucket(
                        anchorAsset: asset,
                        anchorSignature: signature,
                        anchorFeaturePrint: featurePrint,
                        fallbackKey: fallbackKey,
                        assets: [asset]
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

    private func shouldPlace(
        asset: MediaAssetRecord,
        signature: MediaVisualSignature?,
        featurePrint: VNFeaturePrintObservation?,
        into group: VisualClusterBucket,
        category: DashboardCategoryKind
    ) async -> Bool {
        guard group.assets.count < maximumClusterSize(for: category) else {
            return false
        }

        if category == .similar {
            let assetFaceCount = await faceCount(for: asset)
            let anchorFaceCount = await faceCount(for: group.anchorAsset)
            guard assetFaceCount == anchorFaceCount else {
                return false
            }
        }

        guard isWithinRefinementWindow(asset, comparedTo: group.anchorAsset, category: category) else {
            return false
        }

        guard isComparableResolution(asset, comparedTo: group.anchorAsset, category: category) else {
            return false
        }

        let sizeFloor = max(min(asset.sizeInBytes, group.anchorAsset.sizeInBytes), 1)
        let sizeCeiling = max(asset.sizeInBytes, group.anchorAsset.sizeInBytes)
        let sizeRatio = Double(sizeCeiling) / Double(sizeFloor)
        guard sizeRatio <= refinementSizeRatioThreshold(for: category) else {
            return false
        }

        if let featurePrint, let anchorFeaturePrint = group.anchorFeaturePrint {
            let semanticDistance = Self.featurePrintDistance(from: featurePrint, to: anchorFeaturePrint)
            guard semanticDistance <= refinementFeatureDistanceThreshold(for: category) else {
                return false
            }

            if category == .similar {
                return true
            }
        }

        if let signature, let anchorSignature = group.anchorSignature {
            let hashDistance = Self.hammingDistance(signature.dHash, anchorSignature.dHash)
            let lumaDistance = abs(signature.meanLuma - anchorSignature.meanLuma)
            let spreadDistance = abs(signature.spread - anchorSignature.spread)

            return hashDistance <= refinementHashThreshold(for: category)
                && lumaDistance <= refinementLumaThreshold(for: category)
                && spreadDistance <= refinementSpreadThreshold(for: category)
        }

        return group.fallbackKey == refinementFallbackKey(for: asset, category: category)
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
        case .similarScreenshots:
            return 9
        case .similarVideos:
            return 10
        default:
            return 11
        }
    }

    private func refinementLumaThreshold(for category: DashboardCategoryKind) -> Int {
        switch category {
        case .similarScreenshots:
            return 22
        case .similarVideos:
            return 26
        default:
            return 24
        }
    }

    private func refinementSpreadThreshold(for category: DashboardCategoryKind) -> Int {
        switch category {
        case .similarScreenshots:
            return 20
        case .similarVideos:
            return 24
        default:
            return 22
        }
    }

    private func refinementSizeRatioThreshold(for category: DashboardCategoryKind) -> Double {
        switch category {
        case .similarScreenshots:
            return 1.35
        case .similarVideos:
            return 1.8
        default:
            return 1.5
        }
    }

    private func refinementFeatureDistanceThreshold(for category: DashboardCategoryKind) -> Float {
        switch category {
        case .similarScreenshots:
            return 0.18
        case .similarVideos:
            return 0.24
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

        await ensureAnalysisSignals(for: asset, includeFaceCount: true)
        return faceCountCache[asset.id] ?? 0
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

    private func ensureAnalysisSignals(for asset: MediaAssetRecord, includeFaceCount: Bool) async {
        await hydratePersistedAnalysisCaches(for: asset)

        let needsVisualSignature = visualSignatureCache[asset.id] == nil
        let needsFeaturePrint = semanticFeaturePrintCache[asset.id] == nil
        let needsFaceCount = includeFaceCount && faceCountCache[asset.id] == nil

        guard needsVisualSignature || needsFeaturePrint || needsFaceCount else {
            return
        }

        guard let sourceAsset = assetForLookupIdentifier(asset.id),
              let thumbnail = await Self.requestIndexingThumbnail(for: sourceAsset)
        else {
            if needsFaceCount {
                faceCountCache[asset.id] = 0
            }
            return
        }

        if needsVisualSignature, let signature = Self.makeVisualSignature(from: thumbnail.uiImage) {
            visualSignatureCache[asset.id] = signature
        }

        if needsFeaturePrint || needsFaceCount {
            let result = await Self.analyzeVisionSignals(
                from: thumbnail.ciImage,
                includeFeaturePrint: needsFeaturePrint,
                includeFaceCount: needsFaceCount
            )
            if needsFeaturePrint, let featurePrint = result.featurePrint {
                semanticFeaturePrintCache[asset.id] = featurePrint
            }
            if needsFaceCount {
                faceCountCache[asset.id] = result.faceCount ?? 0
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

    nonisolated private static func analyzeVisionSignals(
        from image: CIImage,
        includeFeaturePrint: Bool,
        includeFaceCount: Bool
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

            var faceRequest: VNDetectFaceRectanglesRequest?
            if includeFaceCount {
                let request = VNDetectFaceRectanglesRequest()
                request.preferBackgroundProcessing = true
                configurePreferredComputeDevices(for: request)
                requests.append(request)
                faceRequest = request
            }

            guard !requests.isEmpty else {
                return VisionAnalysisResult(featurePrint: nil, faceCount: nil)
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform(requests)
                return VisionAnalysisResult(
                    featurePrint: featurePrintRequest?.results?.first,
                    faceCount: faceRequest?.results?.count
                )
            } catch {
                return VisionAnalysisResult(
                    featurePrint: nil,
                    faceCount: includeFaceCount ? 0 : nil
                )
            }
        }
    }

    /// Fetch a small 256×256 thumbnail for indexing. This is I/O-bound work
    /// so it does NOT hold the indexing semaphore — only Vision compute should.
    nonisolated private static func requestIndexingThumbnail(for asset: PHAsset) async -> IndexingThumbnail? {
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
                targetSize: indexingTargetSize,
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

    private func estimatedFileSize(for asset: PHAsset) -> Int64 {
        let pixelCount = max(asset.pixelWidth * asset.pixelHeight, 1)
        if asset.mediaType == .video {
            return Int64(Double(pixelCount) * max(asset.duration, 1) * 0.08)
        }
        return Int64(Double(pixelCount) * 0.45)
    }

    private func isScreenRecordingAsset(_ asset: PHAsset) -> Bool {
        guard asset.mediaType == .video else { return false }
        // Cheap pre-filter: screen recordings are captured at the device's
        // native screen resolution, portrait-oriented, and don't come from
        // the camera. Everything that fails this is definitely not a screen
        // recording, so we skip the expensive PHAssetResource lookup (which
        // triggers a main-queue PHAssetOriginalMetadataProperties fetch and
        // spams the log at scan time).
        guard asset.pixelHeight >= asset.pixelWidth else { return false }
        guard isLikelyScreenResolution(width: asset.pixelWidth, height: asset.pixelHeight) else {
            return false
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let filename = resources.first?.originalFilename else { return false }
        let lower = filename.lowercased()
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

    private func exactDuplicateKey(for asset: PHAsset, size: Int64) -> String {
        let timeBucket = Int((asset.creationDate?.timeIntervalSince1970 ?? 0) / 60)
        return [asset.mediaType.rawValue.description, "\(asset.pixelWidth)x\(asset.pixelHeight)", "\(size)", "\(timeBucket)"].joined(separator: "-")
    }

    private func similarPhotoKey(for asset: PHAsset) -> String {
        let timestamp = asset.creationDate?.timeIntervalSince1970 ?? 0
        return [
            Int(timestamp / (15 * 60)).description,
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

private struct VisualClusterBucket {
    let anchorAsset: MediaAssetRecord
    let anchorSignature: MediaVisualSignature?
    let anchorFeaturePrint: VNFeaturePrintObservation?
    let fallbackKey: String
    var assets: [MediaAssetRecord]
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

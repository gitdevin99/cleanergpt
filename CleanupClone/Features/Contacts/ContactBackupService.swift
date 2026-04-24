import Contacts
import Foundation

// MARK: - Model

struct ContactBackup: Identifiable, Hashable {
    let id: String          // filename without extension
    let url: URL
    let createdAt: Date
    let contactCount: Int
    let isInCloud: Bool     // true if stored in iCloud ubiquity container
}

// MARK: - Service

/// Creates, lists, restores, and deletes full-address-book snapshots.
///
/// Snapshots are written as vCard (.vcf) files. When the user's iCloud is
/// available we write into the app's ubiquity container (user-visible as
/// "iCloud backups"); otherwise we fall back to the app's local Documents
/// directory (still labeled "Backups" in the UI). The same filename format is
/// used in both locations, so a later iCloud migration can simply move files.
///
/// Filename format: `Backup-{ISO8601 timestamp}-{contactCount}.vcf`
/// Example: `Backup-2026-04-21T08-45-00Z-2673.vcf`
@MainActor
final class ContactBackupService: ObservableObject {

    // Published state the UI observes
    @Published private(set) var backups: [ContactBackup] = []
    @Published private(set) var isWorking: Bool = false
    @Published var autoBackupEnabled: Bool {
        didSet { UserDefaults.standard.set(autoBackupEnabled, forKey: Self.autoBackupKey) }
    }
    @Published private(set) var lastBackupDate: Date? {
        didSet {
            if let date = lastBackupDate {
                UserDefaults.standard.set(date, forKey: Self.lastBackupDateKey)
            }
        }
    }

    // Persistence keys
    private static let autoBackupKey = "cleanup.contacts.autoBackup.enabled"
    private static let lastBackupDateKey = "cleanup.contacts.lastBackupDate"

    // iCloud container id – matches the one in the entitlements file
    private let containerIdentifier = "iCloud.com.sanjana.cleanupclone"

    // Time between auto-backups (24h). Used by ensureRecentBackup().
    private let autoBackupStalenessInterval: TimeInterval = 24 * 60 * 60

    private let contactStore: CNContactStore
    private let fileManager = FileManager.default

    init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
        self.autoBackupEnabled = UserDefaults.standard.object(forKey: Self.autoBackupKey) as? Bool ?? true
        self.lastBackupDate = UserDefaults.standard.object(forKey: Self.lastBackupDateKey) as? Date
        refreshBackups()
    }

    // MARK: - Public API

    /// Returns the directory where we read/write backup files. Prefers the
    /// iCloud ubiquity container; falls back to local Documents if iCloud
    /// isn't available (no account, signed out, etc.).
    var backupsDirectory: URL {
        if let cloudDir = iCloudBackupsDirectory() {
            return cloudDir
        }
        return localBackupsDirectory()
    }

    /// True if the current backupsDirectory lives in the user's iCloud.
    var isUsingICloud: Bool {
        return iCloudBackupsDirectory() != nil
    }

    /// Creates a new backup from the user's current address book.
    @discardableResult
    func createBackup() async -> ContactBackup? {
        isWorking = true
        defer { isWorking = false }

        do {
            let contacts = try fetchAllContactsForBackup()
            guard !contacts.isEmpty else {
                return nil
            }

            let data = try CNContactVCardSerialization.data(with: contacts)
            let timestamp = Self.timestampFormatter.string(from: Date())
            let filename = "Backup-\(timestamp)-\(contacts.count).vcf"

            let directory = backupsDirectory
            try ensureDirectoryExists(directory)
            let fileURL = directory.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)

            lastBackupDate = Date()
            refreshBackups()

            return backups.first(where: { $0.url == fileURL })
        } catch {
            #if DEBUG
            print("[ContactBackupService] createBackup failed: \(error)")
            #endif
            return nil
        }
    }

    /// Creates a backup ONLY IF the most recent one is older than 24 hours, or
    /// if no backups exist. Safe to call liberally before destructive actions.
    @discardableResult
    func ensureRecentBackup() async -> ContactBackup? {
        guard autoBackupEnabled else { return nil }

        let needsBackup: Bool
        if let last = lastBackupDate {
            needsBackup = Date().timeIntervalSince(last) > autoBackupStalenessInterval
        } else {
            needsBackup = true
        }

        guard needsBackup else { return nil }
        return await createBackup()
    }

    /// Restores a backup by ADDING its contacts to the current address book.
    /// Does not delete or replace existing contacts. May create duplicates if
    /// the same contact is already present – user can run the duplicate merger
    /// afterward to clean up.
    @discardableResult
    func restoreBackup(_ backup: ContactBackup) async -> Int {
        isWorking = true
        defer { isWorking = false }

        do {
            let data = try Data(contentsOf: backup.url)
            let restored = try CNContactVCardSerialization.contacts(with: data)
            guard !restored.isEmpty else { return 0 }

            let saveRequest = CNSaveRequest()
            for contact in restored {
                // Serialization returns CNContact; convert to mutable for adding.
                if let mutable = contact.mutableCopy() as? CNMutableContact {
                    saveRequest.add(mutable, toContainerWithIdentifier: nil)
                }
            }
            try contactStore.execute(saveRequest)
            return restored.count
        } catch {
            #if DEBUG
            print("[ContactBackupService] restoreBackup failed: \(error)")
            #endif
            return 0
        }
    }

    /// Deletes the given backup files.
    func deleteBackups(_ backups: [ContactBackup]) {
        for backup in backups {
            try? fileManager.removeItem(at: backup.url)
        }
        refreshBackups()
    }

    /// Rescans the backups directory and updates `backups`.
    func refreshBackups() {
        let directory = backupsDirectory
        guard fileManager.fileExists(atPath: directory.path) else {
            backups = []
            return
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let inCloud = isUsingICloud
            let parsed: [ContactBackup] = contents.compactMap { url in
                guard url.pathExtension.lowercased() == "vcf" else { return nil }
                return parseBackup(at: url, isInCloud: inCloud)
            }
            backups = parsed.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            #if DEBUG
            print("[ContactBackupService] refreshBackups failed: \(error)")
            #endif
            backups = []
        }
    }

    // MARK: - Private helpers

    private func fetchAllContactsForBackup() throws -> [CNContact] {
        // vCard serialization needs a comprehensive set of keys. Use the
        // descriptor Apple recommends so we don't drop fields silently.
        let descriptor = CNContactVCardSerialization.descriptorForRequiredKeys()
        let request = CNContactFetchRequest(keysToFetch: [descriptor])
        request.unifyResults = true

        var results: [CNContact] = []
        try contactStore.enumerateContacts(with: request) { contact, _ in
            results.append(contact)
        }
        return results
    }

    private func iCloudBackupsDirectory() -> URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return nil
        }
        return containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("ContactBackups", isDirectory: true)
    }

    private func localBackupsDirectory() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return documents.appendingPathComponent("ContactBackups", isDirectory: true)
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func parseBackup(at url: URL, isInCloud: Bool) -> ContactBackup? {
        let filename = url.deletingPathExtension().lastPathComponent
        // Format: Backup-{timestamp}-{count}
        let parts = filename.components(separatedBy: "-")

        // Count is always the last component when we wrote it; fallback to 0.
        let countString = parts.last ?? "0"
        let count = Int(countString) ?? 0

        // Prefer embedded timestamp; fall back to file creation date.
        var createdAt: Date?
        if parts.count >= 3 {
            // All components between "Backup" and the count make up the timestamp
            // (it contains dashes), joined back with "-".
            let timestampParts = parts.dropFirst().dropLast()
            let timestampString = timestampParts.joined(separator: "-")
            createdAt = Self.timestampFormatter.date(from: timestampString)
        }

        if createdAt == nil {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            createdAt = attrs?[.creationDate] as? Date
                ?? attrs?[.modificationDate] as? Date
        }

        guard let finalDate = createdAt else { return nil }

        return ContactBackup(
            id: filename,
            url: url,
            createdAt: finalDate,
            contactCount: count,
            isInCloud: isInCloud
        )
    }

    // Filenames use dashes in place of colons so they're valid on all platforms.
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return f
    }()
}

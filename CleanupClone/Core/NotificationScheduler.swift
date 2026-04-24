import Foundation
import UserNotifications
import UIKit

/// Aggressive local-notification campaign for free users. When onboarding
/// completes and the user grants notification permission, we snapshot the
/// scan results (duplicate count, recoverable GB, storage %) and pre-schedule
/// ~18 notifications spread across the first two weeks. Each notification
/// carries a deep-link payload in `userInfo` so taps land on the exact
/// upgrade surface we want.
///
/// The schedule is upfront — we don't need the app to re-open to keep nagging,
/// and if the numbers go stale that's fine (they were accurate when the user
/// first scanned). The moment `EntitlementStore.isPremium` flips to true we
/// `cancelAll()` so paying users don't get spammed.
///
/// Notifications are intentionally blunt. The market is ruthless; polite
/// notifications get ignored. We trade deliverability for conversion.
struct ScanSummary {
    /// Percent of device storage used (0–100). Used in copy like "Storage 92% full".
    let storagePercentUsed: Int
    /// Count of duplicate photos we found.
    let duplicateCount: Int
    /// Total recoverable space across duplicates + similar + large videos.
    let recoverableGB: Double
    /// Compressible-video savings — shown in compression-focused nags.
    let compressibleGB: Double
}

/// Deep-link destinations a notification can route to when tapped.
enum NotificationDeeplink: String {
    case upgrade       // Show the Adapty paywall directly
    case duplicates    // Dashboard → Duplicates cluster
    case compress      // Compress tab
    case vault         // Secret Vault
    case dashboard     // Just the dashboard
}

@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let scheduledKey = "notifications.campaignScheduled"
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Public API

    /// Schedule the full 18-notification campaign using real scan data.
    /// Safe to call multiple times — it cancels any previous campaign first
    /// so numbers stay consistent with whatever scan just finished.
    func scheduleUpfrontCampaign(with summary: ScanSummary) {
        center.removeAllPendingNotificationRequests()

        let entries = buildSchedule(summary: summary)
        for entry in entries {
            schedule(entry)
        }
        defaults.set(true, forKey: scheduledKey)
    }

    /// Kill every pending notification. Called the moment the user upgrades.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        defaults.set(false, forKey: scheduledKey)
    }

    /// Whether a campaign is currently armed.
    var hasActiveCampaign: Bool {
        defaults.bool(forKey: scheduledKey)
    }

    // MARK: - Schedule shape

    /// Returns (offsetSeconds, title, body, deeplink) tuples. Offsets are from
    /// "now" — the install/permission-grant moment. The curve is deliberately
    /// front-loaded: the first 6 hours get 3 pings, then we back off to
    /// a daily rhythm that still hits morning + afternoon + evening on the
    /// first few days.
    private func buildSchedule(summary: ScanSummary) -> [ScheduleEntry] {
        let dupes = max(summary.duplicateCount, 1)
        let gb = String(format: "%.1f", max(summary.recoverableGB, 0.1))
        let compressGB = String(format: "%.1f", max(summary.compressibleGB, 0.1))
        let storagePct = max(min(summary.storagePercentUsed, 99), 1)

        let hour: TimeInterval = 3600
        let day: TimeInterval = 86_400

        return [
            // ——— Day 0: front-load while intent is hot ———
            .init(after: 45 * 60,
                  title: "\(dupes) duplicates waiting",
                  body: "Your library still has \(dupes) duplicate photos. Clean them in one tap.",
                  deeplink: .duplicates),
            .init(after: 3 * hour,
                  title: "Storage is \(storagePct)% full",
                  body: "We found \(gb) GB you can reclaim right now. Tap to free up space.",
                  deeplink: .upgrade),
            .init(after: 6 * hour,
                  title: "Don't lose that photo",
                  body: "You're running low. Clear \(gb) GB before your next shot fails to save.",
                  deeplink: .upgrade),

            // ——— Day 1: three touches, morning / midday / evening ———
            .init(after: 1 * day + 9 * hour,
                  title: "Morning cleanup 🧹",
                  body: "\(dupes) duplicates, \(gb) GB recoverable. Two taps to clean.",
                  deeplink: .duplicates),
            .init(after: 1 * day + 13 * hour,
                  title: "Videos eating your storage",
                  body: "Compress videos to save \(compressGB) GB without losing quality.",
                  deeplink: .compress),
            .init(after: 1 * day + 20 * hour,
                  title: "Unlock unlimited cleanup",
                  body: "Free plan hit its cap. Upgrade to clear \(gb) GB tonight.",
                  deeplink: .upgrade),

            // ——— Day 2 ———
            .init(after: 2 * day + 10 * hour,
                  title: "Still \(storagePct)% full",
                  body: "Yesterday's scan is still waiting. \(dupes) duplicates to go.",
                  deeplink: .duplicates),
            .init(after: 2 * day + 15 * hour,
                  title: "Private photos?",
                  body: "Lock sensitive photos behind a PIN in Secret Space.",
                  deeplink: .vault),
            .init(after: 2 * day + 21 * hour,
                  title: "\(gb) GB is a lot",
                  body: "That's hundreds of photos you could take instead. Clear them now.",
                  deeplink: .upgrade),

            // ——— Day 3 ———
            .init(after: 3 * day + 11 * hour,
                  title: "Your phone is slowing down",
                  body: "Low storage makes iOS sluggish. Reclaim \(gb) GB in under a minute.",
                  deeplink: .upgrade),
            .init(after: 3 * day + 18 * hour,
                  title: "Free trial ending soon?",
                  body: "3 days free, cancel anytime. Unlock unlimited cleanup.",
                  deeplink: .upgrade),

            // ——— Day 4 ———
            .init(after: 4 * day + 12 * hour,
                  title: "Duplicate alert",
                  body: "\(dupes) duplicates still in your library. One tap deletes them all.",
                  deeplink: .duplicates),

            // ——— Day 5 ———
            .init(after: 5 * day + 14 * hour,
                  title: "Compress videos → save \(compressGB) GB",
                  body: "Originals stay safe. Quality preserved. Unlock with Pro.",
                  deeplink: .compress),
            .init(after: 5 * day + 19 * hour,
                  title: "Storage still \(storagePct)% full",
                  body: "Nothing has changed in 5 days. Let's fix it tonight.",
                  deeplink: .upgrade),

            // ——— Day 6 ———
            .init(after: 6 * day + 11 * hour,
                  title: "Last-minute cleanup",
                  body: "\(gb) GB waiting. Before the weekend fills your camera roll.",
                  deeplink: .duplicates),

            // ——— Day 7 ———
            .init(after: 7 * day + 10 * hour,
                  title: "One week in — still full",
                  body: "Your phone hasn't had a cleanup in 7 days. Unlock Pro and catch up.",
                  deeplink: .upgrade),

            // ——— Week 2 taper ———
            .init(after: 10 * day + 12 * hour,
                  title: "\(dupes) duplicates, still waiting",
                  body: "Recover \(gb) GB in two taps. Pro unlocks everything.",
                  deeplink: .upgrade),
            .init(after: 13 * day + 18 * hour,
                  title: "Final reminder",
                  body: "Your cleanup is still pending. \(gb) GB recoverable. Don't let it pile up.",
                  deeplink: .upgrade),
        ]
    }

    // MARK: - Plumbing

    private struct ScheduleEntry {
        let after: TimeInterval
        let title: String
        let body: String
        let deeplink: NotificationDeeplink
    }

    private func schedule(_ entry: ScheduleEntry) {
        let content = UNMutableNotificationContent()
        content.title = entry.title
        content.body = entry.body
        content.sound = .default
        content.userInfo = ["deeplink": entry.deeplink.rawValue]

        // UNTimeIntervalNotificationTrigger requires > 0. Clamp defensively.
        let interval = max(entry.after, 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "cleanup.campaign.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - Tap handling

    /// Parse a tapped notification's userInfo into a deep-link.
    /// Caller routes the result through AppFlow.
    static func deeplink(from userInfo: [AnyHashable: Any]) -> NotificationDeeplink? {
        guard let raw = userInfo["deeplink"] as? String else { return nil }
        return NotificationDeeplink(rawValue: raw)
    }
}

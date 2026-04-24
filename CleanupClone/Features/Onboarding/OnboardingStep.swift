import Foundation
import SwiftUI

/// New 12-screen onboarding flow. Order:
/// emotional hook → social proof → feature showcases → photo permission →
/// paywall → notifications. Photo permission is asked BEFORE the paywall
/// so we can show the real scan running while the user considers the
/// offer — makes the value proposition concrete instead of abstract.
enum OnboardingStep: Int, CaseIterable {
    case hero             // 1 — "Your iPhone is full. Let's fix that." Animated storage bar.
    case socialProof      // 2 — 4M+ users, 3 testimonials
    case duplicates       // 3 — Feature: delete duplicate photos
    case similar          // 4 — Feature: similar photos cluster
    case speakerDust      // 5 — Feature: speaker clean (dust)
    case speakerWater     // 6 — Feature: speaker clean (water)
    case contactsBackup   // 7 — Feature: contacts merge + iCloud backup
    case secretSpace      // 8 — Feature: vault for private media
    case emailCleaner     // 9 — Feature: Gmail cleanup
    case photosPermission // 10 — Photo library permission (moved before paywall)
    case paywall          // 11 — "Free Up Storage Easily" paywall
    case notifications    // 12 — Weekly reminder (optional ask)

    var title: String {
        switch self {
        case .hero: "Your iPhone is Full.\nLet's Fix That."
        case .socialProof: "Trusted by\n4 Million+ Users"
        case .duplicates: "Delete Duplicate\nPhotos Instantly"
        case .similar: "Merge Similar\nShots Smartly"
        case .speakerDust: "Blast Dust\nFrom Your Speakers"
        case .speakerWater: "Push Water\nOut of Your Speakers"
        case .contactsBackup: "Clean Up\nYour Contacts"
        case .secretSpace: "Your Private\nSecret Space"
        case .emailCleaner: "Clean Your\nEmail Inbox"
        case .paywall: "Free Up Storage\nEasily"
        case .photosPermission: "Access Your Photos"
        case .notifications: "Stay on Top\nof Clutter"
        }
    }

    var subtitle: String {
        switch self {
        case .hero:
            "Reclaim gigabytes in seconds. Duplicates, blurred shots, junk. Gone."
        case .socialProof:
            "Real results, real people. Join the community freeing up storage daily."
        case .duplicates:
            "Eliminate duplicate photos instantly and reclaim your storage."
        case .similar:
            "Keep the best shot from every burst. Delete the rest in one tap."
        case .speakerDust:
            "Scientifically tuned vibrations dislodge dust trapped in your speaker grille."
        case .speakerWater:
            "A proven low-frequency sound wave physically pushes water out of your speaker."
        case .contactsBackup:
            "Merge duplicates and back up contacts to iCloud automatically."
        case .secretSpace:
            "Lock personal photos and videos behind a PIN. Only you can see them."
        case .emailCleaner:
            "Unsubscribe and delete promo emails with one tap."
        case .paywall:
            ""  // Paywall has its own custom layout
        case .photosPermission:
            "We'll scan your library to find duplicates and free up space. Your photos never leave your phone."
        case .notifications:
            "We'll remind you weekly so your phone never fills up again."
        }
    }

    var buttonTitle: String {
        switch self {
        case .hero: "Get Started"
        case .paywall: "Continue"
        case .photosPermission: "Allow Access"
        case .notifications: "Enable Reminders"
        default: "Continue"
        }
    }

    /// Secondary button text when a step has a skip/deny option.
    var secondaryButtonTitle: String? {
        switch self {
        case .paywall: "Restore Purchase"
        case .notifications: "Not Now"
        default: nil
        }
    }
}

struct OnboardingCardPreview: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let palette: [Color]
}

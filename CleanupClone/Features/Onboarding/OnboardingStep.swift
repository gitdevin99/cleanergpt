import Foundation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case duplicates
    case optimize
    case email

    var title: String {
        switch self {
        case .welcome: "Welcome to\nCleanup"
        case .duplicates: "Delete Duplicate\nPhotos"
        case .optimize: "Optimize iPhone\nStorage"
        case .email: "Clean Your Email\nInbox"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            "Cleanup needs access to your photos to free up storage. We intend to provide transparency and protect your privacy."
        case .duplicates:
            "Eliminate duplicate photos instantly and reclaim your storage."
        case .optimize:
            "Free up to 80% of your storage and get more space."
        case .email:
            "Delete spam and promotional emails with just one tap."
        }
    }

    var buttonTitle: String {
        switch self {
        case .welcome: "Get started"
        default: "Next"
        }
    }
}

struct OnboardingCardPreview: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let palette: [Color]
}

import SwiftUI

enum AppStage {
    case onboarding
    case paywall
    case mainApp
}

enum CleanupTab: String, CaseIterable, Identifiable {
    case charging
    case secret
    case contacts
    case email
    case compress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charging: "Charging"
        case .secret: "Secret Space"
        case .contacts: "Contacts"
        case .email: "Email Cleaner"
        case .compress: "Compress"
        }
    }

    var symbol: String {
        switch self {
        case .charging: "bolt.fill"
        case .secret: "lock.fill"
        case .contacts: "person.crop.circle.fill"
        case .email: "sparkles"
        case .compress: "play.square.fill"
        }
    }
}

final class AppFlow: ObservableObject {
    @Published var stage: AppStage = .onboarding
    @Published var selectedTab: CleanupTab = .charging
    @Published var onboardingIndex = 0

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
}

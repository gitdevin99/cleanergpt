import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        ZStack {
            CleanupTheme.background.ignoresSafeArea()

            switch appFlow.stage {
            case .onboarding:
                OnboardingFlowView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .paywall:
                PaywallView()
                    .transition(.opacity)
            case .mainApp:
                MainShellView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: appFlow.stage)
    }
}

import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPermissionSheet = false
    @State private var showTrialInterstitial = false
    @State private var interstitialStage = 0

    private var currentStep: OnboardingStep {
        OnboardingStep.allCases[appFlow.onboardingIndex]
    }

    var body: some View {
        ScreenContainer {
            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                Spacer(minLength: 14)

                if showTrialInterstitial {
                    trialInterstitial
                } else {
                    stepContent
                }
            }
            .padding(.bottom, 20)
        }
        .task {
            appFlow.refreshDeviceAndStorage()
        }
        .onChange(of: appFlow.onboardingIndex) { _, _ in
            appFlow.refreshDeviceAndStorage()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            appFlow.refreshDeviceAndStorage()
        }
        .sheet(isPresented: $showPermissionSheet) {
            PhotosPermissionSheet {
                Task {
                    let granted = await appFlow.requestPhotoAuthorizationOnly()
                    showPermissionSheet = false
                    guard granted else { return }
                    appFlow.advanceOnboarding()
                    Task {
                        await appFlow.scanLibrary()
                    }
                }
            }
            .presentationDetents([.height(540)])
            .presentationCornerRadius(32)
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= appFlow.onboardingIndex ? CleanupTheme.electricBlue : Color.white.opacity(0.08))
                    .frame(height: 4)
            }
        }
    }

    private var stepContent: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 16)

            Text(currentStep.title)
                .font(CleanupFont.hero(42))
                .multilineTextAlignment(.center)
                .foregroundStyle(CleanupTheme.textPrimary)

            Text(currentStep.subtitle)
                .font(CleanupFont.body(15))
                .foregroundStyle(CleanupTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            previewForStep(currentStep)
                .frame(maxHeight: .infinity)

            VStack(spacing: 10) {
                PrimaryCTAButton(title: currentStep.buttonTitle, action: handleCTA)
                HStack(spacing: 8) {
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    Text("and")
                    Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
                }
                .font(CleanupFont.caption(12))
                .foregroundStyle(CleanupTheme.textTertiary)
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private func previewForStep(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            VStack(spacing: 18) {
                HStack(spacing: 26) {
                    HeaderIconTile(symbol: "photo.fill.on.rectangle.fill", title: "Photos", palette: [Color(hex: "#F67179"), Color(hex: "#A63EFF")])
                    HeaderIconTile(symbol: "icloud.fill", title: "iCloud", palette: [Color(hex: "#54B8FF"), Color(hex: "#76E6FF")])
                }

                UsageBar(progress: max(0.04, min(appFlow.storageSnapshot.progress, 1)), palette: CleanupTheme.redBar)
                    .frame(height: 18)
                    .padding(.horizontal, 34)

                Text("\(ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.usedBytes)) of \(ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.totalBytes)) used")
                    .font(CleanupFont.sectionTitle(28))
                    .foregroundStyle(CleanupTheme.textPrimary)

                Text("with your photos driving the storage pressure")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textTertiary)
            }
        case .duplicates:
            HStack(alignment: .top, spacing: 16) {
                DuplicatePairPreview(assetName: "DuplicateSelfieWomen")
                DuplicatePairPreview(assetName: "DuplicateSelfieMen")
            }
            .padding(.horizontal, 26)
        case .optimize:
            VStack(spacing: 20) {
                HStack(spacing: 26) {
                    HeaderIconTile(symbol: "photo.stack.fill", title: "Photos", palette: [Color(hex: "#FF6B6B"), Color(hex: "#BC31FF")])
                    HeaderIconTile(symbol: "icloud.and.arrow.down.fill", title: "iCloud", palette: [Color(hex: "#5AB7FF"), Color(hex: "#84E9FF")])
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("\(appFlow.deviceSnapshot.deviceName)       \(ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.usedBytes)) of \(ByteCountFormatter.cleanupString(fromByteCount: appFlow.storageSnapshot.totalBytes)) used")
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)

                    UsageBar(progress: max(0.04, min(appFlow.storageSnapshot.progress, 1)), palette: CleanupTheme.redBar)
                    .frame(height: 16)

                    HStack(spacing: 12) {
                        legendItem("Photos", CleanupTheme.accentRed)
                        legendItem("Applications", .orange)
                        legendItem("System Data", .gray.opacity(0.5))
                    }
                }
                .padding(.horizontal, 30)
            }
        case .email:
            VStack(spacing: 24) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#3358FF"), Color(hex: "#31D2FF")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 164, height: 164)
                        .overlay {
                            Image(systemName: "envelope.open.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.white)
                        }

                    Text("8.137")
                        .font(CleanupFont.badge(18))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(CleanupTheme.accentRed, in: Capsule(style: .continuous))
                        .offset(x: 12, y: -8)
                }

                UsageBar(progress: 0.84, palette: CleanupTheme.redBar)
                    .frame(height: 18)
                    .padding(.horizontal, 42)
            }
        }
    }

    private var trialInterstitial: some View {
        VStack {
            Spacer()

            ZStack {
                Circle()
                    .fill(CleanupTheme.electricBlue.opacity(0.08))
                    .frame(width: 260, height: 260)
                    .blur(radius: 12)

                VStack(spacing: 4) {
                    Text("Try 7 days")
                        .font(CleanupFont.hero(34))
                        .foregroundStyle(CleanupTheme.accentCyan)
                    Text(interstitialStage == 0 ? "" : "For free!")
                        .font(CleanupFont.hero(54))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .task {
            guard showTrialInterstitial else { return }
            try? await Task.sleep(for: .milliseconds(700))
            interstitialStage = 1
            try? await Task.sleep(for: .milliseconds(800))
            appFlow.showPaywall()
        }
    }

    private func handleCTA() {
        if currentStep == .welcome {
            showPermissionSheet = true
        } else if currentStep == .email {
            showTrialInterstitial = true
        } else {
            appFlow.advanceOnboarding()
        }
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(CleanupFont.caption(11))
                .foregroundStyle(CleanupTheme.textSecondary)
        }
    }
}

private struct DuplicatePairPreview: View {
    let assetName: String

    var body: some View {
        VStack(spacing: 10) {
            duplicateCard(
                badgeTitle: "KEEP",
                badgeTint: CleanupTheme.electricBlue,
                symbol: "checkmark",
                removeState: false
            )

            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CleanupTheme.textTertiary)
                .padding(.vertical, 2)

            duplicateCard(
                badgeTitle: "DELETE",
                badgeTint: CleanupTheme.accentRed,
                symbol: "xmark",
                removeState: true
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func duplicateCard(badgeTitle: String, badgeTint: Color, symbol: String, removeState: Bool) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(height: 108)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(removeState ? Color.black.opacity(0.22) : Color.clear)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .bold))
                    Text(badgeTitle)
                        .font(CleanupFont.badge(10))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(badgeTint, in: Capsule(style: .continuous))
                .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(removeState ? CleanupTheme.accentRed : Color.white.opacity(0.92))
                        .frame(width: 32, height: 32)

                    Image(systemName: removeState ? "xmark" : "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(removeState ? .white : CleanupTheme.electricBlue)
                }
                .padding(10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(removeState ? CleanupTheme.accentRed.opacity(0.42) : Color.white.opacity(0.08), lineWidth: 1.5)
            }
    }
}

private struct PhotosPermissionSheet: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#20263A"), Color(hex: "#101522")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 160)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(CleanupTheme.electricBlue)
                        Text("31,969 Photos, 5,816 Videos")
                            .font(CleanupFont.body(18))
                            .foregroundStyle(.white)
                    }
                }

            Text("“Cleanup” would like full access to your Photo Library.")
                .font(CleanupFont.screenTitle(24))
                .multilineTextAlignment(.center)
                .foregroundStyle(CleanupTheme.textPrimary)

            Text("Access is needed to search for similar and duplicate photos. Your photos will not be stored on any server.")
                .font(CleanupFont.body(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(CleanupTheme.textSecondary)

            VStack(spacing: 10) {
                button("Continue to Photos Access", filled: true, action: onContinue)
                button("Maybe Later", filled: false, action: onContinue)
            }
        }
        .padding(24)
        .background(CleanupTheme.background)
    }

    private func button(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CleanupFont.body(16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(filled ? AnyShapeStyle(CleanupTheme.cta) : AnyShapeStyle(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

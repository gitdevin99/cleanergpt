import SwiftUI

struct SecretSpaceView: View {
    @State private var stage: SecretStage = .empty

    var body: some View {
        FeatureScreen(title: "Secret Library", leadingSymbol: "xmark") {
            VStack(spacing: 22) {
                Spacer(minLength: 20)

                ZStack {
                    Circle()
                        .fill(CleanupTheme.electricBlue.opacity(0.12))
                        .frame(width: 180, height: 180)

                    GeneratedArtworkView(
                        assetName: "SecretLibraryArt",
                        fallbackSymbol: stage == .locked ? "lock.square.stack.fill" : "lock.shield.fill",
                        tint: stage == .locked ? .white : CleanupTheme.electricBlue,
                        size: 86
                    )
                    .frame(width: 132, height: 132)
                }

                Text(stage.title)
                    .font(CleanupFont.hero(32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(stage.subtitle)
                    .font(CleanupFont.body(16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .padding(.horizontal, 24)

                if stage == .empty {
                    PrimaryCTAButton(title: "+ Add Files") {
                        stage = .pinGate
                    }
                } else if stage == .pinGate {
                    VStack(spacing: 12) {
                        PrimaryCTAButton(title: "Create PIN") {
                            stage = .locked
                        }
                        Button("Maybe Later") {}
                            .font(CleanupFont.body(16))
                            .foregroundStyle(CleanupTheme.textSecondary)
                    }
                } else {
                    PrimaryCTAButton(title: "Unlock Now") {}
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private enum SecretStage {
    case empty
    case pinGate
    case locked

    var title: String {
        switch self {
        case .empty: "This is your Secret Library"
        case .pinGate: "Protect your private photos and videos"
        case .locked: "Your Secret Library is locked"
        }
    }

    var subtitle: String {
        switch self {
        case .empty: "No Secret Files"
        case .pinGate: "Create a PIN to keep hidden media out of sight and protected."
        case .locked: "Use your PIN or Face ID to access the private vault."
        }
    }
}

import SwiftUI

struct ContactsView: View {
    var body: some View {
        FeatureScreen(title: "Contacts", leadingSymbol: "xmark") {
            VStack(spacing: 24) {
                Spacer(minLength: 30)

                ZStack {
                    Circle()
                        .fill(CleanupTheme.accentCyan.opacity(0.12))
                        .frame(width: 210, height: 210)

                    GeneratedArtworkView(
                        assetName: "CleanupRobot",
                        fallbackSymbol: "person.crop.circle.badge.exclamationmark",
                        tint: CleanupTheme.accentCyan,
                        size: 88
                    )
                    .frame(width: 148, height: 148)
                }

                Text("Need Access to Start Scanning")
                    .font(CleanupFont.hero(34))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Cleanup needs access to your contacts to find and merge duplicate entries.")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                PrimaryCTAButton(title: "Go to Settings") {}

                Spacer()
            }
            .padding(.horizontal, 18)
        }
    }
}

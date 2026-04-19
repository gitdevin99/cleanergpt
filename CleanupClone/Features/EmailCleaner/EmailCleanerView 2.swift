import SwiftUI

struct EmailCleanerView: View {
    var body: some View {
        FeatureScreen(title: "Email Cleaner", leadingSymbol: "xmark") {
            VStack(spacing: 24) {
                Spacer(minLength: 28)

                ZStack {
                    Circle()
                        .fill(CleanupTheme.electricBlue.opacity(0.12))
                        .frame(width: 220, height: 220)

                    GeneratedArtworkView(
                        assetName: "CleanupRobot",
                        fallbackSymbol: "mail.and.text.magnifyingglass",
                        tint: CleanupTheme.electricBlue,
                        size: 92
                    )
                    .frame(width: 156, height: 156)
                }

                Text("Cleans the mails in the categories you choose, according to the filters you apply.")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    .font(CleanupFont.body(15))
                    .foregroundStyle(.white.opacity(0.75))

                Button {} label: {
                    HStack(spacing: 12) {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 24))
                        Text("Sign in with Google")
                            .font(CleanupFont.body(18))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 18)
        }
    }
}

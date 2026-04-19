import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button("Restore Purchase") {}
                        .font(CleanupFont.body(15))
                        .foregroundStyle(CleanupTheme.textSecondary)

                    Spacer()

                    Button {
                        appFlow.enterApp()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CleanupTheme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                Text("Clean your Storage")
                    .font(CleanupFont.hero(42))
                    .foregroundStyle(CleanupTheme.textPrimary)

                Text("Get rid of what you don’t need")
                    .font(CleanupFont.body(19))
                    .foregroundStyle(CleanupTheme.textSecondary)

                HStack(spacing: 24) {
                    sourceIcon("Photos", symbol: "photo.fill", palette: [Color(hex: "#FF7084"), Color(hex: "#BC42FF")], badge: "611")
                    sourceIcon("iCloud", symbol: "icloud.fill", palette: [Color(hex: "#52B8FF"), Color(hex: "#85E6FF")], badge: "329")
                }

                UsageBar(progress: 0.95, palette: CleanupTheme.redBar)
                    .frame(height: 20)

                Text("95 from 100% used")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(CleanupTheme.accentRed)

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cleanup Pro")
                            .font(CleanupFont.sectionTitle())
                        Text("Smart Cleaning, Video Compressor, Secret Storage, Manage Contacts, No Ads and Limits.")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(CleanupTheme.textSecondary)
                        Text("Free for 7 days, then AED 39.99/week")
                            .font(CleanupFont.body(20))
                            .foregroundStyle(.white)
                    }
                }

                GlassCard(cornerRadius: 24) {
                    Text("Free trial enabled")
                        .font(CleanupFont.sectionTitle(18))
                        .foregroundStyle(.white)
                }

                GlassCard {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Due today")
                                    .font(CleanupFont.body(16))
                                Text("Due 23 April 2026")
                                    .font(CleanupFont.body(15))
                                    .foregroundStyle(CleanupTheme.textSecondary)
                            }

                            Spacer()

                            Text("7 days free")
                                .font(CleanupFont.badge(14))
                                .foregroundStyle(CleanupTheme.accentGreen)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(CleanupTheme.accentGreen.opacity(0.12), in: Capsule(style: .continuous))
                        }
                    }
                }

                PrimaryCTAButton(title: "Try Free") {
                    appFlow.enterApp()
                }

                Text("Secured with Apple")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
        }
    }

    private func sourceIcon(_ title: String, symbol: String, palette: [Color], badge: String) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 106, height: 106)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 46))
                            .foregroundStyle(.white)
                    }

                Text(badge)
                    .font(CleanupFont.badge(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(CleanupTheme.accentRed, in: Capsule(style: .continuous))
                    .offset(x: 10, y: -10)
            }
            Text(title)
                .font(CleanupFont.body(19))
                .foregroundStyle(.white)
        }
    }
}

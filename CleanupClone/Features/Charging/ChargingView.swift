import SwiftUI

struct ChargingView: View {
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        FeatureScreen(
            title: "Charging Animation",
            leadingSymbol: "chevron.left",
            trailingSymbol: "checkmark.circle.fill",
            leadingAction: { appFlow.closeFeature() },
            trailingAction: { appFlow.applyChargingPoster() }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if let poster = appFlow.currentChargingPoster() {
                    GlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Current Selection")
                                .font(CleanupFont.caption(12))
                                .foregroundStyle(CleanupTheme.textTertiary)
                            Text(poster.title)
                                .font(CleanupFont.sectionTitle(24))
                                .foregroundStyle(.white)
                            Text("\(poster.subtitle) • \(appFlow.appliedChargingPosterID == poster.id ? "Applied" : "Tap the check button to apply")")
                                .font(CleanupFont.body(15))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }
                    }
                }

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(appFlow.chargingPosters) { poster in
                            Button {
                                appFlow.selectChargingPoster(poster)
                            } label: {
                                PosterTile(
                                    title: poster.title,
                                    subtitle: poster.locked ? "Pro poster" : poster.subtitle,
                                    palette: poster.palette,
                                    locked: poster.locked,
                                    assetName: poster.assetName
                                )
                                .frame(height: 250)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(
                                            appFlow.selectedChargingPosterID == poster.id ? CleanupTheme.electricBlue : Color.white.opacity(0.06),
                                            lineWidth: appFlow.selectedChargingPosterID == poster.id ? 2 : 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

import SwiftUI

struct ChargingView: View {
    private let posters: [PosterModel] = [
        .init(title: "Battery", subtitle: "Neon charge loop", palette: [Color.black, Color(hex: "#3DFF44")], assetName: "ChargingBatteryPoster", locked: false),
        .init(title: "Bloom", subtitle: "Amber pulse", palette: [Color(hex: "#462100"), Color(hex: "#FFB445")], assetName: "ChargingBloomPoster", locked: false),
        .init(title: "Storm", subtitle: "Electric arc", palette: [Color(hex: "#040716"), Color(hex: "#52C3FF")], assetName: "ChargingStormPoster", locked: true),
        .init(title: "Cat", subtitle: "Psychedelic pet", palette: [Color(hex: "#240E3B"), Color(hex: "#E33C7B")], assetName: "ChargingCatPoster", locked: true),
        .init(title: "Glow", subtitle: "Soft spectrum", palette: [Color(hex: "#D48B8B"), Color(hex: "#A5B8FF")], assetName: nil, locked: true)
    ]

    var body: some View {
        FeatureScreen(title: "Charging Animation", leadingSymbol: "chevron.left", trailingSymbol: "questionmark.circle") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(posters) { poster in
                    PosterTile(title: poster.title, subtitle: poster.subtitle, palette: poster.palette, locked: poster.locked, assetName: poster.assetName)
                        .frame(height: 250)
                }
            }
        }
    }
}

private struct PosterModel: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let palette: [Color]
    let assetName: String?
    let locked: Bool
}

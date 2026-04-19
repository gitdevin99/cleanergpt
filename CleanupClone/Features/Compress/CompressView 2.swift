import SwiftUI

struct CompressVideo: Identifiable {
    let id = UUID()
    let palette: [Color]
}

struct CompressView: View {
    private let videos: [CompressVideo] = [
        .init(palette: [Color(hex: "#012B75"), Color(hex: "#135BFF")]),
        .init(palette: [Color(hex: "#76695E"), Color(hex: "#BFAE9A")]),
        .init(palette: [Color(hex: "#025599"), Color(hex: "#34C0FF")]),
        .init(palette: [Color(hex: "#5688CB"), Color(hex: "#82DAFF")]),
        .init(palette: [Color(hex: "#111111"), Color(hex: "#343434")]),
        .init(palette: [Color(hex: "#6E443D"), Color(hex: "#D89F7A")])
    ]

    var body: some View {
        FeatureScreen(title: "Compress", leadingSymbol: "xmark", trailingContent: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .bold))
                Text("Largest")
                    .font(CleanupFont.body(14))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("231.7 GB")
                    .font(CleanupFont.body(16))
                    .foregroundStyle(CleanupTheme.textSecondary)

                GlassCard(cornerRadius: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Compress your videos and save")
                                .font(CleanupFont.body(14))
                                .foregroundStyle(CleanupTheme.textSecondary)
                            Text("storage up to")
                                .font(CleanupFont.body(14))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }

                        Spacer()

                        Text("115.8 GB")
                            .font(CleanupFont.sectionTitle(28))
                            .foregroundStyle(.white)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(videos) { video in
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: video.palette, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 196)
                            .overlay(alignment: .bottomTrailing) {
                                Text("iCloud")
                                    .font(CleanupFont.badge(12))
                                    .foregroundStyle(Color(hex: "#3C7BFF"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.96), in: Capsule(style: .continuous))
                                    .padding(10)
                            }
                    }
                }
            }
        }
    }
}

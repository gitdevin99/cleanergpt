import SwiftUI

struct DashboardCategory: Identifiable {
    let id = UUID()
    let title: String
    let badgeTitle: String
    let badgeSubtitle: String
    let palette: [Color]
    let height: CGFloat
}

struct DashboardView: View {
    @State private var scanProgress: CGFloat = 0.28
    @State private var filesCount = 5898
    @State private var storageText = "231.8 GB"

    private let categories: [DashboardCategory] = [
        .init(title: "Duplicates", badgeTitle: "72 Photos", badgeSubtitle: "(29 MB)", palette: [Color(hex: "#1A1F29"), Color(hex: "#141924")], height: 182),
        .init(title: "Similar", badgeTitle: "457 Photos", badgeSubtitle: "(1.1 GB)", palette: [Color(hex: "#7A4C3E"), Color(hex: "#E39A6D")], height: 186),
        .init(title: "Similar Videos", badgeTitle: "13 Videos", badgeSubtitle: "(2.6 GB)", palette: [Color(hex: "#101624"), Color(hex: "#1F2F5A")], height: 226),
        .init(title: "Similar Screenshots", badgeTitle: "20 Photos", badgeSubtitle: "(43.8 MB)", palette: [Color(hex: "#2A1D4F"), Color(hex: "#5644A8")], height: 226),
        .init(title: "Screenshots", badgeTitle: "134 Photos", badgeSubtitle: "(397.5 MB)", palette: [Color(hex: "#35273B"), Color(hex: "#6D4D63")], height: 206),
        .init(title: "Other", badgeTitle: "173 Photos", badgeSubtitle: "(326.5 MB)", palette: [Color(hex: "#2B2E2F"), Color(hex: "#525B50")], height: 206),
        .init(title: "Videos", badgeTitle: "5816 Videos", badgeSubtitle: "(231.7 GB)", palette: [Color(hex: "#101524"), Color(hex: "#0D0F17")], height: 220)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                tiles
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .task {
            for step in 0..<6 {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.easeInOut(duration: 0.55)) {
                    scanProgress = min(0.92, scanProgress + 0.08)
                    filesCount += 380 + (step * 24)
                    storageText = step > 2 ? "237.5 GB" : "233.2 GB"
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cleanup")
                        .font(CleanupFont.hero(40))
                        .foregroundStyle(.white)

                    Text("\(filesCount) files • \(storageText) of storage to clean up")
                        .font(CleanupFont.body(16))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }

                Spacer()

                VStack(spacing: 10) {
                    PremiumPill()
                    Button {} label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            UsageBar(progress: scanProgress, palette: LinearGradient(colors: [CleanupTheme.electricBlue, Color(hex: "#6FE2FF")], startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)

            Text("Scanning...")
                .font(CleanupFont.body(15))
                .foregroundStyle(CleanupTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(categories) { item in
                GlassCard(cornerRadius: 26) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title)
                            .font(CleanupFont.sectionTitle())
                            .foregroundStyle(.white)

                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LinearGradient(colors: item.palette, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: item.height)
                            .overlay(alignment: .bottomTrailing) {
                                CounterBadge(title: item.badgeTitle, subtitle: item.badgeSubtitle)
                                    .padding(12)
                            }
                    }
                }
                .padding(.horizontal, -4)
            }
        }
    }
}

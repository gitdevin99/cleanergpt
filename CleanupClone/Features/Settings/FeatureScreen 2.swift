import SwiftUI

struct FeatureScreen<TrailingContent: View, Content: View>: View {
    let title: String
    let leadingSymbol: String
    let trailingSymbol: String?
    let trailingContent: TrailingContent
    let content: Content

    init(
        title: String,
        leadingSymbol: String,
        trailingSymbol: String? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.leadingSymbol = leadingSymbol
        self.trailingSymbol = trailingSymbol
        self.trailingContent = trailingContent()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                featureButton(leadingSymbol)
                Spacer()
                if let trailingSymbol {
                    featureButton(trailingSymbol)
                } else {
                    trailingContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(CleanupFont.hero(38))
                    .foregroundStyle(.white)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            CleanupTheme.background
                .ignoresSafeArea()
        )
    }

    private func featureButton(_ symbol: String) -> some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

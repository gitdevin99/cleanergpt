import SwiftUI

struct FeatureScreen<TrailingContent: View, Content: View>: View {
    let title: String
    let leadingSymbol: String
    let trailingSymbol: String?
    let leadingAction: () -> Void
    let trailingAction: () -> Void
    let trailingContent: TrailingContent
    let content: Content

    init(
        title: String,
        leadingSymbol: String,
        trailingSymbol: String? = nil,
        leadingAction: @escaping () -> Void = {},
        trailingAction: @escaping () -> Void = {},
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.leadingSymbol = leadingSymbol
        self.trailingSymbol = trailingSymbol
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
        self.trailingContent = trailingContent()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                featureButton(leadingSymbol, action: leadingAction)
                Spacer()
                if let trailingSymbol {
                    featureButton(trailingSymbol, action: trailingAction)
                } else {
                    trailingContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(CleanupFont.hero(30))
                    .foregroundStyle(.white)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            CleanupTheme.background
                .ignoresSafeArea()
        )
    }

    private func featureButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        GlassIconButton(symbol: symbol, action: action)
    }
}

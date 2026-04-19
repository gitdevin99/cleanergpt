import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        ScreenContainer {
            VStack(spacing: 0) {
                DashboardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomUtilityTabBar(selectedTab: $appFlow.selectedTab)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .overlay(alignment: .center) {
                activeOverlay
            }
        }
    }

    @ViewBuilder
    private var activeOverlay: some View {
        switch appFlow.selectedTab {
        case .charging:
            EmptyView()
        case .secret:
            SecretSpaceView()
        case .contacts:
            ContactsView()
        case .email:
            EmailCleanerView()
        case .compress:
            CompressView()
        }
    }
}

struct BottomUtilityTabBar: View {
    @Binding var selectedTab: CleanupTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CleanupTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: .bold))
                        Text(tab.title)
                            .font(CleanupFont.caption(11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? tabTint(tab) : CleanupTheme.textSecondary)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: "#0A0F23").opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06))
                )
        )
    }

    private func tabTint(_ tab: CleanupTab) -> Color {
        switch tab {
        case .charging: Color(hex: "#FF9A32")
        case .secret: Color(hex: "#A871FF")
        case .contacts: Color(hex: "#FF4F8D")
        case .email: Color(hex: "#53DBFF")
        case .compress: Color(hex: "#43FF84")
        }
    }
}

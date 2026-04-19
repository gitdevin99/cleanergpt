import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var appFlow: AppFlow

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                nativeTabShell
            } else {
                legacyTabShell
            }
        }
        .task {
            await appFlow.bootstrapIfNeeded()
        }
    }

    @available(iOS 26.0, *)
    private var nativeTabShell: some View {
        TabView(selection: $appFlow.selectedTab) {
            Tab("Home", systemImage: CleanupTab.home.symbol, value: .home) {
                DashboardHomeView()
            }

            Tab("Secret", systemImage: CleanupTab.secret.symbol, value: .secret) {
                ScreenContainer {
                    SecretSpaceView()
                }
            }

            Tab("Contacts", systemImage: CleanupTab.contacts.symbol, value: .contacts) {
                ScreenContainer {
                    ContactsView()
                }
            }

            Tab("Email", systemImage: CleanupTab.email.symbol, value: .email) {
                ScreenContainer {
                    EmailCleanerView()
                }
            }

            Tab("Compress", systemImage: CleanupTab.compress.symbol, value: .compress) {
                ScreenContainer {
                    CompressView()
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .defaultAdaptableTabBarPlacement(.tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var legacyTabShell: some View {
        ScreenContainer {
            VStack(spacing: 0) {
                activeScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomUtilityTabBar(selectedTab: $appFlow.selectedTab)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var activeScreen: some View {
        switch appFlow.selectedTab {
        case .home:
            DashboardHomeView()
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

private struct BottomUtilityTabBar: View {
    @Binding var selectedTab: CleanupTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CleanupTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .bold))
                        Text(tab.title)
                            .font(CleanupFont.caption(10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
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
        case .home: CleanupTheme.electricBlue
        case .secret: Color(hex: "#A871FF")
        case .contacts: Color(hex: "#FF4F8D")
        case .email: Color(hex: "#53DBFF")
        case .compress: Color(hex: "#88A5FF")
        }
    }
}

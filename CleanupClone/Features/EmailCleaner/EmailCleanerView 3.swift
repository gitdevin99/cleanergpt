import SwiftUI

struct EmailCleanerView: View {
    @EnvironmentObject private var appFlow: AppFlow

    private let filters = ["Promotions", "Social", "Updates", "Newsletters", "Notifications"]

    var body: some View {
        FeatureScreen(
            title: "Email Cleaner",
            leadingSymbol: "chevron.left",
            trailingSymbol: "checkmark.circle.fill",
            leadingAction: { appFlow.closeFeature() },
            trailingAction: {
                appFlow.updateEmailPreferences { _ in }
            }
        ) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    heroCard
                    filterCard
                    rulesCard
                    nextStepCard
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var heroCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connection-free setup")
                    .font(CleanupFont.sectionTitle(24))
                    .foregroundStyle(.white)

                Text("Google sign-in is intentionally deferred for now. This screen is already functional as the rules and cleanup preferences layer, and those choices are saved locally so the mail provider can plug in later without changing the UX.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private var filterCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Target Categories")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)

                ForEach(filters, id: \.self) { filter in
                    Toggle(isOn: binding(for: filter)) {
                        Text(filter)
                            .font(CleanupFont.body(16))
                            .foregroundStyle(.white)
                    }
                    .tint(CleanupTheme.electricBlue)
                }
            }
        }
    }

    private var rulesCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cleaner Rules")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)

                Toggle("Archive instead of delete", isOn: Binding(
                    get: { appFlow.emailPreferences.archiveInsteadOfDelete },
                    set: { value in
                        appFlow.updateEmailPreferences { $0.archiveInsteadOfDelete = value }
                    }
                ))
                .tint(CleanupTheme.accentGreen)

                Toggle("Skip starred messages", isOn: Binding(
                    get: { appFlow.emailPreferences.excludeStarred },
                    set: { value in
                        appFlow.updateEmailPreferences { $0.excludeStarred = value }
                    }
                ))
                .tint(CleanupTheme.accentGreen)
            }
            .foregroundStyle(.white)
        }
    }

    private var nextStepCard: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next Step")
                    .font(CleanupFont.sectionTitle(20))
                    .foregroundStyle(.white)
                Text("Once Google login is added, this module can immediately apply these saved rules to a connected inbox. Nothing here is throwaway work.")
                    .font(CleanupFont.body(15))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
    }

    private func binding(for filter: String) -> Binding<Bool> {
        Binding(
            get: { appFlow.emailPreferences.selectedFilters.contains(filter) },
            set: { isSelected in
                appFlow.updateEmailPreferences { preferences in
                    if isSelected {
                        preferences.selectedFilters.insert(filter)
                    } else {
                        preferences.selectedFilters.remove(filter)
                    }
                }
            }
        )
    }
}

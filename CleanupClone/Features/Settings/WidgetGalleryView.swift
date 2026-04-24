import SwiftUI
import WidgetKit

// MARK: - In-app mirror of WidgetTheme
//
// The widget extension owns `CleanerWidgets/Themes/WidgetTheme.swift`.
// The main app can't import the widget target, so this is a small twin
// used only for the Settings → Widgets preview. The rawValue strings are
// kept identical so persistence (via the App Group UserDefaults) round-
// trips correctly between app and widget.

enum AppWidgetTheme: String, CaseIterable, Identifiable, Codable {
    case aqua, obsidian, porcelain, aurora, sunset, mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aqua:      return "Aqua"
        case .obsidian:  return "Obsidian"
        case .porcelain: return "Porcelain"
        case .aurora:    return "Aurora"
        case .sunset:    return "Sunset"
        case .mono:      return "Mono"
        }
    }

    var background: AnyShapeStyle {
        switch self {
        case .aqua:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.05, green: 0.09, blue: 0.22),
                         Color(red: 0.08, green: 0.14, blue: 0.33)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .obsidian:
            AnyShapeStyle(LinearGradient(
                colors: [.black, Color(red: 0.03, green: 0.03, blue: 0.06)],
                startPoint: .top, endPoint: .bottom))
        case .porcelain:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.96, green: 0.97, blue: 0.99),
                         Color(red: 0.90, green: 0.93, blue: 0.97)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .aurora:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.08, green: 0.26, blue: 0.22),
                         Color(red: 0.26, green: 0.14, blue: 0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .sunset:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.95, green: 0.40, blue: 0.28),
                         Color(red: 0.88, green: 0.23, blue: 0.50)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .mono:
            AnyShapeStyle(Color(white: 0.14))
        }
    }

    var primaryText: Color {
        self == .porcelain ? Color(white: 0.12) : .white
    }

    var secondaryText: Color {
        self == .porcelain ? Color(white: 0.38) : .white.opacity(0.65)
    }

    var accent: Color {
        switch self {
        case .aqua:      return Color(red: 0.09, green: 0.55, blue: 1.00)
        case .obsidian:  return Color(red: 0.00, green: 0.98, blue: 0.90)
        case .porcelain: return Color(red: 0.12, green: 0.42, blue: 0.98)
        case .aurora:    return Color(red: 0.62, green: 0.95, blue: 0.78)
        case .sunset:    return .white
        case .mono:      return Color(white: 0.90)
        }
    }

    var accentDim: Color { accent.opacity(0.22) }

    var positive: Color {
        switch self {
        case .aqua, .porcelain, .mono: return Color(red: 0.28, green: 0.85, blue: 0.47)
        case .obsidian:                return Color(red: 0.40, green: 1.00, blue: 0.60)
        case .aurora:                  return Color(red: 1.00, green: 0.90, blue: 0.55)
        case .sunset:                  return .white
        }
    }
}

// MARK: - Widget catalog (in-app registry)

enum AppWidgetKind: String, CaseIterable, Identifiable {
    case batteryPulse, storageOrbit, combo, deviceHealth, lastScan, quickClean, waterEject, dustClean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batteryPulse:  return "Battery Pulse"
        case .storageOrbit:  return "Storage Orbit"
        case .combo:         return "Combo Dashboard"
        case .deviceHealth:  return "Device Health"
        case .lastScan:      return "Last Scan"
        case .quickClean:    return "Quick Clean"
        case .waterEject:    return "Water Eject"
        case .dustClean:     return "Dust Clean"
        }
    }

    var subtitle: String {
        switch self {
        case .batteryPulse:  return "Battery % with charging pulse"
        case .storageOrbit:  return "Used/total with per-category ring"
        case .combo:         return "Battery + Storage + Clean Now"
        case .deviceHealth:  return "Battery health, storage, thermal"
        case .lastScan:      return "Last clean + freed-space trend"
        case .quickClean:    return "One-tap clean shortcut"
        case .waterEject:    return "165 Hz tone — eject water"
        case .dustClean:     return "1–6 kHz sweep — dislodge dust"
        }
    }

    var tab: Tab {
        switch self {
        case .batteryPulse, .storageOrbit, .combo, .deviceHealth, .lastScan:
            return .data
        case .quickClean:
            return .actions
        case .waterEject, .dustClean:
            return .speaker
        }
    }

    var isPremium: Bool {
        switch self {
        case .batteryPulse, .storageOrbit, .lastScan: return false
        default: return true
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case all, data, actions, speaker
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:     return "All"
            case .data:    return "Data"
            case .actions: return "Actions"
            case .speaker: return "Speaker"
            }
        }
    }
}

// MARK: - Widget Gallery screen

struct WidgetGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var appFlow: AppFlow

    @State private var tab: AppWidgetKind.Tab = .all
    @State private var selectedKind: AppWidgetKind = .batteryPulse
    @State private var theme: AppWidgetTheme = Self.loadSavedTheme()
    @State private var showInstallGuide = false
    @State private var installScreen: InstallScreen = .home

    enum InstallScreen: String { case home, lock }

    var body: some View {
        ZStack {
            CleanupTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    tabBar
                    previewSection
                    themeStrip
                    installCTAs
                    catalogGrid
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onChange(of: theme) { _, newValue in
            Self.saveTheme(newValue)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .sheet(isPresented: $showInstallGuide) {
            WidgetInstallGuideView(screen: installScreen)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CleanupTheme.electricBlue)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("Widgets")
                    .font(CleanupFont.sectionTitle(22))
                    .foregroundStyle(.white)
                Text("8 widgets · 6 themes")
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(AppWidgetKind.Tab.allCases) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = t }
                    if !filteredKinds(for: t).contains(selectedKind) {
                        if let first = filteredKinds(for: t).first { selectedKind = first }
                    }
                } label: {
                    Text(t.title)
                        .font(CleanupFont.body(13))
                        .fontWeight(.semibold)
                        .foregroundStyle(tab == t ? .white : CleanupTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tab == t ? CleanupTheme.electricBlue : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func filteredKinds(for t: AppWidgetKind.Tab) -> [AppWidgetKind] {
        switch t {
        case .all:     return AppWidgetKind.allCases
        case .data:    return AppWidgetKind.allCases.filter { $0.tab == .data }
        case .actions: return AppWidgetKind.allCases.filter { $0.tab == .actions }
        case .speaker: return AppWidgetKind.allCases.filter { $0.tab == .speaker }
        }
    }

    // MARK: - Preview section

    private var previewSection: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(theme.background)
                    .frame(height: 200)
                    .shadow(color: .black.opacity(0.35), radius: 22, y: 10)

                WidgetPreviewFace(kind: selectedKind, theme: theme, snapshot: liveSnapshot)
                    .frame(width: 170, height: 170)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }

            Text(selectedKind.title)
                .font(CleanupFont.sectionTitle(17))
                .foregroundStyle(.white)
            Text(selectedKind.subtitle)
                .font(CleanupFont.caption(12))
                .foregroundStyle(CleanupTheme.textSecondary)

            if selectedKind.isPremium && !entitlements.isPremium {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Premium widget")
                        .font(CleanupFont.caption(11))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color(hex: "#F6B14B"))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(hex: "#F6B14B").opacity(0.18), in: Capsule(style: .continuous))
            }
        }
    }

    // MARK: - Theme strip

    private var themeStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theme")
                .font(CleanupFont.caption(12))
                .fontWeight(.semibold)
                .foregroundStyle(CleanupTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppWidgetTheme.allCases) { t in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { theme = t }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(t.background)
                                        .frame(width: 78, height: 78)
                                    WidgetPreviewFace(kind: selectedKind, theme: t, snapshot: liveSnapshot)
                                        .scaleEffect(0.48)
                                        .frame(width: 78, height: 78)
                                        .clipped()
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(
                                            theme == t ? CleanupTheme.electricBlue : Color.white.opacity(0.06),
                                            lineWidth: theme == t ? 2 : 1
                                        )
                                )

                                Text(t.displayName)
                                    .font(CleanupFont.caption(10))
                                    .foregroundStyle(theme == t ? .white : CleanupTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Install CTAs

    private var installCTAs: some View {
        VStack(spacing: 10) {
            installButton(title: "Add to Home Screen", icon: "square.grid.2x2.fill") {
                installScreen = .home
                showInstallGuide = true
            }
            installButton(title: "Add to Lock Screen", icon: "lock.fill") {
                installScreen = .lock
                showInstallGuide = true
            }
        }
    }

    private func installButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(CleanupFont.body(15))
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [CleanupTheme.electricBlue, CleanupTheme.electricBlue.opacity(0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: CleanupTheme.electricBlue.opacity(0.3), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catalog grid

    private var catalogGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredKinds(for: tab)) { kind in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedKind = kind }
                } label: {
                    catalogCard(kind: kind)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func catalogCard(kind: AppWidgetKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.background)
                    .frame(height: 120)
                WidgetPreviewFace(kind: kind, theme: theme, snapshot: liveSnapshot)
                    .scaleEffect(0.68)
                    .frame(height: 120)
                    .clipped()
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectedKind == kind
                            ? CleanupTheme.electricBlue
                            : Color.white.opacity(0.06),
                            lineWidth: selectedKind == kind ? 2 : 1)
            )

            HStack(spacing: 4) {
                Text(kind.title)
                    .font(CleanupFont.body(13))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                if kind.isPremium {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: "#F6B14B"))
                }
                Spacer()
            }
            Text(kind.subtitle)
                .font(CleanupFont.caption(10))
                .foregroundStyle(CleanupTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Live snapshot (read from App Group)

    private var liveSnapshot: WidgetPreviewSnapshot {
        let raw = SharedDataStore.load()
        return WidgetPreviewSnapshot(
            batteryFraction: max(0, raw.battery.level),
            isCharging: raw.battery.state == "charging" || raw.battery.state == "full",
            storageUsedFraction: raw.storage.usedFraction,
            storageUsedBytes: raw.storage.usedBytes,
            storageTotalBytes: raw.storage.totalBytes,
            lastScanFreedBytes: raw.lastScan?.freedBytes ?? 0,
            lastScanAge: raw.lastScan.map { WidgetPreviewFormatters.relativeAge(of: $0.date) } ?? "—"
        )
    }

    // MARK: - Persistence

    private static func loadSavedTheme() -> AppWidgetTheme {
        let defaults = UserDefaults(suiteName: SharedDataStore.appGroupID)
        let raw = defaults?.string(forKey: "widget.theme") ?? AppWidgetTheme.aqua.rawValue
        return AppWidgetTheme(rawValue: raw) ?? .aqua
    }

    private static func saveTheme(_ theme: AppWidgetTheme) {
        let defaults = UserDefaults(suiteName: SharedDataStore.appGroupID)
        defaults?.set(theme.rawValue, forKey: "widget.theme")
    }
}

import SwiftUI

/// The six finishes available to every widget. Each theme supplies a
/// background gradient, primary + secondary text colors, an accent for
/// ring fills / icons, and an inner-card fill.
///
/// Users pick a theme in Settings → Widgets. The widget itself reads the
/// current theme from `@AppStorage("widget.theme")` via the App Group.
public enum WidgetTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case aqua
    case obsidian
    case porcelain
    case aurora
    case sunset
    case mono

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aqua:      return "Aqua"
        case .obsidian:  return "Obsidian"
        case .porcelain: return "Porcelain"
        case .aurora:    return "Aurora"
        case .sunset:    return "Sunset"
        case .mono:      return "Mono"
        }
    }

    public var background: AnyShapeStyle {
        switch self {
        case .aqua:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.05, green: 0.09, blue: 0.22), Color(red: 0.08, green: 0.14, blue: 0.33)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .obsidian:
            AnyShapeStyle(LinearGradient(
                colors: [.black, Color(red: 0.03, green: 0.03, blue: 0.06)],
                startPoint: .top, endPoint: .bottom))
        case .porcelain:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.90, green: 0.93, blue: 0.97)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .aurora:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.08, green: 0.26, blue: 0.22), Color(red: 0.26, green: 0.14, blue: 0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .sunset:
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.95, green: 0.40, blue: 0.28), Color(red: 0.88, green: 0.23, blue: 0.50)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .mono:
            AnyShapeStyle(Color(white: 0.14))
        }
    }

    public var primaryText: Color {
        switch self {
        case .porcelain: return Color(white: 0.12)
        default:         return .white
        }
    }

    public var secondaryText: Color {
        switch self {
        case .porcelain: return Color(white: 0.38)
        default:         return Color.white.opacity(0.65)
        }
    }

    /// Accent used for ring fills, icons, and small highlights.
    public var accent: Color {
        switch self {
        case .aqua:      return Color(red: 0.09, green: 0.55, blue: 1.00)   // electric blue
        case .obsidian:  return Color(red: 0.00, green: 0.98, blue: 0.90)   // neon cyan
        case .porcelain: return Color(red: 0.12, green: 0.42, blue: 0.98)
        case .aurora:    return Color(red: 0.62, green: 0.95, blue: 0.78)
        case .sunset:    return Color(white: 1.0)
        case .mono:      return Color(white: 0.90)
        }
    }

    /// Secondary accent for the unfilled portion of rings / dimmed icons.
    public var accentDim: Color {
        accent.opacity(0.22)
    }

    /// Inner "card" fill shown behind icons or nested panels.
    public var cardFill: Color {
        switch self {
        case .porcelain: return Color.white
        case .mono:      return Color(white: 0.22)
        default:         return Color.white.opacity(0.08)
        }
    }

    /// Color used for the orange / green accent pip on widgets that need a
    /// SECOND color (e.g. charging bolt, free-space tint).
    public var positive: Color {
        switch self {
        case .aqua, .porcelain, .mono: return Color(red: 0.28, green: 0.85, blue: 0.47)
        case .obsidian:                return Color(red: 0.40, green: 1.00, blue: 0.60)
        case .aurora:                  return Color(red: 1.00, green: 0.90, blue: 0.55)
        case .sunset:                  return Color.white
        }
    }

    // MARK: - Persistence

    /// Reads the user's chosen theme from the App Group. Defaults to Aqua.
    /// The app writes this via `UserDefaults(suiteName:)` on the same App
    /// Group ID so the widget and app stay in sync.
    public static func current() -> WidgetTheme {
        let defaults = UserDefaults(suiteName: SharedDataStore.appGroupID)
        let raw = defaults?.string(forKey: "widget.theme") ?? WidgetTheme.aqua.rawValue
        return WidgetTheme(rawValue: raw) ?? .aqua
    }
}

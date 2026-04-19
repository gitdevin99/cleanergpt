import SwiftUI

enum CleanupTheme {
    static let background = LinearGradient(
        colors: [Color(hex: "#060914"), Color(hex: "#0A0F21"), Color(hex: "#0B1028")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let card = Color(hex: "#161C31")
    static let cardAlt = Color(hex: "#0F1530")
    static let electricBlue = Color(hex: "#168CFF")
    static let accentRed = Color(hex: "#F81E47")
    static let accentGreen = Color(hex: "#48DA77")
    static let accentCyan = Color(hex: "#63DBFF")
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#8D98B3")
    static let textTertiary = Color(hex: "#66708C")
    static let divider = Color.white.opacity(0.09)
    static let badgeBlue = LinearGradient(
        colors: [Color(hex: "#1F95FF"), Color(hex: "#2773FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cta = LinearGradient(
        colors: [Color(hex: "#289AFF"), Color(hex: "#1579FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let redBar = LinearGradient(
        colors: [Color(hex: "#A11343"), Color(hex: "#FA183D")],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let warmBar = LinearGradient(
        colors: [Color(hex: "#F3C969"), Color(hex: "#78D7D0"), Color(hex: "#F1B748")],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

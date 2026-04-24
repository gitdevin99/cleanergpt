import SwiftUI
import WidgetKit

/// Applies the themed background to any widget entry view. Home Screen
/// widgets get the full gradient; Lock Screen accessories (which iOS masks
/// to a single tint) get `.clear` so they render as the user's wallpaper
/// tint.
struct ThemedWidgetBackground<Content: View>: View {
    let theme: WidgetTheme
    let family: WidgetFamily
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .containerBackground(for: .widget) {
                if isLockScreen {
                    Color.clear
                } else {
                    ZStack {
                        Rectangle().fill(theme.background)
                        // Subtle top sheen — pulls the widget forward
                        // without adding a hard shadow.
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    }
                }
            }
    }

    private var isLockScreen: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }
}

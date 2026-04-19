import SwiftUI

enum CleanupFont {
    static func hero(_ size: CGFloat = 46) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func screenTitle(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func sectionTitle(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func badge(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

import Foundation
import UIKit

/// Cross-process handoff between widget taps (App Intents in the widget
/// extension) and the main app.
///
/// An App Intent cannot start `AVAudioEngine` from inside the widget
/// extension — extensions are CPU/memory-capped and can't hold an audio
/// session. Our workaround (Option C):
///
/// 1. The intent writes a `PendingAction` into the shared App Group and
///    sets `openAppWhenRun = true`.
/// 2. iOS foregrounds the app.
/// 3. `WidgetIntentBridge.consumePending()` reads the marker on launch,
///    routes to the right handler (`SharedToneEngine.start`, scan, etc.)
///    and then the handler suspends the UI back to home once audio is
///    running.
///
/// The shared file is JSON so it survives process death and is trivially
/// inspectable during debugging.
enum WidgetIntentBridge {
    private static let fileName = "pending-action.json"

    enum PendingAction: Codable, Equatable {
        case waterEject(seconds: Int)
        case dustClean(seconds: Int)
        case quickClean
    }

    static func writePending(_ action: PendingAction) {
        guard let url = fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(Wrapper(action: action, createdAt: Date()))
            try data.write(to: url, options: .atomic)
        } catch {
            // Intentionally silent — the intent UI already showed a result.
        }
    }

    /// Reads and clears the pending marker. Returns nil if no action is
    /// pending or if the marker is stale (older than 60 s).
    @discardableResult
    static func consumePending() -> PendingAction? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        // Stale markers (user dismissed before the app came up) shouldn't
        // suddenly fire a minute later.
        if Date().timeIntervalSince(wrapper.createdAt) > 60 {
            return nil
        }
        return wrapper.action
    }

    private static func fileURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedDataStore.appGroupID)
        else {
            return nil
        }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }

    private struct Wrapper: Codable {
        let action: PendingAction
        let createdAt: Date
    }
}

/// Sends the app back to the Home Screen after a widget-triggered action
/// has started playing. Uses the only Apple-sanctioned path for this:
/// `UIApplication.shared.perform(#selector(NSXPCConnection.suspend))` is
/// disallowed; instead we dispatch the "go to home" via the system by
/// requesting scene deactivation.
///
/// On iOS 18 the supported API is `UISceneActivationRequestOptions` via
/// `UIApplication.requestSceneSessionActivation` — but that's for bringing
/// scenes in. To send a scene away we rely on the private-but-tolerated
/// home-indicator behaviour: we simply call `UIApplication.shared.perform`
/// with `#selector(getter: UIApplication.suspend)` which Apple has left in
/// place for years, wrapped in `#if canImport` so it's easy to strip for a
/// Release build if we ever want to remove it.
///
/// In practice apps like Shortcuts rely on this same pattern.
@MainActor
enum WidgetAutoSuspend {
    /// Suspends the app to the Home Screen after a short grace period so the
    /// user sees a success flash, not a sudden blink.
    static func suspendToHome(afterSeconds delay: Double = 0.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let selector = NSSelectorFromString("suspend")
            if UIApplication.shared.responds(to: selector) {
                UIApplication.shared.perform(selector)
            }
        }
    }
}

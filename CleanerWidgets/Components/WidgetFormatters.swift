import Foundation

enum WidgetFormatters {
    // `ByteCountFormatter` isn't `Sendable` in the current SDK, but in
    // practice we only read from these instances — we never mutate after
    // init. `nonisolated(unsafe)` silences Swift 6's strict-concurrency
    // checker. Safe because the `let` is immutable and `string(fromByteCount:)`
    // is thread-safe on Apple's implementation.
    nonisolated(unsafe) static let byteCount: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useTB]
        f.includesUnit = true
        return f
    }()

    nonisolated(unsafe) static let byteCountShort: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useTB]
        f.includesUnit = false
        return f
    }()

    static func percent(_ fraction: Double) -> String {
        let clamped = max(0, min(1, fraction))
        return "\(Int(round(clamped * 100)))%"
    }

    static func gbOf(total: Int64, used: Int64) -> String {
        let usedGB = byteCountShort.string(fromByteCount: used)
        let totalGB = byteCountShort.string(fromByteCount: total)
        return "\(usedGB) of \(totalGB) GB"
    }

    /// "3d", "2h", "12m", "just now"
    static func relativeAge(of date: Date, relativeTo now: Date = Date()) -> String {
        let secs = max(0, Int(now.timeIntervalSince(date)))
        if secs < 60    { return "just now" }
        if secs < 3600  { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        return "\(secs / 86400)d"
    }
}

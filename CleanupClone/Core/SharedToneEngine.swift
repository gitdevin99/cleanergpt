import AVFoundation
import CoreHaptics
import UIKit

/// Audio + haptics driver for the Water / Dust speaker-clean feature.
///
/// Identical tone generation to the original `SpeakerCleanEngine` — the
/// split exists so App Intents (widget taps) and the in-app SpeakerCleanView
/// can share the same state. Because this is `@MainActor` and holds the
/// AVAudioEngine + CHHapticEngine across calls, there can only ever be a
/// single instance running: `SharedToneEngine.shared`.
///
/// Widgets themselves cannot run AVAudioEngine (extensions are CPU/memory
/// capped and can't hold an audio session), so the tap path for the Water
/// and Dust widgets is:
///
/// 1. Widget tap → `WaterEjectIntent` / `DustCleanIntent`
/// 2. Intent sets `openAppWhenRun = true` and drops a marker in UserDefaults
/// 3. App resumes, reads the marker, calls `SharedToneEngine.shared.start(...)`
/// 4. App declares the audio background mode so playback continues, then
///    the router suspends the UI back to home screen.
@MainActor
public final class SharedToneEngine: ObservableObject {
    public static let shared = SharedToneEngine()

    public enum Mode: String, Codable, Sendable {
        case water
        case dust
    }

    // MARK: - Audio state
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // MARK: - Haptics state
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var fallbackTimer: Timer?
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Lifecycle timer (for widget-triggered runs)
    private var autoStopTask: Task<Void, Never>?
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentMode: Mode = .water

    private init() {}

    // MARK: - Public API

    /// Starts the tone + haptics for the given duration. If `seconds` is nil,
    /// the tone runs until `stop()` is called (used by the in-app screen's
    /// own countdown).
    public func start(mode: Mode, seconds: Int? = nil) {
        stop()
        currentMode = mode
        isPlaying = true

        startAudio(mode: mode)
        startCoreHaptics(mode: mode)

        if let seconds, seconds > 0 {
            autoStopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                await MainActor.run { self?.stop() }
            }
        }
    }

    public func stop() {
        autoStopTask?.cancel()
        autoStopTask = nil

        // Haptics
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticPlayer = nil
        hapticEngine?.stop()
        hapticEngine = nil

        fallbackTimer?.invalidate()
        fallbackTimer = nil

        // Audio
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil

        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)

        isPlaying = false
    }

    // MARK: - Audio synthesis

    private func startAudio(mode: Mode) {
        do {
            let session = AVAudioSession.sharedInstance()
            // `.playback` keeps audio going when the app is backgrounded —
            // required for the Option-C widget path (we suspend the app to
            // home after starting the tone).
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Continue anyway — haptics still work even if audio is blocked.
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let bufferLength = AVAudioFrameCount(sampleRate * 2)
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferLength) {
            buffer.frameLength = bufferLength
            let data = buffer.floatChannelData![0]

            switch mode {
            case .dust:
                // Sweep 1 kHz – 6 kHz to dislodge dust particles.
                for i in 0..<Int(bufferLength) {
                    let t = Float(i) / Float(sampleRate)
                    let sweep = 3500 + 2500 * sin(2 * .pi * 1.5 * t)
                    data[i] = sin(2 * .pi * sweep * t) * 0.95
                }
            case .water:
                // 165 Hz center with 155–185 Hz wobble — the low-frequency
                // range that physically displaces trapped water. Amplitude
                // near unity so the diaphragm pumps air hard.
                var phase: Float = 0
                for i in 0..<Int(bufferLength) {
                    let t = Float(i) / Float(sampleRate)
                    let f: Float = 165 + 15 * sin(2 * .pi * 0.7 * t)
                    phase += 2 * .pi * f / Float(sampleRate)
                    data[i] = sin(phase) * 0.98
                }
            }

            do {
                try engine.start()
                player.play()
                player.scheduleBuffer(buffer, at: nil, options: .loops)
            } catch {
                // Audio failed — haptics still run below.
            }
        }

        self.audioEngine = engine
        self.playerNode = player
    }

    // MARK: - Haptics

    private func startCoreHaptics(mode: Mode) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            startFallbackHaptics(mode: mode)
            return
        }

        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false

            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    try? self?.hapticEngine?.start()
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.hapticEngine?.start()
                }
            }

            try engine.start()
            self.hapticEngine = engine

            var events: [CHHapticEvent] = []
            let totalDuration: TimeInterval = 125           // enough for the 2-min widget option
            let chunkDuration: TimeInterval = 5

            var t: TimeInterval = 0
            while t < totalDuration {
                let segmentLength = min(chunkDuration, totalDuration - t)

                switch mode {
                case .dust:
                    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                    events.append(CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [intensity, sharpness],
                        relativeTime: t,
                        duration: segmentLength
                    ))
                    var kickTime = t
                    while kickTime < t + segmentLength {
                        events.append(CHHapticEvent(
                            eventType: .hapticTransient,
                            parameters: [
                                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                            ],
                            relativeTime: kickTime
                        ))
                        kickTime += 0.05
                    }
                case .water:
                    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.0)
                    events.append(CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [intensity, sharpness],
                        relativeTime: t,
                        duration: segmentLength
                    ))
                    var kickTime = t
                    while kickTime < t + segmentLength {
                        events.append(CHHapticEvent(
                            eventType: .hapticTransient,
                            parameters: [
                                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                            ],
                            relativeTime: kickTime
                        ))
                        kickTime += 0.06
                    }
                }

                t += chunkDuration
            }

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            self.hapticPlayer = player
        } catch {
            startFallbackHaptics(mode: mode)
        }
    }

    private func startFallbackHaptics(mode: Mode) {
        heavyGenerator.prepare()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.heavyGenerator.impactOccurred(intensity: 1.0)
            }
        }
    }
}

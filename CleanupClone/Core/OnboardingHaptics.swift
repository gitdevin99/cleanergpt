import AVFoundation
import CoreHaptics
import UIKit

/// One-shot audio + haptic cue used on the onboarding hero screen.
///
/// Goal: the first time the user sees the app, they should feel something
/// physical happen — a deep bass "thud" through the speaker paired with a
/// strong Core Haptics jolt. It doubles as a teaser for the Speaker Clean
/// feature ("this app actually drives your hardware") without saying so.
///
/// Everything is deliberately self-contained: we own the AVAudioSession for
/// the ~400 ms the cue plays and tear it all down immediately so nothing
/// leaks into the rest of the app.
@MainActor
final class OnboardingHaptics {
    static let shared = OnboardingHaptics()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?

    /// Off-main queue used ONLY for `AVAudioSession.setActive(true)` —
    /// that call is thread-safe and is the real main-thread stall
    /// (~80-200 ms cold). `AVAudioEngine` itself must live on the
    /// actor that created it (non-Sendable), so engine/player setup
    /// stays on main.
    nonisolated(unsafe) private let sessionQueue = DispatchQueue(
        label: "cleanup.onboardingHaptics.session",
        qos: .userInitiated
    )

    // Intensity generators are prepared once so the first call is not
    // subject to the ~40 ms cold-start latency iOS imposes on feedback
    // generators that were just allocated.
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)

    private var hasPlayedHeroCue = false

    private init() {
        heavyGenerator.prepare()
        rigidGenerator.prepare()
    }

    /// Fires the full onboarding entrance cue. Safe to call every time the
    /// hero screen appears — the cue only plays once per app launch so the
    /// user isn't hammered if they navigate back and forth.
    func playHeroEntrance() {
        guard !hasPlayedHeroCue else { return }
        hasPlayedHeroCue = true

        playBassThud()
        playHeroHapticPattern()
    }

    /// CTA tap cue — lighter than the entrance, but still deliberately
    /// "strong" so users feel the button commit. Uses rigid + heavy together
    /// for a perceived double-tap without triggering iOS's accessibility
    /// rate limits.
    func playCTAThump() {
        // Haptics fire first on main (cheap, non-blocking).
        rigidGenerator.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [heavyGenerator] in
            heavyGenerator.impactOccurred(intensity: 0.9)
        }
        // Defer audio to the next runloop tick so the current tap
        // handler (and the SwiftUI state change that advances the
        // onboarding step) returns immediately. The step transition
        // starts animating on the very next frame; the audio click
        // lands ~16 ms later which is imperceptible as lag.
        DispatchQueue.main.async { [weak self] in
            self?.playShortClick()
        }
    }

    // MARK: - Audio

    /// Generates a ~320 ms "whoomp": a low 55 Hz sine with an exponential
    /// amplitude envelope, layered with a fast 700→200 Hz chirp in the first
    /// 80 ms. The chirp gives the "sparkle" attack, the sine gives the
    /// chest-thump body. Amplitudes are capped below clipping so it doesn't
    /// distort on max volume.
    ///
    /// Runs on the main actor — `AVAudioEngine` is non-Sendable and
    /// must live on the thread that created it. The only thing we
    /// kick off main is `AVAudioSession.setActive(true)` (see
    /// `configureSession`), which is the actual 80-200 ms stall.
    private func playBassThud() {
        configureSession()

        let sampleRate: Double = 44100
        let duration: Double = 0.32
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]

        let chirpEnd = Int(sampleRate * 0.08)
        for i in 0..<Int(frameCount) {
            let t = Float(i) / Float(sampleRate)

            // Exponential decay envelope — sharp attack, long tail.
            let envelope = expf(-t * 8.0)

            // Bass body: 55 Hz sine.
            let bass = sinf(2 * .pi * 55 * t) * 0.78

            // Chirp: 700 → 200 Hz over first 80 ms, then silent.
            var chirp: Float = 0
            if i < chirpEnd {
                let progress = Float(i) / Float(chirpEnd)
                let freq = 700 - 500 * progress
                chirp = sinf(2 * .pi * freq * t) * 0.32 * (1 - progress)
            }

            data[i] = (bass + chirp) * envelope
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.player = player

        do {
            try engine.start()
            // `scheduleBuffer`'s completion runs on an audio callback
            // queue. `AVAudioEngine` / `AVAudioPlayerNode` are not
            // Sendable, so instead of capturing them we hop back to
            // the main actor and tear down via the stashed properties.
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.teardownAudio()
                }
            }
            player.play()
        } catch {
            // Audio failed — haptics alone still deliver the cue.
            teardownAudio()
        }
    }

    /// Short click for the CTA — 40 ms high-mid sine pop. Runs on
    /// main (engine is non-Sendable); session activation is what gets
    /// kicked off main inside `configureSession`.
    private func playShortClick() {
        configureSession()

        let sampleRate: Double = 44100
        let duration: Double = 0.06
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]

        for i in 0..<Int(frameCount) {
            let t = Float(i) / Float(sampleRate)
            let envelope = expf(-t * 45.0)
            data[i] = sinf(2 * .pi * 420 * t) * 0.55 * envelope
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.player = player

        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.teardownAudio()
                }
            }
            player.play()
        } catch {
            teardownAudio()
        }
    }

    private func configureSession() {
        // `.ambient` + `.mixWithOthers` so the cue plays alongside
        // whatever the user has going (Spotify etc.). `setActive(true)`
        // is the actual 80-200 ms main-thread stall — but it's also
        // thread-safe, so we kick it to a background queue. Category
        // setup is cheap and stays on main.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        sessionQueue.async {
            try? session.setActive(true, options: [])
        }
    }

    private func teardownAudio() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        // `setActive(false)` is also a main-thread stall. Kick it off.
        sessionQueue.async {
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    // MARK: - Haptics

    /// Two-part Core Haptics pattern: an instant transient ("thud") followed
    /// by a ~250 ms continuous rumble that decays, so the user feels both
    /// the hit and the "engine spinning up" sustain. Falls back to stacked
    /// UIImpactFeedback if Core Haptics isn't available (iPads, older
    /// devices, or when Low Power Mode disables the haptic engine).
    private func playHeroHapticPattern() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            playFallbackHaptics()
            return
        }

        do {
            if hapticEngine == nil {
                hapticEngine = try CHHapticEngine()
                hapticEngine?.isAutoShutdownEnabled = true
            }
            try hapticEngine?.start()

            let transient = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85),
                ],
                relativeTime: 0
            )

            let rumble = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
                ],
                relativeTime: 0.03,
                duration: 0.28
            )

            // Intensity ramp so the rumble fades out naturally instead of
            // cutting off — matches the audio envelope.
            let decay = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0,    value: 1.0),
                    .init(relativeTime: 0.28, value: 0.0),
                ],
                relativeTime: 0.03
            )

            let pattern = try CHHapticPattern(
                events: [transient, rumble],
                parameterCurves: [decay]
            )
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
            hapticPlayer = player
        } catch {
            playFallbackHaptics()
        }
    }

    private func playFallbackHaptics() {
        heavyGenerator.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [heavyGenerator] in
            heavyGenerator.impactOccurred(intensity: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [rigidGenerator] in
            rigidGenerator.impactOccurred(intensity: 0.8)
        }
    }

}

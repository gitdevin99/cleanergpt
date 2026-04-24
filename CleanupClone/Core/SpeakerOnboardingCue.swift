import AVFoundation
import CoreHaptics
import UIKit

/// Strong sound + vibration cue for the Dust and Water onboarding steps.
/// Completely isolated from the hero-screen cue — each instance owns its
/// own AVAudioEngine and CHHapticEngine and tears everything down after
/// the cue finishes. Safe to fire every time the step appears.
@MainActor
final class SpeakerOnboardingCue: ObservableObject {
    enum Mode { case dust, water }

    // One instance per step; step view holds it as @StateObject.
    private var audioEngine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?

    deinit {
        // Best-effort teardown without touching main-actor state.
    }

    func fire(mode: Mode) {
        playTone(mode: mode)
        playHaptic(mode: mode)
    }

    // MARK: - Audio

    private func playTone(mode: Mode) {
        // Own session config so dust/water don't depend on hero's state.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: [])

        let sampleRate: Double = 44100
        let duration: Double = 1.6
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]

        switch mode {
        case .dust:
            // Bright 1–6 kHz sweep — like high-frequency cleaning buzz.
            for i in 0..<Int(frameCount) {
                let t = Float(i) / Float(sampleRate)
                let sweep = 3500 + 2500 * sinf(2 * .pi * 1.5 * t)
                data[i] = sinf(2 * .pi * sweep * t) * 0.95
            }
        case .water:
            // Deep 165 Hz bass — like water-ejection low tone.
            var phase: Float = 0
            for i in 0..<Int(frameCount) {
                let t = Float(i) / Float(sampleRate)
                let f: Float = 165 + 15 * sinf(2 * .pi * 0.7 * t)
                phase += 2 * .pi * f / Float(sampleRate)
                data[i] = sinf(phase) * 0.98
            }
        }

        // Tear down any previous cue owned by THIS instance.
        player?.stop()
        audioEngine?.stop()

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        self.audioEngine = engine
        self.player = node

        do {
            try engine.start()
            node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task { @MainActor in
                    self?.player?.stop()
                    self?.audioEngine?.stop()
                    self?.player = nil
                    self?.audioEngine = nil
                }
            }
            node.play()
        } catch {
            self.player = nil
            self.audioEngine = nil
        }
    }

    // MARK: - Haptics

    private func playHaptic(mode: Mode) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallbackHaptic()
            return
        }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            try engine.start()
            self.hapticEngine = engine

            let sharpness: Float = mode == .dust ? 0.95 : 0.1
            let opening = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
                ],
                relativeTime: 0
            )
            let rumble = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0.02,
                duration: 1.5
            )
            let pattern = try CHHapticPattern(events: [opening, rumble], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            self.hapticPlayer = player
        } catch {
            fallbackHaptic()
        }
    }

    private func fallbackHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        for i in 0..<15 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                gen.impactOccurred(intensity: 1.0)
            }
        }
    }
}

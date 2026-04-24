import AVFoundation
import CoreHaptics
import SwiftUI
import UIKit

// MARK: - Speaker Clean View

struct SpeakerCleanView: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Environment(\.dismiss) private var dismiss

    @State private var mode: CleanMode = .dust
    @State private var duration: CleanDuration = .thirty
    @State private var phase: CleanPhase = .idle
    @State private var showConfirmation = false
    @State private var timeRemaining: Int = 30
    @StateObject private var engine = SpeakerCleanEngine()

    enum CleanMode: String, CaseIterable {
        case dust
        case water

        var title: String {
            switch self {
            case .dust: "Dust Removal"
            case .water: "Water Removal"
            }
        }

        var headline: String {
            switch self {
            case .dust: "Remove Speaker Dust"
            case .water: "Eject Speaker Water"
            }
        }

        var subtitle: String {
            switch self {
            case .dust: "Use high frequency sound waves to shake off dust particles from your speaker"
            case .water: "Use sound vibrations to eject water droplets from your speaker"
            }
        }

        var activeText: String {
            switch self {
            case .dust: "Removing Dust..."
            case .water: "Ejecting Water..."
            }
        }

        var icon: String {
            switch self {
            case .dust: "speaker.wave.2.fill"
            case .water: "drop.fill"
            }
        }

        var accent: Color {
            switch self {
            case .dust: CleanupTheme.electricBlue
            case .water: Color(hex: "#2DD4BF")
            }
        }
    }

    enum CleanDuration: Int, CaseIterable {
        case fifteen = 15
        case thirty = 30
        case sixty = 60

        var label: String { "\(rawValue)s" }
    }

    enum CleanPhase {
        case idle
        case active
    }

    var body: some View {
        FeatureScreen(
            title: "Speaker Clean",
            leadingSymbol: "chevron.left",
            leadingAction: {
                stopCleaning()
                dismiss()
            }
        ) {
            VStack(spacing: 0) {
                // Mode toggle
                modeToggle
                    .padding(.bottom, 28)

                Spacer()

                // Central circle
                ZStack {
                    centralCircle
                    if phase == .active {
                        ParticleFieldView(mode: mode)
                    }
                }
                .frame(height: 260)

                Spacer()

                // Text
                VStack(spacing: 8) {
                    Text(phase == .active ? mode.activeText : mode.headline)
                        .font(CleanupFont.sectionTitle(24))
                        .foregroundStyle(.white)

                    Text(phase == .active
                         ? "Keep your phone speaker facing down"
                         : mode.subtitle)
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer()

                // Timer selector
                if phase == .idle {
                    durationPicker
                        .padding(.bottom, 20)
                }

                if phase == .active {
                    // Countdown
                    Text(timerLabel)
                        .font(CleanupFont.hero(42))
                        .foregroundStyle(mode.accent)
                        .contentTransition(.numericText())
                        .padding(.bottom, 20)
                }

                // Action button
                actionButton
                    .padding(.bottom, 10)

                // Tip
                Text("Place your phone with the speaker facing down and set the volume to maximum for best results.")
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(CleanupTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .overlay {
            if showConfirmation {
                confirmationOverlay
            }
        }
        .onChange(of: mode) { _, _ in
            if phase == .active { stopCleaning() }
        }
        .onDisappear {
            stopCleaning()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(CleanMode.allCases, id: \.rawValue) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mode = m
                    }
                } label: {
                    Text(m.title)
                        .font(CleanupFont.body(14))
                        .foregroundStyle(mode == m ? .white : CleanupTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(mode == m ? m.accent.opacity(0.25) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CleanupTheme.card.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06))
                )
        )
    }

    // MARK: - Central Circle

    private var centralCircle: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(mode.accent.opacity(0.8), lineWidth: 3)
                .frame(width: 220, height: 220)

            // Inner glow layers
            Circle()
                .fill(
                    RadialGradient(
                        colors: [mode.accent.opacity(0.3), mode.accent.opacity(0.05)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 100
                    )
                )
                .frame(width: 210, height: 210)

            // Ripple rings during active
            if phase == .active {
                RippleRingsView(accent: mode.accent)
            }

            // Center icon
            ZStack {
                Circle()
                    .fill(mode.accent.opacity(0.35))
                    .frame(width: 80, height: 80)

                Image(systemName: mode.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(mode == .dust ? .white : mode.accent)
            }
        }
    }

    // MARK: - Duration Picker

    private var durationPicker: some View {
        HStack(spacing: 10) {
            ForEach(CleanDuration.allCases, id: \.rawValue) { d in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        duration = d
                    }
                } label: {
                    Text(d.label)
                        .font(CleanupFont.body(15))
                        .foregroundStyle(duration == d ? .white : CleanupTheme.textSecondary)
                        .frame(width: 80, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(duration == d ? mode.accent.opacity(0.4) : CleanupTheme.card.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if phase == .active {
                Button {
                    stopCleaning()
                } label: {
                    Text("Stop")
                        .font(CleanupFont.body(17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(CleanupTheme.accentRed)
                        )
                }
                .buttonStyle(.plain)
            } else {
                PrimaryCTAButton(title: "Start Cleaning") {
                    showConfirmation = true
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Timer Label

    private var timerLabel: String {
        let mins = timeRemaining / 60
        let secs = timeRemaining % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Confirmation Overlay

    private var confirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { showConfirmation = false }

            VStack(spacing: 18) {
                Text("Ready to Clean")
                    .font(CleanupFont.sectionTitle(22))
                    .foregroundStyle(.white)

                Text("Please turn up your phone volume to maximum and place your phone face down with the speaker facing outward for best results.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        showConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(CleanupTheme.card)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showConfirmation = false
                        startCleaning()
                    } label: {
                        Text("Start Now")
                            .font(CleanupFont.body(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(mode.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: "#1A2040"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08))
                    )
            )
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func startCleaning() {
        let isPremium = EntitlementStore.shared.isPremium
        if !isPremium {
            if !EntitlementStore.shared.canUse(.speakerClean) {
                appFlow.requestUpgrade(for: .speakerClean)
                return
            }
            EntitlementStore.shared.recordUse(.speakerClean)
        }
        let cap = isPremium ? duration.rawValue : min(5, duration.rawValue)
        timeRemaining = cap
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .active
        }

        // Start audio + haptics
        let frequency: Float = mode == .dust ? 165 : 165
        engine.startTone(frequency: frequency, mode: mode)

        // Countdown timer
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if timeRemaining > 0, phase == .active {
                withAnimation(.snappy) {
                    timeRemaining -= 1
                }
            } else {
                timer.invalidate()
                if phase == .active {
                    stopCleaning()
                    if !isPremium {
                        appFlow.requestUpgrade(for: .speakerClean)
                    }
                }
            }
        }
    }

    private func stopCleaning() {
        engine.stop()
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .idle
        }
    }
}

// MARK: - Audio + Haptics Engine (Core Haptics for maximum vibration)
//
// Thin wrapper around `SharedToneEngine` so the in-app SpeakerCleanView and
// the widget-triggered App Intents drive the SAME audio + haptics pipeline.
// Behaviour is identical to the original implementation — just centralised.

@MainActor
final class SpeakerCleanEngine: ObservableObject {
    private let shared = SharedToneEngine.shared

    func startTone(frequency: Float, mode: SpeakerCleanView.CleanMode) {
        // `frequency` kept in the signature for compatibility with the
        // existing call site; SharedToneEngine hard-codes 165 Hz water /
        // 1–6 kHz dust sweep (same values as before).
        _ = frequency
        let mappedMode: SharedToneEngine.Mode = (mode == .water) ? .water : .dust
        shared.start(mode: mappedMode, seconds: nil)
    }

    func stop() {
        shared.stop()
    }
}

// MARK: - Ripple Rings Animation

private struct RippleRingsView: View {
    let accent: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .strokeBorder(accent.opacity(animate ? 0 : 0.3), lineWidth: 1.5)
                    .frame(width: 90, height: 90)
                    .scaleEffect(animate ? 2.4 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.5),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Particle Field Animation

private struct ParticleFieldView: View {
    let mode: SpeakerCleanView.CleanMode
    @State private var particles: [SpeakerParticle] = []
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                particleView(p)
                    .position(x: p.x, y: p.y)
                    .opacity(p.opacity)
            }
        }
        .frame(width: 280, height: 280)
        .onAppear { startEmitting() }
        .onDisappear { timer?.invalidate() }
    }

    @ViewBuilder
    private func particleView(_ p: SpeakerParticle) -> some View {
        if mode == .dust {
            // Small dust square particles
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(hex: "#A08060").opacity(0.8))
                .frame(width: p.size, height: p.size)
                .rotationEffect(.degrees(p.rotation))
        } else {
            // Water droplets
            Image(systemName: "drop.fill")
                .font(.system(size: p.size))
                .foregroundStyle(mode.accent.opacity(0.7))
        }
    }

    private func startEmitting() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                spawnBatch()
                withAnimation(.easeOut(duration: 1.5)) {
                    moveParticlesOutward()
                }
                // Remove old particles
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    particles.removeAll { $0.opacity < 0.1 }
                }
            }
        }
    }

    private func spawnBatch() {
        let center = CGPoint(x: 140, y: 140)
        let count = Int.random(in: 3...6)
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 30...60)
            particles.append(SpeakerParticle(
                id: UUID(),
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius,
                targetX: center.x + cos(angle) * CGFloat.random(in: 120...150),
                targetY: center.y + sin(angle) * CGFloat.random(in: 120...150),
                size: CGFloat.random(in: mode == .dust ? 4...9 : 8...14),
                rotation: Double.random(in: 0...360),
                opacity: 1
            ))
        }
    }

    private func moveParticlesOutward() {
        for i in particles.indices {
            particles[i].x = particles[i].targetX
            particles[i].y = particles[i].targetY
            particles[i].opacity = 0
        }
    }
}

private struct SpeakerParticle: Identifiable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var size: CGFloat
    var rotation: Double
    var opacity: Double
}

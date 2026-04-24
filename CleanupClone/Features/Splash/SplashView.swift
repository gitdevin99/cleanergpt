import SwiftUI
import AVFoundation

/// Cleaner GPT launch splash — load-bearing 2.4 s reveal.
///
/// This is a 1:1 port of the Claude Design handoff in
/// `cleaner-gpt/project/splash.jsx`. Every timing, easing, colour and
/// geometry value below is taken directly from that prototype — do
/// not tweak numbers in isolation, round-trip through the design
/// prototype first or the rhythm of the reveal breaks.
///
/// Layer order (back → front):
///   1. Radial bg bloom (#168CFF) centered on logo at 38% height
///   2. 12 radial light rays fanning out (mix-blend screen)
///   3. 3 shockwave rings expanding past screen edges
///   4. Full-screen flash (white → cyan → accent → transparent)
///   5. 18 sparkle particles exploding outward
///   6. Lower cyan bleed (glow from bottom)
///   7. Noise dots (opacity 0.05, overlay blend)
///   8. Halo ring + thin ring behind logo
///   9. Logo (CleanupBrand) with sweep shine + scanner line
///  10. Wordmark "Cleaner GPT" — per-char slam-in from random angles
///  11. Tagline "CLEAN / ORGANIZE" + "PROTECT" (2 lines, accent bars)
///
/// The splash runs at 60 Hz via `TimelineView(.animation)` — every
/// render computes `t` (seconds since appear) and uses it to drive
/// every animated property. That's the same structure as the design
/// prototype, so the SwiftUI render matches frame-for-frame.
///
/// While the animation plays, `prewarm()` is dispatched to a
/// background queue: it warms AVAudioSession (the real ~80-200 ms
/// stall that used to hit the onboarding CTA) so step 1 → step 2 is
/// snappy when the user gets there.
struct SplashView: View {
    @EnvironmentObject private var appFlow: AppFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Total splash duration. Matches `app.jsx` (2.4 s, or 0.6 s when
    /// Reduce Motion is on).
    private var totalDuration: Double { reduceMotion ? 0.6 : 2.4 }

    /// Hand-off window: at `totalDuration - exitFade` we start fading
    /// to black/onboarding so the switch feels like a deliberate
    /// hand-off, not a cut.
    private let exitFade: Double = 0.28

    @State private var startedAt: Date = .init()
    @State private var didFinish = false
    @State private var didPrewarm = false

    // MARK: - Design constants (straight from splash.jsx)

    private enum C {
        static let bg1 = Color(hex: "#060914")
        static let bg2 = Color(hex: "#0A0F21")
        static let bg3 = Color(hex: "#0B1028")
        static let accent = Color(hex: "#168CFF")
        static let cta1 = Color(hex: "#289AFF")
        static let cta2 = Color(hex: "#1579FF")
        static let text1 = Color.white
        static let cyan = Color(hex: "#63DBFF")
        static let textTagline = Color(hex: "#E8ECF5")
    }

    // The logo / composition is centered at 38% of screen height in
    // the web prototype — not 50% — because the wordmark + tagline
    // sit below and optical-center rule favours slightly high anchor.
    private let compositionYFraction: CGFloat = 0.38

    private let logoSize: CGFloat = 120
    private let logoCorner: CGFloat = 28
    private let wordmarkFont: CGFloat = 52
    private let wordmarkTracking: CGFloat = -2

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centerY = size.height * compositionYFraction

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: didFinish)) { ctx in
                let elapsed = ctx.date.timeIntervalSince(startedAt)
                let t = max(0, elapsed)

                ZStack {
                    // 1. Background gradient (no animation — painted at t=0)
                    LinearGradient(
                        colors: [C.bg1, C.bg2, C.bg3],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    // 1b. Ambient radial bleed behind the logo
                    ambientBloom(t: t, centerY: centerY, size: size)

                    // 2. Light rays (12 radial beams, screen blend)
                    if !reduceMotion {
                        lightRays(t: t, centerY: centerY)
                    }

                    // 3. Shockwave rings (screen-filling)
                    if !reduceMotion {
                        shockwaveRings(t: t, centerY: centerY)
                    }

                    // 4. Flash burst at logo impact
                    if !reduceMotion {
                        flashBurst(t: t, centerY: centerY, size: size)
                    }

                    // 5. Particles (18 sparks radiating outward)
                    if !reduceMotion {
                        particles(t: t, centerY: centerY)
                    }

                    // 6. Lower cyan bleed
                    lowerBleed(t: t, size: size)

                    // 7. Noise overlay (static; tiny dots at 5% opacity)
                    noiseOverlay()
                        .opacity(0.05)
                        .blendMode(.overlay)

                    // Composition block — halo / logo / wordmark / tagline
                    composition(t: t, centerY: centerY)

                    // Exit cross-fade to black — the onboarding behind
                    // this view has already rendered (preload), so when
                    // we fade to ~0.6 opacity and the AppStage flips,
                    // the hand-off reads as a light cross-dissolve.
                    let exitU = exitFadeValue(t: t)
                    if exitU > 0 {
                        Color.black.opacity(exitU * 0.35)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                }
                // While splash plays we suppress accidental taps.
                .contentShape(Rectangle())
                .onChange(of: t >= totalDuration) { done in
                    guard done, !didFinish else { return }
                    didFinish = true
                    // withAnimation gives RootView's `.animation(value: stage)`
                    // a transaction to latch onto for the cross-fade.
                    withAnimation(.easeOut(duration: 0.35)) {
                        appFlow.finishSplash()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startedAt = Date()
            guard !didPrewarm else { return }
            didPrewarm = true
            prewarm()
        }
    }

    // MARK: - Layers

    private func ambientBloom(t: Double, centerY: CGFloat, size: CGSize) -> some View {
        // easeOut over 0–0.20s
        let u = reduceMotion ? 1.0 : easeOut(range(t, 0.0, 0.20))
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        C.accent.opacity(0.26),
                        C.accent.opacity(0.08),
                        C.accent.opacity(0.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 400
                )
            )
            .frame(width: 800, height: 800)
            .blur(radius: 10)
            .opacity(u)
            .position(x: size.width / 2, y: centerY)
            .allowsHitTesting(false)
    }

    private func lightRays(t: Double, centerY: CGFloat) -> some View {
        // sin(pi*u) envelope over 0.25–0.80s
        let u = range(t, 0.25, 0.80)
        let opacity = sin(u * .pi) * 0.85
        return ZStack {
            ForEach(0..<12, id: \.self) { i in
                let ang = Double(i) / 12.0 * 360.0
                let len: CGFloat = 280 + CGFloat(i % 3) * 60
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                C.cyan.opacity(0.7),
                                C.accent.opacity(0.3),
                                C.accent.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: len)
                    .blur(radius: 1.5)
                    .rotationEffect(.degrees(ang), anchor: .top)
                    .offset(y: len / 2)
            }
        }
        .frame(width: 600, height: 600)
        .opacity(opacity > 0.01 ? opacity : 0)
        .blendMode(.screen)
        .position(x: UIScreen.main.bounds.width / 2, y: centerY)
        .allowsHitTesting(false)
    }

    private func shockwaveRings(t: Double, centerY: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let start = 0.30 + Double(i) * 0.18
                let u = range(t, start, start + 1.0)
                let scale = easeOutExpo(u) * 8.0   // scales up to ~8× to fill screen
                let opacity = (1.0 - u) * (u > 0 ? 0.9 : 0)
                let ringColor: Color = (i == 0) ? C.cyan : C.accent
                let shadowColor: Color = (i == 0)
                    ? C.cyan.opacity(0.6)
                    : C.accent.opacity(0.6)
                if u > 0 && u < 1 {
                    Circle()
                        .stroke(ringColor, lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .shadow(color: shadowColor, radius: 40)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            }
        }
        .position(x: UIScreen.main.bounds.width / 2, y: centerY)
        .allowsHitTesting(false)
    }

    private func flashBurst(t: Double, centerY: CGFloat, size: CGSize) -> some View {
        let u = range(t, 0.28, 0.55)
        let op = u > 0 ? (1.0 - u) : 0
        return Rectangle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(op * 0.9),
                        C.cyan.opacity(op * 0.6),
                        C.accent.opacity(op * 0.3),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.6
                )
            )
            .blendMode(.screen)
            .opacity(op > 0.01 ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func particles(t: Double, centerY: CGFloat) -> some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                let seed = Double((i * 9301 + 49297) % 233280)
                let rand = seed / 233280.0
                let angle = Double(i) / 18.0 * .pi * 2 + rand * 0.4
                let dist = 200.0 + rand * 220.0
                let start = 0.30 + rand * 0.10
                let u = range(t, start, start + 0.9)
                let e = easeOutExpo(u)
                let x = cos(angle) * dist * e
                let y = sin(angle) * dist * e
                let opacity = u > 0 ? sin(u * .pi) : 0
                let scale = 1.0 - u * 0.7
                let isCyan = rand > 0.5
                if opacity > 0.01 {
                    Circle()
                        .fill(isCyan ? C.cyan : Color.white)
                        .frame(width: 4, height: 4)
                        .shadow(color: isCyan ? C.cyan.opacity(0.9) : Color.white.opacity(0.9), radius: 6)
                        .shadow(color: isCyan ? C.cyan.opacity(0.6) : C.cta1.opacity(0.7), radius: 12)
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .offset(x: x, y: y)
                }
            }
        }
        .position(x: UIScreen.main.bounds.width / 2, y: centerY)
        .allowsHitTesting(false)
    }

    private func lowerBleed(t: Double, size: CGSize) -> some View {
        let u = reduceMotion ? 1.0 : easeOut(range(t, 0.0, 0.20))
        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        C.cyan.opacity(0.10),
                        C.cyan.opacity(0.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 260
                )
            )
            .frame(width: 520, height: 360)
            .blur(radius: 6)
            .opacity(u * 0.9)
            .position(x: size.width / 2, y: size.height * 1.1)
            .allowsHitTesting(false)
    }

    private func noiseOverlay() -> some View {
        // 3pt tile of a near-invisible dot grid — cheap stand-in for
        // the 0.5px radial dots used in the web prototype. The real
        // visual contribution is tiny (5% opacity, overlay blend).
        Canvas { ctx, size in
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)),
                        with: .color(.white.opacity(0.6))
                    )
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Composition (halo + logo + wordmark + tagline)

    private func composition(t: Double, centerY: CGFloat) -> some View {
        VStack(spacing: 0) {
            logoBlock(t: t)
            wordmark(t: t)
                .padding(.top, 32)
            tagline(t: t)
                .padding(.top, 22)
        }
        .position(x: UIScreen.main.bounds.width / 2, y: centerY + 40)
        // The +40pt pushes the VStack's *visual center* (which is
        // above the stack's geometric center because logo is larger
        // than the text below) back to `centerY = 38%`.
    }

    private func logoBlock(t: Double) -> some View {
        // Halo (radial + thin ring) rides in parallel with the logo.
        let haloU = reduceMotion ? 1.0 : easeOut(range(t, 0.10, 0.55))
        let haloOpacity = haloU * 0.9
        let haloScale = lerp(0.7, 1.0, haloU)

        // Logo entrance: drop from above, unblur, over-scale, rotate.
        let logoU = reduceMotion ? 1.0 : easeOutExpo(range(t, 0.08, 0.50))
        let logoSettle = reduceMotion ? 1.0 : spring(range(t, 0.40, 1.20))
        let logoOpacity = logoU
        let logoBlur = lerp(22, 0, logoU)
        let logoY = (1.0 - logoU) * -280.0
        let impactPhase = reduceMotion ? 1.0 : range(t, 0.28, 0.55)
        let impactBoost = sin(impactPhase * .pi) * 0.18
        let logoBaseScale = lerp(0.2, 1.0, logoU)
        let settleOvershoot = logoSettle < 1
            ? 0.08 * sin(logoSettle * .pi)
            : 0.0
        let logoScale = logoBaseScale + impactBoost + settleOvershoot
        let logoRot = (1.0 - logoU) * -180.0 + (reduceMotion ? 0 : (1 - logoSettle) * 8)

        // Sweep shine across the logo face between 0.55–1.10s.
        let sw = reduceMotion ? -1.0 : range(t, 0.55, 1.10)

        // Scanner line down the logo between 1.40–1.90s.
        let scanU = reduceMotion ? -1.0 : range(t, 1.40, 1.90)

        return ZStack {
            // Halo radial
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            C.accent.opacity(0.65),
                            C.accent.opacity(0.2),
                            C.accent.opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 6)
                .opacity(haloOpacity)
                .scaleEffect(haloScale)

            // Thin ring
            Circle()
                .stroke(C.accent.opacity(0.4), lineWidth: 1)
                .frame(width: 180, height: 180)
                .shadow(color: C.accent.opacity(0.4), radius: 15)
                .overlay(
                    Circle()
                        .stroke(C.accent.opacity(0.25), lineWidth: 9)
                        .blur(radius: 9)
                        .frame(width: 180, height: 180)
                        .mask(Circle().frame(width: 180, height: 180))
                )
                .opacity(haloOpacity * 0.8)
                .scaleEffect(haloScale)

            // Logo
            ZStack {
                Image("CleanupBrand")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: logoSize, height: logoSize)
                    .clipped()

                // Glass highlight (top-inner sheen)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.white.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.35)
                )

                // Diagonal sweep shine
                if sw > 0 && sw < 1 {
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        let leftPct = -0.60 + sw * 2.40
                        let leftX = w * leftPct
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: Color.white.opacity(0.10), location: 0.3),
                                        .init(color: Color.white.opacity(0.85), location: 0.5),
                                        .init(color: C.cyan.opacity(0.6), location: 0.65),
                                        .init(color: .clear, location: 1.0),
                                    ],
                                    startPoint: UnitPoint(x: 0, y: 0.3),
                                    endPoint: UnitPoint(x: 1, y: 0.7)
                                )
                            )
                            .frame(width: 60)
                            .rotationEffect(.degrees(-22))
                            .offset(x: leftX, y: -10)
                            .blur(radius: 1)
                            .blendMode(.screen)
                            .opacity(sin(sw * .pi))
                    }
                    .allowsHitTesting(false)
                }

                // Scanner line
                if scanU > 0 && scanU < 1 {
                    GeometryReader { proxy in
                        let h = proxy.size.height
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        C.cyan.opacity(0),
                                        C.cyan,
                                        C.cyan.opacity(0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .shadow(color: C.cyan.opacity(0.9), radius: 8)
                            .offset(y: h * scanU - h / 2)
                            .opacity(sin(scanU * .pi))
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: logoSize, height: logoSize)
            .background(C.bg3)
            .clipShape(RoundedRectangle(cornerRadius: logoCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: logoCorner, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: C.accent.opacity(0.55), radius: 30, x: 0, y: 20)
            .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 8)
            .blur(radius: logoBlur)
            .opacity(logoOpacity)
            .scaleEffect(logoScale)
            .rotationEffect(.degrees(logoRot))
            .offset(y: logoY)
        }
        .frame(width: logoSize, height: logoSize)
    }

    private func wordmark(t: Double) -> some View {
        let chars: [Character] = Array("Cleaner GPT")
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(chars.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let ch = pair.element
                let isGPT = i >= 8           // "GPT" starts at index 8 (after "Cleaner ")

                // Per-char reveal — each character has a randomised
                // angle/distance/rotation and eases in with easeOutBack.
                let start = 0.70 + Double(i) * 0.055
                let u = reduceMotion ? 1.0 : clamp01((t - start) / 0.60)
                let eased = reduceMotion ? 1.0 : easeOutBack(u)

                let seed = Double((i * 9301 + 49297) % 233280)
                let rand = seed / 233280.0
                let angle = Double(i) / Double(chars.count) * .pi * 2 + rand * 1.4
                let dist = 180.0 + rand * 140.0
                let dx = cos(angle) * dist
                let dy = sin(angle) * dist - 40.0
                let rot = (rand - 0.5) * 180.0
                let startScale = 0.1 + rand * 0.3
                let inv = 1.0 - eased
                let finalScale = max(0.05, eased * 1.0 + inv * startScale)

                Text(String(ch))
                    // Space Grotesk isn't bundled — SF Pro Rounded Heavy
                    // is the closest native approximation (geometric,
                    // slightly rounded corners, tight tracking).
                    .font(.system(size: wordmarkFont, weight: .heavy, design: .rounded))
                    .tracking(wordmarkTracking)
                    .foregroundStyle(
                        isGPT
                            ? AnyShapeStyle(LinearGradient(
                                colors: [C.cta1, C.cta2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            : AnyShapeStyle(C.text1)
                    )
                    .shadow(
                        color: isGPT ? .clear : Color.white.opacity(inv * 0.7),
                        radius: inv * 9
                    )
                    .opacity(max(0, min(1, eased)))
                    .blur(radius: inv * 8)
                    .scaleEffect(finalScale)
                    .rotationEffect(.degrees(inv * rot))
                    .offset(x: inv * dx, y: inv * dy)
            }
        }
        // Shimmer sweep across the wordmark between 1.20–1.60s.
        .overlay(
            Group {
                let shimmerU = reduceMotion ? 1.0 : clamp01((t - 1.20) / 0.40)
                if shimmerU > 0 && shimmerU < 1 {
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.3),
                                        .init(color: Color.white.opacity(0.5), location: 0.5),
                                        .init(color: .clear, location: 0.7),
                                    ],
                                    startPoint: UnitPoint(x: 0, y: 0.2),
                                    endPoint: UnitPoint(x: 1, y: 0.8)
                                )
                            )
                            .frame(width: 110, height: 50)
                            .rotationEffect(.degrees(-20))
                            .offset(x: w / 2 - 55 - 60 + shimmerU * 140, y: -6)
                            .blendMode(.overlay)
                            .opacity(sin(shimmerU * .pi))
                    }
                    .allowsHitTesting(false)
                }
            }
        )
    }

    private func tagline(t: Double) -> some View {
        // "Clean. Organize. Protect." → parts = ["Clean", "Organize", "Protect"]
        // split into line 1 = ["Clean", "Organize"], line 2 = ["Protect"]
        // per the prototype's `Math.ceil(parts.length / 2)` split.
        let line1 = ["CLEAN", "ORGANIZE"]
        let line2 = ["PROTECT"]

        let tagU = reduceMotion ? 1.0 : easeOut(range(t, 1.30, 1.60))

        return VStack(spacing: 8) {
            taglineLine(words: line1, highlightIndex: 1)
            taglineLine(words: line2, highlightIndex: 0)
        }
        .opacity(tagU)
        .offset(y: (1.0 - tagU) * 10)
    }

    private func taglineLine(words: [String], highlightIndex: Int) -> some View {
        HStack(spacing: 12) {
            // Left accent bar (fades in from left)
            accentBar(fadeFromLeading: true)

            HStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.offset) { pair in
                    let i = pair.offset
                    let w = pair.element
                    Text(w)
                        .foregroundStyle(i == highlightIndex ? C.cyan : C.textTagline)
                    if i < words.count - 1 {
                        Text(" / ")
                            .foregroundStyle(C.accent)
                            .fontWeight(.bold)
                    }
                }
            }
            // JetBrains Mono isn't bundled — SF Mono Medium is the
            // closest native equivalent for the subtitle mono treatment.
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .tracking(1.6)
            .textCase(.uppercase)
            .shadow(color: C.cyan.opacity(0.35), radius: 6)
            .fixedSize(horizontal: true, vertical: false)

            // Right accent bar
            accentBar(fadeFromLeading: false)
        }
    }

    private func accentBar(fadeFromLeading: Bool) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: fadeFromLeading
                        ? [C.accent.opacity(0), C.accent]
                        : [C.accent, C.accent.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 24, height: 1)
            .shadow(color: C.accent, radius: 4)
    }

    // MARK: - Exit fade

    private func exitFadeValue(t: Double) -> Double {
        let start = totalDuration - exitFade
        return clamp01((t - start) / exitFade)
    }

    // MARK: - Preload / warm-up
    //
    // The splash is load-bearing. While the reveal animates, we
    // amortize work that would otherwise hit the main thread on the
    // first onboarding CTA. Everything here runs on a background
    // queue (or is already async). Failures are silent — worst case
    // the onboarding CTA just pays the cost the old way.

    private func prewarm() {
        DispatchQueue.global(qos: .userInitiated).async {
            // AVAudioSession cold activation is the real ~80-200 ms
            // stall that used to hit playCTAThump() on first tap.
            // Flip it on then off inside the splash — by the time
            // onboarding fires, the session is warm.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true, options: [])
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        }

        // UIImpactFeedbackGenerator is already prepared in
        // OnboardingHaptics.init(). Nothing else to do here.
    }

    // MARK: - Easing helpers (match splash.jsx)

    private func clamp01(_ u: Double) -> Double { max(0, min(1, u)) }
    private func range(_ t: Double, _ t0: Double, _ t1: Double) -> Double {
        clamp01((t - t0) / (t1 - t0))
    }
    private func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double {
        a + (b - a) * u
    }
    private func easeOut(_ u: Double) -> Double { 1 - pow(1 - u, 3) }
    private func easeOutExpo(_ u: Double) -> Double {
        u >= 1 ? 1 : 1 - pow(2, -10 * u)
    }
    private func easeOutBack(_ u: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(u - 1, 3) + c1 * pow(u - 1, 2)
    }
    /// Critically-damped spring, closed-form. Matches the JS
    /// `spring` from splash.jsx.
    private func spring(_ u: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        let decay = exp(-3.5 * u)
        return 1 - decay * cos(7 * u)
    }
}

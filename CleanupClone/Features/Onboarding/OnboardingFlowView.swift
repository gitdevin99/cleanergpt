import SwiftUI
import UserNotifications
import PostHog

// MARK: - OnboardingFlowView
//
// 12-screen onboarding:
//   1. Hero (storage bar animating red→green)
//   2. Social proof (testimonials + 4M+ stars)
//   3. Duplicates feature
//   4. Similar photos feature
//   5. Speaker clean — dust (animated particles)
//   6. Speaker clean — water (animated droplets)
//   7. Contacts cleanup + iCloud backup
//   8. Secret Space vault
//   9. Email inbox cleaner (Gmail)
//   10. Paywall — "Free Up Storage Easily" with counting badges + color bar
//   11. Photos permission request
//   12. Notifications (optional weekly reminder)
//
// Permission is deliberately at step 11 — users who reach this point have seen
// value for 10 screens and paid (or dismissed paywall), so grant rate is much
// higher than asking on screen 1.

struct OnboardingFlowView: View {
    @EnvironmentObject private var appFlow: AppFlow
    @StateObject private var paywallStore = PaywallStore()
    @StateObject private var speakerCue = SpeakerOnboardingCue()
    @State private var selectedPaywallPlan: PaywallPlan = .yearly
    @State private var didRequestNotifications = false
    @State private var paywallCloseVisible = false
    /// True while a StoreKit purchase/restore is in flight. Prevents
    /// double-taps from queuing two purchase Tasks back-to-back and
    /// also disables the primary/secondary CTAs while Apple's sheet
    /// is up.
    @State private var paywallPurchaseInFlight = false
    /// Brief toast-style status shown inline when a purchase fails or
    /// a restore finds no active subscription — so the user isn't
    /// left wondering why the paywall didn't advance.
    @State private var paywallStatusMessage: String?

    private var currentStep: OnboardingStep {
        OnboardingStep.allCases[min(appFlow.onboardingIndex, OnboardingStep.allCases.count - 1)]
    }

    var body: some View {
        ZStack {
            CleanupTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 14)
                    .padding(.horizontal, 22)

                stepContent
                    // No `.id(currentStep)` — that would destroy and
                    // rebuild the entire step's view tree on every
                    // transition, which is exactly what caused the
                    // "heavy / laggy" step-change. Steps are now held
                    // alive as a ZStack (see `stepContent`) so the
                    // transition is a pure GPU-level opacity/offset
                    // change on already-built views. No main-thread
                    // work during the switch.

                bottomCTAs
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }

            // Soft paywall: render the X (revealed after a delay).
            // Hard paywall: don't render it at all — the only way forward
            // is subscribe. Flag comes from Adapty remote config so we can
            // flip it post-ship without resubmitting the binary.
            if currentStep == .paywall && !paywallStore.hardPaywall {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            PostHogSDK.shared.capture("paywall_closed")
                            finishOnboarding()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CleanupTheme.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                        .opacity(paywallCloseVisible ? 1 : 0)
                        .allowsHitTesting(paywallCloseVisible)
                    }
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.35), value: paywallCloseVisible)
            }
        }
        // Intentionally no `.task { refreshDeviceAndStorage() }` here —
        // that call did blocking disk I/O on the main thread every time
        // an onboarding step appeared, which stalled the first frame of
        // the hero animation. AppFlow already refreshes storage in
        // `init()` and we don't need a fresh reading to render these
        // pre-permission screens.
        //
        // Top-level .animation(value: onboardingIndex) is REQUIRED for
        // the stepContent `.transition()` to fire. Without it, changing
        // the `.id(currentStep)` swaps the view but there's no animation
        // transaction attached to the state change, so the transition
        // becomes a hard cut — and because other onboarding state (audio
        // dispatch, async permissions) lands on the same runloop tick,
        // it *looks* like the app froze. The real perf win came from
        // moving AVAudioEngine spin-up off the main thread in
        // OnboardingHaptics — not from touching this modifier.
        .animation(.easeInOut(duration: 0.3), value: appFlow.onboardingIndex)
        .onAppear {
            // Analytics off-main so it never contends with the
            // onboarding's first-frame render.
            let step = currentStep
            Task.detached {
                PostHogSDK.shared.capture("onboarding_step_viewed",
                    properties: ["step": step.rawValue, "step_name": "\(step)"])
            }
            if currentStep == .paywall { schedulePaywallClose() }
        }
        .onChange(of: appFlow.onboardingIndex) { _ in
            // Same rule on every step-change — PostHog off-main so it
            // can't stutter the transition frame.
            let step = currentStep
            Task.detached {
                PostHogSDK.shared.capture("onboarding_step_viewed",
                    properties: ["step": step.rawValue, "step_name": "\(step)"])
            }
            paywallCloseVisible = false
            if currentStep == .paywall { schedulePaywallClose() }
        }
    }

    // MARK: - Header

    private var progressBar: some View {
        let total = OnboardingStep.allCases.count
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= appFlow.onboardingIndex ? CleanupTheme.electricBlue : Color.white.opacity(0.08))
                    .frame(height: 3)
            }
        }
    }

    // MARK: - Step content router

    /// All 12 onboarding steps are held alive in a single ZStack from
    /// first render. Only the current one is visible (opacity) and
    /// interactive (allowsHitTesting); the rest sit in memory with
    /// opacity 0, ready to fade in instantly.
    ///
    /// Why: SwiftUI's `.id(value)` + `.transition()` pattern destroys
    /// and rebuilds the entire step tree on every tap. For heavy
    /// steps (SocialProofStep has 6 testimonials + animated stars +
    /// a ticker + image decoding), that rebuild cost blows past the
    /// 16.6 ms frame budget and drops 2-4 frames — what the user
    /// perceives as "the transition feels heavy."
    ///
    /// The persistent-ZStack pattern is what `TabView(.page)` does
    /// internally. Memory cost is ~5-8 MB for all 12 steps (mostly
    /// asset thumbnails); transitions are essentially free because
    /// no view tree is rebuilt.
    @ViewBuilder
    private var stepContent: some View {
        ZStack {
            ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.element) { pair in
                let step = pair.element
                stepView(for: step)
                    .opacity(step == currentStep ? 1 : 0)
                    .allowsHitTesting(step == currentStep)
                    // The opacity-only fade is deliberately simple —
                    // adding a translation would re-invoke layout
                    // on every step, which is the kind of work we
                    // just removed. Pure opacity is GPU-only.
                    .animation(.easeInOut(duration: 0.28), value: currentStep)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .hero:              HeroStep()
        case .socialProof:       SocialProofStep()
        case .duplicates:        DuplicatesStep()
        case .similar:           SimilarStep()
        case .speakerDust:       SpeakerParticleStep(mode: .dust)
        case .speakerWater:      SpeakerParticleStep(mode: .water)
        case .contactsBackup:    ContactsBackupStep()
        case .secretSpace:       SecretVaultStep()
        case .emailCleaner:      EmailCleanerStep()
        case .paywall:           PaywallContentStep(selectedPlan: $selectedPaywallPlan)
                                    .environmentObject(paywallStore)
        case .photosPermission:  PhotosPermissionStep()
        case .notifications:     NotificationsStep()
        }
    }

    // MARK: - CTAs

    private var bottomCTAs: some View {
        VStack(spacing: 8) {
            // Inline status text for the paywall — appears when a
            // purchase or restore attempt completes without advancing
            // the user. Sits directly above the CTA so it's obvious
            // why the button didn't progress the flow.
            if currentStep == .paywall, let msg = paywallStatusMessage {
                Text(msg)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            PrimaryCTAButton(title: currentStep.buttonTitle, action: handleCTA)
                .disabled(currentStep == .paywall && paywallPurchaseInFlight)
                .opacity(currentStep == .paywall && paywallPurchaseInFlight ? 0.55 : 1)

            if let secondary = currentStep.secondaryButtonTitle {
                Button(secondary) {
                    handleSecondary()
                }
                .font(CleanupFont.body(14))
                .foregroundStyle(CleanupTheme.textSecondary)
                .padding(.top, 2)
                .disabled(currentStep == .paywall && paywallPurchaseInFlight)
                .opacity(currentStep == .paywall && paywallPurchaseInFlight ? 0.55 : 1)
            }

            HStack(spacing: 8) {
                Link("Privacy Policy", destination: URL(string: "https://cleanergpt.app/privacy")!)
                Text("·")
                Link("Terms", destination: URL(string: "https://cleanergpt.app/terms")!)
            }
            .font(CleanupFont.caption(11))
            .foregroundStyle(CleanupTheme.textTertiary)
            .padding(.top, 2)
        }
    }

    private func handleCTA() {
        // FIRST-PRINCIPLES LAG FIX — the tap handler's only job on the
        // current run-loop tick is to flip the `currentStep` state.
        // Everything else (haptics, audio, analytics) is deferred so
        // it lands on the NEXT tick, AFTER the transition has started
        // animating. This keeps the 16.6 ms frame budget clean during
        // the moment the user is actually watching.
        //
        //   BEFORE: haptic → audio → state flip → SwiftUI rebuild
        //           → all on one frame → drops 2-4 frames
        //   AFTER:  state flip → GPU handles transition → next tick:
        //           haptic + async audio + async analytics
        //
        // Analytics is fired on a detached Task so PostHog's
        // synchronous capture never lands on main during transition.

        // Capture the step BEFORE we flip, so the async analytics
        // logs the step the user was actually on when they tapped.
        let steppedFrom = currentStep

        // 1. Flip state synchronously. This is the only main-thread
        //    work that's allowed on this tick. GPU takes over from here.
        switch steppedFrom {
        case .photosPermission:
            Task {
                let granted = await appFlow.requestPhotoAuthorizationOnly()
                appFlow.advanceOnboarding()
                Task.detached {
                    PostHogSDK.shared.capture("photos_permission_response",
                        properties: ["granted": granted])
                }
                // Intentionally DO NOT kick off `scanLibrary` here.
                // The next step is the paywall (AdaptyUI WebView) and
                // a concurrent scan saturates the Photos XPC channel
                // that the WebView also needs for its render + input
                // plumbing. Throttling the scan makes the paywall
                // render but the dashboard arrives empty; running the
                // scan at full speed strands the paywall buttons.
                // Neither is acceptable.
                //
                // Instead, the scan is deferred until the user leaves
                // the paywall step — see `finishOnboardingPaywall()`
                // below. By the time they're watching the dashboard
                // load, the WebView is gone and the scan can run at
                // full 8-worker speed with no contention.
            }
        case .notifications:
            Task {
                await requestNotificationPermissionIfPossible()
                Task.detached {
                    PostHogSDK.shared.capture("notifications_permission_tapped")
                }
                finishOnboarding()
            }
        case .paywall:
            guard !paywallPurchaseInFlight else { return }
            paywallPurchaseInFlight = true
            paywallStatusMessage = nil
            let planRaw = selectedPaywallPlan.rawValue
            Task.detached {
                PostHogSDK.shared.capture("paywall_cta_tapped",
                    properties: ["action": "subscribe", "plan": planRaw])
            }
            Task {
                let success = await paywallStore.purchase(plan: selectedPaywallPlan)
                Task.detached {
                    PostHogSDK.shared.capture("paywall_purchase_result",
                        properties: ["success": success, "plan": planRaw])
                }
                paywallPurchaseInFlight = false
                if success {
                    kickOffFirstScanIfNeeded()
                    appFlow.advanceOnboarding()
                } else {
                    paywallStatusMessage = "Purchase didn't complete. Try again or wait to close."
                }
            }
        default:
            appFlow.advanceOnboarding()
        }

        // 2. Defer everything that's NOT state-flip to the next
        //    run-loop tick. By then, SwiftUI has already committed
        //    the transition and the GPU is animating. Haptics + audio
        //    are now free — they can't stutter a frame because the
        //    frame has already shipped.
        DispatchQueue.main.async {
            OnboardingHaptics.shared.playCTAThump()

            // Strong speaker cue fires when the user advances INTO the
            // dust step (from .similar) or INTO the water step (from
            // .speakerDust). Runs here so audio/haptics start right as
            // the new step slides in.
            switch steppedFrom {
            case .similar:
                speakerCue.fire(mode: .dust)
            case .speakerDust:
                speakerCue.fire(mode: .water)
            default:
                break
            }
        }
    }

    private func handleSecondary() {
        switch currentStep {
        case .paywall:
            // Same rule: Restore only advances if it actually found an
            // active subscription. "Restore" with no prior purchase is
            // not an escape hatch for the paywall.
            guard !paywallPurchaseInFlight else { return }
            paywallPurchaseInFlight = true
            paywallStatusMessage = nil
            PostHogSDK.shared.capture("paywall_cta_tapped", properties: ["action": "restore"])
            Task {
                let active = await paywallStore.restore()
                PostHogSDK.shared.capture("paywall_restore_result", properties: ["active": active])
                paywallPurchaseInFlight = false
                if active {
                    kickOffFirstScanIfNeeded()
                    appFlow.advanceOnboarding()
                } else {
                    paywallStatusMessage = "No active subscription found to restore."
                }
            }
        case .notifications:
            PostHogSDK.shared.capture("notifications_skipped")
            finishOnboarding()
        default:
            break
        }
    }

    private func schedulePaywallClose() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if currentStep == .paywall { paywallCloseVisible = true }
            }
        }
    }

    private func finishOnboarding() {
        PostHogSDK.shared.capture("onboarding_completed")
        // Persist the "done with onboarding" flag BEFORE transitioning
        // so that a crash or force-quit between here and the dashboard
        // still skips onboarding on the next launch. Without this the
        // user would replay the whole 12-step flow.
        appFlow.markOnboardingCompleted()
        kickOffFirstScanIfNeeded()
        appFlow.enterApp()
    }

    /// Fires the first library scan. Intentionally called ONLY when the
    /// user leaves the paywall step (purchased, restored, or closed via
    /// the X) or finishes the final onboarding step. We don't start
    /// earlier because the scan's `PHAssetResource` preflight saturates
    /// Photos XPC, which competes with AdaptyUI's WebView and strands
    /// the paywall's Continue button. Deferring the scan to AFTER the
    /// WebView is gone gives both the paywall and the scan their own
    /// runways — the paywall stays responsive, the scan runs at full
    /// 8-worker speed, and the dashboard loads without throttling.
    private func kickOffFirstScanIfNeeded() {
        guard appFlow.photoAuthorization.isReadable else { return }
        Task { await appFlow.scanLibrary(trigger: .firstLoad) }
    }

    private func requestNotificationPermissionIfPossible() async {
        // Real iOS notifications permission prompt. If the status is
        // already determined (granted or denied) the system returns
        // immediately without showing UI — this matches how the Photos
        // prompt behaves, so the onboarding flow advances either way.
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            didRequestNotifications = true
            return
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        didRequestNotifications = true
        if granted {
            await scheduleUpfrontNotificationCampaign()
        }
    }

    /// After permission is granted, freeze the current scan numbers and hand
    /// them to the scheduler. If the scan didn't run (permission denied for
    /// photos), we still ship a campaign — copy falls back to generic nags.
    private func scheduleUpfrontNotificationCampaign() async {
        // Don't spam paying users — we check premium state before scheduling.
        if EntitlementStore.shared.isPremium { return }

        let used = Double(appFlow.storageSnapshot.usedBytes)
        let total = max(Double(appFlow.storageSnapshot.totalBytes), 1)
        let pct = Int((used / total * 100).rounded())

        let dupSummary = appFlow.dashboardCategories.first(where: { $0.kind == .duplicates })
        let simSummary = appFlow.dashboardCategories.first(where: { $0.kind == .similar })
        let videosSummary = appFlow.dashboardCategories.first(where: { $0.kind == .videos })

        let dupCount = (dupSummary?.count ?? 0) + (simSummary?.count ?? 0)
        let recoverableBytes = (dupSummary?.totalBytes ?? 0)
            + (simSummary?.totalBytes ?? 0)
            + (videosSummary?.totalBytes ?? 0)
        let compressibleBytes = videosSummary?.totalBytes ?? 0

        let gb = Double(recoverableBytes) / 1_073_741_824.0
        let compressGB = Double(compressibleBytes) / 1_073_741_824.0

        let summary = ScanSummary(
            storagePercentUsed: pct,
            duplicateCount: max(dupCount, 12), // never show "0 duplicates" — fallback keeps copy urgent
            recoverableGB: max(gb, 0.8),
            compressibleGB: max(compressGB, 0.5)
        )
        NotificationScheduler.shared.scheduleUpfrontCampaign(with: summary)
    }
}

// MARK: - Reusable step chrome

// MARK: - Step 5/6: Speaker Clean (Dust + Water) — real SwiftUI particle animation

/// Live-rendered speaker clean screen. No PNG — the dust (or water) particles
/// are drawn per-frame via TimelineView + Canvas with actual orbital physics.
/// The central speaker uses SF Symbol + .symbolEffect(.variableColor.iterative)
/// so the wave arcs pulse, matching the "it's cleaning" vibe.
private struct SpeakerParticleStep: View {
    enum Mode { case dust, water }
    let mode: Mode


    private var title: String {
        mode == .dust ? "Blast Dust\nFrom Your Speakers" : "Push Water\nOut of Your Speakers"
    }
    private var subtitle: String {
        mode == .dust
            ? "Scientifically tuned vibrations dislodge dust trapped in your speaker grille."
            : "A proven low-frequency sound wave physically pushes water out of your speaker."
    }
    private var accent: Color {
        mode == .dust ? Color(hex: "#3FA9FF") : Color(hex: "#4DE3E3")
    }
    private var particleTint: Color {
        mode == .dust ? Color(hex: "#C9B99A") : Color(hex: "#7FD4FF")
    }

    var body: some View {
        ZStack {
            AmbientParticleLayer(particleCount: 20, tint: accent)
                .allowsHitTesting(false)

        VStack(spacing: 18) {
            Spacer(minLength: 12)

            ZStack {
                // Expanding sound-wave rings radiating from speaker
                SoundWaveRings(color: accent)
                    .frame(width: 300, height: 300)

                // Concentric dashed rings
                ForEach(0..<3, id: \.self) { i in
                    let ringSize = 170 + CGFloat(i) * 40
                    Circle()
                        .strokeBorder(accent.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                        .frame(width: ringSize, height: ringSize)
                }

                // Animated particle field
                ParticleField(mode: mode, tint: particleTint, accent: accent)
                    .frame(width: 260, height: 260)

                // Center speaker glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.45), accent.opacity(0.0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 80
                        )
                    )
                    .frame(width: 180, height: 180)

                // Speaker icon with native symbol effect
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(accent)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeat(.continuous))
                    .shadow(color: accent.opacity(0.55), radius: 12)
            }
            .frame(height: 300)

            VStack(spacing: 10) {
                Text(title)
                    .font(CleanupFont.hero(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CleanupTheme.textPrimary)

                Text(subtitle)
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 8)
        }
        } // close outer ZStack
    }
}

/// Draws particles (dust squares or water droplets) orbiting the speaker with
/// slight radial drift. Uses TimelineView(.animation) so the Canvas redraws
/// every frame — genuine animation, not a rotating PNG.
private struct ParticleField: View {
    let mode: SpeakerParticleStep.Mode
    let tint: Color
    let accent: Color

    /// Pre-computed particle seeds — angle, radius, size, speed, phase.
    private let particles: [Particle] = {
        var rng = SystemRandomNumberGenerator()
        return (0..<36).map { _ in
            Particle(
                angle: Double.random(in: 0...(2 * .pi), using: &rng),
                radius: CGFloat.random(in: 60...130, using: &rng),
                size: CGFloat.random(in: 3...7, using: &rng),
                angularSpeed: Double.random(in: 0.15...0.45, using: &rng) * (Bool.random(using: &rng) ? 1 : -1),
                radialPhase: Double.random(in: 0...(2 * .pi), using: &rng)
            )
        }
    }()

    struct Particle {
        let angle: Double        // initial angle (radians)
        let radius: CGFloat      // base orbital radius
        let size: CGFloat
        let angularSpeed: Double // radians per second
        let radialPhase: Double  // offset so radii pulse independently
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for p in particles {
                    // Orbital position
                    let currentAngle = p.angle + p.angularSpeed * t
                    // Radial pulse (particles drift in/out slightly)
                    let radialOffset = sin(t * 1.2 + p.radialPhase) * 6
                    let r = p.radius + radialOffset
                    let x = center.x + cos(currentAngle) * r
                    let y = center.y + sin(currentAngle) * r

                    let opacity = 0.55 + sin(t * 2 + p.radialPhase) * 0.35

                    switch mode {
                    case .dust:
                        // Small rotated squares — debris
                        let rect = CGRect(x: x - p.size/2, y: y - p.size/2, width: p.size, height: p.size)
                        let path = Path(CGRect(origin: .zero, size: CGSize(width: p.size, height: p.size)))
                        ctx.translateBy(x: rect.minX, y: rect.minY)
                        ctx.rotate(by: .radians(currentAngle * 2))
                        ctx.fill(path, with: .color(tint.opacity(opacity)))
                        ctx.transform = .identity
                    case .water:
                        // Teardrop-ish ellipse with glow
                        let rect = CGRect(x: x - p.size/2, y: y - p.size, width: p.size, height: p.size * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
                        ctx.fill(
                            Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)),
                            with: .color(accent.opacity(opacity * 0.25))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Step 3: Duplicates — garbage-toss loop
//
// Continuous 4-phase loop:
//   0.0–0.5s   Rest. Both pairs visible (KEEP top + DELETE bottom, with
//              down-arrow between them).
//   0.5–1.4s   DELETE cards fly down + curve inward + scale down toward
//              the trash icon that fades in at the bottom-center. Little
//              red ✕ pops on the trash when each lands.
//   1.4–1.8s   Trash shakes, KEEP cards pulse green ("saved!").
//   1.8–2.2s   Fresh DELETE cards fade in below the arrows — new
//              duplicates found — and we loop back to phase 0.
//
// The whole timeline is driven by a single @State `phase` value that
// gets stepped by a repeating timer inside `.task`. No TimelineView,
// no per-frame canvas — Core Animation interpolates all the
// offset/scale/opacity transitions natively.

private struct DuplicatesStep: View {
    /// Normalized position in the 2.2s loop (0…1).
    @State private var phase: CGFloat = 0
    @State private var tossCount: Int = 0    // increments each loop — used
                                             // to trigger trash wiggle + KEEP pulse
    @State private var pairFamily: Int = 0   // alternates which asset is
                                             // shown so the "new duplicates
                                             // found" moment feels real

    // Two asset rotations so each loop shows a different pair,
    // reinforcing the "we keep finding more" feel.
    private let leftAssets = ["DuplicateSelfieWomen", "TestimonialSarah", "TestimonialPriya"]
    private let rightAssets = ["DuplicateSelfieMen", "TestimonialMarcus", "DuplicateSelfieMen"]

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            ZStack {
                HStack(alignment: .top, spacing: 14) {
                    DuplicatePairCard(
                        assetName: leftAssets[pairFamily % leftAssets.count],
                        phase: phase,
                        tossCount: tossCount
                    )
                    DuplicatePairCard(
                        assetName: rightAssets[pairFamily % rightAssets.count],
                        phase: phase,
                        tossCount: tossCount,
                        delayed: true   // right-side toss starts ~120ms later
                    )
                }
                .padding(.horizontal, 22)

                // Trash icon: fades in during the toss, shakes on impact.
                TrashCatcher(phase: phase, tossCount: tossCount)
                    .offset(y: 140)
            }
            .frame(height: 290)

            VStack(spacing: 10) {
                Text("Delete Duplicate\nPhotos Instantly")
                    .font(CleanupFont.hero(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CleanupTheme.textPrimary)

                Text("Eliminate duplicate photos instantly and reclaim your storage.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 8)
        }
        .task {
            // Drive the loop by animating `phase` 0 → 1 over 2.2s, then
            // bumping tossCount + cycling pairFamily and restarting.
            // Using Task.sleep keeps this off the main render pipeline;
            // each phase change is a single state mutation that Core
            // Animation interpolates natively.
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 2.2)) {
                    phase = 1
                }
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                // Snap back + advance to next pair family.
                phase = 0
                tossCount += 1
                pairFamily = (pairFamily + 1) % leftAssets.count
            }
        }
    }
}

/// One side of the duplicate-pair column: KEEP card on top, arrow,
/// DELETE card below that toss-animates toward the trash during the
/// loop. Uses `phase` (0…1) from the parent to position itself on the
/// shared timeline.
private struct DuplicatePairCard: View {
    let assetName: String
    let phase: CGFloat
    let tossCount: Int
    var delayed: Bool = false

    // Cache the "trash landing point" relative to this column so the
    // toss curves converge on the trash icon. Right column starts
    // slightly later so the two cards don't land simultaneously —
    // reads more like a real "cleaning" sweep.
    private var localPhase: CGFloat {
        let offset: CGFloat = delayed ? -0.08 : 0
        return max(0, min(1, phase + offset))
    }

    var body: some View {
        VStack(spacing: 10) {
            // KEEP tile — pulses green briefly when the DELETE card
            // lands in trash (phase ~0.75).
            duplicateTile(keep: true)
                .scaleEffect(keepPulse)
                .shadow(
                    color: CleanupTheme.accentGreen.opacity(keepGlow),
                    radius: 14
                )

            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CleanupTheme.textTertiary)
                .opacity(1 - deleteTossProgress) // arrow fades as toss advances

            // DELETE tile — rides the toss curve to the trash, then
            // fades in again as a "new duplicate" once phase wraps.
            duplicateTile(keep: false)
                .scaleEffect(deleteScale)
                .rotationEffect(.degrees(deleteRotation))
                .offset(x: deleteOffsetX, y: deleteOffsetY)
                .opacity(deleteOpacity)
        }
    }

    // MARK: - Derived timeline values

    /// 0 before toss start, ramps to 1 during the "fly to trash" window.
    private var deleteTossProgress: CGFloat {
        let start: CGFloat = 0.22
        let end: CGFloat = 0.70
        let p = (localPhase - start) / (end - start)
        return max(0, min(1, p))
    }

    /// 0 outside the post-toss window, ramps to 1 while card is "in trash".
    private var settledProgress: CGFloat {
        let start: CGFloat = 0.70
        let end: CGFloat = 0.85
        let p = (localPhase - start) / (end - start)
        return max(0, min(1, p))
    }

    /// 0 before respawn, ramps to 1 as the new DELETE card fades back in.
    private var respawnProgress: CGFloat {
        let start: CGFloat = 0.85
        let end: CGFloat = 1.0
        let p = (localPhase - start) / (end - start)
        return max(0, min(1, p))
    }

    private var deleteOffsetY: CGFloat {
        // Curve toward the trash icon sitting ~130pt below this column.
        // ease-in for gravity feel.
        let t = deleteTossProgress
        return CGFloat(t * t) * 140
    }

    private var deleteOffsetX: CGFloat {
        // Converge toward screen center — left column slides right,
        // right column slides left. We can't know our column from
        // here, so use a small vertical sway instead.
        let t = deleteTossProgress
        return sin(CGFloat(t) * .pi) * 6
    }

    private var deleteRotation: Double {
        Double(deleteTossProgress) * (delayed ? -22 : 22)
    }

    private var deleteScale: CGFloat {
        if respawnProgress > 0 {
            return 0.6 + respawnProgress * 0.4
        }
        let shrink = 1.0 - deleteTossProgress * 0.7
        return max(0.1, shrink)
    }

    private var deleteOpacity: Double {
        if respawnProgress > 0 { return Double(respawnProgress) }
        if settledProgress > 0 { return 1.0 - Double(settledProgress) }
        return 1.0
    }

    private var keepPulse: CGFloat {
        // Tiny bounce at the "landed" moment.
        let center: CGFloat = 0.72
        let width: CGFloat = 0.12
        let d = abs(localPhase - center)
        guard d < width else { return 1.0 }
        let k = 1 - d / width
        return 1.0 + k * 0.04
    }

    private var keepGlow: Double {
        let center: CGFloat = 0.72
        let width: CGFloat = 0.15
        let d = abs(localPhase - center)
        guard d < width else { return 0 }
        return Double(1 - d / width) * 0.55
    }

    @ViewBuilder
    private func duplicateTile(keep: Bool) -> some View {
        let badgeColor: Color = keep ? CleanupTheme.accentGreen : CleanupTheme.accentRed
        let badgeSymbol = keep ? "checkmark" : "xmark"
        let badgeText = keep ? "KEEP" : "DELETE"

        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(height: 94)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if !keep {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Image(systemName: badgeSymbol)
                        .font(.system(size: 9, weight: .bold))
                    Text(badgeText)
                        .font(CleanupFont.badge(9))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(badgeColor, in: Capsule(style: .continuous))
                .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(keep ? Color.white.opacity(0.1) : badgeColor.opacity(0.45), lineWidth: 1.5)
            )
    }
}

/// Trash bin that fades in during the toss window and bobs/shakes when
/// the DELETE cards land. Used purely as visual feedback for the
/// "photos are being thrown away" metaphor.
private struct TrashCatcher: View {
    let phase: CGFloat
    let tossCount: Int

    /// Bin is invisible at rest, fades in during toss, stays visible
    /// through the settle, fades out before respawn.
    private var binOpacity: Double {
        if phase < 0.15 { return 0 }
        if phase < 0.30 { return Double((phase - 0.15) / 0.15) }
        if phase < 0.85 { return 1 }
        return max(0, Double(1 - (phase - 0.85) / 0.10))
    }

    /// Shake when the cards hit the bin (~phase 0.70).
    private var shake: CGFloat {
        let center: CGFloat = 0.72
        let width: CGFloat = 0.10
        let d = abs(phase - center)
        guard d < width else { return 0 }
        let k = 1 - d / width
        return sin(phase * 80) * 4 * k
    }

    /// Lid lifts slightly right before impact.
    private var lidOffset: CGFloat {
        let center: CGFloat = 0.60
        let width: CGFloat = 0.14
        let d = abs(phase - center)
        guard d < width else { return 0 }
        return -(1 - d / width) * 6
    }

    var body: some View {
        ZStack {
            // Glow pad behind trash
            Circle()
                .fill(
                    RadialGradient(
                        colors: [CleanupTheme.accentRed.opacity(0.35), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)

            VStack(spacing: -6) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#FF7373"), Color(hex: "#B83C3C")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .offset(y: lidOffset)
                    .shadow(color: CleanupTheme.accentRed.opacity(0.55), radius: 10)
            }
            .offset(x: shake)
        }
        .opacity(binOpacity)
    }
}

// MARK: - Step 4: Similar photos — animated fanned-out stack

private struct SimilarStep: View {
    // Card-carousel: six distinct real portraits are always visible, fanned
    // in a 3D spread. The stack gently "shuffles" so the KEEP slot cycles
    // through each face — giving a strong sense of motion without any card
    // ever leaving the visible area (no empty frames, ever). Each back
    // card carries a small ✕ DELETE badge; the front card gets KEEP.
    private let photoAssets: [String] = [
        "TestimonialSarah",
        "TestimonialPriya",
        "TestimonialMarcus",
        "DuplicateSelfieWomen",
        "DuplicateSelfieMen",
        "TestimonialSarah",
    ]

    // Per-card geometry in the fanned stack. Index 0 = closest to the
    // viewer (front / KEEP), index 5 = furthest back. x offset increases
    // to the right so all 6 photos are simultaneously legible.
    // Slot positions are already pre-centered so the front card (slot 0)
    // sits at x=0 and the back cards fan symmetrically to the right. No
    // post-hoc .offset() is needed on the ZStack — applying one caused
    // the front card to clip off the left edge of its parent frame.
    private var slots: [CardSlot] {
        [
            .init(x: -40, y: 0,   rotation: -3,  scale: 1.00, zIndex: 100, tint: 0.0),
            .init(x: 0,   y: -6,  rotation: 3,   scale: 0.94, zIndex: 90,  tint: 0.25),
            .init(x: 36,  y: -10, rotation: 8,   scale: 0.89, zIndex: 80,  tint: 0.38),
            .init(x: 68,  y: -12, rotation: 12,  scale: 0.85, zIndex: 70,  tint: 0.48),
            .init(x: 96,  y: -12, rotation: 16,  scale: 0.81, zIndex: 60,  tint: 0.56),
            .init(x: 118, y: -10, rotation: 19,  scale: 0.77, zIndex: 50,  tint: 0.62),
        ]
    }

    struct CardSlot {
        let x: CGFloat
        let y: CGFloat
        let rotation: Double
        let scale: CGFloat
        let zIndex: Double
        let tint: Double // how much dark overlay
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 16)

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // 2.4s per cycle. At each tick, each card's slot rotates one
                // step through the stack (shuffle). Within a tick we
                // interpolate smoothly between its current slot and its
                // next slot so motion is continuous.
                let cycleSeconds = 2.4
                let raw = t / cycleSeconds
                let step = Int(raw) % photoAssets.count
                let frac = raw.truncatingRemainder(dividingBy: 1.0)   // 0...1
                let eased = easeInOut(frac)

                ZStack {
                    ForEach(0..<photoAssets.count, id: \.self) { i in
                        similarCard(index: i, step: step, eased: eased, t: t)
                    }
                }
            }
            .frame(height: 220)

            VStack(spacing: 10) {
                Text("Merge Similar\nShots Smartly")
                    .font(CleanupFont.hero(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CleanupTheme.textPrimary)

                Text("Keep the best shot from every burst. Delete the rest in one tap.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func similarCard(index i: Int, step: Int, eased: Double, t: Double) -> some View {
        // Which slot is this card currently in? The stack cycles: at step=0
        // card 0 is in slot 0 (front), step=1 → card 0 moved to slot 5
        // (back) and card 1 is in front, etc.
        let n = photoAssets.count
        let currentSlot = (i - step + n) % n
        let nextSlot = (i - step - 1 + n) % n
        let a = slots[currentSlot]
        let b = slots[nextSlot]

        // Smoothly interpolate between current slot and next slot
        let x = lerp(a.x, b.x, eased)
        let y = lerp(a.y, b.y, eased)
        let rot = lerp(a.rotation, b.rotation, eased)
        let scale = lerp(a.scale, b.scale, eased)
        let tint = lerp(a.tint, b.tint, eased)
        let zIdx = lerp(a.zIndex, b.zIndex, eased)

        // Front card (zIndex >= 95) gets KEEP + blue ring + no dimming
        let isFront = zIdx > 92

        Image(photoAssets[i])
            .resizable()
            .scaledToFill()
            .frame(width: 128, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                // Darken back cards so the front one pops; smoothly
                // animated so the newly-promoted front card brightens.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(tint))
            }
            .overlay(alignment: .topLeading) {
                if isFront {
                    Text("KEEP")
                        .font(CleanupFont.badge(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CleanupTheme.accentGreen, in: Capsule(style: .continuous))
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !isFront {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(CleanupTheme.accentRed, in: Circle())
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isFront ? CleanupTheme.electricBlue : Color.white.opacity(0.12),
                        lineWidth: isFront ? 2.5 : 1
                    )
            )
            .shadow(
                color: isFront
                    ? CleanupTheme.electricBlue.opacity(0.45)
                    : Color.black.opacity(0.4),
                radius: isFront ? 14 : 8,
                x: 0, y: isFront ? 0 : 6
            )
            .rotationEffect(.degrees(rot))
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .zIndex(zIdx)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}

// MARK: - Step 8: Secret Space — vault with flying photo tiles

private struct SecretVaultStep: View {
    @State private var tilesIn: Bool = false
    @State private var lockPulse: Bool = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 16)

            ZStack {
                // Photo tiles flying in from outside toward the lock
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) * .pi / 2 + .pi / 4
                    let radius: CGFloat = tilesIn ? 0 : 120
                    let colors = vaultPalette(i)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: colors.first!.opacity(0.5), radius: 6)
                        .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                        .opacity(tilesIn ? 0.0 : 1.0)
                        .scaleEffect(tilesIn ? 0.4 : 1.0)
                }

                // Glowing gold lock
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "#FFCE5B").opacity(0.5), .clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 110
                            )
                        )
                        .frame(width: 220, height: 220)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 92, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#FFE28C"), Color(hex: "#D9A23C")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(hex: "#FFCE5B").opacity(0.6), radius: 14)
                        .scaleEffect(lockPulse ? 1.05 : 1.0)
                }
            }
            .frame(height: 260)
            .onAppear {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.65).repeatForever(autoreverses: true)) {
                    tilesIn = true
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    lockPulse = true
                }
            }

            VStack(spacing: 10) {
                Text("Your Private\nSecret Space")
                    .font(CleanupFont.hero(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CleanupTheme.textPrimary)

                Text("Lock personal photos and videos behind a PIN. Only you can see them.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 8)
        }
    }

    private func vaultPalette(_ i: Int) -> [Color] {
        [
            [Color(hex: "#FF8C42"), Color(hex: "#B83C3C")],
            [Color(hex: "#3FA9FF"), Color(hex: "#123E66")],
            [Color(hex: "#7DFF99"), Color(hex: "#1E5F3C")],
            [Color(hex: "#D36BFF"), Color(hex: "#4B1E80")],
        ][i % 4]
    }
}

/// Generic feature step: image hero + title + subtitle. Kept for any
/// screens that still want a static illustration (currently unused — most
/// steps now have their own custom animated views).
private struct IllustratedFeatureStep: View {
    let imageName: String
    let title: String
    let subtitle: String
    var rotateImage: Bool = false

    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 320)
                .rotationEffect(.degrees(rotateImage ? rotation : 0))
                .onAppear {
                    guard rotateImage else { return }
                    withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            VStack(spacing: 10) {
                Text(title)
                    .font(CleanupFont.hero(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CleanupTheme.textPrimary)

                Text(subtitle)
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 8)
        }
    }
}

// MARK: - Step 1: Hero — non-stop animation
//
// Everything on this screen is ALWAYS moving:
//   • Ambient background particles float around continuously
//   • Phone mockup floats up-and-down
//   • Storage bar oscillates 95% → 12% and back, forever
//   • Percentage counts up/down with numericText transition
//   • "Junk" icons (camera, photo, envelope) orbit around the phone

private struct HeroStep: View {
    // LAG FIX — final pass.
    //
    // The previous "5-second stutter" on first appearance was caused by
    // THREE concurrent `TimelineView(.animation)` drivers on this screen
    // (AmbientParticleLayer Canvas, OrbitingIcons, and the outer phone
    // mockup). Each fires on every vsync, and on first appearance
    // SwiftUI has to realize the whole layer tree in the same tick as
    // the onboarding step-change slide-in transition. The compounded
    // first-frame cost is what the user perceived as "animation stuck,
    // then becomes normal after 5 seconds."
    //
    // This rewrite:
    //   • Kills every TimelineView on this screen.
    //   • Drops `AmbientParticleLayer` entirely (Canvas + per-frame
    //     particle math was pure overhead — the orbit + glow already
    //     give the "always moving" feel).
    //   • Uses three plain `@State` properties animated by
    //     `withAnimation(.repeatForever)`. These register ONCE with
    //     Core Animation, which interpolates them off the SwiftUI
    //     main thread — no re-evaluation of the view tree per frame.
    //   • Starts the infinite animations inside a `.task` that yields
    //     for 400ms first, so they begin AFTER the onboarding slide-in
    //     transition completes. No animation work overlaps with the
    //     initial view realization.

    // Start at 0.05 (matches the "Plenty of space / 5%" end) so the
    // first visible frame is already the green/low state — no flash.
    // The infinite animation then ramps up toward 0.95.
    @State private var progress: CGFloat = 0.05
    @State private var phoneFloat: CGFloat = 0
    @State private var glowPulse: Double = 0.28
    @State private var orbitAngle: Double = 0
    @State private var animationsStarted = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 16)

            ZStack {
                // Glow aura behind phone
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [CleanupTheme.electricBlue.opacity(glowPulse), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 180
                        )
                    )
                    .frame(width: 340, height: 340)

                // Orbiting junk icons — driven by a single @State angle
                // rotated by Core Animation, not by TimelineView.
                OrbitingIconsStatic(angle: orbitAngle)

                // Phone body
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#0F1530"), Color(hex: "#070B19")],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: 170, height: 300)
                    .shadow(color: CleanupTheme.electricBlue.opacity(0.25), radius: 20)

                // AnimatedStorageDisplay wraps the number + bar + label
                // in a single `Animatable` view. SwiftUI interpolates its
                // `progress` frame-by-frame through Core Animation, and
                // the view's `body` reads the interpolated value each
                // frame — so the "95% → 5%" ramp shows every integer in
                // between (95, 94, 93, ...) and the label and color
                // flip in lock-step with the bar. No `.contentTransition`
                // (that was the blurry-digit look you didn't want).
                AnimatedStorageDisplay(progress: progress)
            }
            .frame(width: 340, height: 340)
            .offset(y: phoneFloat)

            VStack(spacing: 8) {
                Text("Your iPhone is full, and your speakers need help too.")
                    .font(CleanupFont.hero(28))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CleanupTheme.textPrimary)
                    .padding(.horizontal, 20)

                Text("Clean up photos, emails, and junk. Then flush out water and dust. All in one tap.")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }

            Spacer(minLength: 8)
        }
        .onAppear {
            // Start animations IMMEDIATELY on appear — the old 400ms
            // Task.sleep made the screen feel "stuck" for the first
            // second. withAnimation hands off to Core Animation, which
            // runs on its own thread; it does not contend with the
            // onboarding slide-in transition (0.3s easeInOut), they
            // just composite.
            guard !animationsStarted else { return }
            animationsStarted = true

            // First-touch cue: deep bass thud through the speaker + a
            // strong Core Haptics jolt. Doubles as a teaser for Speaker
            // Clean (the app literally drives the hardware). Delayed ~300 ms
            // so it lands after the slide-in transition settles, not on
            // top of it — lands much more satisfyingly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                OnboardingHaptics.shared.playHeroEntrance()
            }

            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                phoneFloat = -6
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glowPulse = 0.5
            }
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                orbitAngle = .pi * 2
            }

            withAnimation(.easeOut(duration: 1.8)) {
                progress = 0.95
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                    progress = 0.15
                }
            }
        }
    }
}

/// Static-offset version of the orbiting icons — takes a single angle
/// from its parent (driven by withAnimation, not TimelineView) and
/// positions 4 SF Symbols around a circle. No per-frame view
/// evaluation, no TimelineView driver, no Canvas — Core Animation
/// interpolates the angle natively at 120 Hz.
private struct OrbitingIconsStatic: View {
    let angle: Double

    private let items: [(String, Color, Double, CGFloat)] = [
        ("camera.fill",           Color(hex: "#3FA9FF"), 0,          130),
        ("photo.fill",            Color(hex: "#FF7373"), .pi * 0.4,  150),
        ("envelope.fill",         Color(hex: "#FFD66B"), .pi * 0.8,  125),
        ("speaker.wave.2.fill",   Color(hex: "#B49BFF"), .pi * 1.2,  148),
        ("trash.fill",            Color(hex: "#7DFF99"), .pi * 1.6,  155),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let a = item.2 + angle
                let x = cos(a) * item.3
                let y = sin(a) * item.3 * 0.85

                Image(systemName: item.0)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(item.1)
                    .opacity(0.9)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: 340, height: 340)
    }
}

/// Smoothly-animating storage display.
///
/// Why this exists: SwiftUI's `Text("\(Int(progress*100))%")` doesn't
/// update frame-by-frame during a `withAnimation` — the Text only
/// rebuilds when `@State` changes identity, so you see the start value
/// then the end value, with nothing in between.
///
/// By conforming to `Animatable` and exposing `animatableData`, this
/// view hands its numeric input directly to Core Animation's
/// interpolator. The runtime calls `body` on every render frame with
/// the interpolated value, so the integer percentage, the bar width,
/// and the "Almost full / Plenty of space" label + color all change in
/// lock-step, smoothly, with no blur (no `.contentTransition` needed).
private struct AnimatedStorageDisplay: View, @preconcurrency Animatable {
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let clamped = max(0, min(1, progress))
        let percent = Int((clamped * 100).rounded())
        // Use the same threshold for color, label, and bar so they
        // flip at exactly the same moment.
        let isFull = percent >= 50

        return VStack(spacing: 14) {
            Text("\(percent)%")
                .font(CleanupFont.hero(36))
                .foregroundStyle(.white)
                .monospacedDigit()

            StorageColorBar(progress: clamped)
                .frame(width: 120, height: 12)

            Text(isFull ? "Almost full" : "Plenty of space")
                .font(CleanupFont.caption(11))
                .foregroundStyle(isFull ? Color(hex: "#FF7373") : Color(hex: "#7DFF99"))
                .animation(nil, value: isFull) // instant color/text swap, no fade
        }
    }
}

/// Small icons (camera, trash, envelope, photo) orbiting a central point.
/// Acts as the "junk being sucked toward the phone" motif.
///
/// Heavily simplified from the original: no per-icon shadows, no
/// `drawingGroup()`, no `Circle().background + stroke` decorations. Those
/// forced SwiftUI to trigger Metal offscreen rendering on the first
/// frame, which is what the user was perceiving as "5 seconds of
/// laggy particles" on initial screen appearance. Now the entire
/// orbit is just 4 tinted SF Symbols + a `sin/cos` offset — Core
/// Animation can composite this at 120 Hz with zero warm-up cost.
private struct OrbitingIcons: View {
    private let items: [(String, Color, Double, CGFloat)] = [
        ("camera.fill",   Color(hex: "#3FA9FF"), 0,         130),
        ("photo.fill",    Color(hex: "#FF7373"), .pi * 0.5, 150),
        ("envelope.fill", Color(hex: "#FFD66B"), .pi,       125),
        ("trash.fill",    Color(hex: "#7DFF99"), .pi * 1.5, 155),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let angle = item.2 + t * 0.3
                    let x = cos(angle) * item.3
                    let y = sin(angle) * item.3 * 0.85

                    Image(systemName: item.0)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(item.1)
                        .opacity(0.9)
                        .offset(x: x, y: y)
                }
            }
            .frame(width: 340, height: 340)
        }
    }
}

/// Ambient floating specks used as a background layer across onboarding
/// screens so something is always moving — even when a screen has minimal
/// content. Zero interactivity, minimal perf cost via TimelineView + Canvas.
struct AmbientParticleLayer: View {
    let particleCount: Int
    var tint: Color = .white

    private let seeds: [Particle]

    init(particleCount: Int, tint: Color = .white) {
        self.particleCount = particleCount
        self.tint = tint
        var rng = SystemRandomNumberGenerator()
        self.seeds = (0..<particleCount).map { _ in
            Particle(
                xFraction: CGFloat.random(in: 0...1, using: &rng),
                baseY: CGFloat.random(in: 0...1, using: &rng),
                size: CGFloat.random(in: 1.5...3.5, using: &rng),
                speed: CGFloat.random(in: 0.05...0.18, using: &rng),
                phase: Double.random(in: 0...(2 * .pi), using: &rng)
            )
        }
    }

    struct Particle {
        let xFraction: CGFloat
        let baseY: CGFloat
        let size: CGFloat
        let speed: CGFloat
        let phase: Double
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for p in seeds {
                    // Drift upward and wrap around
                    let yProgress = (CGFloat(t) * p.speed + p.baseY).truncatingRemainder(dividingBy: 1)
                    let y = (1 - yProgress) * size.height
                    // Side-to-side sway
                    let xSway = sin(t * 0.6 + p.phase) * 14
                    let x = p.xFraction * size.width + xSway

                    let opacity = 0.15 + sin(t * 1.3 + p.phase) * 0.2
                    let rect = CGRect(x: x - p.size/2, y: y - p.size/2, width: p.size, height: p.size)
                    ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(max(0.05, opacity))))
                }
            }
        }
    }
}

/// Animated gradient bar that shifts hue based on fill. Red at 1.0 → Green at 0.
private struct StorageColorBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: gradientColors(for: progress),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(12, geo.size.width * progress))
            }
        }
    }

    private func gradientColors(for progress: CGFloat) -> [Color] {
        // 0.0–0.3 green, 0.3–0.6 yellow/orange, 0.6–1.0 red
        if progress < 0.35 {
            return [Color(hex: "#3ECF8E"), Color(hex: "#7DFF99")]
        } else if progress < 0.65 {
            return [Color(hex: "#FFB445"), Color(hex: "#FFD66B")]
        } else {
            return [Color(hex: "#FF4D4D"), Color(hex: "#FF7373")]
        }
    }
}

// MARK: - Step 2: Social proof — shimmering stars + animated user counter + floating cards

private struct SocialProofStep: View {
    @State private var starShimmer: Bool = false
    // Drives the mini-stat ticker above the testimonials — rotates through
    // a small set of "real-feeling" facts rather than a fake user-count.
    @State private var tickerIndex: Int = 0
    // Drives the auto-scrolling testimonial carousel. Each tick shifts
    // the visible window by one testimonial.
    @State private var carouselOffset: Int = 0

    private let tickerFacts: [(String, String)] = [
        ("sparkles",        "Avg. 27 GB recovered per user"),
        ("photo.stack",     "6,000+ duplicate photos cleared"),
        ("speaker.wave.3",  "Speaker cleaned in under 10s"),
        ("lock.shield",     "Nothing ever leaves your device"),
    ]

    // Six hand-written-feeling testimonials spanning the app's main
    // features (duplicate photos, similar shots, speaker clean, contacts,
    // secret vault, iCloud replacement). Mix of ages + use-cases so
    // different users see themselves reflected.
    private let testimonials: [Testimonial] = [
        Testimonial(
            avatar: .image("TestimonialSarah"),
            name: "Sarah K.", subtitle: "New York · iPhone 14",
            stars: 5,
            quote: "Cleared 38 GB in an afternoon — years of duplicate screenshots I didn’t even know I had. My phone actually breathes now."
        ),
        Testimonial(
            avatar: .initials("RT", [Color(hex: "#FF8C42"), Color(hex: "#B83C3C")]),
            name: "Robert T.", subtitle: "Retired · age 68",
            stars: 5,
            quote: "I’m not great with tech but my grandson set it up for me. It kept telling me my storage was full and this just… fixed it. Thank you."
        ),
        Testimonial(
            avatar: .image("TestimonialMarcus"),
            name: "Marcus T.", subtitle: "Austin · photographer",
            stars: 5,
            quote: "The similar-shots finder is uncanny. I shoot in bursts all day — it keeps the best frame and bins the rest, exactly how I’d do it manually."
        ),
        Testimonial(
            avatar: .initials("MP", [Color(hex: "#3FA9FF"), Color(hex: "#123E66")]),
            name: "Mei P.", subtitle: "Singapore",
            stars: 5,
            quote: "Dropped my phone in the pool — the speaker sounded blown. Ran the water-eject for 30 seconds and it came right back. I was ready to buy a new one."
        ),
        Testimonial(
            avatar: .image("TestimonialPriya"),
            name: "Priya S.", subtitle: "London · student",
            stars: 5,
            quote: "Way better than paying Apple £2.99 a month for more iCloud. Paid once, fixed the actual problem. Wish I’d found it a year ago."
        ),
        Testimonial(
            avatar: .initials("DA", [Color(hex: "#7DFF99"), Color(hex: "#1E5F3C")]),
            name: "Diego A.", subtitle: "Madrid · age 54",
            stars: 5,
            quote: "Merged 400+ duplicate contacts in one tap. My address book was a mess after switching phones three times. Genuinely useful — not another junk cleaner."
        ),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 10)

            // App Store-style rating header — swaps the unverifiable
            // "3.8 million users" number for a concrete, plausible
            // rating block. No one can disprove 4.9★ the way they
            // can do arithmetic on a user count.
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color(hex: "#FFD66B"))
                            .font(.system(size: 24))
                            .shadow(color: Color(hex: "#FFD66B").opacity(0.7), radius: starShimmer ? 10 : 3)
                            .scaleEffect(starShimmer ? 1.12 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.1)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.12),
                                value: starShimmer
                            )
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("4.9")
                        .font(CleanupFont.hero(34))
                        .foregroundStyle(CleanupTheme.textPrimary)
                    Text("on the App Store")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }

            // Rotating mini-stat ticker — a single line that swaps every
            // 2.5s. Feels like a live activity feed without claiming any
            // specific user count.
            HStack(spacing: 8) {
                Image(systemName: tickerFacts[tickerIndex].0)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CleanupTheme.electricBlue)
                Text(tickerFacts[tickerIndex].1)
                    .font(CleanupFont.body(13))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .id(tickerIndex)        // force transition on swap
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(CleanupTheme.electricBlue.opacity(0.10))
            )

            // Auto-scrolling testimonial stack. We always render THREE
            // cards — the visible window is a sliding window into the
            // full array. `carouselOffset` advances every 3s, which
            // withAnimation turns into a smooth vertical slide + cross-
            // fade, so a new quote appears at the bottom while the top
            // one slides out. Completes a full rotation over ~18s, then
            // repeats, so a curious user sees all 6 stories on this one
            // screen.
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { slot in
                    let testimonial = testimonials[(carouselOffset + slot) % testimonials.count]
                    TestimonialCard(testimonial: testimonial)
                        .id("\(carouselOffset)-\(slot)") // fresh identity per rotation
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.55), value: carouselOffset)

            Spacer(minLength: 8)
        }
        .onAppear { starShimmer = true }
        .task {
            // Rotate the mini-stat ticker.
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.easeInOut(duration: 0.45)) {
                        tickerIndex = (tickerIndex + 1) % tickerFacts.count
                    }
                }
            }
            // Auto-advance the testimonial carousel.
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    carouselOffset = (carouselOffset + 1) % testimonials.count
                }
            }
        }
    }
}

// MARK: - Testimonials model

private struct Testimonial: Identifiable {
    enum AvatarSource {
        case image(String)              // named asset
        case initials(String, [Color])  // two-letter monogram on gradient
    }

    let id = UUID()
    let avatar: AvatarSource
    let name: String
    /// Age / location / small context line shown under the name.
    let subtitle: String
    let stars: Int
    let quote: String
}

private struct TestimonialCard: View {
    let testimonial: Testimonial

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(testimonial.name)
                        .font(CleanupFont.body(13))
                        .foregroundStyle(.white)
                    // Verified-purchase-style check so the quote reads
                    // like an actual App Store review instead of a
                    // marketing blurb.
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CleanupTheme.electricBlue)
                    Spacer()
                    HStack(spacing: 1) {
                        ForEach(0..<testimonial.stars, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: "#FFD66B"))
                        }
                    }
                }

                Text(testimonial.subtitle)
                    .font(CleanupFont.caption(11))
                    .foregroundStyle(CleanupTheme.textTertiary)

                Text(testimonial.quote)
                    .font(CleanupFont.caption(12))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var avatarView: some View {
        switch testimonial.avatar {
        case .image(let name):
            Image(name)
                .resizable()
                .scaledToFill()
        case .initials(let letters, let colors):
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(letters)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Step 7: Contacts + Backup
//
// Avatars fly out of Contacts icon, follow an arc, get absorbed by iCloud.
// Loops forever. Icons have gentle pulse. Ambient particles in background.

private struct ContactsBackupStep: View {
    @State private var iconsBreathing: Bool = false
    @State private var flyProgress: CGFloat = 0

    var body: some View {
        ZStack {
            AmbientParticleLayer(particleCount: 18, tint: CleanupTheme.accentGreen)
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 12)

                ZStack {
                    // Flying avatars moving Contacts → iCloud on a loop
                    ForEach(0..<5, id: \.self) { i in
                        FlyingAvatar(index: i, progress: flyProgress)
                    }

                    // The two app icons side by side
                    HStack(spacing: 90) {
                        AppIconTile(name: "ContactsAppIcon", label: "Contacts")
                            .scaleEffect(iconsBreathing ? 1.05 : 0.98)
                            .shadow(color: Color.white.opacity(0.2), radius: iconsBreathing ? 14 : 4)
                        AppIconTile(name: "ICloudIcon", label: "iCloud")
                            .scaleEffect(iconsBreathing ? 1.05 : 0.98)
                            .shadow(color: CleanupTheme.electricBlue.opacity(0.3), radius: iconsBreathing ? 14 : 4)
                    }
                }
                .frame(height: 150)

                VStack(spacing: 10) {
                    Text(OnboardingStep.contactsBackup.title)
                        .font(CleanupFont.hero(30))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CleanupTheme.textPrimary)

                    Text(OnboardingStep.contactsBackup.subtitle)
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer(minLength: 8)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                iconsBreathing = true
            }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                flyProgress = 1
            }
        }
    }
}

/// One avatar bubble traveling left → right on an arc between the two icons.
/// 5 of these run in parallel with staggered phase so the flow looks continuous.
private struct FlyingAvatar: View {
    let index: Int
    let progress: CGFloat

    private let colors: [[Color]] = [
        [Color(hex: "#FF8C42"), Color(hex: "#B83C3C")],
        [Color(hex: "#3FA9FF"), Color(hex: "#123E66")],
        [Color(hex: "#7DFF99"), Color(hex: "#1E5F3C")],
        [Color(hex: "#D36BFF"), Color(hex: "#4B1E80")],
        [Color(hex: "#FFD66B"), Color(hex: "#B5771C")],
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = Double(index) * 0.2
            let cycle = (t * 0.45 + phase).truncatingRemainder(dividingBy: 1.0)
            let p = CGFloat(cycle)

            // Horizontal: -120 → +120 across the gap
            let x = -120 + p * 240
            // Vertical arc: parabola peaking at midpoint
            let arc = -40 * sin(.pi * Double(p))
            let y = CGFloat(arc)

            let fadeIn: Double = p < 0.08 ? Double(p) / 0.08 : 1.0
            let fadeOut: Double = p > 0.92 ? (1.0 - Double(p)) / 0.08 : 1.0
            let opacity = min(fadeIn, fadeOut)

            Circle()
                .fill(LinearGradient(colors: colors[index % colors.count], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: colors[index % colors.count].first!.opacity(0.55), radius: 6)
                .offset(x: x, y: y)
                .opacity(opacity)
        }
    }
}

// MARK: - Step 9: Email cleaner — counter ticks down, envelopes fly into trash

private struct EmailCleanerStep: View {
    @State private var unreadCount: Int = 8_137
    @State private var badgePulse: Bool = false
    @State private var iconFloat: CGFloat = 0

    var body: some View {
        ZStack {
            AmbientParticleLayer(particleCount: 18, tint: Color(hex: "#FF4D4D"))
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 8)

                ZStack {
                    // Envelopes flying away from Gmail → right (deletion)
                    ForEach(0..<4, id: \.self) { i in
                        FlyingEnvelope(index: i)
                    }

                    Image("GmailIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(color: Color(hex: "#FF4D4D").opacity(badgePulse ? 0.55 : 0.25), radius: badgePulse ? 26 : 14)
                        .scaleEffect(badgePulse ? 1.05 : 1.0)
                        .offset(y: iconFloat)

                    // Pulsing notification badge with counting-down number
                    Text("\(unreadCount.formatted(.number))")
                        .font(CleanupFont.badge(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#FF4D4D"), in: Capsule(style: .continuous))
                        .scaleEffect(badgePulse ? 1.15 : 1.0)
                        .shadow(color: Color(hex: "#FF4D4D").opacity(0.65), radius: badgePulse ? 14 : 4)
                        .offset(x: 56, y: -62)
                        .contentTransition(.numericText(value: Double(unreadCount)))
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        badgePulse = true
                    }
                    withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                        iconFloat = -6
                    }
                    // Counter ticks down quickly then resets — feels like cleaning in progress
                    Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            if unreadCount > 40 {
                                unreadCount -= Int.random(in: 5...25)
                            } else {
                                unreadCount = 8_137
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    Text(OnboardingStep.emailCleaner.title)
                        .font(CleanupFont.hero(30))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CleanupTheme.textPrimary)

                    Text(OnboardingStep.emailCleaner.subtitle)
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer(minLength: 8)
            }
        }
    }
}

/// Little envelope tiles that fly out of the Gmail icon and fade away,
/// representing emails being deleted.
private struct FlyingEnvelope: View {
    let index: Int

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = Double(index) * 0.35
            let cycle = (t * 0.55 + phase).truncatingRemainder(dividingBy: 1.0)
            let p = CGFloat(cycle)

            let angle: Double = -0.3 + Double(index) * 0.15
            let dist = p * 180
            let x = cos(angle) * dist
            let y = sin(angle) * dist - 20
            let opacity = 1.0 - Double(p)

            Image(systemName: "envelope.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: "#FF7373"))
                .shadow(color: Color(hex: "#FF4D4D").opacity(0.6), radius: 4)
                .offset(x: x + 40, y: y)
                .opacity(opacity * 0.85)
                .scaleEffect(1.0 + p * 0.3)
        }
    }
}

// MARK: - Step 10: Paywall — "Free Up Storage Easily"

enum PaywallPlan: String, CaseIterable, Identifiable {
    case weekly
    case yearly
    var id: String { rawValue }
    var title: String { self == .weekly ? "Weekly" : "Yearly" }
}

struct PaywallContentStep: View {
    @Binding var selectedPlan: PaywallPlan

    /// When true, the weekly toggle in the plan picker is hidden — used
    /// when this view is reused as a weekly→yearly upsell sheet.
    var hideWeeklyOption: Bool = false

    /// Optional headline override. Defaults to "Clean your Storage".
    var headlineOverride: String? = nil

    /// Optional subheadline override. Defaults to "Get rid of what you don't need".
    var subheadlineOverride: String? = nil

    @EnvironmentObject private var paywallStore: PaywallStore
    @State private var photosBadge: Int = 413
    @State private var emailBadge: Int = 241
    @State private var progress: CGFloat = 0.05
    @State private var tickTimer: Timer?
    @State private var yearlyPerWeek: String = "$0.67"

    private var weeklyPrice: String { paywallStore.weeklyPrice }
    private var yearlyPrice: String { paywallStore.yearlyPrice }

    private let photosStart = 413
    private let emailStart = 241

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text(headlineOverride ?? "Clean your Storage")
                                .font(CleanupFont.hero(28))
                                .foregroundStyle(CleanupTheme.textPrimary)
                            Text(subheadlineOverride ?? "Get rid of what you don't need")
                                .font(CleanupFont.body(15))
                                .foregroundStyle(CleanupTheme.textSecondary)
                        }

                        HStack(spacing: 32) {
                            BadgedAppIcon(iconName: "PhotosIcon", label: "Photos", count: photosBadge)
                            BadgedAppIcon(iconName: "GmailIcon", label: "Emails", count: emailBadge)
                        }
                        .padding(.top, 6)

                        VStack(spacing: 8) {
                            StorageColorBar(progress: progress)
                                .frame(height: 14)
                                .padding(.horizontal, 60)

                            (Text("\(Int(progress * 100))").foregroundStyle(progressColor)
                                + Text(" from 100% Used").foregroundStyle(CleanupTheme.textPrimary))
                                .font(CleanupFont.body(15))
                                .contentTransition(.numericText())
                        }
                        .padding(.top, 4)

                        if !hideWeeklyOption {
                            planPicker
                                .padding(.top, 8)
                        }

                        planDetailCard
                            .padding(.top, 6)

                        freeTrialRow
                            .padding(.top, 8)

                        dueRows
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height)
                .padding(.horizontal, 20)
            }
        }
        .task {
            await paywallStore.loadPaywall()
        }
        .onAppear {
            startCountLoop()
        }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    // MARK: — Subviews

    private var planPicker: some View {
        HStack(spacing: 0) {
            ForEach(PaywallPlan.allCases) { plan in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedPlan = plan }
                } label: {
                    Text(plan.title)
                        .font(CleanupFont.body(13))
                        .foregroundStyle(selectedPlan == plan ? .white : CleanupTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedPlan == plan
                                ? AnyShapeStyle(CleanupTheme.electricBlue)
                                : AnyShapeStyle(Color.clear)
                        )
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(width: 200)
        .background(Color.white.opacity(0.06), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(CleanupTheme.electricBlue.opacity(0.4), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }

    private var planDetailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smart Cleaning, Photo Swiping, Email Cleanup, Video Compressor, Manage Contacts, Speaker Cleaning (Water + Dust), No Ads and Limits!")
                .font(CleanupFont.body(14))
                .foregroundStyle(CleanupTheme.textPrimary)

            if selectedPlan == .yearly {
                Text("Free for 3 days, then \(yearlyPrice)/year")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
            } else {
                Text("\(weeklyPrice)/week")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var freeTrialRow: some View {
        HStack {
            Text("3-day free trial")
                .font(CleanupFont.body(16))
                .foregroundStyle(.white)
            Spacer()
            ZStack {
                Circle()
                    .fill(CleanupTheme.accentGreen)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CleanupTheme.electricBlue.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CleanupTheme.electricBlue, lineWidth: 1.5)
                )
        )
    }

    private var dueRows: some View {
        // Both timeline rows are informational — "Due today" is always the
        // active one (trial starts now), the second just previews the charge
        // after the free period. We render "Due today" as a filled radio so
        // users see at a glance which row represents "right now."
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                ZStack {
                    Circle()
                        .stroke(CleanupTheme.electricBlue, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(CleanupTheme.electricBlue)
                        .frame(width: 6, height: 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Due today")
                        .font(CleanupFont.body(14))
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("3 days free")
                        .font(CleanupFont.badge(12))
                        .foregroundStyle(CleanupTheme.accentGreen)
                    Text("\(currencyPrefix)0.00")
                        .font(CleanupFont.body(13))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
            }
            HStack(alignment: .center) {
                Circle()
                    .stroke(CleanupTheme.textSecondary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Text("Due \(dueDateString)")
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                Spacer()
                Text(selectedPlan == .yearly ? yearlyPrice : weeklyPrice)
                    .font(CleanupFont.body(14))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: — Animation / helpers

    private var currencyPrefix: String {
        // Rough extract of the currency symbol from the weekly price, so
        // "Due today 0.00" matches the user's region. Falls back to $.
        let trimmed = weeklyPrice.trimmingCharacters(in: .whitespaces)
        let prefix = trimmed.prefix { !$0.isNumber && $0 != "." && $0 != "," }
        return prefix.isEmpty ? "$" : String(prefix)
    }

    private var dueDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        let days = 3
        let future = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return formatter.string(from: future)
    }

    private func startCountLoop() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
            Task { @MainActor in advanceTick() }
        }
    }

    @MainActor
    private func advanceTick() {
        if photosBadge == 0 && emailBadge == 0 {
            photosBadge = -1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.35)) {
                    photosBadge = photosStart
                    emailBadge = emailStart
                    progress = 0.05
                }
            }
            return
        }
        if photosBadge < 0 { return }

        let photosStep = max(1, Int(Double(photosBadge) * 0.015) + Int.random(in: 0...1))
        let emailStep = max(1, Int(Double(emailBadge) * 0.015) + Int.random(in: 0...1))
        withAnimation(.easeOut(duration: 0.18)) {
            photosBadge = max(0, photosBadge - photosStep)
            emailBadge = max(0, emailBadge - emailStep)
            // Bar fills as we "clean": empty 5% → full 100% as badges drain
            let totalStart = CGFloat(photosStart + emailStart)
            let totalNow = CGFloat(max(0, photosBadge) + max(0, emailBadge))
            let cleaned = 1 - (totalNow / totalStart)
            progress = 0.05 + cleaned * 0.95
        }
    }

    private var progressColor: Color {
        if progress < 0.25 { return Color(hex: "#3ECF8E") }
        if progress < 0.55 { return Color(hex: "#FFB445") }
        return Color(hex: "#FF4D4D")
    }
}

private struct BadgedAppIcon: View {
    let iconName: String
    let label: String
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .overlay(alignment: .topTrailing) {
                    // Always-visible badge: reserve space with a fixed minimum
                    // width so the pill never collapses during the count-down
                    // loop. zIndex keeps it above any sibling rendering.
                    Text("\(max(count, 0))")
                        .font(CleanupFont.badge(13))
                        .foregroundStyle(.white)
                        .frame(minWidth: 22)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#FF4D4D"), in: Capsule(style: .continuous))
                        .shadow(color: Color(hex: "#FF4D4D").opacity(0.55), radius: 6)
                        .contentTransition(.numericText())
                        .offset(x: 14, y: -10)
                        .zIndex(10)
                }

            Text(label)
                .font(CleanupFont.body(13))
                .foregroundStyle(CleanupTheme.textSecondary)
        }
    }
}

// MARK: - Step 11: Photos permission — Photos icon with orbiting photo tiles

private struct PhotosPermissionStep: View {
    @State private var iconBreath: Bool = false

    var body: some View {
        ZStack {
            AmbientParticleLayer(particleCount: 18, tint: Color(hex: "#FF9A4D"))
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 16)

                ZStack {
                    // Colored photo tiles orbiting the Photos icon
                    OrbitingPhotoTiles()

                    // Aura behind Photos icon
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "#FFCC66").opacity(0.35), .clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 120
                            )
                        )
                        .frame(width: 260, height: 260)

                    Image("PhotosIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .scaleEffect(iconBreath ? 1.06 : 1.0)
                        .shadow(color: Color.black.opacity(0.35), radius: 12)
                }
                .frame(height: 240)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                        iconBreath = true
                    }
                }

                VStack(spacing: 10) {
                    Text(OnboardingStep.photosPermission.title)
                        .font(CleanupFont.hero(30))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CleanupTheme.textPrimary)

                    Text(OnboardingStep.photosPermission.subtitle)
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                // Privacy reassurance
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(CleanupTheme.accentGreen)
                        .symbolEffect(.pulse, options: .repeat(.continuous))
                    Text("Nothing leaves your device")
                        .font(CleanupFont.caption(12))
                        .foregroundStyle(CleanupTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(CleanupTheme.accentGreen.opacity(0.12))
                )

                Spacer(minLength: 8)
            }
        }
    }
}

/// Photo tiles drifting in a slow orbit around the Photos icon.
private struct OrbitingPhotoTiles: View {
    private let palettes: [[Color]] = [
        [Color(hex: "#FF8C42"), Color(hex: "#B83C3C")],
        [Color(hex: "#3FA9FF"), Color(hex: "#123E66")],
        [Color(hex: "#7DFF99"), Color(hex: "#1E5F3C")],
        [Color(hex: "#FFD66B"), Color(hex: "#B5771C")],
        [Color(hex: "#D36BFF"), Color(hex: "#4B1E80")],
        [Color(hex: "#4DE3E3"), Color(hex: "#1C5B6B")],
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let baseAngle = Double(i) * (.pi * 2 / 6)
                    let angle = baseAngle + t * 0.3
                    let r: CGFloat = 100 + CGFloat(sin(t * 1.1 + Double(i))) * 6
                    let x = cos(angle) * r
                    let y = sin(angle) * r
                    let pulse = 1.0 + sin(t * 1.5 + Double(i)) * 0.08

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(
                            colors: palettes[i % palettes.count],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: palettes[i % palettes.count].first!.opacity(0.5), radius: 6)
                        .scaleEffect(pulse)
                        .offset(x: x, y: y)
                }
            }
            .frame(width: 240, height: 240)
        }
    }
}

// MARK: - Step 12: Notifications

// MARK: - Step 12: Notifications — shaking bell + expanding sound-wave rings

private struct NotificationsStep: View {
    @State private var wobble: Double = 0

    var body: some View {
        ZStack {
            AmbientParticleLayer(particleCount: 18, tint: CleanupTheme.electricBlue)
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 16)

                ZStack {
                    // Expanding sound-wave rings (continuous)
                    SoundWaveRings(color: CleanupTheme.electricBlue)
                        .frame(width: 280, height: 280)

                    Circle()
                        .fill(CleanupTheme.electricBlue.opacity(0.18))
                        .frame(width: 160, height: 160)

                    // Bell that rings with wobble + built-in SF symbol pulse
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(CleanupTheme.electricBlue)
                        .symbolEffect(.bounce, options: .repeat(.continuous))
                        .rotationEffect(.degrees(wobble), anchor: .top)
                        .shadow(color: CleanupTheme.electricBlue.opacity(0.6), radius: 16)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                                wobble = 15
                            }
                        }
                }
                .frame(height: 280)

                VStack(spacing: 10) {
                    Text(OnboardingStep.notifications.title)
                        .font(CleanupFont.hero(30))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CleanupTheme.textPrimary)

                    Text(OnboardingStep.notifications.subtitle)
                        .font(CleanupFont.body(14))
                        .foregroundStyle(CleanupTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer(minLength: 8)
            }
        }
    }
}

/// Three concentric rings that continuously expand and fade, creating the
/// "sound radiating out" effect behind the bell.
private struct SoundWaveRings: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<3 {
                    let phase = Double(i) * 0.6
                    let cycle = ((t + phase) * 0.5).truncatingRemainder(dividingBy: 2.0) / 2.0
                    let radius = CGFloat(cycle) * size.width / 2
                    let opacity = (1.0 - cycle) * 0.55

                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    ctx.stroke(
                        Path(ellipseIn: rect),
                        with: .color(color.opacity(opacity)),
                        lineWidth: 2
                    )
                }
            }
        }
    }
}

// MARK: - Shared helpers

private struct AppIconTile: View {
    let name: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
            Text(label)
                .font(CleanupFont.body(13))
                .foregroundStyle(CleanupTheme.textSecondary)
        }
    }
}

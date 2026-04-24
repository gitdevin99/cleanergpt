import SwiftUI
import WidgetKit

/// Step-by-step coach marks for installing a widget on the Home Screen or
/// Lock Screen. Pure SwiftUI — no external assets. Animated finger taps draw
/// attention to the active step.
struct WidgetInstallGuideView: View {
    let screen: WidgetGalleryView.InstallScreen

    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 0
    @State private var pulse = false

    private var steps: [Step] {
        switch screen {
        case .home:
            return [
                Step(icon: "hand.tap.fill",
                     title: "Long-press your Home Screen",
                     body: "Tap and hold anywhere on an empty spot until the apps start to jiggle."),
                Step(icon: "plus.app.fill",
                     title: "Tap the + in the top corner",
                     body: "Opens the widget picker with every widget installed on your phone."),
                Step(icon: "sparkles",
                     title: "Search for “Cleaner GPT”",
                     body: "Pick the widget you want, choose a size, and tap Add Widget."),
                Step(icon: "checkmark.seal.fill",
                     title: "Position it and tap Done",
                     body: "Your live data will start flowing in within a few seconds.")
            ]
        case .lock:
            return [
                Step(icon: "lock.fill",
                     title: "Lock your phone, then long-press",
                     body: "Long-press the Lock Screen until the Customize button appears."),
                Step(icon: "paintbrush.fill",
                     title: "Tap Customize → Lock Screen",
                     body: "Tap the widget slot below the clock."),
                Step(icon: "square.grid.2x2.fill",
                     title: "Pick a Cleaner GPT widget",
                     body: "Battery, Storage, and Quick Clean all fit on the Lock Screen."),
                Step(icon: "checkmark.seal.fill",
                     title: "Tap Done",
                     body: "Your widget will live-update right from the Lock Screen.")
            ]
        }
    }

    var body: some View {
        ZStack {
            CleanupTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $step) {
                    ForEach(steps.indices, id: \.self) { i in
                        stepPage(steps[i], index: i)
                            .tag(i)
                            .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: step)

                dotsIndicator

                footer
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(screen == .home ? "Home Screen" : "Lock Screen")
                .font(CleanupFont.sectionTitle(18))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Step page

    private func stepPage(_ s: Step, index: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [CleanupTheme.electricBlue.opacity(0.35), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(pulse ? 1.06 : 0.94)
                    .opacity(pulse ? 0.9 : 0.5)

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 160, height: 160)
                    .overlay(
                        Circle().stroke(CleanupTheme.electricBlue.opacity(0.3), lineWidth: 1)
                    )

                Image(systemName: s.icon)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, CleanupTheme.electricBlue],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: CleanupTheme.electricBlue.opacity(0.5), radius: 18)

                // Animated finger tap — bottom-trailing of the icon
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .offset(x: 62, y: 52)
                    .scaleEffect(pulse ? 1.0 : 0.85)
                    .opacity(pulse ? 1.0 : 0.7)
            }

            VStack(spacing: 10) {
                Text("Step \(index + 1) of \(steps.count)")
                    .font(CleanupFont.caption(11))
                    .fontWeight(.semibold)
                    .foregroundStyle(CleanupTheme.electricBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(CleanupTheme.electricBlue.opacity(0.15), in: Capsule(style: .continuous))

                Text(s.title)
                    .font(CleanupFont.sectionTitle(22))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(s.body)
                    .font(CleanupFont.body(14))
                    .foregroundStyle(CleanupTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    // MARK: - Dots

    private var dotsIndicator: some View {
        HStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i == step ? CleanupTheme.electricBlue : Color.white.opacity(0.18))
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Text("Back")
                        .font(CleanupFont.body(15))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                if step == steps.count - 1 {
                    dismiss()
                } else {
                    withAnimation { step += 1 }
                }
            } label: {
                Text(step == steps.count - 1 ? "Done" : "Next")
                    .font(CleanupFont.body(15))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [CleanupTheme.electricBlue, CleanupTheme.electricBlue.opacity(0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: CleanupTheme.electricBlue.opacity(0.35), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Step model

    private struct Step {
        let icon: String
        let title: String
        let body: String
    }
}

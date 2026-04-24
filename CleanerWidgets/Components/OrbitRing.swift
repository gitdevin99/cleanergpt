import SwiftUI

/// A circular ring that can be filled as a single arc (Battery-style) or
/// split into multiple colored segments (Storage-by-category style).
///
/// The "segmented" mode is our core differentiator vs. the competitor —
/// their storage widget shows one flat blue fill; ours shows photos /
/// videos / apps / other as distinct wedges around the same ring.
struct OrbitRing: View {
    struct Segment: Identifiable, Equatable {
        let id: String
        let fraction: Double   // 0...1 of the ring
        let color: Color
    }

    var fraction: Double = 0          // Used when segments is empty.
    var segments: [Segment] = []
    var lineWidth: CGFloat = 10
    var trackColor: Color = Color.white.opacity(0.12)
    var ringFill: Color = .blue

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            if segments.isEmpty {
                Circle()
                    .trim(from: 0, to: CGFloat(fraction.clamped01))
                    .stroke(
                        AngularGradient(
                            colors: [ringFill.opacity(0.55), ringFill],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                // Cumulative offset so each segment picks up where the
                // previous one ended. Small gap between segments keeps the
                // wedges visually distinct without bezels.
                let gap: Double = 0.01
                let totalGap = gap * Double(segments.count)
                let availableFraction = max(0, 1 - totalGap)
                let normalizer = segments.reduce(0) { $0 + $1.fraction }
                let scale = normalizer > 0 ? availableFraction / normalizer : 0

                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let start = cumulativeStart(before: index, scale: scale, gap: gap)
                    let end = start + segment.fraction * scale
                    Circle()
                        .trim(from: CGFloat(start), to: CGFloat(end))
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }

    private func cumulativeStart(before index: Int, scale: Double, gap: Double) -> Double {
        var sum: Double = 0
        for i in 0..<index {
            sum += segments[i].fraction * scale + gap
        }
        return sum
    }
}

private extension Double {
    var clamped01: Double { Swift.max(0, Swift.min(1, self)) }
}

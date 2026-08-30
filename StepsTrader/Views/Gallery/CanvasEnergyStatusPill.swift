import SwiftUI

/// Compact daily-energy readout pinned under the Dynamic Island on Canvas.
///
/// It shows `remaining / earnedToday`, plus the day's static ceiling, and a
/// bar whose track is the product's 100 ceiling — not today's earnings. A
/// quiet dim band marks how far the day got; the bright fill marks what is
/// still unspent. There is deliberately no `Energy` caption, no reset timer,
/// no expand chevron and no metric chips: what used to be a card is now one
/// line the user reads without stopping.
struct CanvasEnergyStatusPill: View {
    let status: CanvasEnergyStatus
    var canPullDataPanel = false
    var onPullChanged: (CGFloat) -> Void = { _ in }
    var onPullEnded: (_ distance: CGFloat, _ velocity: CGFloat) -> Void = { _, _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let minWidth: CGFloat = 176
    private static let maxWidth: CGFloat = 208
    private static let minHeight: CGFloat = 58
    private static let progressHeight: CGFloat = 6

    private var textPrimary: Color { AppColors.Night.textPrimary }

    var body: some View {
        VStack(spacing: 7) {
            numbers
            progressBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth, minHeight: Self.minHeight)
        .glassCard(cornerRadius: 16, style: .lens)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "Daily energy", comment: "Canvas status pill – VoiceOver label")
        )
        .accessibilityValue(
            String(
                localized: "\(status.remaining) remaining of \(status.earned) earned today, out of \(status.maximum)",
                comment: "Canvas status pill – VoiceOver value"
            )
        )
        .accessibilityHint(
            canPullDataPanel
                ? String(localized: "Pull down to show canvas data", comment: "Canvas status pill – VoiceOver hint")
                : ""
        )
        .accessibilityIdentifier("canvas_energy_pill")
        .overlay {
            if canPullDataPanel {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(pullGesture)
            }
        }
    }

    private var numbers: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(status.remaining)")
                .font(.geist(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColors.brandAccent)

            // Not localizable copy — a separator between two numbers.
            Text(verbatim: "/")
                .font(.geist(size: 17, weight: .medium))
                .foregroundStyle(textPrimary.opacity(0.65))

            Text("\(status.earned)")
                .font(.geist(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(textPrimary)

            Spacer(minLength: 8)

            // The day's ceiling. Static, and quieter than the two numbers that
            // move, so it reads as the scale rather than as a third reading.
            Text("\(status.maximum)")
                .font(.geist(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(textPrimary.opacity(0.45))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .contrastingOnGlass()
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(textPrimary.opacity(0.20))

                // Everything earned today, as a quiet band: it shows how far
                // the day got, which spending no longer erases.
                Capsule(style: .continuous)
                    .fill(AppColors.brandAccent.opacity(0.35))
                    .frame(width: max(0, width * status.earnedProgress))

                // What is actually left to spend.
                Capsule(style: .continuous)
                    .fill(AppColors.brandAccent)
                    .frame(width: max(0, width * status.progress))
            }
        }
        .frame(height: Self.progressHeight)
        // Ease only, never a spring: an overshooting bar reads as a value the
        // user briefly did not have.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: status)
        // The numbers above already say this; VoiceOver should not repeat it.
        .accessibilityHidden(true)
    }

    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canPullDataPanel else { return }
                onPullChanged(max(0, value.translation.height))
            }
            .onEnded { value in
                guard canPullDataPanel else { return }
                onPullEnded(
                    max(0, value.translation.height),
                    max(0, value.velocity.height)
                )
            }
    }
}

#Preview {
    VStack(spacing: 16) {
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 58, baseEnergyToday: 72, maximum: EnergyDefaults.maxBaseEnergy))
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 40, baseEnergyToday: 60, maximum: EnergyDefaults.maxBaseEnergy))
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 40, maximum: EnergyDefaults.maxBaseEnergy))
    }
    .padding()
    .background(Color.black)
}

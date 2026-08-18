import SwiftUI

/// Compact daily-energy readout pinned under the Dynamic Island on Canvas.
///
/// It shows `remaining / earnedToday` and a bar whose track *is* today's
/// earnings — not the product's 100 ceiling. There is deliberately no `100`,
/// no `Energy` caption, no reset timer, no expand chevron and no metric chips:
/// what used to be a card is now one line the user reads without stopping.
struct CanvasEnergyStatusPill: View {
    let status: CanvasEnergyStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let minWidth: CGFloat = 148
    private static let maxWidth: CGFloat = 176
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
                localized: "\(status.remaining) remaining out of \(status.earned) earned today",
                comment: "Canvas status pill – VoiceOver value"
            )
        )
        .accessibilityIdentifier("canvas_energy_pill")
    }

    private var numbers: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(status.remaining)")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColors.brandAccent)

            // Not localizable copy — a separator between two numbers.
            Text(verbatim: "/")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(textPrimary.opacity(0.65))

            Text("\(status.earned)")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
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
                Capsule(style: .continuous)
                    .fill(AppColors.brandAccent)
                    .frame(width: max(0, width * status.progress))
            }
        }
        .frame(height: Self.progressHeight)
        // Ease only, never a spring: an overshooting bar reads as a value that
        // briefly went past what the user actually has.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: status)
        // The numbers above already say this; VoiceOver should not repeat it.
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 58, baseEnergyToday: 72))
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 0))
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 40))
    }
    .padding()
    .background(Color.black)
}

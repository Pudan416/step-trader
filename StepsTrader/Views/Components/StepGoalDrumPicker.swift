import SwiftUI

struct StepGoalDrumPicker: View {
    @Binding var value: Double
    @Environment(\.appTheme) private var theme
    @ScaledMetric private var separatorSize: CGFloat = 24
    @ScaledMetric private var labelSize: CGFloat = 10

    private let minSteps = 1000
    private let maxSteps = 99500

    private var digitValues: [Int] {
        let clamped = max(minSteps, min(maxSteps, Int(value)))
        return String(format: "%05d", clamped).map { Int(String($0))! }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                DrumDigitColumn(
                    digit: digitValues[0],
                    isInteractive: true,
                    onChange: { updateDigit(at: 0, to: $0) },
                    theme: theme
                )
                DrumDigitColumn(
                    digit: digitValues[1],
                    isInteractive: true,
                    onChange: { updateDigit(at: 1, to: $0) },
                    theme: theme
                )

                Text(",")
                    .font(.system(size: separatorSize, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.adaptiveMutedText)
                    .padding(.top, 16)

                DrumDigitColumn(
                    digit: digitValues[2],
                    isInteractive: false,
                    onChange: { _ in },
                    theme: theme
                )
                DrumDigitColumn(
                    digit: digitValues[3],
                    isInteractive: false,
                    onChange: { _ in },
                    theme: theme
                )
                DrumDigitColumn(
                    digit: digitValues[4],
                    isInteractive: false,
                    onChange: { _ in },
                    theme: theme
                )
            }
        }
    }

    private func updateDigit(at index: Int, to newDigit: Int) {
        var digits = digitValues
        digits[index] = newDigit
        let raw = digits[0] * 10000 + digits[1] * 1000 + digits[2] * 100 + digits[3] * 10 + digits[4]
        let rounded = (Double(raw) / 500.0).rounded() * 500
        let clamped = max(Double(minSteps), min(Double(maxSteps), rounded))
        withAnimation(.snappy(duration: 0.15)) { value = clamped }
    }
}

// MARK: - Single digit column

private struct DrumDigitColumn: View {
    let digit: Int
    let isInteractive: Bool
    let onChange: (Int) -> Void
    let theme: AppTheme

    @ScaledMetric private var activeDigitSize: CGFloat = 30
    @ScaledMetric private var inactiveDigitSize: CGFloat = 26
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        if isInteractive {
            activeColumn
        } else {
            passiveColumn
        }
    }

    private var activeColumn: some View {
        VStack(spacing: 2) {
            chevronButton(direction: .up)
            digitTile(active: true)
                .gesture(dragGesture)
            chevronButton(direction: .down)
        }
    }

    private var passiveColumn: some View {
        VStack(spacing: 2) {
            Color.clear.frame(width: 44, height: 24)
            digitTile(active: false)
            Color.clear.frame(width: 44, height: 24)
        }
    }

    private func digitTile(active: Bool) -> some View {
        Text("\(digit)")
            .font(.system(size: active ? activeDigitSize : inactiveDigitSize, weight: active ? .bold : .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(active ? theme.adaptivePrimaryText : theme.adaptiveMutedText)
            .offset(y: active ? dragOffset : 0)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.2), value: digit)
            .frame(width: 44, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? theme.backgroundSecondary.opacity(0.5) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                active
                                    ? AppColors.brandAccent.opacity(isDragging ? 0.5 : 0.15)
                                    : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private enum ChevronDirection { case up, down }

    private func chevronButton(direction: ChevronDirection) -> some View {
        let isUp = direction == .up
        let canMove = isUp ? digit < 9 : digit > 0
        return Button {
            onChange(isUp ? digit + 1 : digit - 1)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isUp ? "chevron.up" : "chevron.down")
                .font(.system(size: labelSize, weight: .bold))
                .foregroundStyle(canMove ? theme.adaptiveSecondaryText : theme.adaptiveMutedText.opacity(0.2))
                .frame(width: 44, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canMove)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { g in dragOffset = g.translation.height * 0.25 }
            .onEnded { g in
                let threshold: CGFloat = 15
                if g.translation.height < -threshold, digit < 9 {
                    onChange(digit + 1)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else if g.translation.height > threshold, digit > 0 {
                    onChange(digit - 1)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { dragOffset = 0 }
            }
    }
}

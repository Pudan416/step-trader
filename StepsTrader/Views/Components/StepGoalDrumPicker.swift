import SwiftUI

struct StepGoalDrumPicker: View {
    @Binding var value: Double
    @Environment(\.appTheme) private var theme

    private let minSteps = 1000
    private let maxSteps = 99500

    private var accessibilityLabel: String {
        String(localized: "Daily Steps Goal")
    }

    private var accessibilityValue: String {
        let steps = Int(value).formatted(.number)
        return String(
            localized: "\(steps) steps",
            comment: "Daily steps goal picker accessibility value"
        )
    }

    private var digitValues: [Int] {
        let clamped = max(minSteps, min(maxSteps, Int(value)))
        let str = String(clamped)
        let padded = String(repeating: "0", count: max(0, 5 - str.count)) + str
        return padded.compactMap { $0.wholeNumberValue }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                DrumDigitColumn(
                    digit: digitValues[0],
                    isInteractive: true,
                    onChange: { updateDigit(at: 0, to: $0) },
                    stepAmount: 10_000,
                    accessibilityValue: accessibilityValue,
                    accessibilityIdentifierPrefix: "settings.yourDay.steps.tenThousands",
                    theme: theme
                )
                DrumDigitColumn(
                    digit: digitValues[1],
                    isInteractive: true,
                    onChange: { updateDigit(at: 1, to: $0) },
                    stepAmount: 1_000,
                    accessibilityValue: accessibilityValue,
                    accessibilityIdentifierPrefix: "settings.yourDay.steps.thousands",
                    theme: theme
                )

                Text(",")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.adaptiveMutedText)
                    .padding(.top, 16)

                DrumDigitColumn(
                    digit: digitValues[2],
                    isInteractive: false,
                    onChange: { _ in },
                    stepAmount: 0,
                    accessibilityValue: accessibilityValue,
                    accessibilityIdentifierPrefix: "",
                    theme: theme
                )
                DrumDigitColumn(
                    digit: digitValues[3],
                    isInteractive: false,
                    onChange: { _ in },
                    stepAmount: 0,
                    accessibilityValue: accessibilityValue,
                    accessibilityIdentifierPrefix: "",
                    theme: theme
                )
                DrumDigitColumn(
                    digit: digitValues[4],
                    isInteractive: false,
                    onChange: { _ in },
                    stepAmount: 0,
                    accessibilityValue: accessibilityValue,
                    accessibilityIdentifierPrefix: "",
                    theme: theme
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("settings.yourDay.steps.adjustable")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustGoal(by: 500)
            case .decrement:
                adjustGoal(by: -500)
            @unknown default:
                break
            }
        }
    }

    private func adjustGoal(by amount: Double) {
        let updated = max(Double(minSteps), min(Double(maxSteps), value + amount))
        withAnimation(.snappy(duration: 0.15)) { value = updated }
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
    let stepAmount: Int
    let accessibilityValue: String
    let accessibilityIdentifierPrefix: String
    let theme: AppTheme

    @State private var dragOffset: CGFloat = 0
    @State private var lightHapticTick = 0
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
        .sensoryFeedback(.impact(weight: .light), trigger: lightHapticTick)
    }

    private var passiveColumn: some View {
        VStack(spacing: 2) {
            Color.clear.frame(width: 44, height: 44)
            digitTile(active: false)
            Color.clear.frame(width: 44, height: 44)
        }
        .accessibilityHidden(true)
    }

    private func digitTile(active: Bool) -> some View {
        Text("\(digit)")
            .font(.system(size: active ? 30 : 26, weight: active ? .bold : .semibold, design: .rounded))
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
            .accessibilityHidden(true)
    }

    private enum ChevronDirection { case up, down }

    private func chevronButton(direction: ChevronDirection) -> some View {
        let isUp = direction == .up
        let canMove = isUp ? digit < 9 : digit > 0
        return Button {
            onChange(isUp ? digit + 1 : digit - 1)
            lightHapticTick &+= 1
        } label: {
            Image(systemName: isUp ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(canMove ? theme.adaptiveSecondaryText : theme.adaptiveMutedText.opacity(0.2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canMove)
        .accessibilityLabel(
            isUp
                ? String(
                    localized: "Increase daily steps goal by \(stepAmount.formatted()) steps",
                    comment: "Daily steps goal picker increment button"
                )
                : String(
                    localized: "Decrease daily steps goal by \(stepAmount.formatted()) steps",
                    comment: "Daily steps goal picker decrement button"
                )
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(
            "\(accessibilityIdentifierPrefix).\(isUp ? "increment" : "decrement")"
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { g in dragOffset = g.translation.height * 0.25 }
            .onEnded { g in
                let threshold: CGFloat = 15
                if g.translation.height < -threshold, digit < 9 {
                    onChange(digit + 1)
                    lightHapticTick &+= 1
                } else if g.translation.height > threshold, digit > 0 {
                    onChange(digit - 1)
                    lightHapticTick &+= 1
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { dragOffset = 0 }
            }
    }
}

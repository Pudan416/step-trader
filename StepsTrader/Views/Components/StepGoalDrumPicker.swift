import SwiftUI

/// Shared validation for both the whole-value controls and precise numeric entry.
enum StepGoalValue {
    static let minimum: Double = 1_000
    static let maximum: Double = 99_500
    static let increment: Double = 500

    static func adjusted(_ value: Double, by amount: Double) -> Double {
        min(maximum, max(minimum, value + amount))
    }

    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.compactMap(\.wholeNumberValue)
        guard digits.count == trimmed.count,
              let number = Double(digits.map(String.init).joined()),
              (minimum...maximum).contains(number) else { return nil }
        return number
    }
}

struct StepGoalDrumPicker: View {
    @Binding var value: Double
    @Environment(\.appTheme) private var theme
    @State private var isEditing = false
    @State private var exactValue = ""

    private var accessibilityValue: String {
        let steps = Int(value).formatted(.number)
        return String(localized: "\(steps) steps", comment: "Daily steps goal picker accessibility value")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                stepButton(increasing: false)

                Button {
                    exactValue = String(Int(value))
                    isEditing = true
                } label: {
                    VStack(spacing: 1) {
                        Text(Int(value).formatted(.number))
                            .font(.geist(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.adaptivePrimaryText)
                            .contentTransition(.numericText())
                        HStack(spacing: 4) {
                            Text(String(localized: "steps"))
                            Image(systemName: "pencil")
                        }
                        .font(.geist(.caption).weight(.medium))
                        .foregroundStyle(theme.adaptiveSecondaryText)
                    }
                    .frame(minWidth: 100, minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Enter exact step goal"))
                .accessibilityHint(String(localized: "Adjust by 500 steps, or tap the number to enter a goal."))
                .accessibilityValue(accessibilityValue)
                .accessibilityIdentifier("settings.yourDay.steps.exactValue")

                stepButton(increasing: true)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Daily step goal"))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("settings.yourDay.steps.adjustable")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: StepGoalValue.increment)
            case .decrement: adjust(by: -StepGoalValue.increment)
            @unknown default: break
            }
        }
        .alert(String(localized: "Daily step goal"), isPresented: $isEditing) {
            TextField(String(localized: "Steps"), text: $exactValue)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("settings.yourDay.steps.input")
            Button(String(localized: "Cancel"), role: .cancel) { }
            Button(String(localized: "Save")) {
                if let parsed = StepGoalValue.parse(exactValue) { value = parsed }
            }
            .disabled(StepGoalValue.parse(exactValue) == nil)
        } message: {
            Text(String(localized: "Enter a whole number from \(Int(StepGoalValue.minimum).formatted()) to \(Int(StepGoalValue.maximum).formatted()) steps."))
        }
    }

    private func adjust(by amount: Double) {
        withAnimation(.snappy(duration: 0.15)) {
            value = StepGoalValue.adjusted(value, by: amount)
        }
    }

    private func stepButton(increasing: Bool) -> some View {
        let enabled = increasing ? value < StepGoalValue.maximum : value > StepGoalValue.minimum
        return Button {
            adjust(by: increasing ? StepGoalValue.increment : -StepGoalValue.increment)
        } label: {
            Image(systemName: increasing ? "plus" : "minus")
                .font(.geist(size: 15, weight: .bold))
                .foregroundStyle(enabled ? theme.adaptivePrimaryText : theme.adaptiveMutedText.opacity(0.3))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(theme.backgroundSecondary.opacity(0.5))
                        .overlay(Circle().stroke(theme.adaptiveDividerColor, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(increasing
            ? String(localized: "Increase daily steps goal by \(Int(StepGoalValue.increment).formatted()) steps", comment: "Daily steps goal picker increment button")
            : String(localized: "Decrease daily steps goal by \(Int(StepGoalValue.increment).formatted()) steps", comment: "Daily steps goal picker decrement button"))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("settings.yourDay.steps.\(increasing ? "increment" : "decrement")")
    }
}

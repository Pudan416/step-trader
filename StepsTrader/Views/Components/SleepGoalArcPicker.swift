import SwiftUI

// MARK: - Day start time picker

struct DayResetTimePicker: View {
    @Binding var selectedMinutes: Int
    let allowedMinutes: [Int]
    @Environment(\.locale) private var locale

    @State private var showsPicker = false
    @State private var pendingMinutes = 0

    var body: some View {
        Button {
            pendingMinutes = selectedMinutes
            showsPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(timeLabel(selectedMinutes))
                    .font(.geist(.title3).weight(.semibold).monospacedDigit())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.geist(.caption))
            }
            .padding(.horizontal, 16)
            .frame(minWidth: 100, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Day starts at"))
        .accessibilityValue(timeLabel(selectedMinutes))
        .accessibilityIdentifier("settings.yourDay.boundary.picker")
        .sensoryFeedback(.impact(weight: .light), trigger: selectedMinutes)
        .sheet(isPresented: $showsPicker) {
            NavigationStack {
                Picker(String(localized: "Day starts at"), selection: $pendingMinutes) {
                    if !allowedMinutes.contains(pendingMinutes) {
                        Text(timeLabel(pendingMinutes)).tag(pendingMinutes)
                    }
                    ForEach(allowedMinutes, id: \.self) { minutes in
                        Text(timeLabel(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .accessibilityIdentifier("settings.yourDay.boundary.wheel")
                .navigationTitle(String(localized: "Day starts at"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showsPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            selectedMinutes = pendingMinutes
                            showsPicker = false
                        }
                        .accessibilityIdentifier("settings.yourDay.boundary.done")
                    }
                }
            }
            .presentationDetents([.height(320)])
        }

    }

    private func timeLabel(_ minutes: Int) -> String {
        SettingsYourDaySummary(
            stepsTarget: 0,
            sleepTargetHours: 0,
            dayEndHour: minutes / 60,
            dayEndMinute: minutes % 60
        ).dayStartText(locale: locale)
    }
}

// MARK: - Sleep duration stepper

struct SleepDurationStepper: View {
    @Binding var hours: Double
    @Environment(\.appTheme) private var theme

    private let minHours: Double = 5
    private let maxHours: Double = 10
    private let step: Double = 0.5

    private var accessibilityLabel: String {
        String(localized: "Sleep goal")
    }

    private var accessibilityValue: String {
        String(
            localized: "\(formattedHours) hours",
            comment: "Sleep goal picker accessibility value"
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            stepButton(
                icon: "minus",
                enabled: hours > minHours,
                accessibilityLabel: String(
                    localized: "Decrease sleep goal",
                    comment: "Sleep goal picker decrement button"
                ),
                accessibilityIdentifier: "settings.yourDay.sleep.decrement"
            ) {
                withAnimation(.snappy(duration: 0.15)) { hours = max(minHours, hours - step) }
            }

            VStack(spacing: 1) {
                Text(formattedHours)
                    .font(.geist(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: hours)
                Text(String(localized: "hours"))
                    .font(.geist(.caption).weight(.medium))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            .frame(minWidth: 80)
            .accessibilityHidden(true)

            stepButton(
                icon: "plus",
                enabled: hours < maxHours,
                accessibilityLabel: String(
                    localized: "Increase sleep goal",
                    comment: "Sleep goal picker increment button"
                ),
                accessibilityIdentifier: "settings.yourDay.sleep.increment"
            ) {
                withAnimation(.snappy(duration: 0.15)) { hours = min(maxHours, hours + step) }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hours)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("settings.yourDay.sleep.adjustable")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                withAnimation(.snappy(duration: 0.15)) {
                    hours = min(maxHours, hours + step)
                }
            case .decrement:
                withAnimation(.snappy(duration: 0.15)) {
                    hours = max(minHours, hours - step)
                }
            @unknown default:
                break
            }
        }
    }

    private var formattedHours: String {
        hours.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(hours))"
            : hours.formatted(.number.precision(.fractionLength(1)))
    }

    private func stepButton(
        icon: String,
        enabled: Bool,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

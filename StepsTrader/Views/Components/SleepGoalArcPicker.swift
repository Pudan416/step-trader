import SwiftUI

// MARK: - Day reset time picker (flip-clock)

struct DayResetTimePicker: View {
    @Binding var selectedMinutes: Int
    let allowedMinutes: [Int]

    private var allowedHours: [Int] {
        Array(Set(allowedMinutes.map { ($0 / 60) % 24 })).sorted { a, b in
            let order = [21, 22, 23, 0, 1, 2, 3]
            return (order.firstIndex(of: a) ?? a) < (order.firstIndex(of: b) ?? b)
        }
    }

    private let minuteSteps = [0, 15, 30, 45]

    private var currentHour: Int { (selectedMinutes / 60) % 24 }
    private var currentMinute: Int { selectedMinutes % 60 }

    var body: some View {
        HStack(spacing: 6) {
            FlipClockPanel(
                displayText: String(format: "%02d", currentHour),
                onIncrement: { stepHour(forward: true) },
                onDecrement: { stepHour(forward: false) }
            )

            Text(":")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .offset(y: -2)

            FlipClockPanel(
                displayText: String(format: "%02d", currentMinute),
                onIncrement: { stepMinute(forward: true) },
                onDecrement: { stepMinute(forward: false) }
            )
        }
    }

    private func stepHour(forward: Bool) {
        let hours = allowedHours
        guard let idx = hours.firstIndex(of: currentHour) else { return }
        let next = forward
            ? hours[(idx + 1) % hours.count]
            : hours[(idx - 1 + hours.count) % hours.count]
        let snappedMinute = minuteSteps.min(by: { abs($0 - currentMinute) < abs($1 - currentMinute) }) ?? 0
        let newTotal = next * 60 + snappedMinute
        commit(newTotal)
    }

    private func stepMinute(forward: Bool) {
        guard let idx = minuteSteps.firstIndex(of: currentMinute) else {
            commit(currentHour * 60)
            return
        }
        var nextMinuteIdx = forward ? idx + 1 : idx - 1
        var hour = currentHour
        if nextMinuteIdx >= minuteSteps.count {
            nextMinuteIdx = 0
            stepHourValue(forward: true, from: &hour)
        } else if nextMinuteIdx < 0 {
            nextMinuteIdx = minuteSteps.count - 1
            stepHourValue(forward: false, from: &hour)
        }
        commit(hour * 60 + minuteSteps[nextMinuteIdx])
    }

    private func stepHourValue(forward: Bool, from hour: inout Int) {
        let hours = allowedHours
        guard let idx = hours.firstIndex(of: hour) else { return }
        hour = forward
            ? hours[(idx + 1) % hours.count]
            : hours[(idx - 1 + hours.count) % hours.count]
    }

    private func commit(_ totalMinutes: Int) {
        let clamped = ((totalMinutes % (24 * 60)) + 24 * 60) % (24 * 60)
        guard allowedMinutes.contains(clamped) else { return }
        withAnimation(.snappy(duration: 0.15)) { selectedMinutes = clamped }
        // TODO: Migrate to .sensoryFeedback()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Single flip panel (hours or minutes)

private struct FlipClockPanel: View {
    let displayText: String
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    private let tileWidth: CGFloat = 88
    private let tileHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            chevronButton(up: true)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(isDragging ? 0.15 : 0.06), lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                        .frame(height: tileHeight / 2)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: tileHeight / 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                Text(displayText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: displayText)
                    .offset(y: dragOffset)
            }
            .frame(width: tileWidth, height: tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .gesture(
                DragGesture(minimumDistance: 5)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { g in dragOffset = g.translation.height * 0.2 }
                    .onEnded { g in
                        let threshold: CGFloat = 15
                        if g.translation.height < -threshold {
                            onIncrement()
                        } else if g.translation.height > threshold {
                            onDecrement()
                        }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { dragOffset = 0 }
                    }
            )

            chevronButton(up: false)
        }
    }

    private func chevronButton(up: Bool) -> some View {
        Button {
            if up { onIncrement() } else { onDecrement() }
        } label: {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: tileWidth, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sleep duration stepper

struct SleepDurationStepper: View {
    @Binding var hours: Double
    @Environment(\.appTheme) private var theme

    private let minHours: Double = 5
    private let maxHours: Double = 10
    private let step: Double = 0.5

    var body: some View {
        HStack(spacing: 16) {
            stepButton(icon: "minus", enabled: hours > minHours) {
                withAnimation(.snappy(duration: 0.15)) { hours = max(minHours, hours - step) }
                // TODO: Migrate to .sensoryFeedback()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            VStack(spacing: 1) {
                Text(formattedHours)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: hours)
                Text(String(localized: "hours"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            .frame(minWidth: 80)

            stepButton(icon: "plus", enabled: hours < maxHours) {
                withAnimation(.snappy(duration: 0.15)) { hours = min(maxHours, hours + step) }
                // TODO: Migrate to .sensoryFeedback()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private var formattedHours: String {
        hours.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(hours))"
            : hours.formatted(.number.precision(.fractionLength(1)))
    }

    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
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
    }
}

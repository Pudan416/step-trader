import SwiftUI

struct StepBalanceCard: View {
    let remainingSteps: Int
    let totalSteps: Int
    let spentSteps: Int
    let healthKitSteps: Int
    let dayEndHour: Int
    let dayEndMinute: Int
    let showDetails: Bool
    
    // Category points
    let stepsPoints: Int
    let sleepPoints: Int
    let bodyPoints: Int
    let mindPoints: Int
    let heartPoints: Int
    let baseEnergyToday: Int
    
    // Navigation handlers
    var onStepsTap: (() -> Void)? = nil
    var onSleepTap: (() -> Void)? = nil
    var onMoveTap: (() -> Void)? = nil
    var onRebootTap: (() -> Void)? = nil
    var onJoyTap: (() -> Void)? = nil
    var onColorsHelpTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    
    private let maxEnergy: Int = 100
    
    private var currentEnergy: Int {
        min(maxEnergy, remainingSteps)
    }
    
    private var progress: Double {
        guard maxEnergy > 0 else { return 0 }
        return min(1, Double(currentEnergy) / Double(maxEnergy))
    }

    private var earnedTodayProgress: Double {
        guard maxEnergy > 0 else { return 0 }
        return min(1, Double(baseEnergyToday) / Double(maxEnergy))
    }

    private var accent: Color { AppColors.brandAccent }
    private var balanceYellow: Color { AppColors.brandAccent }
    
    private static func formatTimeUntilReset(dayEndHour: Int, dayEndMinute: Int, now: Date = Date()) -> String {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.hour = dayEndHour
        comps.minute = dayEndMinute
        let nextReset = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
        let diff = max(0, nextReset.timeIntervalSince(now))
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // ── Header: TODAY'S COLORS + balance + timer ──
            HStack(alignment: .center, spacing: 4) {
                Image("colors")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(balanceYellow)
                    .frame(width: 51, height: 51)
                
                HStack(spacing: 4) {
                    Text("\(currentEnergy)")
                        .font(.title3.bold())
                        .foregroundColor(.black)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(balanceYellow))
                    
                    Text("/")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    Text("\(baseEnergyToday)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().strokeBorder(balanceYellow, lineWidth: 1.5))
                    
                    Text("/")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    Text("\(maxEnergy)")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
                
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    HStack(spacing: 3) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(Self.formatTimeUntilReset(dayEndHour: dayEndHour, dayEndMinute: dayEndMinute, now: timeline.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.primary)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(currentEnergy) of \(baseEnergyToday) earned, \(maxEnergy) maximum colors", comment: "StepBalanceCard – header VoiceOver label"))
            
            // ── Progress bar ──
            GeometryReader { proxy in
                let w = proxy.size.width
                let inset: CGFloat = 2
                let innerW = max(0, w - inset * 2)
                let fillWidth = max(0, innerW * progress)
                let earnedWidth = max(0, innerW * earnedTodayProgress)

                ZStack(alignment: .leading) {
                    // Earned outline (full earned width, sits behind fill)
                    if earnedWidth > 0 {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(balanceYellow, lineWidth: 1.5)
                            .frame(width: max(6, earnedWidth))
                    }
                    // Remaining fill (overlaps the left portion seamlessly)
                    if fillWidth > 0 {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(balanceYellow)
                            .frame(width: max(4, fillWidth))
                    }
                }
                .padding(inset)
                .frame(width: w, height: proxy.size.height, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Steps balance", comment: "StepBalanceCard – progress bar VoiceOver label"))
            .accessibilityValue(String(localized: "\(Int(progress * 100)) percent, \(currentEnergy) of \(maxEnergy) colors", comment: "StepBalanceCard – progress bar VoiceOver value"))
            .animation(.spring(response: 0.4), value: progress)
            .animation(.spring(response: 0.4), value: earnedTodayProgress)
            
            // ── Expand / Collapse toggle + ? help (same line) ──
            if showDetails {
                HStack(spacing: 8) {
                    Button {
                        onColorsHelpTap?()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "About colors", comment: "StepBalanceCard – info button VoiceOver label"))
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 80, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? String(localized: "Collapse categories", comment: "StepBalanceCard – toggle categories VoiceOver label") : String(localized: "Expand categories", comment: "StepBalanceCard – toggle categories VoiceOver label"))
                }
                .frame(minHeight: 30)
            }
            
            // ── Metric chips (two rows, icons only) ──
            if showDetails && isExpanded {
                VStack(spacing: 6) {
                    // Row 1: HealthKit auto-tracked
                    HStack(spacing: 8) {
                        metricChip(
                            icon: "shoeprints.fill",
                            value: stepsPoints,
                            max: EnergyDefaults.stepsMaxPoints,
                            accessibilityId: "chip_steps",
                            onTap: { onStepsTap?() }
                        )
                        metricChip(
                            icon: "bed.double.fill",
                            value: sleepPoints,
                            max: EnergyDefaults.sleepMaxPoints,
                            accessibilityId: "chip_sleep",
                            onTap: { onSleepTap?() }
                        )
                    }
                    
                    // Row 2: Card-based categories
                    HStack(spacing: 8) {
                        metricChip(
                            icon: "figure.walk",
                            value: bodyPoints,
                            max: 20,
                            accessibilityId: "chip_body",
                            onTap: { onMoveTap?() }
                        )
                        metricChip(
                            icon: "brain.head.profile",
                            value: mindPoints,
                            max: 20,
                            accessibilityId: "chip_mind",
                            onTap: { onRebootTap?() }
                        )
                        metricChip(
                            icon: "heart.fill",
                            value: heartPoints,
                            max: 20,
                            accessibilityId: "chip_heart",
                            onTap: { onJoyTap?() }
                        )
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(StepBalanceCardBackgroundModifier())
        .animation(.spring(response: 0.3), value: showDetails)
        .animation(.spring(response: 0.3), value: isExpanded)
    }
}

// MARK: - Background modifier (Liquid Glass on iOS 26+, dark on older)

private struct StepBalanceCardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Glass as background only so buttons stay on top for hit testing
            content
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

// MARK: - Metric chip

@ViewBuilder
private func metricChip(icon: String, value: Int, max: Int, accessibilityId: String, onTap: @escaping () -> Void) -> some View {
    Button(action: onTap) {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.primary.opacity(0.6))
            Spacer(minLength: 0)
            Text("\(value)/\(max)")
                .font(.caption.weight(.bold))
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityId)
}

#Preview {
    VStack(spacing: 20) {
        StepBalanceCard(
            remainingSteps: 85,
            totalSteps: 100,
            spentSteps: 15,
            healthKitSteps: 60,
            dayEndHour: 0,
            dayEndMinute: 0,
            showDetails: true,
            stepsPoints: 14,
            sleepPoints: 16,
            bodyPoints: 20,
            mindPoints: 15,
            heartPoints: 10,
            baseEnergyToday: 75
        )
        
        StepBalanceCard(
            remainingSteps: 45,
            totalSteps: 100,
            spentSteps: 55,
            healthKitSteps: 40,
            dayEndHour: 0,
            dayEndMinute: 0,
            showDetails: false,
            stepsPoints: 10,
            sleepPoints: 8,
            bodyPoints: 20,
            mindPoints: 15,
            heartPoints: 10,
            baseEnergyToday: 40
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

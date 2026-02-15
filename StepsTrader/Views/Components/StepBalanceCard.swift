import SwiftUI

struct StepBalanceCard: View {
    let remainingSteps: Int
    let totalSteps: Int
    let spentSteps: Int
    let healthKitSteps: Int
    let outerWorldSteps: Int
    let grantedSteps: Int
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
    var onOuterWorldTap: (() -> Void)? = nil
    
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

    private var accent: Color { AppColors.brandPink }
    private var balanceYellow: Color { .yellow }
    
    private var timeUntilReset: String {
        let now = Date()
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
            // ── Header: TODAY EXP + balance + timer ──
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("TODAY")
                        .font(.caption2.weight(.heavy))
                    Text("EXP")
                        .font(.title3.weight(.black))
                }
                .foregroundColor(colorScheme == .dark ? balanceYellow : .black)
                
                HStack(spacing: 4) {
                    // Current balance — yellow pill
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
                    
                    // Today's earned — outlined pill
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
                
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(timeUntilReset)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                }
            }
            
            // ── Progress bar ──
            GeometryReader { proxy in
                let w = proxy.size.width
                let inset: CGFloat = 2
                let innerW = max(0, w - inset * 2)
                let fillWidth = max(0, innerW * progress)
                let earnedWidth = max(0, innerW * earnedTodayProgress)
                let spentSegmentWidth = max(0, earnedWidth - fillWidth)

                HStack(spacing: 0) {
                    if fillWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 5, bottomLeadingRadius: 5,
                            bottomTrailingRadius: 0, topTrailingRadius: 0
                        )
                        .fill(balanceYellow)
                        .frame(width: max(4, fillWidth))
                    }
                    if spentSegmentWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: 0,
                            bottomTrailingRadius: 5, topTrailingRadius: 5
                        )
                        .stroke(balanceYellow, lineWidth: 1.5)
                        .frame(width: max(2, spentSegmentWidth))
                    }
                    Spacer(minLength: 0)
                }
                .padding(inset)
                .frame(width: w, height: proxy.size.height, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                }
            }
            .frame(height: 10)
            .animation(.spring(response: 0.4), value: progress)
            .animation(.spring(response: 0.4), value: earnedTodayProgress)
            
            // ── Expand / Collapse toggle ──
            if showDetails {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse categories" : "Expand categories")
            }
            
            // ── Metric chips (two rows, icons only) ──
            if showDetails && isExpanded {
                VStack(spacing: 6) {
                    // Row 1: HealthKit auto-tracked
                    HStack(spacing: 8) {
                        metricChip(
                            icon: "figure.walk",
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
                            icon: "figure.run",
                            value: bodyPoints,
                            max: 20,
                            accessibilityId: "chip_body",
                            onTap: { onMoveTap?() }
                        )
                        metricChip(
                            icon: "sparkles",
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
                        .fill(Color(white: 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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

// MARK: - Helpers

private func formatNumber(_ num: Int) -> String {
    let absValue = abs(num)
    let sign = num < 0 ? "-" : ""
    
    func trimTrailingZero(_ s: String) -> String {
        s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
    
    if absValue < 1000 { return "\(num)" }
    
    if absValue < 10_000 {
        let v = (Double(absValue) / 1000.0 * 10).rounded() / 10
        return sign + trimTrailingZero(String(format: "%.1f", v)) + "K"
    }
    
    if absValue < 1_000_000 {
        let v = Int((Double(absValue) / 1000.0).rounded())
        return sign + "\(v)K"
    }
    
    if absValue < 10_000_000 {
        let v = (Double(absValue) / 1_000_000.0 * 10).rounded() / 10
        return sign + trimTrailingZero(String(format: "%.1f", v)) + "M"
    }
    
    let v = Int((Double(absValue) / 1_000_000.0).rounded())
    return sign + "\(v)M"
}

#Preview {
    VStack(spacing: 20) {
        StepBalanceCard(
            remainingSteps: 85,
            totalSteps: 100,
            spentSteps: 15,
            healthKitSteps: 60,
            outerWorldSteps: 25,
            grantedSteps: 0,
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
            outerWorldSteps: 5,
            grantedSteps: 0,
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

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
    
    // New parameters for category breakdown
    let movePoints: Int
    let rebootPoints: Int
    let joyPoints: Int
    let baseEnergyToday: Int
    
    // Navigation handlers
    var onMoveTap: (() -> Void)? = nil
    var onRebootTap: (() -> Void)? = nil
    var onJoyTap: (() -> Void)? = nil
    var onOuterWorldTap: (() -> Void)? = nil
    
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @Environment(\.colorScheme) private var colorScheme
    
    private let maxEnergy: Int = 100
    
    private var currentEnergy: Int {
        // Текущая энергия = оставшийся баланс после трат (remainingSteps уже содержит totalStepsBalance)
        return min(maxEnergy, remainingSteps)
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
            // Header row: EXP label + balance numbers + timer
            HStack(alignment: .center, spacing: 10) {
                // EXP label
                Text("EXP")
                    .font(.caption.weight(.bold))
                    .foregroundColor(accent)
                    .tracking(0.5)
                
                // Balance: current / earned / max
                HStack(spacing: 4) {
                    // Current balance — yellow pill
                    Text("\(currentEnergy)")
                        .font(.title3.bold())
                        .foregroundColor(.black)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(balanceYellow)
                        )
                    
                    Text("/")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    // Today's earned — yellow outlined pill
                    Text("\(baseEnergyToday)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .strokeBorder(balanceYellow, lineWidth: 1.5)
                        )
                    
                    Text("/")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    // Max
                    Text("\(maxEnergy)")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
                
                // Reset timer — inline, no box
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
            
            // Progress bar
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
                            topLeadingRadius: 5,
                            bottomLeadingRadius: 5,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                        .fill(balanceYellow)
                        .frame(width: max(4, fillWidth))
                    }
                    if spentSegmentWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 5,
                            topTrailingRadius: 5
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
            
            // Category breakdown — inline chips
            if showDetails {
                HStack(spacing: 6) {
                    compactCategoryChip(
                        icon: "figure.run",
                        value: movePoints,
                        color: .primary,
                        accessibilityId: "chip_activity",
                        onTap: { onMoveTap?() }
                    )
                    
                    compactCategoryChip(
                        icon: "sparkles",
                        value: rebootPoints,
                        color: .primary,
                        accessibilityId: "chip_creativity",
                        onTap: { onRebootTap?() }
                    )
                    
                    compactCategoryChip(
                        icon: "heart.fill",
                        value: joyPoints,
                        color: .primary,
                        accessibilityId: "chip_joys",
                        onTap: { onJoyTap?() }
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .animation(.spring(response: 0.3), value: showDetails)
    }
}

// Compact category chip
@ViewBuilder
private func compactCategoryChip(icon: String, value: Int, color: Color, accessibilityId: String, onTap: @escaping () -> Void) -> some View {
    Button(action: onTap) {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color.opacity(0.6))
            
            Text("\(value)")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.06))
        )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityId)
}

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
            movePoints: 30,
            rebootPoints: 25,
            joyPoints: 15,
            baseEnergyToday: 60
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
            movePoints: 20,
            rebootPoints: 15,
            joyPoints: 10,
            baseEnergyToday: 40
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

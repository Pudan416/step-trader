import SwiftUI

struct StepBalanceCard: View {
    let remainingSteps: Int
    let totalSteps: Int
    let spentSteps: Int
    let healthKitSteps: Int
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
    
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    private let maxEnergy: Int = 100
    
    // Max points per category for display
    private let maxCategoryPointsActivityRecovery: Int = 40
    private let maxCategoryPointsJoys: Int = 20
    
    private var totalEnergy: Int {
        min(maxEnergy, totalSteps)
    }
    
    private var currentEnergy: Int {
        // Текущая энергия = оставшийся баланс после трат (remainingSteps уже содержит totalStepsBalance)
        return min(maxEnergy, remainingSteps)
    }
    
    private var totalProgress: Double {
        guard maxEnergy > 0 else { return 0 }
        return min(1, Double(totalEnergy) / Double(maxEnergy))
    }
    
    private var remainingProgress: Double {
        guard maxEnergy > 0 else { return 0 }
        return min(totalProgress, Double(currentEnergy) / Double(maxEnergy))
    }
    
    private var progressColor: Color {
        if currentEnergy > 70 { return .green }
        if currentEnergy > 40 { return .orange }
        return .red
    }
    
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
        VStack(spacing: 16) {
            // Header with balance
            HStack(alignment: .center, spacing: 12) {
                // Energy icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [progressColor.opacity(0.3), progressColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [progressColor, progressColor.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                // Balance text
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "Control Balance"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(currentEnergy)")
                            .font(.title2.bold())
                            .foregroundColor(AppColors.brandPink)
                            .monospacedDigit()
                        Text("/\(totalEnergy)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.brandPink.opacity(0.45))
                            .monospacedDigit()
                        Text("/100")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                
                Spacer()
                
// Reset timer badge with glass
VStack(spacing: 2) {
    HStack(spacing: 4) {
        Image(systemName: "clock.arrow.circlepath")
            .font(.caption2)
            .foregroundColor(.orange)
        Text(timeUntilReset)
            .font(.caption.weight(.bold))
            .monospacedDigit()
    }
    .foregroundColor(.primary)
    Text(loc(appLanguage, "reset"))
        .font(.caption2)
        .foregroundColor(.secondary)
}
.padding(.horizontal, 12)
.padding(.vertical, 8)
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(.thinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
)
            }
            
            // Progress bar - shows current energy out of 100
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                    
                    // Total balance for the day (light pink)
                    if totalProgress > 0 {
                        let totalWidth = proxy.size.width * totalProgress
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.brandPink.opacity(0.35))
                            .frame(width: max(8, totalWidth))
                    }
                    
                    // Remaining balance (bright pink)
                    if remainingProgress > 0 {
                        let remainingWidth = proxy.size.width * remainingProgress
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.brandPink)
                            .frame(width: max(8, remainingWidth))
                            .shadow(color: AppColors.brandPink.opacity(0.35), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .frame(height: 14)
            .animation(.spring(response: 0.4), value: remainingProgress)
            
            // Details section - compact 3-in-a-row category breakdown with N/20 format
            if showDetails {
                HStack(spacing: 8) {
                    compactCategoryChip(
                        icon: "figure.run",
                        value: movePoints,
                        maxValue: maxCategoryPointsActivityRecovery,
                        color: .green,
                        onTap: { onMoveTap?() }
                    )
                    
                    compactCategoryChip(
                        icon: "moon.zzz.fill",
                        value: rebootPoints,
                        maxValue: maxCategoryPointsActivityRecovery,
                        color: .blue,
                        onTap: { onRebootTap?() }
                    )
                    
                    compactCategoryChip(
                        icon: "heart.fill",
                        value: joyPoints,
                        maxValue: maxCategoryPointsJoys,
                        color: .orange,
                        onTap: { onJoyTap?() }
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .animation(.spring(response: 0.3), value: showDetails)
    }
}

// Compact category chip - small icon + N/20 format, 3 in a row
@ViewBuilder
private func compactCategoryChip(icon: String, value: Int, maxValue: Int, color: Color, onTap: @escaping () -> Void) -> some View {
    Button(action: onTap) {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            
            HStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text("/\(maxValue)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
    .buttonStyle(.plain)
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

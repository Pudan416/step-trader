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
    
    private let maxEnergy: Int = 100
    
    private var currentEnergy: Int {
        // Текущая энергия = baseEnergyToday + bonusSteps (outerWorldSteps), но максимум 100
        let total = baseEnergyToday + outerWorldSteps
        return min(maxEnergy, total)
    }
    
    private var progress: Double {
        guard maxEnergy > 0 else { return 0 }
        return min(1, Double(currentEnergy) / Double(maxEnergy))
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
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(currentEnergy)")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                            .monospacedDigit()
                        
                        if outerWorldSteps > 0 {
                            Text("+\(outerWorldSteps)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        
                        Text("/ \(maxEnergy)")
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
                    
                    // Progress bar showing current energy (base + bonus, max 100)
                    if currentEnergy > 0 {
                        let progressWidth = proxy.size.width * progress
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [progressColor, progressColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, progressWidth))
                            .shadow(color: progressColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .frame(height: 14)
            .animation(.spring(response: 0.4), value: progress)
            
            // Details section - category breakdown
            if showDetails {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        categoryChip(
                            icon: "figure.run",
                            title: loc(appLanguage, "Move"),
                            value: movePoints,
                            max: 40,
                            color: .green,
                            category: .move,
                            onTap: { onMoveTap?() }
                        )
                        
                        categoryChip(
                            icon: "moon.zzz.fill",
                            title: loc(appLanguage, "Reboot"),
                            value: rebootPoints,
                            max: 40,
                            color: .blue,
                            category: .reboot,
                            onTap: { onRebootTap?() }
                        )
                    }
                    
                    HStack(spacing: 12) {
                        categoryChip(
                            icon: "heart.fill",
                            title: loc(appLanguage, "Choice"),
                            value: joyPoints,
                            max: 20,
                            color: .orange,
                            category: .joy,
                            onTap: { onJoyTap?() }
                        )
                        
                        categoryChip(
                            icon: "battery.100.bolt",
                            title: loc(appLanguage, "Outer World"),
                            value: outerWorldSteps,
                            max: 50,
                            color: .cyan,
                            category: nil,
                            onTap: { onOuterWorldTap?() }
                        )
                    }
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

@ViewBuilder
private func categoryChip(icon: String, title: String, value: Int, max: Int, color: Color, category: EnergyCategory?, onTap: @escaping () -> Void) -> some View {
    Button(action: onTap) {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.2), color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text("/\(max)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity)
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

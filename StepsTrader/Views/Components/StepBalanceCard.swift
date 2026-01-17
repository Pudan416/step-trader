import SwiftUI

struct StepBalanceCard: View {
    let remainingSteps: Int
    let totalSteps: Int
    let spentSteps: Int
    let healthKitSteps: Int
    let outerWorldSteps: Int
    let grantedSteps: Int
    let showDetails: Bool
    
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1, Double(remainingSteps) / Double(totalSteps))
    }
    
    private var progressColor: Color {
        if remainingSteps > 500 { return .green }
        if remainingSteps > 100 { return .orange }
        return .red
    }
    
    private var timeUntilReset: String {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 0
        components.minute = 0
        
        guard let todayMidnight = calendar.date(from: components),
              let tomorrowMidnight = calendar.date(byAdding: .day, value: 1, to: todayMidnight) else {
            return "--:--"
        }
        
        let diff = tomorrowMidnight.timeIntervalSince(now)
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
                    Text(loc(appLanguage, "Energy Balance", "Баланс энергии"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(formatNumber(remainingSteps))
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                        
                        Text("/ \(formatNumber(totalSteps))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
    Text(loc(appLanguage, "reset", "сброс"))
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
            
            // Progress bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                    
                    // Remaining energy split by source (Steps vs Outer World)
                    if remainingSteps > 0 && totalSteps > 0 {
                        let remainingWidth = proxy.size.width * progress
                        let hkRemaining = max(0, healthKitSteps)
                        let owRemaining = max(0, outerWorldSteps)
                        let grRemaining = max(0, grantedSteps)
                        let denom = max(1, hkRemaining + owRemaining + grRemaining)
                        let hkWidth = remainingWidth * (Double(hkRemaining) / Double(denom))
                        let owWidth = remainingWidth * (Double(owRemaining) / Double(denom))
                        let grWidth = max(0, remainingWidth - hkWidth - owWidth)
                        
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.pink, .pink.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: hkWidth)
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: owWidth)
                            
                            if grRemaining > 0 {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.85, green: 0.65, blue: 0.13), Color.orange.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: grWidth)
                            }
                        }
                        .frame(width: remainingWidth, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .frame(height: 12)
            .animation(.spring(response: 0.4), value: progress)
            
            // Details section (sources only)
            if showDetails {
                HStack(spacing: 10) {
                    sourceChip(
                        icon: "figure.walk",
                        title: loc(appLanguage, "Steps", "Шаги"),
                        value: formatNumber(healthKitSteps),
                        color: .pink
                    )
                    
                    sourceChip(
                        icon: "map.fill",
                        title: loc(appLanguage, "Outer World", "Внешний мир"),
                        value: formatNumber(outerWorldSteps),
                        color: .blue
                    )
                    
                    if grantedSteps > 0 {
                        sourceChip(
                            icon: "wand.and.stars",
                            title: loc(appLanguage, "Doom's Will", "Воля Doom"),
                            value: formatNumber(grantedSteps),
                            color: Color(red: 0.85, green: 0.65, blue: 0.13) // Gold
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
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
    
@ViewBuilder
private func sourceChip(icon: String, title: String, value: String, color: Color) -> some View {
    HStack(spacing: 6) {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 24, height: 24)
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
        }
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(.primary)
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
        Capsule()
            .fill(.thinMaterial)
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
    )
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
}

#Preview {
    VStack(spacing: 20) {
        StepBalanceCard(
            remainingSteps: 4520,
            totalSteps: 6000,
            spentSteps: 1480,
            healthKitSteps: 5000,
            outerWorldSteps: 800,
            grantedSteps: 200,
            showDetails: true
        )
        
        StepBalanceCard(
            remainingSteps: 150,
            totalSteps: 6000,
            spentSteps: 5850,
            healthKitSteps: 6000,
            outerWorldSteps: 0,
            grantedSteps: 0,
            showDetails: false
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

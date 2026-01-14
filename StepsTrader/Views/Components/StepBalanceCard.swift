import SwiftUI

struct StepBalanceCard: View {
    let remainingSteps: Int
    let totalSteps: Int
    let spentSteps: Int
    let healthKitSteps: Int
    let outerWorldSteps: Int
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
                
                // Efficiency badge
                if totalSteps > 0 {
                    VStack(spacing: 2) {
                        Text("\(Int(progress * 100))%")
                            .font(.headline.bold())
                            .foregroundColor(progressColor)
                        Text(loc(appLanguage, "left", "осталось"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(progressColor.opacity(0.1))
                    )
                }
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
                        let denom = max(1, hkRemaining + owRemaining)
                        let hkWidth = remainingWidth * (Double(hkRemaining) / Double(denom))
                        let owWidth = max(0, remainingWidth - hkWidth)
                        
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
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .animation(.spring(response: 0.3), value: showDetails)
    }
    
    @ViewBuilder
    private func sourceChip(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
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
            showDetails: true
        )
        
        StepBalanceCard(
            remainingSteps: 150,
            totalSteps: 6000,
            spentSteps: 5850,
            healthKitSteps: 6000,
            outerWorldSteps: 0,
            showDetails: false
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

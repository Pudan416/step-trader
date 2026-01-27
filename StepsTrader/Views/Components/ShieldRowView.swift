import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct ShieldRowView: View {
    @ObservedObject var model: AppModel
    let group: AppModel.ShieldGroup
    let appLanguage: String
    let onEdit: () -> Void
    @State private var remainingTime: TimeInterval? = nil
    @State private var timer: Timer? = nil
    
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    
    private var isActive: Bool {
        group.settings.familyControlsModeEnabled || group.settings.minuteTariffEnabled
    }
    
    private var isUnlocked: Bool {
        model.isGroupUnlocked(group.id)
    }
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            HStack(spacing: 14) {
                // App icons stack
                appIconsStack
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(group.name.isEmpty ? loc(appLanguage, "Shield") : group.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        
                        if isActive {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        // Apps count
                        Label("\(appsCount)", systemImage: "app.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Difficulty level
                        HStack(spacing: 3) {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption2)
                                .foregroundColor(difficultyColor(for: group.difficultyLevel))
                            Text("\(loc(appLanguage, "Level")) \(group.difficultyLevel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Remaining unlock time
                        if isUnlocked, let remaining = remainingTime {
                            HStack(spacing: 3) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(formatRemainingTime(remaining))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.orange)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(14)
            .background(glassCard)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isUnlocked ? Color.orange.opacity(0.4) : 
                        (isActive ? Color.blue.opacity(0.2) : Color.clear),
                        lineWidth: isUnlocked ? 2 : 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            updateRemainingTime()
            // Обновляем время каждую секунду
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateRemainingTime()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func updateRemainingTime() {
        remainingTime = model.remainingUnlockTime(for: group.id)
    }
    
    private func formatRemainingTime(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    // MARK: - App Icons Stack
    private var appIconsStack: some View {
        ZStack {
            #if canImport(FamilyControls)
            let appTokens = Array(group.selection.applicationTokens.prefix(3))
            let remainingSlots = max(0, 3 - appTokens.count)
            let categoryTokens = Array(group.selection.categoryTokens.prefix(remainingSlots))
            let hasMore = appsCount > 3
            
            // Показываем иконки приложений
            ForEach(Array(appTokens.enumerated()), id: \.offset) { index, token in
                AppIconView(token: token)
                    .frame(width: iconSize(for: index), height: iconSize(for: index))
                    .clipShape(RoundedRectangle(cornerRadius: iconRadius(for: index)))
                    .overlay(
                        RoundedRectangle(cornerRadius: iconRadius(for: index))
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    .offset(x: iconOffset(for: index).x, y: iconOffset(for: index).y)
                    .zIndex(Double(3 - index))
            }
            
            // Показываем иконки категорий, если остались слоты
            ForEach(Array(categoryTokens.enumerated()), id: \.offset) { offset, token in
                let index = appTokens.count + offset
                CategoryIconView(token: token)
                    .frame(width: iconSize(for: index), height: iconSize(for: index))
                    .clipShape(RoundedRectangle(cornerRadius: iconRadius(for: index)))
                    .overlay(
                        RoundedRectangle(cornerRadius: iconRadius(for: index))
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    .offset(x: iconOffset(for: index).x, y: iconOffset(for: index).y)
                    .zIndex(Double(3 - index))
            }
            
            // Empty state
            if appTokens.isEmpty && categoryTokens.isEmpty {
                emptyIcon
            }
            
            // +N badge
            if hasMore {
                Text("+\(appsCount - 3)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .offset(x: 16, y: 16)
                    .zIndex(10)
            }
            #else
            emptyIcon
            #endif
        }
        .frame(width: 56, height: 56)
    }
    
    private func iconSize(for index: Int) -> CGFloat {
        switch index {
        case 0: return 44
        case 1: return 36
        default: return 30
        }
    }
    
    private func iconRadius(for index: Int) -> CGFloat {
        switch index {
        case 0: return 10
        case 1: return 8
        default: return 7
        }
    }
    
    private func iconOffset(for index: Int) -> (x: CGFloat, y: CGFloat) {
        switch index {
        case 0: return (-4, -4)
        case 1: return (8, 6)
        default: return (14, 14)
        }
    }
    
    private var emptyIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
                .frame(width: 44, height: 44)
            
            Image(systemName: "app.dashed")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Glass Card Style
    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
    
    private func difficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
}


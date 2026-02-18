import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct TicketRowView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let onEdit: () -> Void

    
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    
    private var isActive: Bool {
        group.settings.familyControlsModeEnabled || (AppModel.minuteModeEnabled && group.settings.minuteTariffEnabled)
    }
    
    private var isUnlocked: Bool {
        model.isGroupUnlocked(group.id)
    }
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: isUnlocked ? 1 : 60)) { _ in
            Button {
                onEdit()
            } label: {
                HStack(spacing: 14) {
                    appIconsStack
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(group.name.isEmpty ? "Ticket" : group.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            
                            if isActive {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Label("\(appsCount)", systemImage: "app.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if isUnlocked, let remaining = model.remainingUnlockTime(for: group.id) {
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
            
            // App icons
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
            
            // Category icons if slots remain
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
                    .font(.systemSerif(10, weight: .bold))
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
                .font(.systemSerif(20, weight: .semibold))
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
    
}


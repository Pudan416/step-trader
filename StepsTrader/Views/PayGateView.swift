import SwiftUI
import UIKit
#if canImport(FamilyControls)
import FamilyControls
#endif

struct PayGateView: View {
    @ObservedObject var model: AppModel
    @AppStorage("payGateBackgroundStyle") private var backgroundStyle: String = PayGateBackgroundStyle.midnight.rawValue
    @State private var didForfeitSessions: Set<String> = []
    @State private var showTransitionCircle: Bool = false
    @State private var transitionScale: CGFloat = 0.01
    
    private var activeSession: AppModel.PayGateSession? {
        if let id = model.currentPayGateSessionId, let session = model.payGateSessions[id] {
            return session
        }
        if let id = model.payGateTargetGroupId, let session = model.payGateSessions[id] {
            return session
        }
        return nil
    }
    
    private var activeGroup: AppModel.ShieldGroup? {
        guard let groupId = activeSession?.groupId else { return nil }
        return model.shieldGroups.first(where: { $0.id == groupId })
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 700
            
            ZStack {
                payGateBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: isCompact ? 12 : 20) {
                    // App logo and balance header
                    headerSection(isCompact: isCompact)
                    
                    Spacer(minLength: 0)
                    
                    // Center: Target app/group info
                    if let group = activeGroup {
                        targetInfoSection(group: group, isCompact: isCompact)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Bottom: Action buttons (no scroll)
                    if let group = activeGroup {
                        actionSection(group: group, isCompact: isCompact)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isCompact ? 40 : 50)
                .padding(.bottom, isCompact ? 16 : 24)
            }
        }
        .overlay(transitionOverlay)
        .onDisappear {
            if let id = activeSession?.groupId {
                didForfeitSessions.insert(id)
            }
            model.dismissPayGate(reason: .programmatic)
        }
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func headerSection(isCompact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // App Logo
            appLogoView
                .frame(width: isCompact ? 40 : 48, height: isCompact ? 40 : 48)
                .clipShape(RoundedRectangle(cornerRadius: isCompact ? 10 : 12))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            // Control balance
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Control")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.subheadline)
                        .foregroundColor(controlColor)
                    
                    Text("\(model.totalStepsBalance)")
                        .font(.system(size: isCompact ? 24 : 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }
            
            Spacer()
            
            // Today's total
            VStack(alignment: .trailing, spacing: 2) {
                Text("Today")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                Text("\(model.baseEnergyToday + model.bonusSteps)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
        .padding(isCompact ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(0.6))
        )
    }
    
    private var controlColor: Color {
        let balance = model.totalStepsBalance
        if balance > 50 { return AppColors.brandPink }
        if balance > 20 { return .orange }
        return .red
    }
    
    @ViewBuilder
    private var appLogoView: some View {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last,
           let uiImage = UIImage(named: last) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.purple, AppColors.brandPink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "bolt.shield.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Target Info Section
    @ViewBuilder
    private func targetInfoSection(group: AppModel.ShieldGroup, isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 12) {
            // App icons from group
            groupAppIconsView(group: group, isCompact: isCompact)
            
            // Warning message
            Text("Lose control to unlock")
                .font(isCompact ? .subheadline : .headline)
                .foregroundColor(.white.opacity(0.8))
            
            // Difficulty badge
            difficultyBadge(level: group.difficultyLevel)
        }
    }
    
    @ViewBuilder
    private func groupAppIconsView(group: AppModel.ShieldGroup, isCompact: Bool) -> some View {
        #if canImport(FamilyControls)
        let appTokens = Array(group.selection.applicationTokens.prefix(3))
        let remainingSlots = max(0, 3 - appTokens.count)
        let categoryTokens = Array(group.selection.categoryTokens.prefix(remainingSlots))
        let hasMore = (group.selection.applicationTokens.count + group.selection.categoryTokens.count) > 3
        let iconSize: CGFloat = isCompact ? 56 : 68
        
        ZStack {
            // Glow
            Circle()
                .fill(selectedBackgroundStyle.accentColor.opacity(0.25))
                .frame(width: iconSize * 1.8, height: iconSize * 1.8)
                .blur(radius: 25)
            
            // Single icon or stacked
            if appTokens.count == 1 && categoryTokens.isEmpty {
                AppIconView(token: appTokens[0])
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
            } else {
                // Stacked icons
                ForEach(Array(appTokens.enumerated()), id: \.offset) { index, token in
                    let size = iconSize - CGFloat(index * 8)
                    AppIconView(token: token)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                        .offset(x: CGFloat(index - 1) * 16, y: CGFloat(index) * 4)
                        .zIndex(Double(3 - index))
                }
                
                ForEach(Array(categoryTokens.enumerated()), id: \.offset) { offset, token in
                    let index = appTokens.count + offset
                    let size = iconSize - CGFloat(index * 8)
                    CategoryIconView(token: token)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                        .offset(x: CGFloat(index - 1) * 16, y: CGFloat(index) * 4)
                        .zIndex(Double(3 - index))
                }
            }
            
            // +N badge
            if hasMore {
                let total = group.selection.applicationTokens.count + group.selection.categoryTokens.count
                Text("+\(total - 3)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .offset(x: 24, y: 20)
                    .zIndex(10)
            }
        }
        .frame(height: isCompact ? 80 : 100)
        #else
        Image(systemName: "app.fill")
            .font(.system(size: 48))
            .foregroundColor(.white)
        #endif
    }
    
    @ViewBuilder
    private func difficultyBadge(level: Int) -> some View {
        let color = difficultyColor(for: level)
        let label = difficultyLabel(for: level)
        
        HStack(spacing: 4) {
            Image(systemName: "dial.high.fill")
                .font(.caption2)
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.2)))
    }
    
    private func difficultyLabel(for level: Int) -> String {
        switch level {
        case 1: return "Rookie"
        case 2: return "Rebel"
        case 3: return "Fighter"
        case 4: return "Warrior"
        case 5: return "Legend"
        default: return "Fighter"
        }
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
    
    // MARK: - Action Section
    @ViewBuilder
    private func actionSection(group: AppModel.ShieldGroup, isCompact: Bool) -> some View {
        let windows = Array(group.enabledIntervals).sorted { $0.minutes < $1.minutes }
        let isForfeited = didForfeitSessions.contains(group.id)
        
        VStack(spacing: isCompact ? 10 : 14) {
            // Access buttons grid - adaptive columns based on count
            accessButtonsGrid(windows: windows, group: group, isForfeited: isForfeited, isCompact: isCompact)
            
            // Close button
            closeButton(groupId: group.id)
        }
        .padding(isCompact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: -8)
        )
    }
    
    @ViewBuilder
    private func accessButtonsGrid(windows: [AccessWindow], group: AppModel.ShieldGroup, isForfeited: Bool, isCompact: Bool) -> some View {
        let columns: [GridItem] = windows.count <= 2 
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : windows.count == 3
            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        
        LazyVGrid(columns: columns, spacing: isCompact ? 8 : 10) {
            ForEach(windows.prefix(8), id: \.self) { window in
                accessButton(window: window, group: group, isForfeited: isForfeited, isCompact: isCompact)
            }
        }
    }
    
    @ViewBuilder
    private func accessButton(window: AccessWindow, group: AppModel.ShieldGroup, isForfeited: Bool, isCompact: Bool) -> some View {
        let cost = group.cost(for: window)
        let canPay = model.totalStepsBalance >= cost
        let isDisabled = !canPay || isForfeited
        let pink = AppColors.brandPink
        
        Button {
            guard !isDisabled else { return }
            didForfeitSessions.insert(group.id)
            performTransition {
                Task {
                    await model.handlePayGatePaymentForGroup(groupId: group.id, window: window, costOverride: cost)
                }
            }
        } label: {
            VStack(spacing: isCompact ? 4 : 6) {
                // Duration
                Text(windowShortLabel(window))
                    .font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundColor(isDisabled ? .secondary : .primary)
                
                // Cost with "lose" prefix
                HStack(spacing: 2) {
                    Text("-\(cost)")
                        .font(isCompact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                        .monospacedDigit()
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                }
                .foregroundColor(isDisabled ? .gray : (canPay ? pink : .red))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 10 : 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDisabled ? Color.gray.opacity(0.1) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDisabled ? Color.gray.opacity(0.2) : pink.opacity(0.4), lineWidth: 1)
            )
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
        .accessibilityLabel("\(windowShortLabel(window)), lose \(cost) control")
        .accessibilityHint(canPay ? "Unlocks access" : "Not enough control")
    }
    
    private func windowShortLabel(_ window: AccessWindow) -> String {
        switch window {
        case .single: return "1m"
        case .minutes5: return "5m"
        case .minutes15: return "15m"
        case .minutes30: return "30m"
        case .hour1: return "1h"
        case .hour2: return "2h"
        case .day1: return "Day"
        }
    }
    
    @ViewBuilder
    private func closeButton(groupId: String) -> some View {
        Button {
            didForfeitSessions.insert(groupId)
            performTransition(duration: 0.5) {
                model.dismissPayGate(reason: .userDismiss)
                sendAppToBackground()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.medium))
                Text("Stay Focused")
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray5).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stay Focused")
        .accessibilityHint("Closes without unlocking")
    }
    
    private func sendAppToBackground() {
        DispatchQueue.main.async {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
}

// MARK: - Background & Transition
extension PayGateView {
    private var selectedBackgroundStyle: PayGateBackgroundStyle {
        PayGateBackgroundStyle(rawValue: backgroundStyle) ?? .midnight
    }
    
    private func payGateBackground() -> some View {
        let style = selectedBackgroundStyle
        
        return ZStack {
            // Base gradient
            LinearGradient(
                gradient: Gradient(colors: style.colors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Soft gradient orbs
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [style.accentColor.opacity(0.2), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.5
                            )
                        )
                        .frame(width: geo.size.width * 1.2)
                        .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.15)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [style.colors[1].opacity(0.25), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.4
                            )
                        )
                        .frame(width: geo.size.width * 0.9)
                        .offset(x: geo.size.width * 0.25, y: geo.size.height * 0.35)
                }
            }
            
            // Vignette
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.5), location: 0),
                    .init(color: Color.clear, location: 0.25),
                    .init(color: Color.clear, location: 0.75),
                    .init(color: Color.black.opacity(0.6), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private func performTransition(duration: Double = 0.8, action: @escaping () -> Void) {
        guard !showTransitionCircle else {
            action()
            return
        }
        showTransitionCircle = true
        transitionScale = 0.01
        withAnimation(.easeInOut(duration: duration)) {
            transitionScale = 12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.85) {
            action()
        }
    }
    
    @ViewBuilder
    fileprivate var transitionOverlay: some View {
        if showTransitionCircle {
            GeometryReader { proxy in
                Circle()
                    .fill(Color.black)
                    .frame(width: 120, height: 120)
                    .scaleEffect(transitionScale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .ignoresSafeArea()
            }
        }
    }
}

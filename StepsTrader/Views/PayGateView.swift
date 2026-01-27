import SwiftUI
import UIKit
#if canImport(FamilyControls)
import FamilyControls
#endif

struct PayGateView: View {
    @ObservedObject var model: AppModel
    @AppStorage("payGateBackgroundStyle") private var backgroundStyle: String = PayGateBackgroundStyle.midnight.rawValue
    @State private var countdown: Int = 10
    @State private var didForfeitSessions: Set<String> = []
    @State private var timedOutSessions: Set<String> = []
    @State private var lastSessionId: String? = nil
    @State private var showTransitionCircle: Bool = false
    @State private var transitionScale: CGFloat = 0.01
    @State private var selectedWindow: AccessWindow = .single
    private let totalCountdown: Int = 10
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
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
    
    private var isCountdownActive: Bool {
        guard let session = activeSession else { return false }
        return !timedOutSessions.contains(session.groupId) && remainingSeconds(for: session) > 0
    }
    
    private func remainingSeconds(for session: AppModel.PayGateSession) -> Int {
        let elapsed = Date().timeIntervalSince(session.startedAt)
        return max(0, totalCountdown - Int(elapsed))
    }

    
    private var countdownBadge: some View {
        let progress = CGFloat(max(0, countdown)) / CGFloat(totalCountdown)
        let countdownColor: Color = countdown > 5 ? .green : (countdown > 2 ? .orange : .red)
        
        return VStack(spacing: 8) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(countdownColor.opacity(0.15))
                    .frame(width: 110, height: 110)
                    .blur(radius: 10)
                
                // Background ring
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 88, height: 88)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [countdownColor, countdownColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88)
                    .animation(.easeInOut(duration: 0.3), value: countdown)
                
                // Inner circle with number
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 70, height: 70)
                
                Text("\(max(0, countdown))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .animation(.spring(response: 0.3), value: countdown)
            }
            
            Text(loc("seconds left"))
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial.opacity(0.5))
        )
    }
    
    // Compact countdown for smaller screens
    private var countdownBadgeCompact: some View {
        let progress = CGFloat(max(0, countdown)) / CGFloat(totalCountdown)
        let countdownColor: Color = countdown > 5 ? .green : (countdown > 2 ? .orange : .red)
        
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 44, height: 44)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(countdownColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .animation(.easeInOut(duration: 0.3), value: countdown)
                
                Text("\(max(0, countdown))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            
            Text(loc("seconds left"))
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.5))
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                payGateBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top section with balance
                    stepsProgressBar
                        .padding(.horizontal, 20)
                        .padding(.top, 50)
                    
                    Spacer(minLength: 10)
                
                    // Center content - app icons and countdown
                    if let group = activeGroup {
                        VStack(spacing: 16) {
                            // App icons from group
                            groupAppIconsView(group: group)
                                .frame(height: 100)
                            
                            // Group name
                            Text(group.name.isEmpty ? "Shield Group" : group.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            // Difficulty level badge
                            difficultyLevelBadge(level: group.difficultyLevel)
                        }
                    }
                    
                    Spacer(minLength: 10)
                    
                    // Bottom action panel - scrollable for small screens
                    ScrollView(showsIndicators: false) {
                        bottomActionPanel
                    }
                    .frame(maxHeight: geometry.size.height * 0.45)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
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
    
    @ViewBuilder
    private var bottomActionPanel: some View {
        VStack(spacing: 16) {
            if let group = activeGroup {
                openModePanel(group: group, isTimedOut: timedOutSessions.contains(group.id))
                closeButton(groupId: group.id)
            } else {
                Text(loc("No group selected"))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: -10)
        )
    }
    
    @ViewBuilder
    private func openModePanel(group: AppModel.ShieldGroup, isTimedOut: Bool) -> some View {
        let windows = Array(group.enabledIntervals).sorted { $0.minutes < $1.minutes }
        
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text(loc("Choose Access"))
                    .font(.headline)
                Spacer()
                
                // Difficulty level badge
                difficultyLevelBadge(level: group.difficultyLevel)
            }
            
            // Access options grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(windows, id: \.self) { window in
                    accessWindowCard(window: window, group: group, isTimedOut: isTimedOut, isForfeited: isForfeited(group.id))
                }
            }
        }
    }
    
    @ViewBuilder
    private func accessWindowCard(window: AccessWindow, group: AppModel.ShieldGroup, isTimedOut: Bool, isForfeited: Bool) -> some View {
        let baseCost = group.cost(for: window)
        let effectiveCost = baseCost
        let canPay = effectiveCost == 0 || model.totalStepsBalance >= effectiveCost
        let isDisabled = !canPay || isTimedOut || isForfeited
        let pink = AppColors.brandPink
        
        Button {
            guard !isDisabled else { return }
            setForfeit(group.id)
            Task {
                performTransition {
                    Task { await model.handlePayGatePaymentForGroup(groupId: group.id, window: window, costOverride: effectiveCost) }
                }
            }
        } label: {
            VStack(spacing: 8) {
                // Duration icon
                Image(systemName: windowIcon(window))
                    .font(.title2)
                    .foregroundColor(isDisabled ? .gray : pink)
                
                // Duration text
                Text(accessWindowShortName(window))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isDisabled ? .secondary : .primary)
                
                // Cost
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text("\(effectiveCost)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
                .foregroundColor(isDisabled ? .gray : (canPay ? .orange : .red))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDisabled ? Color.gray.opacity(0.1) : Color(.systemBackground))
                    .shadow(color: isDisabled ? .clear : .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDisabled ? Color.gray.opacity(0.2) : pink.opacity(0.3), lineWidth: 1)
            )
        }
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .accessibilityLabel("\(accessWindowShortName(window)) access, \(effectiveCost) control")
        .accessibilityHint(isDisabled ? "Not enough control or timed out" : "Opens access for \(accessWindowShortName(window))")
        .accessibilityValue(canPay ? "Available" : "Insufficient control")
    }
    
    private func windowIcon(_ window: AccessWindow) -> String {
        switch window {
        case .single: return "arrow.right.circle"
        case .minutes5: return "5.circle"
        case .minutes15: return "15.circle"
        case .minutes30: return "30.circle"
        case .hour1: return "clock"
        case .hour2: return "clock.fill"
        case .day1: return "sun.max.fill"
        }
    }
    
    private func accessWindowShortName(_ window: AccessWindow) -> String {
        switch window {
        case .single: return loc("1 min")
        case .minutes5: return loc("5 min")
        case .minutes15: return loc("15 min")
        case .minutes30: return loc("30 min")
        case .hour1: return loc("1 hour")
        case .hour2: return loc("2 hours")
        case .day1: return loc("Day")
        }
    }
    
                
    @ViewBuilder
    private func closeButton(groupId: String) -> some View {
        Button {
            setForfeit(groupId)
            performTransition(duration: 0.6) {
                model.dismissPayGate(reason: .userDismiss)
                sendAppToBackground()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                Text(loc("Close"))
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .contentShape(Rectangle())
        .accessibilityLabel(loc("Close"))
        .accessibilityHint("Closes the pay gate and returns to home screen")
    }
}

extension PayGateView {
    private func refreshCountdown() {
        guard let session = activeSession else {
            countdown = 0
            return
        }
        if lastSessionId != session.groupId {
            lastSessionId = session.groupId
            countdown = remainingSeconds(for: session)
            // reset forfeit/timedOut for new session
            didForfeitSessions.remove(session.groupId)
            timedOutSessions.remove(session.groupId)
        } else {
            countdown = remainingSeconds(for: session)
        }
    }
    
    private func isForfeited(_ groupId: String) -> Bool {
        didForfeitSessions.contains(groupId) || timedOutSessions.contains(groupId)
    }
    
    private func setForfeit(_ groupId: String) {
        didForfeitSessions.insert(groupId)
    }
    
    // MARK: - Group App Icons View
    @ViewBuilder
    private func groupAppIconsView(group: AppModel.ShieldGroup) -> some View {
        #if canImport(FamilyControls)
        let appTokens = Array(group.selection.applicationTokens.prefix(3))
        let remainingSlots = max(0, 3 - appTokens.count)
        let categoryTokens = Array(group.selection.categoryTokens.prefix(remainingSlots))
        let hasMore = (group.selection.applicationTokens.count + group.selection.categoryTokens.count) > 3
        
        ZStack {
            // Glow
            Circle()
                .fill(selectedBackgroundStyle.accentColor.opacity(0.2))
                .frame(width: 120, height: 120)
                .blur(radius: 30)
            
            // App icons stack
            ForEach(Array(appTokens.enumerated()), id: \.offset) { index, token in
                AppIconView(token: token)
                    .frame(width: iconSizeForPayGate(index), height: iconSizeForPayGate(index))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    .offset(x: iconOffsetForPayGate(index).x, y: iconOffsetForPayGate(index).y)
                    .zIndex(Double(3 - index))
            }
            
            // Category icons
            ForEach(Array(categoryTokens.enumerated()), id: \.offset) { offset, token in
                let index = appTokens.count + offset
                CategoryIconView(token: token)
                    .frame(width: iconSizeForPayGate(index), height: iconSizeForPayGate(index))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    .offset(x: iconOffsetForPayGate(index).x, y: iconOffsetForPayGate(index).y)
                    .zIndex(Double(3 - index))
            }
            
            // +N badge if more apps
            if hasMore {
                let totalCount = group.selection.applicationTokens.count + group.selection.categoryTokens.count
                Text("+\(totalCount - 3)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .offset(x: 20, y: 20)
                    .zIndex(10)
            }
        }
        #else
        Image(systemName: "app.fill")
            .font(.system(size: 48))
            .foregroundColor(.white)
        #endif
    }
    
    private func iconSizeForPayGate(_ index: Int) -> CGFloat {
        switch index {
        case 0: return 64
        case 1: return 56
        default: return 48
        }
    }
    
    private func iconOffsetForPayGate(_ index: Int) -> (x: CGFloat, y: CGFloat) {
        switch index {
        case 0: return (-12, -8)
        case 1: return (12, 8)
        default: return (0, 16)
        }
    }
    
    @ViewBuilder
    private func difficultyLevelBadge(level: Int) -> some View {
        let color = difficultyColor(for: level)
        Text("Level \(level)")
            .font(.caption.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
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

// MARK: - PayGate transition helper
extension PayGateView {
    private func handleCountdownTick() {
        refreshCountdown()
        if let session = activeSession {
            let remaining = remainingSeconds(for: session)
            if remaining <= 0 {
                timedOutSessions.insert(session.groupId)
            }
        }
    }
}

// MARK: - PayGate transition helper
extension PayGateView {
    private func performTransition(duration: Double = 1.0, action: @escaping () -> Void) {
        guard !showTransitionCircle else {
            action()
            return
        }
        showTransitionCircle = true
        transitionScale = 0.01
        withAnimation(.easeInOut(duration: duration)) {
            transitionScale = 12
        }
        let delay = duration * 0.9
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
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
            
            // Soft gradient orbs (no blur - GPU safe)
            GeometryReader { geo in
                ZStack {
                    // Large soft circle (using radial gradient instead of blur)
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
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [style.accentColor.opacity(0.15), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.35
                            )
                        )
                        .frame(width: geo.size.width * 0.7)
                        .offset(x: 0, y: geo.size.height * 0.45)
                }
            }
            
            // Top and bottom vignette
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.6), location: 0),
                    .init(color: Color.clear, location: 0.3),
                    .init(color: Color.clear, location: 0.7),
                    .init(color: Color.black.opacity(0.7), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Subtle accent glow at bottom
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    style.accentColor.opacity(0.1)
                ]),
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
    
    private var stepsProgressBar: some View {
        // Текущий баланс = stepsBalance (из шагов) + bonusSteps
        // Это реальный баланс энергии, который отображается в приложении
        let remaining = max(0, model.totalStepsBalance)
        
        // Общее количество энергии за сегодня = базовая энергия + бонусы
        // Если текущий баланс больше начальной энергии (добавились бонусы), используем баланс как total
        let total = max(remaining, model.baseEnergyToday + model.bonusSteps)
        
        // Потрачено = общая энергия - текущий баланс
        let used = max(0, total - remaining)
        let denominator = Double(max(1, total))
        let displayRemaining = min(remaining, total)
        let remainingProgress = min(1, Double(displayRemaining) / denominator)
        let pink = AppColors.brandPink
        let progressColor = remaining > 50 ? pink : (remaining > 20 ? .orange : .red)

        return VStack(spacing: 12) {
            // Balance display
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundColor(progressColor)
                
                Text("\(remaining)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                
                Text(loc("energy left"))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                // Today's total
                VStack(alignment: .trailing, spacing: 2) {
                    Text(loc("Today"))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(total)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .monospacedDigit()
                }
            }
            
            // Progress bar
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 8)
                
                // Progress
                GeometryReader { proxy in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [progressColor, progressColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * CGFloat(remainingProgress)), height: 8)
                        .shadow(color: progressColor.opacity(0.5), radius: 4, x: 0, y: 0)
                }
                .frame(height: 8)
            }
            
            // Labels
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text("\(used) " + loc("spent"))
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 6, height: 6)
                    Text("\(remaining) " + loc("available"))
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.6))
        )
    }
    
    private func accentColor(for tariff: Tariff) -> Color {
        switch tariff {
        case .free: return Color.blue
        case .easy: return Color.green
        case .medium: return Color.orange
        case .hard: return Color.red
        }
    }
    
    private func dailyBoostEndTime() -> String {
        var comps = DateComponents()
        comps.hour = model.dayEndHour
        comps.minute = model.dayEndMinute
        let cal = Calendar.current
        let now = Date()
        let target = cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: target)
    }
    
    @ViewBuilder
    private func appIconView(_ bundleId: String) -> some View {
        if let imageName = SettingsView.automationAppsStatic.first(where: { $0.bundleId == bundleId })?.imageName,
           let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 4)
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.15))
                .overlay(Image(systemName: "app").foregroundColor(.secondary))
        }
    }
    
    @ViewBuilder
    private var doomCtrlIconView: some View {
        // Try to load the actual app icon
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last,
           let uiImage = UIImage(named: last) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            // Fallback to styled icon
            ZStack {
                LinearGradient(
                    colors: [Color.purple, Color.pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                Image(systemName: "bolt.shield.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }
    
    @ViewBuilder
    private func tariffPicker(bundleId: String, selected: Tariff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("en", "Choose tariff for today"))
            .font(.caption)
            .foregroundColor(.red)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tariff.allCases, id: \.self) { tariff in
                        Button {
                            Task { await handleTariffSelection(tariff, bundleId: bundleId) }
                        } label: {
                            Text(tariffDisplayName(tariff))
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(tariff == selected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(tariff == selected ? Color.blue : Color.clear, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }
    
    private func tariffDisplayName(_ tariff: Tariff) -> String {
        tariff.displayName
    }
    
    @MainActor
    private func handleTariffSelection(_ tariff: Tariff, bundleId: String) async {
        // Check balance for entry with this tariff
        model.updateUnlockSettings(for: bundleId, tariff: tariff)
        guard model.canPayForEntry(for: bundleId) else {
            model.message = loc("en", "Not enough control for this option today.")
            // Revert selection so picker stays visible
            model.dailyTariffSelections.removeValue(forKey: bundleId)
            return
        }
        model.selectTariffForToday(tariff, bundleId: bundleId)
        await model.handlePayGatePayment(for: bundleId, window: .single)
    }

    private func windowCost(for window: AccessWindow, bundleId: String? = nil) -> Int {
        // Если есть bundleId, используем настройки из unlockSettings
        if let bundleId = bundleId {
            let settings = model.unlockSettings(for: bundleId)
            let baseCost = settings.entryCostSteps
            
            // Рассчитываем стоимость для разных окон на основе entryCostSteps
            switch window {
            case .single: return baseCost
            case .minutes5: return max(1, baseCost * 5)
            case .minutes15: return max(1, baseCost * 15)
            case .minutes30: return max(1, baseCost * 30)
            case .hour1: return max(1, baseCost * 60)
            case .hour2: return max(1, baseCost * 120)
            case .day1: return max(1, baseCost * 1440)
            }
        }
        
        // Fallback на старую логику с уровнями
        switch window {
        case .single: return 1
        case .minutes5: return 2
        case .minutes15: return 5
        case .minutes30: return 10
        case .hour1: return 20
        case .hour2: return 40
        case .day1: return 20
        }
    }

    private func sendAppToBackground() {
        // Move app to background (returns user to home screen)
        DispatchQueue.main.async {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
}

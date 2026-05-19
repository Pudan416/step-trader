import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif

fileprivate enum PayGatePalette {
    static let accent = AppColors.brandAccent
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textMuted = Color.white.opacity(0.3)
}

struct PayGateView: View {
    @ObservedObject var model: AppModel
    @State private var didForfeitSessions: Set<String> = []
    @State private var hasDismissed: Bool = false
    @State private var showTransitionCircle: Bool = false
    @State private var transitionScale: CGFloat = 0.01
    @State private var appeared = false
    @ScaledMetric(relativeTo: .body) private var compactThreshold: CGFloat = 700

    private var activeSession: PayGateSession? {
        if let id = model.userEconomyStore.currentPayGateSessionId, let session = model.userEconomyStore.payGateSessions[id] {
            return session
        }
        if let id = model.userEconomyStore.payGateTargetGroupId, let session = model.userEconomyStore.payGateSessions[id] {
            return session
        }
        return nil
    }

    private var activeGroup: TicketGroup? {
        guard let groupId = activeSession?.groupId else { return nil }
        return model.blockingStore.ticketGroups.first(where: { $0.id == groupId })
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < compactThreshold

            ZStack {
                background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Close button
                    HStack {
                        Spacer()
                        Button {
                            if let id = activeSession?.groupId {
                                didForfeitSessions.insert(id)
                            }
                            model.dismissPayGate(reason: .userDismiss)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .accessibilityLabel(String(localized: "Close", comment: "PayGate – close button VoiceOver label"))
                    }
                    .padding(.top, isCompact ? 8 : 12)
                    .padding(.trailing, 8)

                    Spacer()

                    if let group = activeGroup {
                        centerSection(group: group)
                    }

                    Spacer()

                    if let group = activeGroup {
                        bottomSection(group: group, isCompact: isCompact)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .overlay(transitionOverlay)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                appeared = true
            }
        }
        .onDisappear {
            guard !hasDismissed else { return }
            hasDismissed = true
            if let id = activeSession?.groupId {
                didForfeitSessions.insert(id)
            }
            if model.userEconomyStore.showPayGate {
                model.dismissPayGate(reason: .programmatic)
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.06, green: 0.06, blue: 0.14),
                    Color(red: 0.03, green: 0.03, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            PayGatePalette.accent.opacity(0.10),
                            PayGatePalette.accent.opacity(0.02),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 350)
                .blur(radius: 40)
        }
    }

    // MARK: - Center (icon + title)

    @ViewBuilder
    private func centerSection(group: TicketGroup) -> some View {
        VStack(spacing: 20) {
            appIconArea(group: group)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.85)

            VStack(spacing: 6) {
                Text(String(localized: "spend what you lived", comment: "PayGate title"))
                    .font(.systemSerif(24, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(PayGatePalette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(group.name)
                    .font(.subheadline)
                    .foregroundStyle(PayGatePalette.textSecondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
    }

    @ViewBuilder
    private func appIconArea(group: TicketGroup) -> some View {
        #if canImport(FamilyControls)
        let appTokens = Array(group.selection.applicationTokens.prefix(3))
        let iconSize: CGFloat = 72

        ZStack {
            if let templateApp = group.templateApp,
               let imageName = TargetResolver.imageName(for: templateApp),
               let uiImage = UIImage(named: imageName) ?? UIImage(named: imageName.lowercased()) ?? UIImage(named: imageName.capitalized) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
            } else if appTokens.isEmpty {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(PayGatePalette.accent)
            } else {
                ForEach(Array(appTokens.enumerated()), id: \.offset) { index, token in
                    let size = iconSize - CGFloat(index * 8)
                    AppIconView(token: token)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                        .offset(x: CGFloat(index - 1) * 18, y: CGFloat(index) * 4)
                        .zIndex(Double(3 - index))
                }
            }
        }
        .frame(height: 100)
        #else
        Image(systemName: "lock.fill")
            .font(.system(size: 36, weight: .regular))
            .foregroundStyle(PayGatePalette.accent)
        #endif
    }

    // MARK: - Bottom (balance + options + dismiss)

    @ViewBuilder
    private func bottomSection(group: TicketGroup, isCompact: Bool) -> some View {
        let windows = Array(group.enabledIntervals).sorted { $0.minutes < $1.minutes }
        let isForfeited = didForfeitSessions.contains(group.id)
        let minsLeft = model.minutesUntilDayReset
        let balance = model.userEconomyStore.totalStepsBalance

        VStack(spacing: 0) {
            if minsLeft <= 60 {
                dayResetBanner(minutesLeft: minsLeft)
                    .padding(.bottom, 16)
            }

            // Balance
            HStack(spacing: 6) {
                Text("\(balance)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PayGatePalette.textPrimary)
                Text(String(localized: "colors available", comment: "PayGate balance label"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PayGatePalette.textMuted)
            }
            .padding(.bottom, 16)
            .opacity(appeared ? 1 : 0)

            // Unlock options
            VStack(spacing: 0) {
                ForEach(Array(windows.prefix(3).enumerated()), id: \.element) { index, window in
                    unlockRow(window: window, group: group, isForfeited: isForfeited)

                    if index < min(windows.count, 3) - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            // Keep it closed
            Button {
                didForfeitSessions.insert(group.id)
                hasDismissed = true
                performTransition(duration: 0.4) {
                    model.dismissPayGate(reason: .userDismiss)
                }
            } label: {
                Text(String(localized: "keep it closed", comment: "PayGate dismiss button"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PayGatePalette.textMuted)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, isCompact ? 16 : 32)
    }

    // MARK: - Unlock Row

    @ViewBuilder
    private func unlockRow(window: AccessWindow, group: TicketGroup, isForfeited: Bool) -> some View {
        let cost = group.cost(for: window)
        let canPay = model.userEconomyStore.totalStepsBalance >= cost
        let isDisabled = !canPay || isForfeited

        Button {
            guard !isDisabled else { return }
            didForfeitSessions.insert(group.id)
            performTransition {
                Task {
                    await model.handlePayGatePaymentForGroup(groupId: group.id, window: window, costOverride: cost)
                }
            }
        } label: {
            HStack {
                Text(unlockLabel(window))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDisabled ? PayGatePalette.textMuted : PayGatePalette.textPrimary)

                Spacer()

                Text("\(cost)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isDisabled ? PayGatePalette.textMuted : PayGatePalette.accent)
                Text(String(localized: "colors"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isDisabled ? PayGatePalette.textMuted : PayGatePalette.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(String(localized: "Unlock for \(unlockLabel(window)), costs \(cost) colors"))
        .accessibilityHint(canPay ? String(localized: "Double tap to unlock") : String(localized: "Not enough colors"))
    }

    // MARK: - Day Reset Banner

    @ViewBuilder
    private func dayResetBanner(minutesLeft: Int) -> some View {
        let text: String = if minutesLeft < 1 {
            String(localized: "Day resets in less than a minute", comment: "PayGate reset warning")
        } else {
            String(localized: "Day resets in \(minutesLeft) min", comment: "PayGate reset warning")
        }

        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PayGatePalette.accent.opacity(0.8))
            Text(text)
                .font(.caption)
                .foregroundStyle(PayGatePalette.textSecondary)
        }
    }

    private func unlockLabel(_ window: AccessWindow) -> String {
        switch window {
        case .minutes10: return String(localized: "10 min")
        case .minutes30: return String(localized: "30 min")
        case .hour1: return String(localized: "1 hour")
        }
    }

    // MARK: - Transition

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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(duration * 850)))
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

#Preview {
    PayGateView(model: DIContainer.shared.makeAppModel())
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

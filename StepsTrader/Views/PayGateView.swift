import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif

/// PayGate palette: black background, yellow accent.
fileprivate enum PayGatePalette {
    static let background = Color.black
    static let accent = Color(red: 0xFF/255.0, green: 0xD3/255.0, blue: 0x69/255.0) // #FFD369
    static let surface = Color(white: 0.12)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
}

struct PayGateView: View {
    @ObservedObject var model: AppModel
    @State private var didForfeitSessions: Set<String> = []
    @State private var showTransitionCircle: Bool = false
    @State private var transitionScale: CGFloat = 0.01
    
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
            let isCompact = geometry.size.height < 700
            
            ZStack {
                PayGatePalette.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header: Balance
                    headerSection
                        .padding(.top, isCompact ? 20 : 40)
                    
                    Spacer()
                    
                    // Center: App Icon & Info
                    if let group = activeGroup {
                        targetInfoSection(group: group)
                    }
                    
                    Spacer()
                    
                    // Bottom: Actions
                    if let group = activeGroup {
                        actionSection(group: group)
                            .padding(.bottom, isCompact ? 20 : 40)
                    }
                }
                .padding(.horizontal, 24)
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
    
    // MARK: - Header (no bolt — strategy: just show number)
    private var headerSection: some View {
        HStack {
            Spacer()
            Text("\(model.userEconomyStore.totalStepsBalance)")
                .font(.notoSerif(32, weight: .bold))
                .foregroundColor(PayGatePalette.textPrimary)
                .monospacedDigit()
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(PayGatePalette.surface)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            Spacer()
        }
    }
    
    // MARK: - Target Info
    @ViewBuilder
    private func targetInfoSection(group: TicketGroup) -> some View {
        VStack(spacing: 24) {
            // Icons
            groupAppIconsView(group: group)
            
            // Text
            VStack(spacing: 8) {
                Text("spend exp")
                    .font(.notoSerif(28, weight: .bold))
                    .foregroundColor(PayGatePalette.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text(group.name)
                    .font(.body)
                    .foregroundColor(PayGatePalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    @ViewBuilder
    private func groupAppIconsView(group: TicketGroup) -> some View {
        #if canImport(FamilyControls)
        let appTokens = Array(group.selection.applicationTokens.prefix(3))
        let iconSize: CGFloat = 80
        
        ZStack {
            // Glow
            Circle()
                .fill(PayGatePalette.accent.opacity(0.2))
                .frame(width: iconSize * 2, height: iconSize * 2)
                .blur(radius: 30)
            
            if let templateApp = group.templateApp,
               let imageName = TargetResolver.imageName(for: templateApp),
               let uiImage = UIImage(named: imageName) ?? UIImage(named: imageName.lowercased()) ?? UIImage(named: imageName.capitalized) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
            } else if appTokens.isEmpty {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(PayGatePalette.accent)
            } else {
                // Stacked icons
                ForEach(Array(appTokens.enumerated()), id: \.offset) { index, token in
                    let size = iconSize - CGFloat(index * 10)
                    AppIconView(token: token)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                        .offset(x: CGFloat(index - 1) * 20, y: CGFloat(index) * 5)
                        .zIndex(Double(3 - index))
                }
            }
        }
        .frame(height: 120)
        #else
        Image(systemName: "lock.fill")
            .font(.system(size: 60))
            .foregroundColor(PayGatePalette.accent)
            .padding(30)
            .background(
                Circle()
                    .fill(PayGatePalette.surface)
            )
        #endif
    }
    
    // MARK: - Actions
    @ViewBuilder
    private func actionSection(group: TicketGroup) -> some View {
        let windows = Array(group.enabledIntervals).sorted { $0.minutes < $1.minutes }
        let isForfeited = didForfeitSessions.contains(group.id)
        
        VStack(spacing: 16) {
            // Unlock Buttons
            ForEach(windows.prefix(3), id: \.self) { window in
                unlockButton(window: window, group: group, isForfeited: isForfeited)
            }
            
            Spacer().frame(height: 8)
            
            // Close Button
            Button {
                didForfeitSessions.insert(group.id)
                performTransition(duration: 0.4) {
                    model.dismissPayGate(reason: .userDismiss)
                    sendAppToBackground()
                }
            } label: {
                Text("keep it closed")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(PayGatePalette.textSecondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func unlockButton(window: AccessWindow, group: TicketGroup, isForfeited: Bool) -> some View {
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
                    .font(.headline.weight(.bold))
                    .foregroundColor(isDisabled ? PayGatePalette.textSecondary.opacity(0.5) : .black)
                
                Spacer()
                
                Text("· \(cost) exp")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(isDisabled ? PayGatePalette.textSecondary.opacity(0.5) : .black)
            }
            .padding()
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDisabled ? PayGatePalette.surface : PayGatePalette.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: isDisabled ? 1 : 0)
            )
        }
        .disabled(isDisabled)
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func unlockLabel(_ window: AccessWindow) -> String {
        switch window {
        case .minutes10: return "10 min"
        case .minutes30: return "30 min"
        case .hour1: return "1 hour"
        }
    }
    
    // MARK: - Helpers
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
    
    private func sendAppToBackground() {
        DispatchQueue.main.async {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
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

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

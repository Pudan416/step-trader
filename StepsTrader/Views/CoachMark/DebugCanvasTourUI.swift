import SwiftUI
#if DEBUG
import HealthKit

private struct CanvasTourAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CanvasTourControlModifier: ViewModifier {
    let id: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var tour: DebugCanvasTour { .shared }
    func body(content: Content) -> some View {
        let enabled = !tour.isActive || tour.allowsControl(id)
        let isTarget = tour.isActive && tour.targetID == id
        let readable = enabled || tour.isContextualControl(id)
        content
            .opacity(readable || tour.quietMode == .normal ? 1 : tour.quietMode == .hide ? 0 : 0.12)
            .allowsHitTesting(enabled)
            .disabled(!enabled)
            .accessibilityHidden(!readable)
            .brightness(isTarget && pulse && !reduceMotion ? 0.035 : 0)
            .animation(isTarget && !reduceMotion ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true) : nil, value: pulse)
            .onChange(of: isTarget, initial: true) { _, active in pulse = active }
            .anchorPreference(key: CanvasTourAnchors.self, value: .bounds) { [id: $0] }
    }
}

extension DebugCanvasTour {
    func isContextualControl(_ id: String) -> Bool {
        guard isActive else { return true }
        if id == "canvas.balanceSummary" { return [.balance, .healthValue, .healthResult, .chooseDuration, .meTab].contains(step) }
        if step == .meTab, let group = selectedGroupID { return id == "feeds.group.\(group)" }
        return false
    }
    func allowsControl(_ id: String) -> Bool {
        guard isActive else { return true }
        // Setup hosts actual product screens in its own navigation stack.
        if step == .setup { return true }
        switch step {
        case .add: return id == "canvas.addHappening"
        case .happening: return id == "canvas.paletteClose" || id == "canvas.happenings"
        case .balance, .healthValue, .healthResult: return id == "canvas.balanceHandle"
        case .feedsTab: return id == "tabs.feeds"
        case .addApps: return id == "feeds.add" || id.hasPrefix("feeds.group.")
        case .selectFeed: return id == selectedGroupID.map { "feeds.group.\($0)" }
        case .chooseDuration:
            return selectedGroupID.map { id.hasPrefix("feeds.duration.\($0).") || id == "feeds.group.\($0)" } ?? false
        case .meTab: return id == "tabs.me"
        case .poster: return id == "me.share"
        default: return false
        }
    }
}

private struct DebugCanvasTourHost: ViewModifier {
    @ObservedObject var model: AppModel
    let context: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.canvasChromePalette) private var palette
    @State private var showSetup = false
    @State private var cardHeight: CGFloat = 0
    @State private var setupSession: UUID?
    @State private var showDiagnostics = false
    @State private var diagnosticsSession: UUID?
    @State private var healthAttempted = false
    @State private var healthFailed = false
    private var tour: DebugCanvasTour { .shared }

    private var recommendedWindow: AccessWindow? {
        guard let group = model.ticketGroups.first(where: { $0.id == tour.selectedGroupID }) else { return nil }
        return group.enabledIntervals.sorted { $0.minutes < $1.minutes }
            .first { group.cost(for: $0) <= model.totalStepsBalance }
    }
    private var target: String? {
        switch tour.step {
        case .add: "canvas.addHappening"
        case .happening: "canvas.happenings"
        case .balance: "canvas.balanceHandle"
        case .healthValue, .healthResult: "canvas.health"
        case .feedsTab: "tabs.feeds"
        case .addApps: "feeds.add"
        case .selectionResult, .selectFeed: tour.selectedGroupID.map { "feeds.group.\($0)" }
        case .chooseDuration:
            if let id = tour.selectedGroupID, let window = recommendedWindow { "feeds.duration.\(id).\(window.minutes)" }
            else { tour.selectedGroupID.map { "feeds.group.\($0)" } }
        case .meTab: "tabs.me"
        case .saveDays: "me.poster"
        case .poster: "me.share"
        default: nil
        }
    }
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(CanvasTourAnchors.self) { anchors in
                GeometryReader { proxy in
                    let rect = target.flatMap { anchors[$0] }.map { proxy[$0] }
                    let usable = rect.flatMap { value -> CGRect? in
                        let visible = value.intersection(CGRect(origin: .zero, size: proxy.size))
                        return value.width > 0 && value.height > 0 && !visible.isNull && visible.height >= min(value.height, 30) ? value : nil
                    }
                    if tour.overlayVisible {
                        card(targetRect: usable, container: proxy.size)
                            .id(tour.step)
                             .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                cardHeight = frame.height
                                tour.cardBottomGlobalY = frame.maxY
                            }
                            .position(cardPosition(targetRect: usable, container: proxy.size))
                            .onChange(of: usable, initial: true) { _, frame in
                                updateTarget(frame)
                            }
                            .onChange(of: target) { _, _ in updateTarget(usable) }
                    }
                }
            }
            .sheet(isPresented: $showSetup, onDismiss: {
                tour.sheetDismissed("setup", sessionID: setupSession)
            }) {
                DebugCanvasTourSetup(model: model, openAccountOnAppear: tour.openAccountOnSetup) {
                    tour.send(.setupCompleted)
                    showSetup = false
                }
                .onAppear { setupSession = tour.sessionID; tour.sheetPresented("setup", returnContext: "setup") }
                .interactiveDismissDisabled(tour.isActive)
            }
            .onChange(of: tour.step) { _, step in
                if step == .setup && tour.isActive && tour.status == .waitingForAction { showSetup = true }
            }
            .onChange(of: tour.status) { _, status in
                if status == .waitingForAction && tour.step == .setup && !showSetup && tour.isActive { showSetup = true }
            }
            .sheet(isPresented: $showDiagnostics, onDismiss: {
                tour.sheetDismissed("diagnostics", sessionID: diagnosticsSession)
            }) {
                NavigationStack {
                    DebugCanvasTourDeveloperPage(model: model)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back to tour") { showDiagnostics = false } } }
                }
                .onAppear { diagnosticsSession = tour.sessionID; tour.sheetPresented("diagnostics", returnContext: "flow") }
            }
            .onChange(of: tour.launchRevision) { _, _ in showDiagnostics = false; showSetup = false }
            .onChange(of: tour.isActive) { _, active in if !active { showSetup = false; showDiagnostics = false } }
            .onChange(of: scenePhase) { _, phase in
                tour.setForeground(phase == .active)
                if phase == .active && tour.isActive {
                    Task { await model.refreshNotificationAuthorizationStatus() }
                }
            }
            .onChange(of: Set(model.ticketGroups.filter { $0.selection.hasGroupTargets }.map(\.id))) { _, ids in tour.revalidate(groupIDs: ids) }
            .onChange(of: tour.sessionID) { _, _ in healthAttempted = false; healthFailed = false }
    }
    private func updateTarget(_ rect: CGRect?) {
        tour.targetID = target
        tour.targetVisible = rect != nil
        let description = rect.map { "\($0) in \(context)" } ?? "missing in \(context)"
        if tour.targetFrameDescription != description {
            tour.targetFrameDescription = description
            tour.report(rect == nil ? "target missing: \(target ?? "card")" : "target resolved: \(target ?? "card")")
        }
    }
    private func cardPosition(targetRect: CGRect?, container: CGSize) -> CGPoint {
        let height = min(max(cardHeight, 1), container.height - 32)
        let low = 16 + height / 2
        let high = max(low, container.height - 16 - height / 2)
        if tour.step == .happening { return CGPoint(x: container.width / 2, y: low) }
        guard let rect = targetRect, tour.step != .saveDays else {
            return CGPoint(x: container.width / 2, y: min(high, max(low, container.height * (tour.step == .happening ? 0.20 : 0.50))))
        }
        let above = rect.minY - 14 - height / 2
        let below = rect.maxY + 14 + height / 2
        let y = above >= low ? above : below <= high ? below : low
        return CGPoint(x: container.width / 2, y: min(high, max(low, y)))
    }
    private var coachSurface: Color {
        palette.textPrimary.perceptualOKLab.x > palette.surface.perceptualOKLab.x ? palette.textColor : palette.surfaceColor
    }
    private var coachInk: Color {
        palette.textPrimary.perceptualOKLab.x > palette.surface.perceptualOKLab.x ? palette.surfaceColor : palette.textColor
    }
    private func cardHeightLimit(targetRect: CGRect?, container: CGSize) -> CGFloat {
        if tour.step == .happening { return dynamicTypeSize.isAccessibilitySize ? min(320, container.height * 0.42) : min(200, container.height * 0.30) }
        guard let rect = targetRect, tour.step != .saveDays else { return max(100, container.height - 48) }
        return max(88, max(rect.minY - 30, container.height - rect.maxY - 30))
    }
    @ViewBuilder private func card(targetRect: CGRect?, container: CGSize) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityCard(targetRect: targetRect, container: container)
        } else {
            standardCard(targetRect: targetRect, container: container)
        }
    }
    private func accessibilityCard(targetRect: CGRect?, container: CGSize) -> some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.geist(.title3).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    cardDetails(targetRect: targetRect)
                    if tour.step == .happening {
                        Button(String(localized: "Use this day")) { tour.send(.useExistingDay) }
                            .font(.geist(.subheadline))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("canvas_tour.existingDay")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button { showDiagnostics = true } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Tour controls").accessibilityIdentifier("canvas_tour.controls")
                Button(String(localized: "Skip tour")) { tour.send(.skipRequested) }
                    .font(.geist(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("canvas_tour.skip")
            }
        }
        .foregroundStyle(coachInk)
        .padding(20)
        .frame(width: min(360, max(100, container.width - 32)))
        .frame(height: min(cardHeightLimit(targetRect: targetRect, container: container), container.height * 0.70))
        .background(coachSurface, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_tour.card.\(tour.step.rawValue)")
    }
    private func standardCard(targetRect: CGRect?, container: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(title).font(.geist(.title3).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { showDiagnostics = true } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 32)
                }
                .accessibilityLabel("Tour controls")
                .accessibilityIdentifier("canvas_tour.controls")
            }
            ViewThatFits(in: .vertical) {
                cardDetails(targetRect: targetRect)
                ScrollView { cardDetails(targetRect: targetRect) }
            }
            HStack {
                if tour.step == .happening {
                    Button(String(localized: "Use this day")) { tour.send(.useExistingDay) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("canvas_tour.existingDay")
                }
                Button(tour.step == .welcome ? String(localized: "Explore on my own") : String(localized: "Skip tour")) {
                    tour.send(.skipRequested)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("canvas_tour.skip")
            }.font(.geist(.subheadline))
        }
        .foregroundStyle(coachInk)
        .padding(20)
        .frame(width: min(360, max(100, container.width - 32)))
        .frame(maxHeight: cardHeightLimit(targetRect: targetRect, container: container))
        .fixedSize(horizontal: false, vertical: true)
        .background(coachSurface, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            if let rect = targetRect, ![.happening, .saveDays].contains(tour.step) {
                let belowCard = rect.midY > cardPosition(targetRect: targetRect, container: container).y
                VStack {
                    if belowCard { Spacer() }
                    Image(systemName: belowCard ? "arrow.down" : "arrow.up")
                        .font(.geist(.caption).weight(.semibold))
                        .foregroundStyle(coachInk)
                        .padding(3).background(coachSurface, in: Circle())
                        .offset(x: min(140, max(-140, rect.midX - container.width / 2)), y: belowCard ? 10 : -10)
                    if !belowCard { Spacer() }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_tour.card.\(tour.step.rawValue)")
    }
    private func cardDetails(targetRect: CGRect?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.geist(.callout)).fixedSize(horizontal: false, vertical: true)
            if let error = tour.errorMessage {
                Text(error).font(.geist(.caption)).fixedSize(horizontal: false, vertical: true)
            }
            if target != nil && targetRect == nil {
                Text(String(localized: "Waiting for the control to appear. You can scroll to it or skip the tour."))
                    .font(.geist(.caption))
            }
            actions
        }
    }
    private func action(_ title: String, id: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.geist(.subheadline).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .foregroundStyle(coachSurface)
                .background(coachInk, in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("canvas_tour.\(id)")
    }
    @ViewBuilder private var actions: some View {
        switch tour.step {
        case .welcome: action(String(localized: "Let’s begin"), id: "begin") { tour.send(.begin) }
        case .healthValue:
            action(String(localized: "Connect Apple Health"), id: "health") { requestHealth() }
            action(String(localized: "Later"), id: "healthLater") { tour.send(.healthDeferred) }
        case .healthResult:
            if healthFailed { action(String(localized: "Retry"), id: "healthRetry") { requestHealth() } }
            action(String(localized: "Continue"), id: "healthContinue") { tour.send(.continueHealth) }
        case .addApps:
            action(String(localized: "Skip app setup"), id: "skipApps") { tour.send(.skipApps) }
        case .selectionResult:
            action(String(localized: "Got it"), id: "appsGotIt") { tour.send(.selectionAcknowledged) }
        case .selectFeed, .chooseDuration:
            if tour.step == .chooseDuration && recommendedWindow == nil {
                action(String(localized: "Add a happening"), id: "addColors") { tour.send(.addMoreColors) }
            }
            action(String(localized: "Skip trial unlock"), id: "skipUnlock") { tour.send(.skipUnlock) }
        case .saveDays:
            if !AuthenticationService.shared.hasAppleAccount {
                action(String(localized: "Sign in"), id: "signIn") {
                    tour.openAccountOnSetup = true; tour.send(.showSetup)
                }.disabled(tour.posterDayID == nil)
            }
            action(AuthenticationService.shared.hasAppleAccount ? String(localized: "Your setup") : String(localized: "Later"), id: "later") {
                tour.openAccountOnSetup = false; tour.send(.showSetup)
            }.disabled(tour.posterDayID == nil)
        case .poster: action(String(localized: "Skip export"), id: "skipExport") { tour.send(.exportSkipped) }
        case .finish: action(String(localized: "Start exploring"), id: "finish") { tour.send(.finish) }
        default: EmptyView()
        }
    }
    private var title: String {
        switch tour.step {
        case .welcome: String(localized: "Hey, I’m Kosta.")
        case .add: String(localized: "Start with a moment.")
        case .happening: String(localized: "What happened today?")
        case .balance: String(localized: "You now have \(model.totalStepsBalance) colors")
        case .healthValue: String(localized: "Your day adds color.")
        case .healthResult: healthFailed ? String(localized: "Couldn’t check Health") : String(localized: "Apple Health")
        case .feedsTab: String(localized: "Unlock apps with your colors.")
        case .addApps: String(localized: "Choose your apps.")
        case .selectionResult: String(localized: "Apps selected.")
        case .selectFeed: String(localized: "Try your first unlock.")
        case .chooseDuration: recommendedWindow == nil ? String(localized: "Not enough colors yet") : String(localized: "Choose your time.")
        case .meTab: String(localized: "See your day.")
        case .saveDays: String(localized: "Keep your days with you.")
        case .setup: String(localized: "Your setup")
        case .poster: String(localized: "Keep this day.")
        case .finish: String(localized: "That’s it. Welcome to Nowhere.")
        }
    }
    private var message: String {
        switch tour.step {
        case .welcome: String(localized: "I made Nowhere to scroll less and notice more. Want a quick tour?")
        case .add: String(localized: "Tap + to add something from your day.")
        case .happening: String(localized: "Tap once to preview. Tap again to add.")
        case .balance: String(localized: "Pull the top panel down, or tap it, to see what else adds color to your day.")
        case .healthValue: String(localized: "Steps can add up to \(EnergyDefaults.stepsMaxPoints) colors a day, and Sleep up to \(EnergyDefaults.sleepMaxPoints). Check Apple Health to read available data.")
        case .healthResult:
            if !HKHealthStore.isHealthDataAvailable() { String(localized: "Health is unavailable on this device. You can continue without it.") }
            else if model.stepsToday > 0 || model.dailySleepHours > 0 { String(localized: "Health data is available. The panel shows your calculated colors for today.") }
            else if healthFailed { String(localized: "Try again, or continue without Health.") }
            else if healthAttempted || model.hasStepsData || model.hasSleepData { String(localized: "Your colors will update as Health data becomes available. An empty result does not tell us which read permissions you allowed.") }
            else { String(localized: "You can check Health access later in Settings.") }
        case .feedsTab: String(localized: "Tap Feeds to choose the apps you’d like to pause.")
        case .addApps: model.ticketGroups.isEmpty ? String(localized: "Tap + to choose the apps you’d like to pause. App access is optional for finishing this tour.") : String(localized: "Tap an existing group to use it, or tap + to choose another set of apps.")
        case .selectionResult: String(localized: "Your group is saved. You can change it later in Feeds.")
        case .selectFeed: String(localized: "Tap your chosen group to see available times and their costs.")
        case .chooseDuration:
            if let window = recommendedWindow { String(localized: "Try \(window.minutes) minutes, or choose any available interval. Your real colors will be spent.") }
            else { String(localized: "Add a happening to earn colors, or skip this trial unlock.") }
        case .meTab: String(localized: "Tap Me to see your day as a poster. You can save it or share it.")
        case .saveDays: tour.posterDayID == nil ? String(localized: "Your current day is getting ready. Account and permissions are optional.") : String(localized: "Sign in with Apple to keep your account, or continue to your optional setup.")
        case .setup: String(localized: "Everything here is optional.")
        case .poster: String(localized: "Save your poster, or share it with someone. Tap the poster’s share button.")
        case .finish: String(localized: "Make room for your day. Enjoy exploring.")
        }
    }
    private func requestHealth() {
        guard HKHealthStore.isHealthDataAvailable() else {
            tour.send(.healthUpdated); return
        }
        guard let token = tour.beginOperation("health") else { return }
        tour.sheetPresented("health")
        Task { @MainActor in
            do {
                try await model.healthStore.requestAuthorization()
                guard tour.isCurrent(token) else { return }
                healthAttempted = true
                await model.refreshStepsIfAuthorized()
                await model.refreshSleepIfAuthorized()
                guard tour.isCurrent(token) else { return }
                healthFailed = model.healthStore.debugStepsQueryOutcome == .failed || model.healthStore.debugSleepQueryOutcome == .failed
                tour.send(.healthUpdated, token: token)
                tour.sheetDismissed("health", sessionID: token.sessionID)
                if healthFailed { tour.recover(String(localized: "Some Health data couldn’t refresh. The panel may show cached values. Retry or continue.")) }
            } catch {
                guard tour.isCurrent(token) else { return }
                healthAttempted = true; healthFailed = true
                tour.send(.healthUpdated, token: token)
                tour.sheetDismissed("health", sessionID: token.sessionID)
                tour.recover(String(localized: "We couldn’t check Health access. Retry or continue without Health."))
            }
        }
    }
}
#endif

extension View {
    @ViewBuilder func canvasTourControl(_ id: String) -> some View {
        #if DEBUG
        modifier(CanvasTourControlModifier(id: id))
        #else
        self
        #endif
    }
    @ViewBuilder func canvasTourAnchor(_ id: String) -> some View {
        #if DEBUG
        anchorPreference(key: CanvasTourAnchors.self, value: .bounds) { [id: $0] }
        #else
        self
        #endif
    }
    @ViewBuilder func canvasTourHost(model: AppModel, context: String = "root") -> some View {
        #if DEBUG
        modifier(DebugCanvasTourHost(model: model, context: context))
        #else
        self
        #endif
    }
}

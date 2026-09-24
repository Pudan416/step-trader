import SwiftUI
import HealthKit
import UIKit

extension EnvironmentValues {
    @Entry var canvasTourContentTopInset: CGFloat = 0
}

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
    private var tour: CanvasTour { .shared }
    func body(content: Content) -> some View {
        let enabled = !tour.isActive || (tour.exitRequest == nil && tour.allowsControl(id))
        let isTarget = tour.isActive && tour.targetID == id
        let readable = tour.exitRequest == nil && (enabled || tour.isContextualControl(id))
        content
            .opacity(readable || tour.quietMode == .normal ? 1 : tour.quietMode == .hide ? 0 : 0.12)
            .allowsHitTesting(enabled)
            .disabled(!enabled)
            .accessibilityHidden(!readable)
            // Scope the repeating animation to brightness. Applying it to the
            // control hierarchy also animates newly resolved anchor/layout values,
            // leaving actual buttons moving away from their hit regions.
            .animation(isTarget && !reduceMotion ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true) : nil) { view in
                view.brightness(isTarget && pulse && !reduceMotion ? 0.035 : 0)
            }
            .onChange(of: isTarget, initial: true) { _, active in pulse = active }
            .transformAnchorPreference(key: CanvasTourAnchors.self, value: .bounds) { anchors, anchor in anchors[id] = anchor }
    }
}

extension CanvasTour {
    func isContextualControl(_ id: String) -> Bool {
        guard isActive else { return true }
        if id == "canvas.balanceSummary" { return [.momentResult, .balance, .healthValue, .healthResult, .chooseDuration, .meTab].contains(step) }
        if step == .meTab, let group = selectedGroupID { return id == "feeds.group.\(group)" }
        return false
    }
    func allowsControl(_ id: String) -> Bool {
        guard isActive else { return true }
        // Setup hosts actual product screens in its own navigation stack.
        if step == .setup { return true }
        switch step {
        case .add: return id == "canvas.addHappening"
        case .happening: return id == "canvas.paletteClose" || id == "canvas.paletteMode" || id == "canvas.happenings" || id.hasPrefix("canvas.happening.")
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

private struct CanvasTourHost: ViewModifier {
    @ObservedObject var model: AppModel
    let context: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.canvasChromePalette) private var palette
    @State private var showSetup = false
    @State private var cardFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var setupSession: UUID?
    @State private var showDiagnostics = false
    @State private var diagnosticsSession: UUID?
    @State private var healthAttempted = false
    @State private var healthFailed = false
    private var tour: CanvasTour { .shared }

    private var recommendedWindow: AccessWindow? {
        guard let group = model.ticketGroups.first(where: { $0.id == tour.selectedGroupID }) else { return nil }
        return group.enabledIntervals.sorted { $0.minutes < $1.minutes }
            .first { group.cost(for: $0) <= model.totalStepsBalance }
    }
    private var target: String? {
        switch tour.step {
        case .add: "canvas.addHappening"
        case .happening: "canvas.happenings"
        case .momentResult: "canvas.balanceSummary"
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
                    let navigationTop = ["tabs.canvas", "tabs.feeds", "tabs.me"].compactMap { anchors[$0].map { proxy[$0].minY } }.min()
                    if tour.overlayVisible {
                        CanvasTourMissedTapObserver(excludedRects: allowedTapRects(anchors: anchors, proxy: proxy) + [cardFrame]) {
                            tour.requestExit(reason: "outside tap")
                        }
                        .allowsHitTesting(false)
                        CanvasTourCardLayout(step: tour.step, target: usable, navigationTop: navigationTop) {
                            card(target: [.happening, .saveDays, .poster].contains(tour.step) ? nil : usable.map {
                                let host = proxy.frame(in: .global)
                                return $0.offsetBy(dx: host.minX, dy: host.minY)
                            })
                                .id(tour.step)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                    let host = proxy.frame(in: .global)
                                    cardFrame = frame.offsetBy(dx: -host.minX, dy: -host.minY)
                                    tour.cardTopGlobalY = frame.minY
                                    tour.cardBottomGlobalY = frame.maxY
                                }
                        }
                        // A step replacement is atomic. Even an asymmetric fade
                        // keeps the outgoing instruction in SwiftUI's transition
                        // tree briefly, which can put two instructions on screen.
                        .transaction { $0.animation = nil }
                        .onChange(of: usable, initial: true) { _, frame in updateTarget(frame) }
                        .onChange(of: target) { _, _ in updateTarget(usable) }
                    }

                }
            }
            .canvasTourExitChrome(context: "flow", onDiagnostics: diagnosticsAction)
            .sheet(isPresented: $showSetup, onDismiss: {
                tour.sheetDismissed("setup", sessionID: setupSession)
            }) {
                CanvasTourSetup(model: model) {
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
            #if DEBUG
            .sheet(isPresented: $showDiagnostics, onDismiss: {
                tour.sheetDismissed("diagnostics", sessionID: diagnosticsSession)
            }) {
                NavigationStack {
                    CanvasTourDeveloperPage(model: model)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back to tour") { showDiagnostics = false } } }
                }
                .onAppear { diagnosticsSession = tour.sessionID; tour.sheetPresented("diagnostics", returnContext: "flow") }
            }
            #endif
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
    private var diagnosticsAction: (() -> Void)? {
        #if DEBUG
        { showDiagnostics = true }
        #else
        nil
        #endif
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
    private func allowedTapRects(anchors: [String: Anchor<CGRect>], proxy: GeometryProxy) -> [CGRect] {
        anchors.compactMap { id, anchor in
            // The field container is full-screen; only actual choices are tap targets.
            guard id != "canvas.happenings", tour.allowsControl(id) else { return nil }
            return proxy[anchor].insetBy(dx: -4, dy: -4)
        }
    }
    private var coachSurface: Color {
        palette.textPrimary.perceptualOKLab.x > palette.surface.perceptualOKLab.x ? palette.textColor : palette.surfaceColor
    }
    private var coachInk: Color {
        palette.textPrimary.perceptualOKLab.x > palette.surface.perceptualOKLab.x ? palette.surfaceColor : palette.textColor
    }
    private func card(target: CGRect?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .vertical) {
                cardContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { cardContent.fixedSize(horizontal: false, vertical: true) }
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("canvas_tour.textScroll")
            }
            VStack(spacing: 10) {
                actions
                if tour.step == .happening {
                    Button(String(localized: "Use this day")) { tour.send(.useExistingDay) }
                        .font(.onest(.subheadline))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("canvas_tour.existingDay")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .foregroundStyle(coachInk)
        .padding(.horizontal, 20)
        .padding(.vertical, [.healthValue, .healthResult].contains(tour.step) ? 12 : 20)
        .frame(maxWidth: .infinity)
        .background { CanvasTourCardSurface(target: target, color: coachSurface) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_tour.card.\(tour.step.rawValue)")
        .accessibilityHidden(tour.exitRequest != nil)
    }
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.onest(.title3).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            cardDetails
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var cardDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.geist(.callout)).fixedSize(horizontal: false, vertical: true)
            if let error = tour.errorMessage {
                Text(error).font(.geist(.caption)).fixedSize(horizontal: false, vertical: true)
            }
            // Missing anchors are reported in Diagnostics. A transient first
            // layout must not insert another line and resize the instruction.
        }
    }
    private func action(_ title: String, id: String, secondary: Bool = false, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.geist(.subheadline).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .foregroundStyle(secondary ? coachInk : coachSurface)
                .background(secondary ? coachSurface : coachInk, in: Capsule())
                .overlay { if secondary { Capsule().strokeBorder(coachInk.opacity(0.6), lineWidth: 1) } }
        }.buttonStyle(.plain).accessibilityIdentifier("canvas_tour.\(id)")
    }
    @ViewBuilder private var actions: some View {
        switch tour.step {
        case .welcome: action(String(localized: "Let’s begin"), id: "begin") { tour.send(.begin) }
        case .momentResult: action(String(localized: "Next"), id: "momentNext") { tour.send(.momentAcknowledged) }
        case .healthValue:
            HStack(spacing: 10) {
                action(String(localized: "Connect Health"), id: "health") { requestHealth() }
                action(String(localized: "Later"), id: "healthLater", secondary: true) { tour.send(.healthDeferred) }
            }
        case .healthResult:
            if healthFailed { action(String(localized: "Retry"), id: "healthRetry") { requestHealth() } }
            action(String(localized: "Continue"), id: "healthContinue") { tour.send(.continueHealth) }
        case .addApps:
            action(String(localized: "Later"), id: "skipApps") { tour.send(.skipApps) }
        case .selectionResult:
            action(String(localized: "Got it"), id: "appsGotIt") { tour.send(.selectionAcknowledged) }
        case .selectFeed, .chooseDuration:
            if tour.step == .chooseDuration && recommendedWindow == nil {
                action(String(localized: "Add a happening"), id: "addColors") { tour.send(.addMoreColors) }
            }
            action(String(localized: "Continue without unlocking"), id: "skipUnlock") { tour.send(.skipUnlock) }
        case .saveDays:
            action(String(localized: "Continue"), id: "later") {
                tour.send(.showSetup)
            }.disabled(tour.posterDayID == nil)
        case .poster: action(String(localized: "Not now"), id: "skipExport") { tour.send(.exportSkipped) }
        case .finish: action(String(localized: "Start exploring"), id: "finish") { tour.send(.finish) }
        default: EmptyView()
        }
    }
    private var title: String {
        switch tour.step {
        case .welcome: String(localized: "Hey, I’m Kosta.")
        case .add: String(localized: "Start with a moment.")
        case .happening: String(localized: "What happened today?")
        case .momentResult: String(localized: "You already have \(model.totalStepsBalance) colors.")
        case .balance: String(localized: "Pull it down.")
        case .healthValue: String(localized: "Activity and Sleep")
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
        case .happening: String(localized: "Tap once to add. Tap twice to remove.")
        case .momentResult: String(localized: "By adding happenings, you can get up to \(HappeningDefaults.happeningsMaxPoints) colors a day.")
        case .balance: String(localized: "To see where the other \(EnergyDefaults.activityMaxPoints + EnergyDefaults.sleepMaxPoints) colors can come from. You can also tap the handle.")
        case .healthValue:
            if EnergyDefaults.activityMaxPoints == EnergyDefaults.sleepMaxPoints {
                String(localized: "Apple Health: up to \(EnergyDefaults.activityMaxPoints) colors each for Activity and Sleep.\nNo activity data? You still get \(EnergyDefaults.assumedActivityPoints) colors.")
            } else {
                String(localized: "Apple Health: Activity up to \(EnergyDefaults.activityMaxPoints),\nSleep up to \(EnergyDefaults.sleepMaxPoints) colors a day.\nNo activity data? You still get \(EnergyDefaults.assumedActivityPoints) colors.")
            }
        case .healthResult:
            if !HKHealthStore.isHealthDataAvailable() { String(localized: "Health is unavailable on this device. You can continue without it.") }
            else if healthFailed { String(localized: "Try again, or continue without Health. The panel may show earlier values.") }
            else if model.stepsToday > 0 || model.dailySleepHours > 0 { String(localized: "The panel shows colors from available Health data. You can change Health access in Settings.") }
            else if healthAttempted || model.hasStepsData || model.hasSleepData { String(localized: "Colors can update as Health data becomes available. You can change Health access in Settings.") }
            else { String(localized: "You can connect Health later or change access in Settings.") }
        case .feedsTab: String(localized: "Tap Feeds to choose the apps you’d like to pause.")
        case .addApps: model.ticketGroups.isEmpty ? String(localized: "Tap +, enter a name and choose your apps, then tap Done. You can also skip this step.") : String(localized: "Tap an existing group, or tap + to name a new group and choose its apps.")
        case .selectionResult: String(localized: "Your group is saved. You can change it later in Feeds.")
        case .selectFeed: String(localized: "Tap your chosen group to see available times and their costs.")
        case .chooseDuration:
            if let window = recommendedWindow { String(localized: "Try \(window.minutes) minutes, or choose any available interval. Your real colors will be spent.") }
            else { String(localized: "Add a happening to earn colors, or skip this trial unlock.") }
        case .meTab: String(localized: "Tap Me to see your day as a poster. You can save it or share it.")
        case .saveDays: tour.posterDayID == nil ? String(localized: "Your current day is getting ready. Permissions are optional.") : String(localized: "Everything here is optional.")
        case .setup: String(localized: "Everything here is optional.")
        case .poster: String(localized: "Save your poster, or share it with someone. Tap the poster’s share button.")
        case .finish: String(localized: "Nowhere = now + here.\nStart living Nowhere.")
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
                healthFailed = model.healthStore.stepsQueryOutcome == .failed || model.healthStore.sleepQueryOutcome == .failed
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
/// Uses the same filled tail as the product hint, anchored to the measured control.
/// The tail extends into the existing gap, without changing card or target layout.
private struct CanvasTourCardSurface: View {
    let target: CGRect?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            if let target,
               target.minY - frame.maxY >= CanvasHintBubbleShape.tailHeight ||
               frame.minY - target.maxY >= CanvasHintBubbleShape.tailHeight {
                let pointsUp = target.maxY <= frame.minY
                CanvasHintBubbleShape(tailX: target.midX - frame.minX,
                                      cornerRadius: 24, pointsUp: pointsUp)
                    .fill(color)
                    .frame(height: proxy.size.height + CanvasHintBubbleShape.tailHeight)
                    .offset(y: pointsUp ? -CanvasHintBubbleShape.tailHeight : 0)
            } else {
                RoundedRectangle(cornerRadius: 24).fill(color)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Measures this card before placing it; no previous-step height enters placement.
enum CanvasTourCardGeometry {
    static func frame(in size: CGSize, idealHeight: CGFloat, step: CanvasTourStep,
                      target: CGRect?, navigationTop: CGFloat?) -> CGRect {
        let width = min(360, max(1, size.width - 32))
        let top: CGFloat = 16
        let bottom = max(top + 44, min(size.height - 16, (navigationTop ?? size.height) - 16))
        let available = max(44, bottom - top)
        var low = top, high = bottom
        if step == .happening {
            high = top + min(220, available * 0.36)
        } else if step == .saveDays || step == .poster {
            low = bottom - min(300, available * 0.48)
        } else if let target, !target.isEmpty {
            let above = max(0, target.minY - 14 - top)
            let below = max(0, bottom - target.maxY - 14)
            if idealHeight <= above || (idealHeight > below && above >= below) {
                high = top + above
            } else {
                low = bottom - below
            }
        }
        let height = min(idealHeight, max(44, high - low))
        let y: CGFloat
        if step == .happening { y = low }
        else if step == .saveDays || step == .poster { y = high - height }
        else if let target { y = high <= target.minY ? high - height : low }
        else { y = low + max(0, high - low - height) / 2 }
        return CGRect(x: (size.width - width) / 2, y: max(top, y), width: width, height: height)
    }
}

private struct CanvasTourCardLayout: Layout {
    let step: CanvasTourStep
    let target: CGRect?
    let navigationTop: CGFloat?
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let width = min(360, max(1, bounds.width - 32))
        let ideal = card.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let frame = CanvasTourCardGeometry.frame(in: bounds.size, idealHeight: ideal.height,
                                                 step: step, target: target, navigationTop: navigationTop)
        card.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                   anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
}

/// Observes only taps, alongside native scrolling/panning. It never owns hit testing
/// and never cancels the product gesture. System sheets disable the observer host.
private struct CanvasTourMissedTapObserver: UIViewRepresentable {
    var excludedRects: [CGRect]
    var onMiss: () -> Void
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.excludedRects = excludedRects; view.onMiss = onMiss
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }
    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var excludedRects: [CGRect] = []
        var onMiss: (() -> Void)?
        private weak var observedWindow: UIWindow?
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(missed))
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow(); detach()
            guard let window else { return }
            observedWindow = window
            tap.cancelsTouchesInView = false; tap.delegate = self
            window.addGestureRecognizer(tap)
        }
        func detach() { observedWindow?.removeGestureRecognizer(tap); observedWindow = nil }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard CanvasTour.shared.overlayVisible, CanvasTour.shared.exitRequest == nil else { return false }
            let point = touch.location(in: self)
            return bounds.contains(point) && !excludedRects.contains { $0.contains(point) }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc private func missed() { if tap.state == .ended { onMiss?() } }
    }
}

private struct CanvasTourExitChrome: ViewModifier {
    let context: String
    var onDiagnostics: (() -> Void)?
    @Environment(\.canvasChromePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var focusConfirmation: Bool
    @State private var exitHeaderHeight: CGFloat = 56
    private var tour: CanvasTour { .shared }
    private var isOwner: Bool { context == "flow" ? tour.presentedSheet == nil : tour.presentedSheet == context }
    private var confirmationVisible: Bool { tour.isActive && isOwner && tour.isForeground && tour.exitRequest != nil }
    private var surface: Color {
        palette.textPrimary.perceptualOKLab.x > palette.surface.perceptualOKLab.x ? palette.textColor : palette.surfaceColor
    }
    private var ink: Color {
        palette.textPrimary.perceptualOKLab.x > palette.surface.perceptualOKLab.x ? palette.surfaceColor : palette.textColor
    }
    func body(content: Content) -> some View {
        content
            .environment(\.canvasTourContentTopInset, tour.isActive ? exitHeaderHeight : 0)
            .safeAreaInset(edge: .top, spacing: 0) {
            if tour.isActive {
                if isOwner && tour.isForeground {
                    HStack {
                        Button("Skip") { tour.requestExit(reason: "skip") }
                            .font(.onest(.subheadline))
                            .padding(.horizontal, 20).frame(minWidth: 76, minHeight: 44)
                            .foregroundStyle(ink).background(surface, in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityLabel("Skip tour")
                            .accessibilityIdentifier("canvas_tour.skip")
                        Spacer(minLength: 12)
                        if let onDiagnostics {
                            Button(action: onDiagnostics) { Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }
                                .foregroundStyle(ink).background(surface, in: Circle())
                                .accessibilityLabel("Tour controls")
                                .accessibilityIdentifier("canvas_tour.controls")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .zIndex(1)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { exitHeaderHeight = $0 }
                    .accessibilityHidden(confirmationVisible)
                } else {
                    // Remove the background host's buttons from both UIKit hit
                    // testing and accessibility while preserving its layout.
                    Color.clear.frame(height: exitHeaderHeight).allowsHitTesting(false)
                }
            }
        }
            .background {
                if tour.isActive {
                    TodayCanvasBackground(matchesCanvas: true).ignoresSafeArea().allowsHitTesting(false)
                }
            }
            .blur(radius: confirmationVisible && !reduceTransparency ? 6 : 0)
            .allowsHitTesting(!confirmationVisible)
            .accessibilityHidden(confirmationVisible)
            .overlay {
                ZStack {
                if confirmationVisible {
                    GeometryReader { proxy in
                        ZStack {
                            ink.opacity(reduceTransparency ? 0.85 : 0.40).ignoresSafeArea()
                                .contentShape(Rectangle()).onTapGesture { }
                            ViewThatFits(in: .vertical) {
                                confirmationContent.fixedSize(horizontal: false, vertical: true)
                                ScrollView { confirmationContent }
                            }
                            .foregroundStyle(ink).padding(20)
                            .frame(width: min(360, max(1, proxy.size.width - 32)))
                            .frame(maxHeight: max(100, proxy.size.height - 32))
                            .fixedSize(horizontal: false, vertical: true)
                            .background(surface, in: RoundedRectangle(cornerRadius: 24))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("canvas_tour.exit.card")
                            .accessibilityAction(.escape) { tour.continueTour() }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .transition(.opacity)
                }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: confirmationVisible)
            }
    }
    private var confirmationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Want to keep going?").font(.onest(.title3).weight(.semibold))
                .accessibilityAddTraits(.isHeader).accessibilityFocused($focusConfirmation)
            Text("I can guide you through the next step.").font(.onest(.callout))
            Button { tour.continueTour() } label: {
                Text("Tapped by mistake. Keep going.").font(.onest(.subheadline).weight(.medium))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12).padding(.vertical, 4)
                    .foregroundStyle(surface).background(ink, in: RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(.plain).accessibilityIdentifier("canvas_tour.exit.continue")
            Button("I’ll explore on my own") { tour.confirmExit() }
                .font(.onest(.subheadline)).frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityIdentifier("canvas_tour.exit.confirm")
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { focusConfirmation = true }
    }
}

extension View {
    @ViewBuilder func canvasTourExitChrome(context: String, onDiagnostics: (() -> Void)? = nil) -> some View {
        modifier(CanvasTourExitChrome(context: context, onDiagnostics: onDiagnostics))
    }

    @ViewBuilder func canvasTourControl(_ id: String) -> some View {
        modifier(CanvasTourControlModifier(id: id))
    }
    @ViewBuilder func canvasTourAnchor(_ id: String) -> some View {
        transformAnchorPreference(key: CanvasTourAnchors.self, value: .bounds) { anchors, anchor in anchors[id] = anchor }
    }
    @ViewBuilder func canvasTourHost(model: AppModel, context: String = "root") -> some View {
        modifier(CanvasTourHost(model: model, context: context))
    }
}

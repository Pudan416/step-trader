import Foundation
import Observation

enum CanvasTourStep: String, CaseIterable, Codable, Identifiable {
    case welcome, add, happening, momentResult, balance, healthValue, healthResult, feedsTab
    case addApps, selectionResult, selectFeed, chooseDuration, meTab, saveDays, setup, poster, finish
    var id: String { rawValue }
    var expectedEvent: String {
        switch self {
        case .welcome: "begin"
        case .add: "palettePresented"
        case .happening: "happeningAdded → paletteDismissed"
        case .momentResult: "momentAcknowledged"
        case .balance: "dataPanelExpanded"
        case .healthValue: "healthUpdated / healthDeferred"
        case .healthResult: "continueHealth"
        case .feedsTab: "tabSelected(1)"
        case .addApps: "appSelectionCommitted → sheetDismissed"
        case .selectionResult: "selectionAcknowledged"
        case .selectFeed: "groupOpened(selectedGroupID)"
        case .chooseDuration: "unlockSucceeded(selectedGroupID)"
        case .meTab: "tabSelected(2)"
        case .saveDays: "posterReady / showSetup"
        case .setup: "setupCompleted → sheetDismissed"
        case .poster: "shareDismissed / exportSkipped"
        case .finish: "finish"
        }
    }
    var preparationTab: Int {
        switch self {
        case .addApps, .selectionResult, .selectFeed, .chooseDuration, .meTab: 1
        case .saveDays, .setup, .poster: 2
        default: 0
        }
    }
}

enum CanvasTourEvent: Equatable {
    case begin, palettePresented, happeningAdded(String), paletteDismissed, useExistingDay
    case momentAcknowledged, dataPanelExpanded, healthUpdated, healthDeferred, continueHealth, tabSelected(Int)
    case appSelectionCommitted(String), selectionAcknowledged, groupOpened(String), unlockSucceeded(String)
    case skipApps, skipUnlock, addMoreColors, posterReady(String), showSetup, setupCompleted
    case shareDismissed(Bool), exportSkipped, finish, skipRequested
}

enum CanvasTourStatus: String, Codable {
    case inactive, preparing, showing, waitingForAction, waitingForSystemUI, resolvingResult
    case paused, completed, skipped, recoverableError
}
enum CanvasTourQuietMode: String, Codable, CaseIterable { case normal = "Normal", dim = "Dim", hide = "Hide" }
struct CanvasTourOperation: Equatable, Codable {
    let sessionID: UUID
    let id: UUID
    let name: String
}

private struct CanvasTourSession: Codable {
    var sessionID = UUID()
    var flowVersion = 2
    var mode = "Live"
    var status = CanvasTourStatus.inactive
    var currentStep = CanvasTourStep.welcome
    var entrySource = "developer"
    var returnContext = "flow"
    var selectedGroupID: String?
    var addedEntryID: String?
    var pendingOperation: CanvasTourOperation?
    var completedSteps: Set<CanvasTourStep> = []
    var skippedBranches: Set<String> = []
    var quietMode = CanvasTourQuietMode.dim
}

/// Progress only. Product mutations and permission semantics belong to existing services.
/// No analytics service, model storage, Health samples or FamilyControls tokens enter this object.
@Observable @MainActor
final class CanvasTour {
    static let shared: CanvasTour = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let defaults: UserDefaults? = arguments.contains("debug-canvas-tour-fixtures") ? nil : .standard
        let suppressesAnalytics = arguments.contains("ui-testing") || arguments.contains("debug-canvas-tour-fixtures")
        #else
        let defaults: UserDefaults? = .standard
        let suppressesAnalytics = false
        #endif
        return CanvasTour(defaults: defaults, suppressesAnalytics: suppressesAnalytics,
                          onStart: { _ = CanvasOnboardingState.shared.claimAutomaticStart() },
                          onFirstLaunchCompleted: { CanvasOnboardingState.shared.complete() })
    }()
    private static let storageKey = "canvas.onboarding.session.v2"
    private var session = CanvasTourSession()
    private(set) var isActive = false
    private(set) var presentedSheet: String?
    private(set) var pendingDestination: CanvasTourStep?
    private(set) var posterDayID: String?
    private(set) var shareCompleted = false
    private(set) var transitions: [String] = []
    private(set) var errorMessage: String?
    private(set) var exitRequest: String?
    var cardTopGlobalY: Double = 0
    var cardBottomGlobalY: Double = 0
    var targetFrameDescription = "unresolved"
    var targetVisible = false
    var targetID: String?
    var isForeground = true
    var launchRevision = UUID()
    var openAccountOnSetup = false
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let suppressesAnalytics: Bool
    @ObservationIgnored private let onStart: (() -> Void)?
    @ObservationIgnored private let onFirstLaunchCompleted: (() -> Void)?

    init(defaults: UserDefaults?, suppressesAnalytics: Bool = false,
         onStart: (() -> Void)? = nil, onFirstLaunchCompleted: (() -> Void)? = nil) {
        self.defaults = defaults
        self.suppressesAnalytics = suppressesAnalytics
        self.onStart = onStart
        self.onFirstLaunchCompleted = onFirstLaunchCompleted
        if let data = defaults?.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(CanvasTourSession.self, from: data), (1...2).contains(saved.flowVersion) {
            session = saved
            if saved.flowVersion == 1, saved.currentStep == .balance { session.currentStep = .momentResult }
            session.flowVersion = 2
            session.pendingOperation = nil
            if ![.completed, .skipped, .inactive].contains(saved.status) { session.status = .paused }
        }
    }
    var step: CanvasTourStep { session.currentStep }
    var sessionID: UUID { session.sessionID }
    var status: CanvasTourStatus { session.status }
    var selectedGroupID: String? { session.selectedGroupID }
    var addedEntryID: String? { session.addedEntryID }
    var operation: CanvasTourOperation? { session.pendingOperation }
    var returnContext: String { session.returnContext }
    var entrySource: String { session.entrySource }
    var completedSteps: Set<CanvasTourStep> { session.completedSteps }
    var skippedBranches: Set<String> { session.skippedBranches }
    var flowVersion: Int { session.flowVersion }
    var canResume: Bool { session.status == .paused }
    var quietMode: CanvasTourQuietMode {
        get { session.quietMode }
        set { session.quietMode = newValue; persist() }
    }
    var overlayVisible: Bool {
        isActive && isForeground && presentedSheet == nil && pendingDestination == nil
            && status != .preparing && status != .waitingForSystemUI
    }

    func start(at step: CanvasTourStep = .welcome, source: String = "developer", selectedGroupID: String? = nil) {
        onStart?()
        let quiet = quietMode
        session = CanvasTourSession()
        session.currentStep = step
        session.entrySource = source
        session.selectedGroupID = selectedGroupID
        session.quietMode = quiet
        session.status = .preparing
        isActive = true
        updateAnalyticsGate()
        presentedSheet = nil; pendingDestination = nil; posterDayID = nil; shareCompleted = false
        errorMessage = nil; targetVisible = false; targetFrameDescription = "unresolved"
        openAccountOnSetup = false; exitRequest = nil
        cardTopGlobalY = 0; cardBottomGlobalY = 0
        launchRevision = UUID()
        report("step entered: \(step.rawValue); new session")
    }
    func resume(groupIDs: Set<String>) {
        guard canResume else { return }
        // Every continuation has fresh identity; callbacks from the prior process/session cannot apply.
        session.sessionID = UUID(); session.pendingOperation = nil
        session.status = .preparing; isActive = true
        updateAnalyticsGate()
        revalidate(groupIDs: groupIDs)
        if step == .healthValue || step == .healthResult { enter(.balance, reason: "open Health panel again") }
        if step == .happening { enter(.add, reason: "palette must be opened again") }
        if step == .chooseDuration { enter(.selectFeed, reason: "choose group again") }
        launchRevision = UUID()
        report("resume requested")
    }
    func hostReady() {
        guard isActive else { return }
        session.status = .waitingForAction
        report("host ready: \(step.rawValue)")
    }
    func stop(skipped: Bool = false) {
        exitRequest = nil
        cardTopGlobalY = 0; cardBottomGlobalY = 0
        session.status = skipped ? .skipped : .inactive
        session.pendingOperation = nil
        CanvasTourAnalyticsGate.shared.setSuppressed(false)
        isActive = false; pendingDestination = nil; presentedSheet = nil
        targetVisible = false; targetID = nil; errorMessage = nil
        report(skipped ? "tour skipped" : "tour stopped")
    }
    /// Presentation only: never replace the current step or invalidate its operation.
    func requestExit(reason: String) {
        guard isActive, isForeground, exitRequest == nil,
              pendingDestination == nil, status != .preparing,
              !["health", "screenTimeAuthorization", "share"].contains(presentedSheet ?? "") else { return }
        exitRequest = reason
        report("exit confirmation requested: \(reason)")
    }
    func continueTour() {
        guard exitRequest != nil else { return }
        exitRequest = nil
        report("exit confirmation cancelled; keep current step")
    }
    func confirmExit() {
        guard exitRequest != nil else { return }
        completeFirstLaunchIfNeeded()
        stop(skipped: true)
    }
    func setForeground(_ active: Bool) {
        isForeground = active
        if !active { targetVisible = false }
        report(active ? "foreground: waiting for layout" : "background: visual coaching paused")
    }
    func isCurrent(_ token: CanvasTourOperation?) -> Bool {
        guard let token else { return !isActive }
        return isActive && token.sessionID == sessionID && token == operation
    }
    @discardableResult
    func beginOperation(_ name: String, returnContext: String = "flow") -> CanvasTourOperation? {
        guard isActive, operation == nil else { return nil }
        let token = CanvasTourOperation(sessionID: sessionID, id: UUID(), name: name)
        session.pendingOperation = token; session.returnContext = returnContext
        errorMessage = nil
        report("operation started: \(name)")
        return token
    }
    func endOperation(_ token: CanvasTourOperation?, error: String? = nil) {
        guard isCurrent(token) else { report("operation ignored: stale result"); return }
        session.pendingOperation = nil
        if let error { recover(error) } else { report("operation resolved") }
    }
    func sheetPresented(_ name: String, returnContext: String = "flow") {
        guard isActive else { return }
        presentedSheet = name; session.returnContext = returnContext
        session.status = .waitingForSystemUI
        report("sheet presented: \(name)")
    }
    func sheetDismissed(_ name: String, sessionID expectedSession: UUID? = nil) {
        guard isActive, presentedSheet == name else { return }
        if let expectedSession, expectedSession != sessionID { report("sheet dismissal ignored: stale session"); return }
        presentedSheet = nil; session.pendingOperation = nil
        session.status = .waitingForAction
        report("sheet dismissed: \(name)")
        if let destination = pendingDestination {
            pendingDestination = nil; enter(destination, reason: "confirmed result after \(name) dismissal")
        }
    }
    func recover(_ message: String) {
        guard isActive else { return }
        errorMessage = message; session.status = .recoverableError
        report("operation failed: \(message)")
    }
    func report(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        transitions.append("\(stamp) \(message)")
        if transitions.count > 120 { transitions.removeFirst(transitions.count - 120) }
        persist()
    }
    func revalidate(groupIDs: Set<String>) {
        guard isActive, let id = selectedGroupID, !groupIDs.contains(id) else { return }
        session.selectedGroupID = nil
        if [.selectionResult, .selectFeed, .chooseDuration].contains(step) {
            enter(.addApps, reason: "selected group no longer available")
        }
    }
    func send(_ event: CanvasTourEvent, token: CanvasTourOperation? = nil) {
        guard isActive else { return }
        if let token, !isCurrent(token) { report("transition ignored: stale session/operation"); return }
        if case .skipRequested = event { requestExit(reason: "skip"); return }
        if case .posterReady(let id) = event { posterDayID = id; return }
        if pendingDestination != nil {
            if event == .paletteDismissed, pendingDestination == .momentResult {
                pendingDestination = nil; enter(.momentResult, reason: "persisted happening and palette dismissed")
            } else { report("transition ignored: waiting for presentation dismissal") }
            return
        }
        let destination: CanvasTourStep?
        switch (step, event) {
        case (.welcome, .begin): destination = .add
        case (.add, .palettePresented): destination = .happening
        case (.happening, .happeningAdded(let id)) where !id.isEmpty:
            session.addedEntryID = id; pendingDestination = .momentResult
            session.status = .resolvingResult; report("happening persisted; waiting for palette dismiss"); return
        case (.happening, .paletteDismissed): destination = .add
        case (.happening, .useExistingDay):
            session.skippedBranches.insert("addHappening"); destination = .momentResult
        case (.momentResult, .momentAcknowledged): destination = .balance
        case (.balance, .dataPanelExpanded): destination = .healthValue
        case (.healthValue, .healthUpdated): destination = .healthResult
        case (.healthValue, .healthDeferred):
            session.skippedBranches.insert("health"); destination = .healthResult
        case (.healthResult, .continueHealth): destination = .feedsTab
        case (.feedsTab, .tabSelected(1)): destination = .addApps
        case (.addApps, .appSelectionCommitted(let id)) where !id.isEmpty:
            session.selectedGroupID = id
            if presentedSheet != nil {
                pendingDestination = .selectionResult; session.status = .resolvingResult
                report("group committed; waiting for picker dismiss"); return
            }
            destination = .selectionResult
        case (.addApps, .skipApps):
            session.skippedBranches.insert("apps"); destination = .meTab
        case (.selectionResult, .selectionAcknowledged): destination = .selectFeed
        case (.selectFeed, .groupOpened(let id)) where id == selectedGroupID: destination = .chooseDuration
        case (.chooseDuration, .unlockSucceeded(let id)) where id == selectedGroupID: destination = .meTab
        case (.selectFeed, .skipUnlock), (.chooseDuration, .skipUnlock):
            session.skippedBranches.insert("unlock"); destination = .meTab
        case (.chooseDuration, .addMoreColors): destination = .add
        case (.meTab, .tabSelected(2)): destination = .saveDays
        case (.saveDays, .showSetup) where posterDayID != nil: destination = .setup
        case (.setup, .setupCompleted):
            if presentedSheet != nil {
                pendingDestination = .poster; report("setup continue; waiting for dismiss"); return
            }
            destination = .poster
        case (.poster, .shareDismissed(let completed)):
            shareCompleted = completed
            if presentedSheet != nil {
                pendingDestination = .finish; report(completed ? "share completed" : "share cancelled"); return
            }
            destination = .finish
        case (.poster, .exportSkipped):
            session.skippedBranches.insert("export"); destination = .finish
        case (.finish, .finish):
            completeFirstLaunchIfNeeded()
            session.completedSteps.insert(.finish); stop(); session.status = .completed; persist(); return
        default: destination = nil
        }
        guard let destination else { report("transition ignored: unexpected event for \(step.rawValue)"); return }
        enter(destination, reason: String(describing: event))
    }
    private func enter(_ destination: CanvasTourStep, reason: String) {
        session.completedSteps.insert(step)
        session.currentStep = destination; session.status = .waitingForAction
        session.pendingOperation = nil
        exitRequest = nil
        targetVisible = false; targetFrameDescription = "unresolved"; errorMessage = nil
        report("step entered: \(destination.rawValue); \(reason)")
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
    private func completeFirstLaunchIfNeeded() {
        if entrySource == "firstLaunch" { onFirstLaunchCompleted?() }
    }
    private func updateAnalyticsGate() {
        #if DEBUG
        CanvasTourAnalyticsGate.shared.setSuppressed(suppressesAnalytics || entrySource != "firstLaunch")
        #endif
    }
}
/// Cross-actor gate for DEBUG replays; first-run product mutations keep normal analytics.
final class CanvasTourAnalyticsGate: @unchecked Sendable {
    static let shared = CanvasTourAnalyticsGate()
    private let lock = NSLock()
    private var suppressed = false
    var isSuppressed: Bool { lock.withLock { suppressed } }
    func setSuppressed(_ value: Bool) { lock.withLock { suppressed = value } }
}

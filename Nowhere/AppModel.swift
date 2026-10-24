import Combine
import Foundation
import HealthKit
import SwiftUI
import UserNotifications
import WidgetKit
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - AppModel
@MainActor
final class AppModel: ObservableObject {
    // Dependencies
    let healthKitService: any HealthKitServiceProtocol
    let familyControlsService: any FamilyControlsServiceProtocol
    let notificationService: any NotificationServiceProtocol
    let budgetEngine: any BudgetEngineProtocol
    private let authService = AuthenticationService.shared
    
    // Stores
    let healthStore: HealthStore
    let blockingStore: BlockingStore
    let userEconomyStore: UserEconomyStore
    let subscriptionStore: SubscriptionStore

    private var cancellables = Set<AnyCancellable>()
    private var localPurchaseStateTask: Task<Void, Never>?
    private var hadLocalStateBeforeInitialization = false
    // In-memory removals also protect an in-flight initial restore after a
    // successful cloud delete has already left the durable retry queue.
    var locallyRemovedAdditionIDs: Set<String> = []
    private var sleepRefetchTask: Task<Void, Never>?
    private var historyWorkTasks: [UUID: Task<Void, Never>] = [:]
    private(set) var isHistoryWorkSuspended = false
    private(set) var historyWorkGeneration = UUID()
    private var historyWorkWaiters: [CheckedContinuation<Void, Never>] = []
    /// In-flight `recalculateDailyEnergy` Task spawned from the steps/sleep
    /// Combine sink (§3.5). Cancelled on next fire and on `deinit` so a stale
    /// recompute can't write back over fresh state after a DI reset / test
    /// teardown.
    private var recalcTask: Task<Void, Never>?

    // Intentionally nonisolated: called from actor contexts (SupabaseSyncService, extensions).
    // UserDefaults is thread-safe for reads, so this is safe outside @MainActor.
    nonisolated static func storedDayEnd() -> (hour: Int, minute: Int) {
        let g = UserDefaults.nowhere()
        let h = (g.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? (UserDefaults.standard.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? 0
        let m = (g.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? (UserDefaults.standard.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? 0
        return (h, m)
    }

    // Intentionally nonisolated: same rationale as storedDayEnd() above.
    nonisolated static func dayKey(for date: Date) -> String {
        let de = storedDayEnd()
        return DayBoundary.dayKey(for: date, dayEndHour: de.hour, dayEndMinute: de.minute)
    }

    // MARK: - Forwarding to Stores
    
    // HealthStore
    var stepsToday: Double {
        get { healthStore.stepsToday }
        set { healthStore.stepsToday = newValue }
    }
    var dailySleepHours: Double {
        get { healthStore.dailySleepHours }
        set { healthStore.dailySleepHours = newValue }
    }
    var baseEnergyToday: Int {
        get { healthStore.baseEnergyToday }
        set { healthStore.baseEnergyToday = newValue }
    }
    /// Whether HealthKit has returned step data today.
    var hasStepsData: Bool { healthStore.hasStepsData }
    /// Whether HealthKit has returned sleep data today.
    var hasSleepData: Bool { healthStore.hasSleepData }

    var healthAuthorizationStatus: HKAuthorizationStatus {
        get { healthStore.authorizationStatus }
        set { healthStore.authorizationStatus = newValue }
    }
    
    // BlockingStore
    var ticketGroups: [TicketGroup] {
        get { blockingStore.ticketGroups }
        set { blockingStore.ticketGroups = newValue }
    }
    var appUnlockSettings: [String: AppUnlockSettings] {
        get { blockingStore.appUnlockSettings }
        set { blockingStore.appUnlockSettings = newValue }
    }
    var appSelection: FamilyActivitySelection {
        get { blockingStore.appSelection }
        set { blockingStore.appSelection = newValue }
    }
    var isBlocked: Bool {
        get { blockingStore.isBlocked }
        set { blockingStore.isBlocked = newValue }
    }
    
    // UserEconomyStore
    var entryCostSteps: Int {
        get { userEconomyStore.entryCostSteps }
        set { userEconomyStore.entryCostSteps = newValue }
    }
    var stepsBalance: Int {
        get { userEconomyStore.stepsBalance }
        set { userEconomyStore.stepsBalance = newValue }
    }
    var bonusSteps: Int {
        get { userEconomyStore.bonusSteps }
        set { userEconomyStore.bonusSteps = newValue }
    }
    var totalStepsBalance: Int {
        get { userEconomyStore.totalStepsBalance }
        set { userEconomyStore.totalStepsBalance = newValue }
    }
    var showPayGate: Bool {
        get { userEconomyStore.showPayGate }
        set { userEconomyStore.showPayGate = newValue }
    }
    var payGateTargetGroupId: String? {
        get { userEconomyStore.payGateTargetGroupId }
        set { userEconomyStore.payGateTargetGroupId = newValue }
    }
    var payGateSessions: [String: PayGateSession] {
        get { userEconomyStore.payGateSessions }
        set { userEconomyStore.payGateSessions = newValue }
    }
    var currentPayGateSessionId: String? {
        get { userEconomyStore.currentPayGateSessionId }
        set { userEconomyStore.currentPayGateSessionId = newValue }
    }
    /// See `UserEconomyStore.payGateError`. (§5.1)
    var payGateError: String? {
        get { userEconomyStore.payGateError }
        set { userEconomyStore.payGateError = newValue }
    }
    var appStepsSpentToday: [String: Int] {
        get { userEconomyStore.appStepsSpentToday }
        set { userEconomyStore.appStepsSpentToday = newValue }
    }
    var appStepsSpentByDay: [String: [String: Int]] {
        get { userEconomyStore.appStepsSpentByDay }
        set { userEconomyStore.appStepsSpentByDay = newValue }
    }
    var appStepsSpentLifetime: [String: Int] {
        get { userEconomyStore.appStepsSpentLifetime }
        set { userEconomyStore.appStepsSpentLifetime = newValue }
    }
    var dayPassGrants: [String: Date] {
        get { userEconomyStore.dayPassGrants }
        set { userEconomyStore.dayPassGrants = newValue }
    }
    
    func isFamilyControlsModeEnabled(for bundleId: String) -> Bool {
        unlockSettings(for: bundleId).familyControlsModeEnabled
    }

    func setFamilyControlsModeEnabled(_ enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        settings.familyControlsModeEnabled = enabled
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseTicketUpsert(bundleId: bundleId)
    }

    // Local bootstrap state: Canvas editing/persistence may begin once this is false.
    // Authentication and background refresh can still be pending.
    @Published var isBootstrapping: Bool = true
    /// Set to true after the first `bootstrap()` routine finishes. Foreground refresh
    /// handlers gate on this so they don't double-fire during cold launch (the cold
    /// launch is covered by `bootstrap()` itself).
    @Published var didCompleteBootstrap: Bool = false
    /// Deferred from bootstrap — HealthKit auth must wait until the scene is active.
    var needsHealthKitAuthorization: Bool = false
    
    /// Every happening added today, in insertion order. Each happening can be
    /// added once per custom day.
    @Published var todayAdditions: [OptionEntry] = []
    let happeningStore = HappeningStore()
    let happeningPaletteSelectionStore = HappeningPaletteSelectionStore()
    let frequentHappeningStore = FrequentHappeningStore()
    let happeningShapeNonceStore = HappeningShapeNonceStore()
    @Published var savedRoutines: [EnergyRoutine] = []
    
    /// Single source of truth: UserEconomyStore.spentSteps (persisted as SharedKeys.spentStepsToday).
    var spentStepsToday: Int {
        get { userEconomyStore.spentSteps }
        set { userEconomyStore.spentSteps = newValue }
    }

    @Published var dayEndHour: Int = storedDayEnd().hour
    @Published var dayEndMinute: Int = storedDayEnd().minute
    
    
    enum PayGateDismissReason {
        case userDismiss
        case background
        case programmatic
    }
    
    @Published var showQuickStatusPage = false
    /// Backing storage for workout suggestions (accessed via extension computed property).
    var _pendingWorkoutSuggestions: [DetectedWorkout] = []
    /// Backing storage for unified workout suggestions.
    var _pendingActivitySuggestions: [ActivitySuggestion] = []

    // Handoff token handling
    @Published var handoffToken: HandoffToken? = nil
    @Published var showHandoffProtection = false
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Safely update appSelection from external sources (e.g., FamilyControlsService callback)
    /// without triggering recursive didSet updates
    func updateAppSelectionFromService(_ selection: FamilyActivitySelection) {
        blockingStore.updateAppSelectionFromService(selection)
    }
    
    private var dayBoundaryTimer: Timer?
    /// Internal (not `private`) so `reanchorForDayEndChange()` in
    /// AppModel+BudgetTracking.swift can re-stamp it when the day-end setting
    /// changes — keeping a re-anchor from being mistaken for a day rollover.
    var lastDayKey: String
    private var lastDayBoundaryCheck: Date?
    /// Debounces rapid day-end picker changes into a single atomic commit
    /// (`commitDayEnd`). Owned by the model so it survives the settings view
    /// being dismissed mid-debounce; cancelled in `deinit`.
    var dayEndCommitTask: Task<Void, Never>?

    init(
        healthKitService: any HealthKitServiceProtocol,
        familyControlsService: any FamilyControlsServiceProtocol,
        notificationService: any NotificationServiceProtocol,
        budgetEngine: any BudgetEngineProtocol,
        subscriptionStore: SubscriptionStore
    ) {
        self.healthKitService = healthKitService
        self.familyControlsService = familyControlsService
        self.notificationService = notificationService
        self.budgetEngine = budgetEngine
        self.subscriptionStore = subscriptionStore
        self.lastDayKey = Self.dayKey(for: Date.now)

        // Initialize Stores
        self.healthStore = HealthStore(healthKitService: healthKitService)
        self.blockingStore = BlockingStore(familyControlsService: familyControlsService)
        self.userEconomyStore = UserEconomyStore(budgetEngine: budgetEngine)
        
        // Subscribe to stores
        healthStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        // Recalc colors total when steps or sleep update (so total = body + mind + heart).
        // §3.5: track the spawned Task so a rapid second fire cancels the first.
        Publishers.CombineLatest(healthStore.$stepsToday, healthStore.$dailySleepHours)
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isHistoryWorkSuspended else { return }
                self.recalcTask?.cancel()
                self.recalcTask = Task { @MainActor [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.recalculateDailyEnergy()
                }
            }
            .store(in: &cancellables)
        
        blockingStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        userEconomyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        subscriptionStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .todayCanvasStorageDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                (self?.notificationService as? NotificationManager)?.scheduleDailyCanvasReminder()
            }
            .store(in: &cancellables)

        authService.postLoginSyncModel = self
    }

    /// Retain account-data producers so a transition can drain them before
    /// replacing the working set. Their operation bodies remain unchanged.
    func scheduleHistoryWork(_ operation: @escaping @MainActor () async -> Void) {
        guard !isHistoryWorkSuspended else { return }
        let id = UUID()
        let syncEpoch = SupabaseSyncService.shared.captureSyncEpoch()
        historyWorkTasks[id] = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await SupabaseSyncService.$historySyncEpoch.withValue(syncEpoch) {
                await operation()
            }
            self?.historyWorkTasks.removeValue(forKey: id)
        }
    }

    func suspendHistoryWork() async {
        isHistoryWorkSuspended = true
        historyWorkGeneration = UUID()
        dayBoundaryTimer?.invalidate()
        dayBoundaryTimer = nil
        let tasks = Array(historyWorkTasks.values) + [recalcTask, sleepRefetchTask, dayEndCommitTask].compactMap { $0 }
        for task in tasks { task.cancel() }
        await localPurchaseStateTask?.value
        for task in tasks { await task.value }
        historyWorkTasks.removeAll()
        recalcTask = nil
        sleepRefetchTask = nil
        dayEndCommitTask = nil
    }

    func resumeHistoryWork() {
        isHistoryWorkSuspended = false
        let waiters = historyWorkWaiters
        historyWorkWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func isHistoryWorkCurrent(_ generation: UUID) -> Bool {
        !isHistoryWorkSuspended && historyWorkGeneration == generation
    }

    private func waitForHistoryWorkResumption() async {
        guard isHistoryWorkSuspended else { return }
        await withCheckedContinuation { historyWorkWaiters.append($0) }
    }

    /// Convenience: always true. The app is free for everyone.
    var isPro: Bool { subscriptionStore.isPro }

    func currentDayStart(for date: Date) -> Date {
        DayBoundary.currentDayStart(for: date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }
    
    func isSameCustomDay(_ a: Date, _ b: Date) -> Bool {
        currentDayStart(for: a) == currentDayStart(for: b)
    }

    func checkDayBoundary() {
        guard !isHistoryWorkSuspended else { return }
        let now = Date.now
        let currentKey = Self.dayKey(for: now)
        let dayChanged = currentKey != lastDayKey
        let anchor = UserDefaults.nowhere().object(forKey: SharedKeys.dailyEnergyAnchor) as? Date
        let needsReset = anchor.map { !isSameCustomDay($0, now) } ?? false
        // Coalesce duplicate checks only within the same day. A timer firing
        // immediately before the cutoff cannot suppress the foreground reset.
        if !dayChanged, !needsReset,
           let last = lastDayBoundaryCheck, now.timeIntervalSince(last) < 1.0 { return }
        lastDayBoundaryCheck = now

        if dayChanged {
            lastDayKey = currentKey
        }
        let didReset = resetDailyEnergyIfNeeded()
        budgetEngine.resetIfNeeded()
        loadSpentStepsBalance()
        if dayChanged {
            loadAppStepsSpentToday()
        }
        if (didReset || dayChanged) && !isBootstrapping {
            AppLogger.healthKit.info("👣 checkDayBoundary: day changed (didReset=\(didReset), dayChanged=\(dayChanged)), stepsToday=\(Int(self.stepsToday)) — stopping observer & clearing cache")
            healthStore.stopObservingSteps()
            healthStore.clearCachedStepCount()
            scheduleHistoryWork { [self] in await refreshStepsIfAuthorized() }
        }
        if dayChanged {
            // Custom day boundary flipped (respects `dayEndHour`/`dayEndMinute`) —
            // give users with Daily Random Theme enabled a fresh palette + style for
            // the new day. Note: `dayChanged` is computed via `AppModel.dayKey(for:)`
            // which is custom-day-aware, so this fires at the user's reset time
            // (e.g. 4am if dayEndHour=4), not at calendar midnight.
            applyDailyRandomThemeIfNeeded()
        }
    }

    func scheduleDayBoundaryTimer() {
        guard !isHistoryWorkSuspended else { return }
        dayBoundaryTimer?.invalidate()
        let next = nextDayBoundary(after: Date.now)
        let interval = max(1, next.timeIntervalSinceNow)
        dayBoundaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkDayBoundary()
                self?.scheduleDayBoundaryTimer()
            }
        }
        AppLogger.app.debug("⏰ Next day boundary scheduled for \(next)")
    }

    private func nextDayBoundary(after date: Date) -> Date {
        DayBoundary.nextBoundary(after: date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }
    
    private func loadDayPassGrants() {
        userEconomyStore.loadDayPassGrants()
    }
    
    func persistDayPassGrants() {
        userEconomyStore.persistDayPassGrants()
    }
    
    func loadAppStepsSpentToday() {
        scheduleHistoryWork { [self] in
            await userEconomyStore.loadAppStepsSpentToday()
        }
    }
    
    func persistAppStepsSpentToday() {
        userEconomyStore.persistAppStepsSpentToday()
    }

    func persistAppStepsSpentByDay() {
        userEconomyStore.persistAppStepsSpentByDay()
    }

    private func loadAppStepsSpentLifetime() {
        scheduleHistoryWork { [self] in
            await userEconomyStore.loadAppStepsSpentLifetime()
        }
    }

    func persistAppStepsSpentLifetime() {
        userEconomyStore.persistAppStepsSpentLifetime()
    }
    
    
    func defaultDayPassCost(forEntryCost entryCost: Int) -> Int {
        if entryCost <= 0 { return 0 }
        return entryCost * 100
    }
    
    func handleAppWillEnterForeground() {
        AppLogger.app.debug("📱 App will enter foreground")
        (notificationService as? NotificationManager)?.scheduleDailyCanvasReminder()
        if let service = familyControlsService as? FamilyControlsService {
            service.refreshAuthorizationStatus()
        }
        checkDayBoundary()
        scheduleDayBoundaryTimer()
        startPendingWidgetBudgetMonitoring()
        reconcileOrphanUsageBudgetMonitors()
        ensureUsageBudgetMonitoringForActiveGroups()
        rebuildFamilyControlsShield()
        scheduleHistoryWork { [self] in
            async let stepsResult: () = refreshStepsBalance()
            async let sleepResult: () = refreshSleepIfAuthorized()
            async let workoutResult: () = refreshWorkoutSuggestions()
            async let notifResult: () = refreshNotificationAuthorizationStatus()
            _ = await (stepsResult, sleepResult, workoutResult, notifResult)
            scheduleDelayedSleepRefetchIfMorning()
        }
    }
    
    /// Apple Watch can take 5-30 min to finalize sleep staging data after waking.
    /// If the app is opened in the morning, the first fetch often returns partial
    /// or zero sleep. Re-fetch after a delay to pick up late-arriving samples.
    private func scheduleDelayedSleepRefetchIfMorning() {
        guard !isHistoryWorkSuspended else { return }
        let hour = Calendar.current.component(.hour, from: Date.now)
        guard (5...11).contains(hour) else { return }
        
        sleepRefetchTask?.cancel()
        sleepRefetchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            AppLogger.healthKit.debug("🛌 Delayed sleep re-fetch (morning catchup)")
            await self?.refreshSleepIfAuthorized()
        }
    }

    func handleAppDidEnterBackground() {
        (notificationService as? NotificationManager)?.scheduleDailyCanvasReminder()
        writeWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    
    /// Shared by foreground startup and app-hosted widget actions. A cold widget
    /// action needs local balances/groups, not a network or HealthKit refresh.
    /// Reuse the same load so startup cannot overwrite an in-flight purchase.
    func prepareLocalPurchaseState() async {
        if let task = localPurchaseStateTask {
            await task.value
            return
        }
        hadLocalStateBeforeInitialization = InitialServerRestoreGate.capturePriorLocalState(
            defaults: .nowhere(),
            hasLiveLocalState: !todayAdditions.isEmpty || !ticketGroups.isEmpty
        )
        let task = Task { @MainActor in
            await self.userEconomyStore.loadAppStepsSpentToday()
            await self.userEconomyStore.loadAppStepsSpentLifetime()
            self.blockingStore.loadTicketGroups()
            self.loadAppUnlockSettings()
            self.loadDayPassGrants()
            self.loadDailyEnergyState()
            self.loadSavedRoutines()
            self.loadSpentStepsBalance()
        }
        localPurchaseStateTask = task
        await task.value
    }

    func restartAccountHistoryWork() {
        resumeHistoryWork()
        scheduleDayBoundaryTimer()
        // Publish incoming derived state before any Health query can suspend.
        writeWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
        ShieldRebuildHelper.rebuild(startPendingBudgets: false)
        ensureUsageBudgetMonitoringForActiveGroups()
        scheduleHistoryWork { [self] in
            await refreshStepsIfAuthorized()
            await refreshSleepIfAuthorized()
            writeWidgetSnapshot()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Reuse the local loaders against the incoming account while every writer
    /// remains paused. Missing keys must clear A's in-memory values for fresh B.
    func reloadAccountHistory() async {
        precondition(isHistoryWorkSuspended)
        let dayEnd = Self.storedDayEnd()
        dayEndHour = dayEnd.hour
        dayEndMinute = dayEnd.minute
        lastDayKey = Self.dayKey(for: .now)
        lastDayBoundaryCheck = nil
        todayAdditions = []
        locallyRemovedAdditionIDs.removeAll()
        savedRoutines = []
        _pendingWorkoutSuggestions = []
        _pendingActivitySuggestions = []
        handoffToken = nil
        showHandoffProtection = false
        showQuickStatusPage = false
        userEconomyStore.showPayGate = false
        userEconomyStore.payGateTargetGroupId = nil
        userEconomyStore.payGateSessions.removeAll()
        userEconomyStore.currentPayGateSessionId = nil
        userEconomyStore.payGateError = nil
        userEconomyStore.dayPassGrants = [:]
        userEconomyStore.stepsBalance = 0
        userEconomyStore.spentSteps = 0
        userEconomyStore.bonusSteps = UserDefaults.nowhere().integer(forKey: SharedKeys.bonusSteps)
        blockingStore.reloadAfterAccountSwitch()
        loadTicketGroups() // Also clears the bundle-ID → group lookup cache.
        loadAppUnlockSettings()
        healthStore.reloadAfterAccountSwitch()
        frequentHappeningStore.reloadAfterAccountSwitch()
        budgetEngine.reloadFromStorage()
        let rawTariff = UserDefaults.nowhere().string(forKey: SharedKeys.selectedTariff) ?? Tariff.medium.rawValue
        budgetEngine.updateTariff(Tariff(rawValue: rawTariff) ?? .medium)
        entryCostSteps = budgetEngine.tariff.entryCostSteps
        await userEconomyStore.loadAppStepsSpentToday()
        await userEconomyStore.loadAppStepsSpentLifetime()
        loadDayPassGrants()
        loadDailyEnergyState()
        loadSavedRoutines()
        loadSpentStepsBalance()
        hadLocalStateBeforeInitialization = false
        objectWillChange.send()
    }

    func bootstrap(
        requestPermissions: Bool,
        waitForAuthentication: @MainActor () async -> Void = {
            await AuthenticationService.shared.waitForInitialization()
        }
    ) async {
        #if DEBUG
        seedActivitySuggestionsForUITesting()
        #endif
        AppLogger.app.debug("🚀 Bootstrapping AppModel...")
        isBootstrapping = true
        
        // Diagnostic: dump raw UD values BEFORE any loading
        let diagG = UserDefaults.nowhere()
        AppLogger.energy.debug("📊 BOOTSTRAP RAW UD: spentStepsToday=\(diagG.integer(forKey: SharedKeys.spentStepsToday)), baseEnergyToday=\(diagG.integer(forKey: SharedKeys.baseEnergyToday)), stepsBalance=\(diagG.integer(forKey: SharedKeys.stepsBalance)), anchor=\(String(describing: diagG.object(forKey: SharedKeys.dailyEnergyAnchor)))")

        await prepareLocalPurchaseState()
        await waitForHistoryWorkResumption()

        // 1.7 Recalculate EXP from loaded selections immediately so baseEnergyToday
        // reflects current selections even before HealthKit data arrives. Without this,
        // baseEnergyToday stays at whatever stale value was in UserDefaults, and if
        // HealthKit refresh fails, EXP from category selections is never counted.
        recalculateDailyEnergy()
        AppLogger.energy.debug("📊 AFTER recalculateDailyEnergy(1.7): base=\(self.baseEnergyToday), spent=\(self.spentStepsToday), balance=\(self.stepsBalance), total=\(self.totalStepsBalance)")
        
        // 2. Request non-HealthKit permissions during bootstrap.
        // HealthKit authorization is deferred to the first scenePhase == .active
        // transition because HKHealthStore.requestAuthorization hangs when the
        // scene isn't fully presented yet (no key window to host the system sheet).
        if requestPermissions {
            needsHealthKitAuthorization = true
            do {
                try await blockingStore.requestAuthorization()
                try await requestNotificationPermission()
            } catch {
                AppLogger.app.debug("Bootstrap permission request failed: \(error.localizedDescription)")
            }
        }
        
        await waitForHistoryWorkResumption()
        // 3. Check day boundary BEFORE fetching so stale state is cleared first
        checkDayBoundary()
        AppLogger.energy.debug("📊 AFTER checkDayBoundary: base=\(self.baseEnergyToday), spent=\(self.spentStepsToday), balance=\(self.stepsBalance), total=\(self.totalStepsBalance)")

        // Widget unlock may run before ticket groups are in memory; foreground can beat bootstrap.
        // Drain pending widget budget + spend handoff after groups are loaded.
        startPendingWidgetBudgetMonitoring()
        reconcileOrphanUsageBudgetMonitors()
        ensureUsageBudgetMonitoringForActiveGroups()
        
        // Schedule daily notifications (canvas reminder + day reset warning)
        if let nm = notificationService as? NotificationManager {
            nm.scheduleDailyCanvasReminder()
            nm.scheduleDayResetWarning(dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
        }

        // 3.9 Apply cached HealthKit values to budget/energy before async refresh.
        if healthStore.hasStepsData {
            budgetEngine.setBudget(minutes: budgetEngine.minutes(from: stepsToday))
        }
        recalculateDailyEnergy()

        // The local Canvas is now safe to edit. Its first-launch tour must not
        // wait for account initialization, server requests or HealthKit queries.
        scheduleDayBoundaryTimer()
        applyDailyRandomThemeIfNeeded()
        isBootstrapping = false
        AppLogger.energy.debug("📊 LOCAL BOOTSTRAP DONE: base=\(self.baseEnergyToday), spent=\(self.spentStepsToday), balance=\(self.stepsBalance), total=\(self.totalStepsBalance)")

        // Keep the restore guard after authentication so it observes any local
        // edits made while the network was unavailable.
        // On a genuine fresh install / data loss, restore from Supabase.
        //
        // §C2: this must NOT key off "today's selections are empty" — those reset
        // at every day boundary, so that signal is also true every morning, which
        // made a full server restore fire daily and unconditionally overwrite ~30
        // local preference keys (reverting any setting whose push hadn't yet
        // landed). Gate instead on a persisted per-install flag.
        //
        // The flag is absent on a true fresh install AND after a UserDefaults wipe
        // (it's stored in the same suite as the data), so both correctly restore.
        // For an existing user upgrading into this build the flag is also absent,
        // but they already hold local state — seed the flag WITHOUT restoring so
        // the upgrade itself doesn't trigger one clobbering restore.
        await waitForAuthentication()
        let isAuthenticated = AuthenticationService.shared.isAuthenticated
        let g = UserDefaults.nowhere()
        let hasCompletedInitialRestore = g.bool(forKey: SharedKeys.hasCompletedInitialRestore)
        if isAuthenticated && !hasCompletedInitialRestore {
            let hasPriorLocalState = hadLocalStateBeforeInitialization
                || !ticketGroups.isEmpty
            if hasPriorLocalState {
                // Existing install predating this flag — mark restored, don't clobber.
                AppLogger.app.debug("🔄 Existing install detected — seeding initial-restore flag without restoring")
                InitialServerRestoreGate.finish(defaults: g, preservedLocalState: true, didRestore: false)
            } else {
                AppLogger.app.debug("🔄 Fresh install (authenticated) — restoring from Supabase")
                let didRestore = await SupabaseSyncService.shared.restoreFromServer(model: self)
                if didRestore {
                    AppLogger.app.debug("✅ Restored from Supabase")
                }
                InitialServerRestoreGate.finish(defaults: g, preservedLocalState: false, didRestore: didRestore)
            }
        }

        // 4. Refresh data AFTER day boundary reset so fresh values aren't wiped
        await refreshStepsIfAuthorized()
        await refreshSleepIfAuthorized()
        AppLogger.energy.debug("📊 AFTER HK refresh: base=\(self.baseEnergyToday), spent=\(self.spentStepsToday), balance=\(self.stepsBalance), total=\(self.totalStepsBalance)")
        
        // 4.5 Snapshot notification authorization so permission badge is accurate on launch
        await refreshNotificationAuthorizationStatus()

        // 4.6 Register for remote notifications if permission already granted
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        // 6. Check for workouts to suggest
        await refreshWorkoutSuggestions()
        
        AppLogger.app.debug("✅ AppModel bootstrap complete")
        didCompleteBootstrap = true

        // HealthKit authorization is deferred until the scene is fully active.
        // A short delay gives the key window time to present so the system
        // sheet isn't swallowed.
        if needsHealthKitAuthorization {
            needsHealthKitAuthorization = false
            scheduleHistoryWork { [weak self] in
                try? await Task.sleep(for: .seconds(0.5))
                guard let self else { return }
                await self.ensureHealthAuthorizationAndRefresh()
            }
        }

        // Drain any offline sync requests that failed previously
        scheduleHistoryWork { await SupabaseSyncService.shared.drainRetryQueue() }
    }
    
    deinit {
        let timer = dayBoundaryTimer
        let sleepTask = sleepRefetchTask
        let recalc = recalcTask
        let dayEndCommit = dayEndCommitTask
        MainActor.assumeIsolated {
            timer?.invalidate()
            sleepTask?.cancel()
            recalc?.cancel()
            dayEndCommit?.cancel()
        }
    }
}

/// Classify the installation before startup seeds a day anchor. An explicit
/// false completion marker keeps an unsuccessful restore pending across launches.
enum InitialServerRestoreGate {
    static func capturePriorLocalState(defaults: UserDefaults, hasLiveLocalState: Bool) -> Bool {
        let key = SharedKeys.hasCompletedInitialRestore
        let isPending = defaults.object(forKey: key) != nil && !defaults.bool(forKey: key)
        let hasPriorState = hasLiveLocalState
            || (!isPending && defaults.object(forKey: SharedKeys.dailyEnergyAnchor) != nil)
        if !hasPriorState && !defaults.bool(forKey: key) {
            defaults.set(false, forKey: key)
        }
        return hasPriorState
    }

    static func finish(defaults: UserDefaults, preservedLocalState: Bool, didRestore: Bool) {
        defaults.set(preservedLocalState || didRestore, forKey: SharedKeys.hasCompletedInitialRestore)
    }
}

// MARK: - Permissions helpers
extension AppModel {
    func requestNotificationPermission() async throws {
        do {
            try await notificationService.requestPermission()
            await refreshNotificationAuthorizationStatus()
        } catch {
            AppLogger.notifications.error(
                "Notification permission failed: \(error.localizedDescription)"
            )
            await refreshNotificationAuthorizationStatus()
            throw error
        }
    }

    func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
    }

    /// True when one or more permissions needed for the full experience are missing.
    var hasPermissionIssues: Bool {
        let familyMissing = !blockingStore.isAuthorized
        let notifications = SettingsPermissionPresentation.notifications(
            status: notificationAuthorizationStatus,
            remindersEnabled: SettingsPermissionPresentation.remindersEnabled(in: UserDefaults.nowhere())
        )
        return familyMissing || notifications.contributesToWarning
    }
}

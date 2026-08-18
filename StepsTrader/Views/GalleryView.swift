import SwiftUI

enum CanvasSpawnOriginMapper {
    static func normalizedPosition(
        for origin: CGPoint,
        viewportSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let canvasOrigin = CGPoint(
            x: (viewportSize.width - canvasSize.width) / 2,
            y: (viewportSize.height - canvasSize.height) / 2
        )
        return CGPoint(
            x: min(max((origin.x - canvasOrigin.x) / canvasSize.width, 0), 1),
            y: min(max((origin.y - canvasOrigin.y) / canvasSize.height, 0), 1)
        )
    }
}

// MARK: - CANVAS tab: generative canvas

struct GalleryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Binding var metricOverlay: MetricOverlayKind?
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var userStepsTarget: Double = 10_000
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var userSleepTarget: Double = 8.0
    @AppStorage("gallery_sleep_color", store: UserDefaults.stepsTrader()) private var sleepColorHex: String = "#000000"
    @AppStorage("gallery_steps_color", store: UserDefaults.stepsTrader()) private var stepsColorHex: String = "#FED415"
    @AppStorage(SharedKeys.gradientStyle) private var currentGradientStyle: String = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette) private var currentGradientPalette: String = GradientPalette.warmSunset.rawValue
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    /// Last day key whose remote bootstrap finished. When `== todayKey`, an empty
    /// canvas (post-fetch with no remote data) is treated as a real "nothing yet"
    /// state instead of re-firing the remote round-trip on every appear.
    @AppStorage("gallery_last_bootstrapped_day", store: UserDefaults.stepsTrader()) private var lastBootstrappedDayKey: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var dayCanvas: DayCanvas = DayCanvas(dayKey: AppModel.dayKey(for: Date.now))
    @State private var activeDayKey: String = AppModel.dayKey(for: Date.now)
    /// True once `loadCanvas()` has run at least once. Prevents `syncCanvasWithModel()`
    /// from saving the empty default canvas to disk before the real one is loaded,
    /// which would overwrite the persisted elements.
    @State private var canvasLoaded = false
    @State private var loadTask: Task<Void, Never>? = nil
    /// Generation counter bumped on every user-driven mutation (spawn/remove/reroll/drag-end).
    /// Used by `loadCanvas()` to detect a race where the user mutates the canvas while a
    /// remote fetch is in flight, so we can MERGE instead of clobbering local additions.
    @State private var localMutationCounter: Int = 0
    /// IDs deleted locally between fetch start and fetch completion. Prevents the merge
    /// logic from resurrecting elements the user explicitly removed mid-flight.
    @State private var pendingDeletedIds: Set<UUID> = []
    /// Toolbar/sheet state (M5 extraction). Backs the six picker/share/export
    /// fields hoisted to a separate Observable manager.
    @State private var toolbar = CanvasToolbarState()
    /// Edit-mode state (M5 extraction). Backs the five drag/freeze/active
    /// canvas-edit fields hoisted to a separate Observable manager.
    @State private var editState = CanvasEditState()
    /// The single source of truth for what Canvas is showing. `isWideCanvas`
    /// below is now a mirror the tab host reads, never something written
    /// independently — the two used to drift into states the design forbids.
    @State private var presentation: CanvasPresentationState = .canvas
    @Binding var isWideCanvas: Bool
    @Binding var paletteRoute: CanvasPaletteRouteState
    let isCanvasSelected: Bool
    var onPalettePresentationChange: (Bool) -> Void = { _ in }
    var onPalettePanelPresentationChange: (Bool) -> Void = { _ in }
    @State private var showHappeningPalette = false
    @State private var paletteHappenings: [Happening] = []
    @State private var paletteCatalog: [Happening] = []
    @State private var paletteSelectedIDs: [String] = []
    @State private var canvasViewportSize: CGSize = .zero
    @State private var spawnPresentation = CanvasSpawnPresentationState()
    @State private var spawnFlightTasks: [UUID: Task<Void, Never>] = [:]
    /// Directed nudge above the + button that invites the user to fill the
    /// day. It fires at most once per time-of-day window (morning / evening,
    /// see `AddHintWindow`) and only while the canvas has fewer than two
    /// elements — so a single one-tap suggestion (e.g. Resting) doesn't
    /// silence it. Each appearance lingers briefly, then fades; the next
    /// window re-arms it. Persisted per day so it survives view rebuilds.
    @State private var showAddHint = false
    @State private var addHintTask: Task<Void, Never>? = nil
    /// Which window's copy is currently on the bubble (set when it appears).
    @State private var activeHintWindow: AddHintWindow = .evening
    /// Day key the `addHintShownWindowsRaw` set belongs to (reset on rollover).
    @AppStorage("addHint_dayKey", store: UserDefaults.stepsTrader()) private var addHintDayKey: String = ""
    /// Comma-joined `AddHintWindow.rawValue`s already shown today.
    @AppStorage("addHint_shownWindows", store: UserDefaults.stepsTrader()) private var addHintShownWindowsRaw: String = ""
    @State private var isManuallyExpanded: Bool = false
    @State private var isNaturallyWide: Bool = false
    /// Tracks whether the user explicitly collapsed wide mode so we don't
    /// re-expand just because the geometry still qualifies as "naturally wide".
    @State private var userCollapsedWide: Bool = false
    @Environment(\.tabBarHeight) private var tabBarHeight

    /// Global mid-Y of the canvas `+`, reported by the button itself. The
    /// palette's dock lines up with it.
    @State private var canvasAddButtonCenterY: CGFloat?
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let usesTask7UITestFixture = ProcessInfo.processInfo.arguments.contains("ui-testing-task7")
    private let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    @State private var safeAreaTop: CGFloat = 0
    @State private var safeAreaBottom: CGFloat = 0

    private var canvasBackground: Color { theme.backgroundColor }
    private var labelColor: Color { theme.textPrimary }
    private var buttonColor: Color { AppColors.Night.textPrimary }
    private var todayKey: String { AppModel.dayKey(for: Date.now) }

    private var bottomControlsPadding: CGFloat {
        if presentation.isWideCanvas || presentation.isEditing {
            return max(safeAreaBottom, 34) + 16
        }
        // Anchor relative to device geometry:
        // safeAreaBottom covers the home indicator (34pt on Face ID, 0 on SE),
        // tabBarHeight is the measured custom tab bar (~80pt),
        // +20 is visual breathing room above the tab bar.
        // max() guards against the first layout pass where the preference
        // hasn't reported the real tab bar height yet.
        return max(safeAreaBottom, 34) + max(tabBarHeight, 50) + 20
    }

    private struct CanvasSyncState: Equatable {
        let sleepPoints: Int
        let stepsPoints: Int
        let baseEnergy: Int
        let spentSteps: Int
        let isBootstrapping: Bool
        let additionIds: [String]
        let gradientStyle: String
        let gradientPalette: String
    }

    private var canvasSyncState: CanvasSyncState {
        CanvasSyncState(
            sleepPoints: model.sleepPointsToday,
            stepsPoints: model.stepsPointsToday,
            baseEnergy: model.baseEnergyToday,
            spentSteps: model.spentStepsToday,
            isBootstrapping: model.isBootstrapping,
            additionIds: model.todayAdditions.map(\.id),
            gradientStyle: currentGradientStyle,
            gradientPalette: currentGradientPalette
        )
    }

    private var isCanvasEmpty: Bool { dayCanvas.elements.isEmpty }

    /// Show routines/repeat/hint when canvas is empty
    private var showQuickStartArea: Bool { isCanvasEmpty }

    /// How long a single nudge lingers before it fades on its own.
    private static let addHintVisibleSeconds: Double = 8

    /// The nudge keeps qualifying until the day has real substance: a lone
    /// one-tap suggestion (Resting) leaves the canvas at one element, which is
    /// still below the bar, so the nudge can return in its next window.
    private var addHintQualifies: Bool { dayCanvas.elements.count < 2 }

    private var renderedCanvasElements: [CanvasElement] {
        spawnPresentation.renderedElements(from: dayCanvas.elements)
    }

    private func refreshHappeningPalette() {
        paletteCatalog = model.paletteHappeningCatalog()
        paletteSelectedIDs = model.selectedPaletteHappeningIDs()
        paletteHappenings = model.availablePaletteHappenings()
    }

    private func openHappeningPalette() {
        metricOverlay = nil
        send(.openHappeningPalette)
        refreshHappeningPalette()
        withAnimation(.easeInOut(duration: 0.2)) {
            showHappeningPalette = true
        }
    }

    /// Every presentation change goes through here, so the mirrored binding and
    /// the edit-mode flag can never disagree with the state.
    private func send(_ event: CanvasPresentationEvent) {
        // `userCollapsedWide` is decided here rather than in the observer below,
        // because only the event knows WHY the canvas stopped being wide. The
        // observer sees just the old and new state, and a day rollover collapsing
        // the canvas looks identical there to the user collapsing it by hand —
        // which would wrongly stop the iPad naturally-wide branch from ever
        // re-expanding. Set ahead of the no-op guard so a rollover clears the flag
        // whether or not it also changes the state, exactly as the pre-refactor
        // rollover sites did.
        switch event {
        case .exitFullScreen where presentation.isWideCanvas: userCollapsedWide = true
        case .dayBoundary:                                    userCollapsedWide = false
        default:                                              break
        }
        let next = presentation.applying(event)
        guard next != presentation else { return }
        withAnimation(.easeInOut(duration: next.isWideCanvas || presentation.isWideCanvas ? 0.35 : 0.3)) {
            presentation = next
        }
    }

    private func closeHappeningPalette() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showHappeningPalette = false
        }
    }

    private func consumePaletteOpenRequestIfReady() {
        var route = paletteRoute
        guard route.consumeIfReady(
            isCanvasSelected: isCanvasSelected,
            canPresent: !presentation.isWideCanvas
        ) != nil else { return }
        paletteRoute = route
        openHappeningPalette()
    }

    @ViewBuilder
    private var happeningPaletteOverlay: some View {
        if showHappeningPalette, !presentation.isWideCanvas {
            HappeningPaletteView(
                happenings: paletteHappenings,
                figures: model.paletteFigures(),
                catalog: paletteCatalog,
                selectedIDs: paletteSelectedIDs,
                onPick: handlePalettePick,
                onCreate: handlePaletteCreation,
                onSaveSelection: handlePaletteSelectionSave,
                onPanelPresentationChange: onPalettePanelPresentationChange,
                onDismiss: closeHappeningPalette,
                onReroll: { model.rerollPaletteFigures() },
                dayKey: todayKey,
                dockCenterY: canvasAddButtonCenterY
            )
            .transition(.opacity)
        }
    }

    private func handlePalettePick(_ happening: Happening, origin: CGPoint) -> Bool {
        // The tile already showed this figure. Spawning anything else would
        // make the palette a lie, so a missing figure refuses the pick rather
        // than falling back to a random colour and shape.
        guard let figure = model.paletteFigures()[happening.id] else { return false }
        return addAndSpawnHappening(
            optionId: happening.id,
            figure: figure,
            recordUse: true,
            origin: origin
        )
    }

    private func handlePaletteCreation(_ title: String) -> Happening? {
        guard let created = model.createPaletteHappening(title: title) else {
            return nil
        }
        refreshHappeningPalette()
        return created
    }

    private func handlePaletteSelectionSave(_ ids: [String]) -> Bool {
        do {
            try model.savePaletteHappeningSelection(ids)
            refreshHappeningPalette()
            return true
        } catch {
            AppLogger.ui.error(
                "Failed to save happening palette selection: \(error.localizedDescription)"
            )
            return false
        }
    }

    /// (Re)evaluate whether the "fill your day" nudge should show. Called from
    /// `.onAppear`, on foreground, and whenever a driving condition changes.
    /// The hint shows only on a non-wide canvas with the fan closed, fewer than
    /// two elements, and an unused time window for today — after a short settle
    /// delay so it doesn't flash during canvas load. It then auto-dismisses.
    private func refreshAddHint() {
        addHintTask?.cancel()
        guard addHintQualifies, !showHappeningPalette, !presentation.isWideCanvas else {
            if showAddHint {
                withAnimation(.easeOut(duration: 0.25)) { showAddHint = false }
            }
            return
        }
        if showAddHint {
            // Already visible — the cancel above killed its fade countdown, so
            // restart it; otherwise a benign onChange (e.g. first element added,
            // still < 2) would leave the bubble on screen indefinitely.
            addHintTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.addHintVisibleSeconds))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { showAddHint = false }
            }
            return
        }
        let dayStart = model.currentDayStart(for: .now)
        let dayEnd = DayBoundary.nextBoundary(
            after: .now,
            dayEndHour: model.dayEndHour,
            dayEndMinute: model.dayEndMinute
        )
        let window = AddHintWindow.current(dayStart: dayStart, dayEnd: dayEnd)
        guard !hasShownHintWindow(window) else { return }
        addHintTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, addHintQualifies, !showHappeningPalette, !presentation.isWideCanvas else { return }
            activeHintWindow = window
            markHintWindowShown(window)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { showAddHint = true }

            // Discrete nudge: linger, then fade. The next window re-arms it.
            try? await Task.sleep(for: .seconds(Self.addHintVisibleSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showAddHint = false }
        }
    }

    /// Clears today's shown-window record when the calendar day rolls over.
    private func resetHintWindowsIfNewDay() {
        let today = todayKey
        if addHintDayKey != today {
            addHintDayKey = today
            addHintShownWindowsRaw = ""
        }
    }

    private func hasShownHintWindow(_ window: AddHintWindow) -> Bool {
        resetHintWindowsIfNewDay()
        return addHintShownWindowsRaw.split(separator: ",").contains(Substring(window.rawValue))
    }

    private func markHintWindowShown(_ window: AddHintWindow) {
        resetHintWindowsIfNewDay()
        var shown = Set(addHintShownWindowsRaw.split(separator: ",").map(String.init))
        shown.insert(window.rawValue)
        addHintShownWindowsRaw = shown.sorted().joined(separator: ",")
    }

    private var decayNorm: Double {
        guard dayCanvas.inkEarned > 0 else { return 0 }
        return min(1.0, Double(dayCanvas.inkSpent) / Double(dayCanvas.inkEarned))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Haptics (§4.1 — declarative via .sensoryFeedback)
    // ═══════════════════════════════════════════════════════════

    /// Bump the corresponding tick to fire the haptic. The `.sensoryFeedback`
    /// modifier on `body` handles Taptic engine warm-up internally — no
    /// `prepareAll()` plumbing needed anymore.
    @State private var lightHapticTick = 0
    @State private var mediumHapticTick = 0

    @ViewBuilder
    private var canvasLayers: some View {
        ZStack {
            GenerativeCanvasView(
                elements: renderedCanvasElements,
                dayKey: dayCanvas.dayKey,
                sleepPoints: model.sleepPointsToday,
                stepsPoints: model.stepsPointsToday,
                sleepColor: Color(hex: sleepColorHex),
                stepsColor: Color(hex: stepsColorHex),
                decayNorm: decayNorm,
                backgroundColor: canvasBackground,
                labelColor: labelColor,
                showLabelsOnCanvas: presentation.isEditing,
                showsBackgroundGradient: false,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData,
                fixedTime: editState.editFreezeTime
            )
            .frame(
                width: GenerativeCanvasView.canonicalPortraitSize.width,
                height: GenerativeCanvasView.canonicalPortraitSize.height
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if !presentation.isEditing {
                CanvasAnimationOverlay(
                    elements: renderedCanvasElements,
                    sleepPoints: model.sleepPointsToday,
                    stepsPoints: model.stepsPointsToday,
                    sleepColor: Color(hex: sleepColorHex),
                    stepsColor: Color(hex: stepsColorHex),
                    decayNorm: decayNorm,
                    backgroundColor: canvasBackground,
                    labelColor: labelColor,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData
                )
                .frame(
                    width: GenerativeCanvasView.canonicalPortraitSize.width,
                    height: GenerativeCanvasView.canonicalPortraitSize.height
                )
                .ignoresSafeArea()
            }

            if presentation.isEditing {
                editModeGestureOverlay
                    .frame(
                        width: GenerativeCanvasView.canonicalPortraitSize.width,
                        height: GenerativeCanvasView.canonicalPortraitSize.height
                    )
                    .ignoresSafeArea()

                editModeElementOverlays
                    .frame(
                        width: GenerativeCanvasView.canonicalPortraitSize.width,
                        height: GenerativeCanvasView.canonicalPortraitSize.height
                    )
                    .ignoresSafeArea()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Body
    // ═══════════════════════════════════════════════════════════

    var body: some View {
        // Hoist Observable managers into the local body scope so SwiftUI
        // can derive `$`-bindings for the .sheet / .alert APIs below.
        @Bindable var toolbar = toolbar
        let visualCanvas = canvasLayers
        // Controls in overlays — completely decoupled from the canvas/texture
        // ZStack so texture changes never trigger a controls re-layout.
        .overlay {
            if !presentation.isWideCanvas,
               HappeningPaletteChromeLayout.showsCanvasControls(
                   isPalettePresented: showHappeningPalette
               ) {
                canvasControls
                    .padding(.horizontal, controlsGuardRail)
            }
        }
        .overlay {
            if presentation.showsFullScreenDock {
                wideCanvasOverlay
                    .ignoresSafeArea()
            }
        }
        .overlay {
            if let kind = metricOverlay, !presentation.isWideCanvas {
                GalleryMetricOverlayView(model: model, kind: kind, onClose: { metricOverlay = nil })
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .overlay {
            TextureOverlayView(texture: CanvasTexture.fromStored(canvasTextureRaw))
                .transaction { $0.animation = nil }
        }
        .overlay {
            happeningPaletteOverlay
        }
        .energyGradientBackground(model: model, showGrain: false)
        .toolbar(.hidden, for: .navigationBar)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size, initial: true) { _, size in
                        canvasViewportSize = size
                        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
                        if isIPad {
                            let canvasW = GenerativeCanvasView.canonicalPortraitSize.width
                            let wide = size.width > canvasW * 1.15
                            if wide != isNaturallyWide { isNaturallyWide = wide }
                            if wide && !userCollapsedWide && !isManuallyExpanded {
                                // Naturally wide is a viewing state. It must
                                // never walk the user into editing.
                                send(.enterFullScreen)
                            }
                        }
                    }
                    .onChange(of: geo.safeAreaInsets, initial: true) { _, insets in
                        safeAreaTop = insets.top
                        safeAreaBottom = insets.bottom
                    }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: metricOverlay != nil)
        .animation(.easeInOut(duration: 0.35), value: showQuickStartArea)

        let observingCanvas = visualCanvas
        .onAppear {
            model.checkDayBoundary()
            refreshHappeningPalette()
            loadCanvas()
            refreshAddHint()
            consumePaletteOpenRequestIfReady()
            let dayKey = AppModel.dayKey(for: Date.now)
            Task {
                await SupabaseSyncService.shared.trackAnalyticsEvent(
                    name: "canvas_viewed",
                    properties: ["day_key": dayKey, "surface": "canvas_tab"],
                    dedupeKey: "canvas_viewed_\(dayKey)"
                )
            }
        }
        .onChange(of: canvasSyncState) {
            syncCanvasWithModel()
        }
        .onChange(of: dayCanvas.elements.count) { refreshAddHint() }
        .onChange(of: showHappeningPalette) { _, isPresented in
            refreshAddHint()
            onPalettePresentationChange(isPresented)
        }
        .onChange(of: paletteRoute) {
            consumePaletteOpenRequestIfReady()
        }
        .onChange(of: isCanvasSelected) { _, selected in
            if CanvasPaletteRouteState.shouldClosePalette(
                isCanvasSelected: selected,
                isPaletteVisible: showHappeningPalette
            ) {
                closeHappeningPalette()
            } else if selected {
                consumePaletteOpenRequestIfReady()
            }
            if !selected { send(.leftCanvasTab) }
        }
        .onChange(of: todayKey) { _, newKey in
            guard newKey != activeDayKey else { return }
            loadTask?.cancel()
            activeDayKey = newKey
            dayCanvas = DayCanvas(dayKey: newKey)
            canvasLoaded = false
            pendingDeletedIds.removeAll()
            send(.dayBoundary)
            refreshHappeningPalette()
            loadCanvas()
        }
        .onChange(of: presentation, initial: true) { old, new in
            if isWideCanvas != new.isWideCanvas { isWideCanvas = new.isWideCanvas }
            editState.isEditMode = new.isEditing

            if !new.isEditing {
                // Leaving editing commits whatever the finger was doing — on
                // EVERY exit, not just Done. Before this plan the collapse button
                // called `editState.reset()` and silently threw the in-flight
                // drag away; spec §7.3 wants the position kept (it already says
                // so for Done and for the app resigning active), and there is no
                // reason a different exit should lose the user's arrangement.
                if editState.isDraggingElement { handleEditDragEnd() }
                editState.editFreezeTime = nil
                editState.activeElementId = nil
            } else if editState.editFreezeTime == nil {
                editState.editFreezeTime = Date.now
            }

            if !new.isWideCanvas {
                isManuallyExpanded = false
            } else {
                userCollapsedWide = false
                isManuallyExpanded = true
            }

            refreshAddHint()
            consumePaletteOpenRequestIfReady()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                if editState.isDraggingElement { handleEditDragEnd() }
                return
            }
            if scenePhase == .inactive {
                if editState.isDraggingElement { handleEditDragEnd() }
                return
            }
            guard scenePhase == .active else { return }
            model.checkDayBoundary()
            let newKey = AppModel.dayKey(for: Date.now)
            if newKey != activeDayKey {
                loadTask?.cancel()
                activeDayKey = newKey
                dayCanvas = DayCanvas(dayKey: newKey)
                canvasLoaded = false
                pendingDeletedIds.removeAll()
                send(.dayBoundary)
                loadCanvas()
            }
            if showHappeningPalette {
                refreshHappeningPalette()
            }
            // Re-evaluate the nudge on foreground so a new time window (or a
            // fresh day) can re-arm it without needing another canvas mutation.
            refreshAddHint()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if editState.isDraggingElement { handleEditDragEnd() }
        }
        // Cross-tab canvas mutations: `MainTabView` posts these when the picker
        // is opened from a non-canvas tab (StepBalanceCard pills) and the user
        // confirms / removes / rerolls. We share the same business logic the
        // local radial-menu sheet uses below.
        .onReceive(NotificationCenter.default.publisher(for: .canvasElementSpawnRequested)) { note in
            guard let info = note.userInfo,
                  let optionId = info["optionId"] as? String else { return }
            addAndSpawnHappening(
                optionId: optionId,
                recordUse: info["recordUse"] as? Bool ?? true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasElementRemoveRequested)) { note in
            guard let info = note.userInfo,
                  let elementId = info["elementId"] as? UUID else { return }
            removeElement(id: elementId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .canvasElementRerollRequested)) { note in
            guard let info = note.userInfo,
                  let elementId = info["elementId"] as? UUID else { return }
            rerollElement(id: elementId)
        }

        return observingCanvas
        .sheet(isPresented: $toolbar.showShareSheet, onDismiss: { toolbar.shareImage = nil }) {
            if let image = toolbar.shareImage {
                CanvasShareSheet(items: [image])
            }
        }
        .onChange(of: toolbar.showShareSheet) { _, isPresented in
            if !isPresented { toolbar.shareImage = nil }
        }
        .animation(.easeInOut(duration: 0.35), value: presentation)
        .onPreferenceChange(CanvasAddButtonCenterKey.self) { value in
            guard let value, value != canvasAddButtonCenterY else { return }
            canvasAddButtonCenterY = value
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lightHapticTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: mediumHapticTick)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Canvas Controls (respects safe area)
    // ═══════════════════════════════════════════════════════════

    /// All interactive overlays: date, share, empty state, category pills, + button.
    /// + is centered horizontally at the bottom (above tab bar); pills in bottom bar.
    /// Gradients are confined to top/bottom strips so the canvas stays visible in the center.
    /// Minimum horizontal inset from screen edge for all canvas controls.
    private let controlsGuardRail: CGFloat = 16

    private var canvasControls: some View {
        ZStack {
            if showQuickStartArea && !presentation.isWideCanvas {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Wide-canvas wallpaper suggestion
            if presentation.isWideCanvas && !model.hasWallpaperShortcut {
                VStack {
                    Spacer()
                    wallpaperPromptBanner
                        .padding(.horizontal, 8)
                        .padding(.bottom, 40)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Proactive workout suggestions
            if !model._pendingActivitySuggestions.isEmpty && !presentation.isWideCanvas {
                VStack {
                    ActivitySuggestionBanner(
                        suggestions: model._pendingActivitySuggestions,
                        onAccept: { suggestion in
                            guard let optionId = model.acceptActivitySuggestion(suggestion) else {
                                return
                            }
                            addAndSpawnHappening(optionId: optionId)
                        },
                        onDismiss: { suggestion in
                            model.dismissActivitySuggestion(suggestion)
                        },
                        onDismissAll: {
                            model.dismissAllActivitySuggestions()
                        }
                    )
                    Spacer()
                }
                .padding(.top, safeAreaTop + topCardHeight + 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Bottom section — always visible, sits above tab bar
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if showAddHint {
                    addActivityHint
                        .padding(.bottom, 14)
                        .transition(
                            .scale(scale: 0.85, anchor: .bottom)
                            .combined(with: .opacity)
                        )
                }
                bottomControlsBar
                    .padding(.bottom, bottomControlsPadding)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Bottom Controls Bar (full screen · show data · +)
    // ═══════════════════════════════════════════════════════════

    private var bottomControlsBar: some View {
        CanvasBottomActionRow(
            isDataExpanded: presentation.showsDataPanel,
            onFullScreen: {
                send(.enterFullScreen)
                lightHapticTick &+= 1
            },
            onToggleData: {
                CoachMarkManager.postAction(for: .expandChevron)
                send(presentation.showsDataPanel ? .hideData : .showData)
                lightHapticTick &+= 1
            },
            onAdd: {
                CoachMarkManager.postAction(for: .tapPlusButton)
                openHappeningPalette()
            }
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Share Button
    // ═══════════════════════════════════════════════════════════

    private var shareButton: some View {
        Button {
            exportCanvas()
        } label: {
            Group {
                if toolbar.isExporting {
                    ProgressView()
                        .tint(buttonColor)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(buttonColor)
                }
            }
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Share canvas", comment: "GalleryView – share button VoiceOver label"))
        .opacity(isCanvasEmpty ? 0.35 : 1.0)
        .disabled(isCanvasEmpty || toolbar.isExporting)
        .contextMenu {
            if !isCanvasEmpty {
                Button {
                    toolbar.showSaveRoutine = true
                } label: {
                    Label(String(localized: "Save as Routine"), systemImage: "square.and.arrow.down")
                }
            }

            if !model.savedRoutines.isEmpty {
                Divider()
                ForEach(model.savedRoutines) { routine in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            model.applyRoutine(routine)
                        }
                        mediumHapticTick &+= 1
                    } label: {
                        Label(routine.name, systemImage: "arrow.counterclockwise")
                    }
                }
            }

        }
        .alert(String(localized: "Save Routine"), isPresented: $toolbar.showSaveRoutine) {
            TextField(String(localized: "e.g. Gym Day", comment: "Placeholder for routine name"), text: $toolbar.routineName)
            Button(String(localized: "Save")) {
                let name = toolbar.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                model.saveCurrentAsRoutine(name: name)
                toolbar.routineName = ""
            }
            Button(String(localized: "Cancel"), role: .cancel) { toolbar.routineName = "" }
        } message: {
            Text(String(localized: "Give this combination a name to reuse it later."))
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Wallpaper Prompt (wide canvas)
    // ═══════════════════════════════════════════════════════════

    private var wallpaperPromptBanner: some View {
        NavigationLink {
            SettingsShortcutPage(model: model)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(buttonColor.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "lock.screen")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(buttonColor.opacity(0.8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Set this canvas as your wallpaper", comment: "Wide canvas – wallpaper prompt"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(buttonColor)
                    Text(String(localized: "Your clock and widgets will overlay this canvas", comment: "Wide canvas – wallpaper prompt subtitle"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(buttonColor.opacity(0.75))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(buttonColor.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 14, style: .lensTinted)
        }
        .buttonStyle(.plain)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Empty State
    // ═══════════════════════════════════════════════════════════

    /// Directed nudge bubble that sits centered just above the + button while
    /// the day is still sparse (< 2 elements). The copy is time-aware
    /// (`activeHintWindow`) and the downward caret visually links it to the
    /// `RadialHoldMenu` so the user understands where to tap.
    private var addActivityHint: some View {
        Text(activeHintWindow.prompt)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(labelColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Reserve room for the tail so the text stays centered in the body.
            .padding(.bottom, BubbleWithTail.tailHeight)
            .liquidGlassControl(in: BubbleWithTail())
            .contrastingOnGlass()
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if !model.savedRoutines.isEmpty {
                routinesRow
            }

            if isCanvasEmpty {
                Text(String(localized: "Today is uncolored", comment: "Canvas empty state hint"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(labelColor.opacity(0.65))
                    .contrastingOnGlass()
            }
        }
        .multilineTextAlignment(.center)
    }

    private var routinesRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.savedRoutines) { routine in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            model.applyRoutine(routine)
                        }
                        mediumHapticTick &+= 1
                    } label: {
                        Text(routine.name)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(labelColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlassControl(in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                    Button(role: .destructive) {
                        model.deleteRoutine(routine)
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Canvas State Management
    // ═══════════════════════════════════════════════════════════

    private func loadCanvas() {
        let dayKey = AppModel.dayKey(for: Date.now)
        // Unit tests run inside the application host. Keep the host Gallery
        // inert so it cannot race persistence tests through the shared canvas
        // directory; tests exercise CanvasStorageService explicitly.
        if isUnitTestHost {
            dayCanvas = DayCanvas(dayKey: dayKey)
            canvasLoaded = true
            return
        }
        if usesTask7UITestFixture {
            dayCanvas = DayCanvas(dayKey: dayKey)
            canvasLoaded = true
            syncCanvasWithModel()
            return
        }
        let local = CanvasStorageService.shared.loadCanvas(for: dayKey)
        if let local {
            dayCanvas = local
            canvasLoaded = true
            syncCanvasWithModel()
            return
        }
        // No on-disk canvas. If we already finished bootstrap for this day,
        // treat that as a real "empty today" rather than re-fetching forever.
        if lastBootstrappedDayKey == dayKey {
            dayCanvas = DayCanvas(dayKey: dayKey)
            canvasLoaded = true
            syncCanvasWithModel()
            return
        }
        dayCanvas = DayCanvas(dayKey: dayKey)
        let snapshotCounter = localMutationCounter
        pendingDeletedIds.removeAll()
        loadTask = Task {
            let remote = await SupabaseSyncService.shared.fetchDayCanvas(for: dayKey)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                lastBootstrappedDayKey = dayKey
                if let remote {
                    if localMutationCounter != snapshotCounter {
                        let merged = mergeRemoteWithLocal(remote: remote, local: dayCanvas)
                        dayCanvas = merged
                        canvasLoaded = true
                        saveCanvasLocally()
                        syncCanvasWithModel()
                    } else {
                        dayCanvas = remote
                        CanvasStorageService.shared.saveCanvas(remote)
                        canvasLoaded = true
                        syncCanvasWithModel()
                        refreshWidgetSnapshot()
                    }
                } else {
                    canvasLoaded = true
                    if localMutationCounter != snapshotCounter {
                        saveCanvasLocally()
                    }
                    syncCanvasWithModel()
                }
                pendingDeletedIds.removeAll()
            }
        }
    }

    /// ID-keyed merge with last-write-wins per element and tombstone protection.
    /// - Local additions (id only on local) are kept.
    /// - Local deletes (`pendingDeletedIds`) suppress matching remote ids permanently.
    /// - For ids present on both sides, the side with the newer `lastEditedAt`
    ///   (falling back to `createdAt`) wins; ties go to local.
    private func mergeRemoteWithLocal(remote: DayCanvas, local: DayCanvas) -> DayCanvas {
        var byId: [UUID: CanvasElement] = [:]
        for el in remote.elements where !pendingDeletedIds.contains(el.id) {
            byId[el.id] = el
        }
        for el in local.elements {
            if let existing = byId[el.id] {
                let localTs = el.lastEditedAt ?? el.createdAt
                let remoteTs = existing.lastEditedAt ?? existing.createdAt
                if localTs >= remoteTs { byId[el.id] = el }
            } else if !pendingDeletedIds.contains(el.id) {
                byId[el.id] = el
            }
        }
        var merged = remote
        let order = local.elements.map(\.id) + remote.elements.map(\.id)
        var seen: Set<UUID> = []
        var ordered: [CanvasElement] = []
        for id in order where seen.insert(id).inserted {
            if let el = byId[id] { ordered.append(el) }
        }
        merged.elements = ordered
        merged.lastModified = Date.now
        return merged
    }

    @MainActor
    private func refreshWidgetSnapshot() {
        CanvasStorageService.shared.saveWidgetSnapshot(
            for: dayCanvas.dayKey,
            elements: dayCanvas.elements,
            sleepPoints: dayCanvas.sleepPoints,
            stepsPoints: dayCanvas.stepsPoints,
            sleepColor: Color(hex: dayCanvas.sleepColorHex),
            stepsColor: Color(hex: dayCanvas.stepsColorHex),
            decayNorm: dayCanvas.decayNorm
        )
    }

    private func syncCanvasWithModel() {
        guard canvasLoaded else { return }
        guard activeDayKey == dayCanvas.dayKey else { return }
        var didChange = false

        // 2. Update canvas metrics from model (sleep, steps, energy)
        let newSleep = model.sleepPointsToday
        let newSteps = model.stepsPointsToday
        let newEarned = model.baseEnergyToday
        let newSpent = model.spentStepsToday

        let currentOverlay = UserDefaults.stepsTrader().string(forKey: SharedKeys.canvasOverlayStyle) ?? CanvasOverlayStyle.smudge.rawValue
        let currentTexture = UserDefaults.standard.string(forKey: SharedKeys.canvasTexture) ?? CanvasTexture.grainSmall.rawValue

        if dayCanvas.sleepPoints != newSleep
           || dayCanvas.stepsPoints != newSteps
           || dayCanvas.inkEarned != newEarned
           || dayCanvas.inkSpent != newSpent
           || dayCanvas.gradientStyle != currentGradientStyle
           || dayCanvas.gradientPalette != currentGradientPalette
           || dayCanvas.overlayStyle != currentOverlay
           || dayCanvas.textureRaw != currentTexture
           || dayCanvas.hasStepsData != model.hasStepsData
           || dayCanvas.hasSleepData != model.hasSleepData {
            dayCanvas.sleepPoints = newSleep
            dayCanvas.stepsPoints = newSteps
            dayCanvas.inkEarned = newEarned
            dayCanvas.inkSpent = newSpent
            dayCanvas.sleepColorHex = sleepColorHex
            dayCanvas.stepsColorHex = stepsColorHex
            dayCanvas.gradientStyle = currentGradientStyle
            dayCanvas.gradientPalette = currentGradientPalette
            dayCanvas.overlayStyle = currentOverlay
            dayCanvas.textureRaw = currentTexture
            dayCanvas.hasStepsData = model.hasStepsData
            dayCanvas.hasSleepData = model.hasSleepData
            didChange = true
        }

        guard didChange else { return }
        dayCanvas.lastModified = Date.now
        saveCanvasLocally()
    }

    @discardableResult
    private func saveCanvasLocally() -> Bool {
        guard !isUnitTestHost else { return false }
        // Gate on canvasLoaded — NOT on `!elements.isEmpty`. The previous
        // empty-skip silently dropped legitimate "deleted last element"
        // saves, so the deletion failed to persist and the element came back
        // from disk on next launch.
        guard canvasLoaded else { return false }
        let didPersist: Bool
        if dayCanvas.elements.isEmpty {
            CanvasStorageService.shared.deleteCanvas(for: dayCanvas.dayKey)
            didPersist = true
        } else {
            didPersist = CanvasStorageService.shared.saveCanvas(dayCanvas)
        }
        guard didPersist else { return false }
        publishCanvasPersistence(dayCanvas)
        return true
    }

    private func publishCanvasPersistence(_ canvas: DayCanvas) {
        Task { await SupabaseSyncService.shared.syncDayCanvas(canvas) }
        Task { @MainActor in refreshWidgetSnapshot() }
        NotificationCenter.default.post(
            name: .historyThumbnailNeedsRefresh,
            object: canvas.dayKey
        )
    }

    @discardableResult
    private func addAndSpawnHappening(
        optionId: String,
        figure: HappeningShapeAssignment? = nil,
        recordUse: Bool = true,
        origin: CGPoint? = nil
    ) -> Bool {
        let now = Date.now
        let transactionDayKey = AppModel.dayKey(for: now)
        guard dayCanvas.dayKey == transactionDayKey else { return false }
        var element = CanvasElement.spawn(
            id: UUID(),
            optionId: optionId,
            label: model.resolveOptionTitle(for: optionId),
            existingElements: dayCanvas.elements,
            dayKey: transactionDayKey,
            composition: DayComposition.forDay(
                dayKey: transactionDayKey,
                happeningCount: dayCanvas.elements.count),
            figure: figure
        )
        element.lastEditedAt = now

        let presentationOrigin: CGPoint?
        if let origin,
           canvasViewportSize.width > 0,
           canvasViewportSize.height > 0 {
            presentationOrigin = CanvasSpawnOriginMapper.normalizedPosition(
                for: origin,
                viewportSize: canvasViewportSize,
                canvasSize: GenerativeCanvasView.canonicalPortraitSize
            )
        } else {
            presentationOrigin = nil
        }

        guard let result = CanvasHappeningSpawnTransaction.commit(
            canvasLoaded: canvasLoaded,
            canvas: dayCanvas,
            model: model,
            element: element,
            recordUse: recordUse,
            at: now,
            persist: { canvas in
                usesTask7UITestFixture
                    ? true
                    : CanvasStorageService.shared.saveCanvas(canvas)
            }
        ) else {
            return false
        }

        if let presentationOrigin {
            spawnPresentation.stage(elementID: element.id, origin: presentationOrigin)
        }
        dayCanvas = result.canvas
        localMutationCounter &+= 1
        publishCanvasPersistence(result.canvas)

        if presentationOrigin != nil {
            animateSpawnToDestination(elementID: element.id)
        }
        if showHappeningPalette {
            refreshHappeningPalette()
        }
        return true
    }

    private func animateSpawnToDestination(elementID: UUID) {
        spawnFlightTasks[elementID]?.cancel()
        spawnFlightTasks[elementID] = Task { @MainActor in
            await CanvasDisplayFrameScheduler.waitForOriginFrame()
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                spawnPresentation.complete(elementID: elementID)
            }
            spawnFlightTasks[elementID] = nil
        }
    }

    private func removeElement(id: UUID) {
        guard let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }
        var updated = dayCanvas
        let removed = updated.elements.remove(at: index)
        model.removeAddition(entryId: removed.id.uuidString)
        pendingDeletedIds.insert(removed.id)
        updated.lastModified = Date.now
        dayCanvas = updated
        localMutationCounter &+= 1
        saveCanvasLocally()
    }

    private func rerollElement(id: UUID) {
        guard let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }
        let composition = DayComposition.forDay(
            dayKey: dayCanvas.dayKey, happeningCount: dayCanvas.elements.count)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dayCanvas.elements[index].reroll(rank: index, composition: composition)
            dayCanvas.elements[index].lastEditedAt = Date.now
        }
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Wide Canvas Overlay (edit button)
    // ═══════════════════════════════════════════════════════════

    private var wideCanvasOverlay: some View {
        VStack {
            Spacer()
            CanvasFullScreenDock(
                onExit: {
                    send(.exitFullScreen)
                    lightHapticTick &+= 1
                },
                onEdit: {
                    send(.beginEditing)
                    lightHapticTick &+= 1
                },
                share: { shareButton }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, max(safeAreaBottom, 34) + 16)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Edit Mode Element Overlays (circle outlines + dice)
    // ═══════════════════════════════════════════════════════════

    private var editModeElementOverlays: some View {
        let refSize = GenerativeCanvasView.canonicalPortraitSize
        let dim = min(refSize.width, refSize.height)
        let freezeDate = editState.editFreezeTime ?? Date.now

        return ZStack {
            ForEach(dayCanvas.elements) { element in
                let center = GenerativeCanvasView.frozenElementCenter(element, size: refSize, at: freezeDate)
                let cx = center.x
                let cy = center.y
                let effectiveSize = Double(element.userSize ?? CGFloat(element.size))
                let diameter = RayShapeRenderer.editBoundsDiameter(
                    normalizedSize: effectiveSize,
                    canvasDim: dim,
                    shapeType: element.resolvedShapeType
                )
                let isActive = editState.activeElementId == element.id

                ZStack {
                    Circle()
                        .strokeBorder(
                            buttonColor.opacity(isActive ? 0.6 : 0.3),
                            lineWidth: isActive ? 1.5 : 0.75
                        )
                        .frame(width: diameter, height: diameter)

                    VStack {
                        HStack {
                            Button {
                                removeElement(id: element.id)
                                mediumHapticTick &+= 1
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.red.opacity(0.9))
                                    .frame(width: 34, height: 34)
                                    .liquidGlassControl(in: Circle())
                                    .contentShape(Circle().scale(1.3))
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(true)

                            Spacer()

                            Button {
                                rerollElement(id: element.id)
                                lightHapticTick &+= 1
                            } label: {
                                Image(systemName: "dice")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(buttonColor.opacity(0.85))
                                    .frame(width: 34, height: 34)
                                    .liquidGlassControl(in: Circle())
                                    .contentShape(Circle().scale(1.3))
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(true)
                        }
                        Spacer()
                    }
                    .frame(width: diameter, height: diameter)
                }
                .position(x: cx, y: cy)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: editState.activeElementId)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Edit Mode Gesture Overlay
    // ═══════════════════════════════════════════════════════════

    private var editModeGestureOverlay: some View {
        GeometryReader { _ in
            let refSize = GenerativeCanvasView.canonicalPortraitSize
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            handleEditDrag(value: value, canvasSize: refSize)
                        }
                        .onEnded { _ in
                            handleEditDragEnd()
                        }
                )
                .simultaneousGesture(
                    RotationGesture()
                        .onChanged { angle in
                            handleEditRotation(angle: angle)
                        }
                        .onEnded { _ in
                            handleEditRotationEnd()
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            handleEditPinch(scale: scale)
                        }
                        .onEnded { _ in
                            handleEditPinchEnd()
                        }
                )
                .onTapGesture { location in
                    if let hit = findClosestElement(to: location, canvasSize: refSize) {
                        withAnimation(.spring(response: 0.2)) {
                            editState.activeElementId = (editState.activeElementId == hit.element.id) ? nil : hit.element.id
                        }
                        lightHapticTick &+= 1
                    } else {
                        withAnimation(.spring(response: 0.2)) { editState.activeElementId = nil }
                    }
                }
        }
    }

    private func handleEditDrag(value: DragGesture.Value, canvasSize: CGSize) {
        if !editState.isDraggingElement {
            if let id = editState.activeElementId,
               let el = dayCanvas.elements.first(where: { $0.id == id }) {
                editState.isDraggingElement = true
                editState.dragStartBasePosition = el.basePosition
            } else {
                let hit = findClosestElement(to: value.startLocation, canvasSize: canvasSize)
                if let hit {
                    editState.activeElementId = hit.element.id
                    editState.isDraggingElement = true
                    editState.dragStartBasePosition = hit.element.basePosition
                }
            }
        }

        guard let id = editState.activeElementId,
              let startPos = editState.dragStartBasePosition,
              let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }

        let dx = value.translation.width / canvasSize.width
        let dy = value.translation.height / canvasSize.height
        dayCanvas.elements[index].basePosition = CGPoint(
            x: min(0.95, max(0.05, startPos.x + dx)),
            y: min(0.95, max(0.05, startPos.y + dy))
        )
    }

    private func handleEditDragEnd() {
        if let id = editState.activeElementId,
           let idx = dayCanvas.elements.firstIndex(where: { $0.id == id }) {
            dayCanvas.elements[idx].lastEditedAt = Date.now
        }
        editState.isDraggingElement = false
        editState.dragStartBasePosition = nil
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()
    }

    // MARK: - Edit Mode Rotation (rays shapes only)

    private func handleEditRotation(angle: Angle) {
        guard let id = editState.activeElementId,
              let index = dayCanvas.elements.firstIndex(where: { $0.id == id }),
              dayCanvas.elements[index].resolvedShapeType == .rays else { return }

        if editState.gestureStartRotation == nil {
            editState.gestureStartRotation = dayCanvas.elements[index].userRotation
        }
        dayCanvas.elements[index].userRotation = (editState.gestureStartRotation ?? 0) + angle.radians
    }

    private func handleEditRotationEnd() {
        guard editState.gestureStartRotation != nil else { return }
        if let id = editState.activeElementId,
           let idx = dayCanvas.elements.firstIndex(where: { $0.id == id }) {
            dayCanvas.elements[idx].lastEditedAt = Date.now
        }
        editState.gestureStartRotation = nil
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()
    }

    // MARK: - Edit Mode Pinch-to-Resize (all shapes)

    private func handleEditPinch(scale: CGFloat) {
        guard let id = editState.activeElementId,
              let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }

        if editState.gestureStartSize == nil {
            editState.gestureStartSize = dayCanvas.elements[index].userSize ?? CGFloat(dayCanvas.elements[index].size)
        }
        let startSize = editState.gestureStartSize ?? CGFloat(dayCanvas.elements[index].size)
        dayCanvas.elements[index].userSize = min(0.65, max(0.02, startSize * scale))
    }

    private func handleEditPinchEnd() {
        guard editState.gestureStartSize != nil else { return }
        if let id = editState.activeElementId,
           let idx = dayCanvas.elements.firstIndex(where: { $0.id == id }) {
            dayCanvas.elements[idx].lastEditedAt = Date.now
        }
        editState.gestureStartSize = nil
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()
    }

    /// Resets transient edit state without persisting drag positions.
    /// Call when an interruption (system alert, app suspension) makes the
    /// drag intent ambiguous — element ends up at its last `basePosition`.
    private func resetEditState() {
        if editState.isDraggingElement {
            handleEditDragEnd()
        }
        editState.reset()
    }

    // MARK: - Edit Mode Hit Testing

    private func findClosestElement(to point: CGPoint, canvasSize: CGSize)
        -> (element: CanvasElement, distance: CGFloat)? {
        let freezeDate = editState.editFreezeTime ?? Date.now
        let dim = min(canvasSize.width, canvasSize.height)
        var closest: (element: CanvasElement, distance: CGFloat)? = nil
        for element in dayCanvas.elements {
            let center = GenerativeCanvasView.frozenElementCenter(element, size: canvasSize, at: freezeDate)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let dist = sqrt(dx * dx + dy * dy)
            let effectiveSize = Double(element.userSize ?? CGFloat(element.size))
            let hitRadius = RayShapeRenderer.editHitRadius(
                normalizedSize: effectiveSize,
                canvasDim: dim,
                shapeType: element.resolvedShapeType
            )
            guard dist <= hitRadius else { continue }
            if closest == nil || dist < closest!.distance {
                closest = (element, dist)
            }
        }
        return closest
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Export Canvas
    // ═══════════════════════════════════════════════════════════

    private func exportCanvas() {
        guard !toolbar.isExporting else { return }
        toolbar.isExporting = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))

            let userName = AuthenticationService.shared.currentUser?.displayName
            let style = PosterStyle.museum

            let canvasContent = ZStack {
                EnergyGradientBackground(
                    stepsPoints: model.stepsPointsToday,
                    sleepPoints: model.sleepPointsToday,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData,
                    showGrain: true,
                    gradientStyleOverride: currentGradientStyle,
                    gradientPaletteOverride: currentGradientPalette,
                    textureOverride: dayCanvas.textureRaw
                )

                GenerativeCanvasView(
                    elements: dayCanvas.elements,
                    dayKey: dayCanvas.dayKey,
                    sleepPoints: model.sleepPointsToday,
                    stepsPoints: model.stepsPointsToday,
                    sleepColor: Color(hex: sleepColorHex),
                    stepsColor: Color(hex: stepsColorHex),
                    decayNorm: decayNorm,
                    backgroundColor: .clear,
                    labelColor: labelColor,
                    showLabelsOnCanvas: true,
                    showsOutlinedLabels: false,
                    showsBackgroundGradient: false,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData,
                    fixedTime: Date.now,
                    isOffscreenRender: true
                )
            }

            // Render the poster at the exact on-screen frame size, then upscale via
            // `renderer.scale`. This keeps every element — including the canvas's
            // absolute-point labels — at the same proportions shown on screen,
            // just at share resolution. Inflating the layout instead would shrink
            // the fixed-size labels relative to the canvas.
            let frameSize = GenerativeCanvasView.framedCanvasSize
            let targetWidth: CGFloat = 2160

            let shareable = CanvasPosterView(
                style: style,
                date: Date.now,
                userName: userName,
                steps: Int(model.stepsToday),
                sleepHours: model.dailySleepHours,
                inkEarned: dayCanvas.inkEarned,
                inkSpent: dayCanvas.inkSpent
            ) {
                canvasContent
            }
            .frame(width: frameSize.width, height: frameSize.height)

            await Task.yield()
            let renderer = ImageRenderer(content: shareable)
            renderer.scale = targetWidth / frameSize.width
            renderer.proposedSize = .init(width: frameSize.width, height: frameSize.height)
            let image = renderer.uiImage

            toolbar.isExporting = false
            if let image {
                toolbar.shareImage = image
                toolbar.showShareSheet = true
            }
        }
    }

}

// MARK: - Share Sheet (UIActivityViewController wrapper)

/// The two daily windows in which the empty-canvas nudge may appear. The split
/// is anchored to the user's configured end-of-day, not the wall clock: the
/// custom day (`dayStart` → `dayEnd`) is halved, so `morning` is its first half
/// and `evening` its second. Both prompts are retrospective — they only ask
/// about what's already happened, never about plans.
private enum AddHintWindow: String {
    case morning
    case evening

    /// - Parameters:
    ///   - dayStart: start of the current custom day (`AppModel.currentDayStart`).
    ///   - dayEnd: the next day boundary (`DayBoundary.nextBoundary`).
    static func current(for date: Date = .now, dayStart: Date, dayEnd: Date) -> AddHintWindow {
        let midpoint = dayStart.addingTimeInterval(dayEnd.timeIntervalSince(dayStart) / 2)
        return date < midpoint ? .morning : .evening
    }

    var prompt: String {
        switch self {
        case .morning:
            return String(localized: "What have you done so far?",
                          comment: "Empty-canvas nudge, morning — retrospective")
        case .evening:
            return String(localized: "What did you do today?",
                          comment: "Empty-canvas nudge, evening — retrospective")
        }
    }
}

/// Capsule body with an integrated downward tail, drawn as one continuous
/// outline so the glass material reads as a single surface (no seam between
/// the bubble and its caret). Used by the empty-canvas "add activity" hint.
private struct BubbleWithTail: InsettableShape {
    static let tailWidth: CGFloat = 16
    static let tailHeight: CGFloat = 7

    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let body = CGRect(x: r.minX, y: r.minY,
                          width: r.width,
                          height: max(0, r.height - Self.tailHeight))
        let radius = min(body.height / 2, body.width / 2)
        let halfTail = Self.tailWidth / 2

        var path = Path()
        // Top edge.
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        // Right cap.
        path.addArc(center: CGPoint(x: body.maxX - radius, y: body.minY + radius),
                    radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(90),
                    clockwise: false)
        // Bottom edge → into the tail → out of the tail.
        path.addLine(to: CGPoint(x: r.midX + halfTail, y: body.maxY))
        path.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.midX - halfTail, y: body.maxY))
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        // Left cap.
        path.addArc(center: CGPoint(x: body.minX + radius, y: body.minY + radius),
                    radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GalleryView(
            model: DIContainer.shared.makeAppModel(),
            metricOverlay: .constant(nil),
            isWideCanvas: .constant(false),
            paletteRoute: .constant(CanvasPaletteRouteState()),
            isCanvasSelected: true
        )
    }
}

/// Where the canvas `+` sits, so the palette can put its dock on the same line
/// instead of re-deriving it from tab-bar height and paddings.
struct CanvasAddButtonCenterKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

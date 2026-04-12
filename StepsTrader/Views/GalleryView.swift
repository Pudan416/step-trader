import SwiftUI

// MARK: - Metric overlay kind (covers all 5 top-bar chips)

enum MetricOverlayKind: Identifiable, Equatable {
    case steps
    case sleep
    case category(EnergyCategory)

    var id: String {
        switch self {
        case .steps: return "steps"
        case .sleep: return "sleep"
        case .category(let c): return c.rawValue
        }
    }
}

// MARK: - CANVAS tab: generative canvas

struct GalleryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Binding var metricOverlay: MetricOverlayKind?
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var userStepsTarget: Double = 10_000
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var userSleepTarget: Double = 8.0
    @AppStorage("gallery_sleep_color") private var sleepColorHex: String = "#000000"
    @AppStorage("gallery_steps_color") private var stepsColorHex: String = "#FED415"

    @Environment(\.scenePhase) private var scenePhase
    @State private var dayCanvas: DayCanvas = DayCanvas(dayKey: AppModel.dayKey(for: Date()))
    @State private var activeDayKey: String = AppModel.dayKey(for: Date())
    /// True once `loadCanvas()` has run at least once. Prevents `syncCanvasWithModel()`
    /// from saving the empty default canvas to disk before the real one is loaded,
    /// which would overwrite the persisted elements.
    @State private var canvasLoaded = false
    @State private var pickerCategory: EnergyCategory? = nil
    @State private var showShareSheet = false
    @State private var shareImage: UIImage? = nil
    @State private var isExporting = false
    @State private var showSaveRoutine = false
    @State private var routineName = ""
    @Binding var isWideCanvas: Bool
    @State private var isManuallyExpanded: Bool = false
    @State private var isNaturallyWide: Bool = false
    /// Tracks whether the user explicitly collapsed wide mode so we don't
    /// re-expand just because the geometry still qualifies as "naturally wide".
    @State private var userCollapsedWide: Bool = false
    @State private var isEditMode: Bool = false
    @State private var editFreezeTime: Date? = nil
    @State private var isDraggingElement: Bool = false
    @State private var dragStartBasePosition: CGPoint? = nil
    @State private var activeElementId: UUID? = nil
    @Environment(\.tabBarHeight) private var tabBarHeight
    @Environment(\.topCardHeight) private var topCardHeight

    @State private var safeAreaTop: CGFloat = 0
    @State private var safeAreaBottom: CGFloat = 0

    private var canvasBackground: Color { theme.backgroundColor }
    private var labelColor: Color { theme.textPrimary }
    /// Button tint: dark in daylight, light in night for contrast on the energy gradient.
    private var buttonColor: Color {
        switch theme {
        case .daylight: return labelColor
        case .night: return AppColors.Night.textPrimary
        case .system: return colorScheme == .dark ? AppColors.Night.textPrimary : labelColor
        }
    }
    private var todayKey: String { AppModel.dayKey(for: Date()) }

    private var bottomControlsPadding: CGFloat {
        if isWideCanvas || isEditMode {
            return max(safeAreaBottom, 34) + 16
        }
        // Anchor relative to device geometry:
        // safeAreaBottom covers the home indicator (34pt on Face ID, 0 on SE),
        // tabBarHeight is the measured custom tab bar (~80pt),
        // +20 is the visual breathing room above the tab bar.
        return safeAreaBottom + tabBarHeight + 60
    }

    private struct CanvasSyncState: Equatable {
        let sleepPoints: Int
        let stepsPoints: Int
        let baseEnergy: Int
        let spentSteps: Int
        let isBootstrapping: Bool
        let activitySelections: [String]
        let restSelections: [String]
        let joysSelections: [String]
    }

    private var canvasSyncState: CanvasSyncState {
        CanvasSyncState(
            sleepPoints: model.sleepPointsToday,
            stepsPoints: model.stepsPointsToday,
            baseEnergy: model.baseEnergyToday,
            spentSteps: model.spentStepsToday,
            isBootstrapping: model.isBootstrapping,
            activitySelections: model.dailyActivitySelections,
            restSelections: model.dailyRestSelections,
            joysSelections: model.dailyJoysSelections
        )
    }

    private var isCanvasEmpty: Bool { dayCanvas.elements.isEmpty }

    /// Show routines/repeat/hint when canvas is empty
    private var showQuickStartArea: Bool { isCanvasEmpty }

    private var decayNorm: Double {
        guard dayCanvas.inkEarned > 0 else { return 0 }
        return min(1.0, Double(dayCanvas.inkSpent) / Double(dayCanvas.inkEarned))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Body
    // ═══════════════════════════════════════════════════════════

    var body: some View {
        ZStack {
            // Layer 1: Fixed-size canvas — never resizes, so the backing
            // buffer stays identical when the viewport gets wider.
            GenerativeCanvasView(
                elements: dayCanvas.elements,
                sleepPoints: model.sleepPointsToday,
                stepsPoints: model.stepsPointsToday,
                sleepColor: Color(hex: sleepColorHex),
                stepsColor: Color(hex: stepsColorHex),
                decayNorm: decayNorm,
                backgroundColor: canvasBackground,
                labelColor: labelColor,
                showLabelsOnCanvas: isWideCanvas,
                showsBackgroundGradient: false,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData,
                fixedTime: editFreezeTime
            )
            .frame(
                width: GenerativeCanvasView.canonicalPortraitSize.width,
                height: GenerativeCanvasView.canonicalPortraitSize.height
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Layer 2: Smudge overlay — interactive when not in edit mode.
            if !isEditMode {
                SmudgeOverlayView(
                    elements: dayCanvas.elements,
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

            // Grain layer — above canvas elements + smudge, below controls
            Image("grain 1")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(0.4)
                .blendMode(.overlay)

            // Layer 2b: Edit mode drag overlay (wide canvas only)
            if isEditMode {
                editModeGestureOverlay
                    .frame(
                        width: GenerativeCanvasView.canonicalPortraitSize.width,
                        height: GenerativeCanvasView.canonicalPortraitSize.height
                    )
                    .ignoresSafeArea()
            }

            // Layer 2c: Edit mode element overlays (circle outlines + dice buttons)
            if isEditMode {
                editModeElementOverlays
                    .frame(
                        width: GenerativeCanvasView.canonicalPortraitSize.width,
                        height: GenerativeCanvasView.canonicalPortraitSize.height
                    )
                    .ignoresSafeArea()
            }

            // Layer 3: Interactive controls — hidden in wide canvas mode
            if !isWideCanvas {
                canvasControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Layer 4: Wide canvas edit button
            if isWideCanvas {
                wideCanvasOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            // Layer 5: Metric popover
            if let kind = metricOverlay, !isWideCanvas {
                metricPopover(kind: kind)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .energyGradientBackground(model: model, showGrain: false)
        .toolbar(.hidden, for: .navigationBar)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width, initial: true) { _, w in
                        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
                        if isIPad {
                            let canvasW = GenerativeCanvasView.canonicalPortraitSize.width
                            let wide = w > canvasW * 1.15
                            if wide != isNaturallyWide { isNaturallyWide = wide }
                            if wide && !userCollapsedWide && !isManuallyExpanded {
                                if !isWideCanvas { isWideCanvas = true }
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
        .onAppear {
            model.checkDayBoundary()
            loadCanvas()
            let dayKey = AppModel.dayKey(for: Date())
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
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            model.checkDayBoundary()
            let newKey = AppModel.dayKey(for: Date())
            if newKey != activeDayKey {
                activeDayKey = newKey
                dayCanvas = DayCanvas(dayKey: newKey)
                canvasLoaded = false
                loadCanvas()
            }
        }
        .sheet(item: $pickerCategory) { category in
            CategoryDetailView(
                model: model,
                category: category,
                outerWorldSteps: 0,
                onActivityConfirmed: { optionId, cat, hexColor, variant in
                    spawnElement(optionId: optionId, category: cat, color: hexColor, assetVariant: variant)
                },
                onActivityUndo: { optionId, cat in
                    removeElement(optionId: optionId, category: cat)
                },
                onReroll: { optionId, cat in
                    rerollElement(optionId: optionId, category: cat)
                }
            )
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareImage = nil }) {
            if let image = shareImage {
                CanvasShareSheet(items: [image])
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isWideCanvas)
        .animation(.easeInOut(duration: 0.3), value: isEditMode)
        .onChange(of: isWideCanvas) { _, wide in
            if !wide {
                isEditMode = false
                editFreezeTime = nil
                activeElementId = nil
                isDraggingElement = false
                isManuallyExpanded = false
            } else {
                userCollapsedWide = false
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Canvas Controls (respects safe area)
    // ═══════════════════════════════════════════════════════════

    /// All interactive overlays: date, share, empty state, category pills, + button.
    /// + is centered horizontally at the bottom (above tab bar); pills in bottom bar.
    /// Gradients are confined to top/bottom strips so the canvas stays visible in the center.
    private var canvasControls: some View {
        ZStack {
            if showQuickStartArea && !isWideCanvas {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Wide-canvas wallpaper suggestion
            if isWideCanvas && !model.hasWallpaperShortcut {
                VStack {
                    Spacer()
                    wallpaperPromptBanner
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Proactive activity suggestions
            if !model._pendingActivitySuggestions.isEmpty && !isWideCanvas {
                VStack {
                    ActivitySuggestionBanner(
                        suggestions: model._pendingActivitySuggestions,
                        onAccept: { suggestion in
                            model.acceptActivitySuggestion(suggestion)
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
            VStack {
                Spacer(minLength: 0)
                bottomControlsBar
                    .padding(.bottom, bottomControlsPadding)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Bottom Controls Bar (share, +, wide toggle)
    // ═══════════════════════════════════════════════════════════

    private var bottomControlsBar: some View {
        HStack(alignment: .center) {
            expandCanvasButton

            Spacer()

            RadialHoldMenu(
                labelColor: buttonColor,
                onCategorySelected: { category in
                    pickerCategory = category
                    #if DEBUG
                    if category == .mind {
                        CoachMarkManager.postAction(for: .tapMind)
                    }
                    #endif
                },
                onFanOpened: {
                    #if DEBUG
                    CoachMarkManager.postAction(for: .tapPlusButton)
                    #endif
                }
            )
            #if DEBUG
            .coachMarkAnchor(.tapPlusButton)
            #endif

            Spacer()

            shareButton
        }
        .padding(.horizontal, 66)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Expand Canvas Button
    // ═══════════════════════════════════════════════════════════

    private var expandCanvasButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35)) {
                userCollapsedWide = false
                isManuallyExpanded = true
                isWideCanvas = true
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.7)
                    .frame(width: 56, height: 56)
                Circle()
                    .strokeBorder(buttonColor.opacity(0.3), lineWidth: 1)
                    .frame(width: 56, height: 56)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 20, weight: .ultraLight))
                    .foregroundStyle(buttonColor.opacity(0.85))
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Expand canvas", comment: "GalleryView – expand button VoiceOver label"))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Share Button
    // ═══════════════════════════════════════════════════════════

    private var shareButton: some View {
        Button {
            exportCanvas()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.7)
                    .frame(width: 56, height: 56)
                Circle()
                    .strokeBorder(buttonColor.opacity(0.3), lineWidth: 1)
                    .frame(width: 56, height: 56)
                if isExporting {
                    ProgressView()
                        .tint(buttonColor.opacity(0.85))
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22, weight: .ultraLight))
                        .foregroundStyle(buttonColor.opacity(0.85))
                }
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Share canvas", comment: "GalleryView – share button VoiceOver label"))
        .opacity(isCanvasEmpty ? 0.35 : 1.0)
        .disabled(isCanvasEmpty || isExporting)
        .contextMenu {
            if !isCanvasEmpty {
                Button {
                    showSaveRoutine = true
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
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label(routine.name, systemImage: "arrow.counterclockwise")
                    }
                }
            }

        }
        .alert(String(localized: "Save Routine"), isPresented: $showSaveRoutine) {
            TextField(String(localized: "e.g. Gym Day", comment: "Placeholder for routine name"), text: $routineName)
            Button(String(localized: "Save")) {
                let name = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                model.saveCurrentAsRoutine(name: name)
                routineName = ""
            }
            Button(String(localized: "Cancel"), role: .cancel) { routineName = "" }
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
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(buttonColor)
                    Text(String(localized: "Your clock and widgets will overlay this canvas", comment: "Wide canvas – wallpaper prompt subtitle"))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(buttonColor.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(buttonColor.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(buttonColor.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Empty State
    // ═══════════════════════════════════════════════════════════

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if !model.savedRoutines.isEmpty {
                routinesRow
            }

            if isCanvasEmpty {
                Text(String(localized: "Today is uncolored", comment: "Canvas empty state hint"))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(labelColor.opacity(0.3))
            }
        }
        .multilineTextAlignment(.center)
    }

    private var routinesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.savedRoutines) { routine in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            model.applyRoutine(routine)
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text(routine.name)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(labelColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
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
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Canvas State Management
    // ═══════════════════════════════════════════════════════════

    private func loadCanvas() {
        let dayKey = AppModel.dayKey(for: Date())
        let local = CanvasStorageService.shared.loadCanvas(for: dayKey)
        if let local {
            dayCanvas = local
            canvasLoaded = true
            syncCanvasWithModel()
        } else {
            // No local data — try restoring from Supabase, fall back to empty canvas.
            // Don't mark canvasLoaded until the remote check completes to prevent
            // syncCanvasWithModel() from saving an empty canvas over the real one.
            dayCanvas = DayCanvas(dayKey: dayKey)
            Task {
                if let remote = await SupabaseSyncService.shared.fetchDayCanvas(for: dayKey) {
                    await MainActor.run {
                        dayCanvas = remote
                        CanvasStorageService.shared.saveCanvas(remote)
                        canvasLoaded = true
                        syncCanvasWithModel()
                    }
                } else {
                    await MainActor.run {
                        canvasLoaded = true
                        syncCanvasWithModel()
                    }
                }
            }
        }
    }

    private func syncCanvasWithModel() {
        // Don't sync (and potentially save) the empty default canvas before
        // loadCanvas() has had a chance to populate it from disk/server.
        guard canvasLoaded else { return }
        var didChange = false

        // 1. Reconcile canvas elements ↔ daily selections.
        //    Remove any element whose optionId is no longer in the model's selections
        //    (e.g. option deleted, preference changed, Supabase restore mismatch).
        //    SKIP during bootstrap: selections haven't loaded from UserDefaults yet,
        //    so activeIds would be empty and wipe the entire canvas. Once bootstrap
        //    finishes (isBootstrapping → false), objectWillChange fires and we
        //    reconcile with the real selections.
        if !model.isBootstrapping {
            let activeIds: Set<String> = Set(
                model.dailyActivitySelections
                + model.dailyRestSelections
                + model.dailyJoysSelections
            )
            // Defensive guard: if selections are transiently empty during launch/restore,
            // don't wipe a non-empty persisted canvas.
            if activeIds.isEmpty && !dayCanvas.elements.isEmpty {
                return
            }
            let before = dayCanvas.elements.count
            dayCanvas.elements.removeAll { !activeIds.contains($0.optionId) }
            if dayCanvas.elements.count != before {
                didChange = true
            }
        }

        // 1b. Spawn canvas elements for selections that don't have one yet
        //     (covers Routines and Supabase restore).
        if !model.isBootstrapping {
            let existingIds = Set(dayCanvas.elements.map(\.optionId))
            let allSelections: [(String, EnergyCategory)] =
                model.dailyActivitySelections.map { ($0, .body) }
                + model.dailyRestSelections.map { ($0, .mind) }
                + model.dailyJoysSelections.map { ($0, .heart) }

            for (optionId, cat) in allSelections where !existingIds.contains(optionId) {
                let color = CanvasColorPalette.paletteHex.randomElement() ?? "#FFD369"
                let label = model.resolveOptionTitle(for: optionId)
                let element = CanvasElement.spawn(
                    optionId: optionId,
                    category: cat,
                    color: color,
                    label: label,
                    existingElements: dayCanvas.elements,
                    forcedVariant: cat == .body ? Int.random(in: 0..<CanvasImageCatalog.body.count) : (cat == .mind ? Int.random(in: 0..<CanvasImageCatalog.mind.count) : nil)
                )
                dayCanvas.elements.append(element)
                didChange = true
            }
        }

        // 2. Update canvas metrics from model (sleep, steps, energy)
        let newSleep = model.sleepPointsToday
        let newSteps = model.stepsPointsToday
        let newEarned = model.baseEnergyToday
        let newSpent = model.spentStepsToday

        if dayCanvas.sleepPoints != newSleep
           || dayCanvas.stepsPoints != newSteps
           || dayCanvas.inkEarned != newEarned
           || dayCanvas.inkSpent != newSpent {
            dayCanvas.sleepPoints = newSleep
            dayCanvas.stepsPoints = newSteps
            dayCanvas.inkEarned = newEarned
            dayCanvas.inkSpent = newSpent
            dayCanvas.sleepColorHex = sleepColorHex
            dayCanvas.stepsColorHex = stepsColorHex
            didChange = true
        }

        guard didChange else { return }
        dayCanvas.lastModified = Date()
        saveCanvasLocally()
    }

    /// Save locally + sync to Supabase (debounced via SupabaseSyncService)
    private func saveCanvasLocally() {
        CanvasStorageService.shared.saveCanvas(dayCanvas)
        let canvasCopy = dayCanvas
        Task { await SupabaseSyncService.shared.syncDayCanvas(canvasCopy) }
        Task { @MainActor in
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
    }

    private func spawnElement(optionId: String, category: EnergyCategory, color: String, assetVariant: Int? = nil) {
        let effectiveVariant = category == .mind ? (assetVariant ?? Int.random(in: 0..<CanvasImageCatalog.mind.count)) : assetVariant

        if let index = dayCanvas.elements.firstIndex(where: { $0.optionId == optionId && $0.category == category }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if category != .mind {
                    dayCanvas.elements[index].hexColor = color
                }
                if let variant = effectiveVariant {
                    dayCanvas.elements[index].assetVariant = variant
                }
            }
        } else {
            let label = model.resolveOptionTitle(for: optionId)
            let element = CanvasElement.spawn(
                optionId: optionId,
                category: category,
                color: color,
                label: label,
                existingElements: dayCanvas.elements,
                forcedVariant: effectiveVariant
            )
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                dayCanvas.elements.append(element)
            }
        }
        dayCanvas.lastModified = Date()
        saveCanvasLocally()
    }

    private func removeElement(optionId: String, category: EnergyCategory) {
        guard let index = dayCanvas.elements.lastIndex(where: { $0.optionId == optionId && $0.category == category }) else { return }
        var updated = dayCanvas
        updated.elements.remove(at: index)
        updated.lastModified = Date()
        dayCanvas = updated
        saveCanvasLocally()
    }

    private func rerollElement(optionId: String, category: EnergyCategory) {
        guard let index = dayCanvas.elements.firstIndex(where: { $0.optionId == optionId && $0.category == category }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dayCanvas.elements[index].reroll()
            if category == .body {
                dayCanvas.elements[index].hexColor = CanvasColorPalette.paletteHex.randomElement() ?? dayCanvas.elements[index].hexColor
            }
        }
        dayCanvas.lastModified = Date()
        saveCanvasLocally()
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Wide Canvas Overlay (edit button)
    // ═══════════════════════════════════════════════════════════

    private var wideCanvasOverlay: some View {
        VStack {
            Spacer()
            HStack {
                // Collapse button (bottom-left)
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isEditMode = false
                        editFreezeTime = nil
                        activeElementId = nil
                        isDraggingElement = false
                        isManuallyExpanded = false
                        userCollapsedWide = true
                        isWideCanvas = false
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.7)
                            .frame(width: 56, height: 56)
                        Circle()
                            .strokeBorder(buttonColor.opacity(0.3), lineWidth: 1)
                            .frame(width: 56, height: 56)
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 20, weight: .ultraLight))
                            .foregroundStyle(buttonColor.opacity(0.85))
                    }
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Collapse canvas", comment: "GalleryView – collapse button VoiceOver label"))

                Spacer()

                // Edit button (bottom-right)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isEditMode.toggle()
                        if isEditMode {
                            editFreezeTime = Date()
                        } else {
                            editFreezeTime = nil
                            activeElementId = nil
                            isDraggingElement = false
                            saveCanvasLocally()
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.7)
                            .frame(width: 56, height: 56)
                        Circle()
                            .strokeBorder(buttonColor.opacity(isEditMode ? 0.5 : 0.3), lineWidth: 1)
                            .frame(width: 56, height: 56)
                        Image(systemName: isEditMode ? "checkmark" : "hand.draw")
                            .font(.system(size: 22, weight: .ultraLight))
                            .foregroundStyle(buttonColor.opacity(0.85))
                    }
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: isEditMode ? "Done editing" : "Edit canvas", comment: "GalleryView – edit button VoiceOver label"))
            }
            .padding(.horizontal, 50)
            .padding(.bottom, safeAreaBottom + 50)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Edit Mode Element Overlays (circle outlines + dice)
    // ═══════════════════════════════════════════════════════════

    private var editModeElementOverlays: some View {
        let refSize = GenerativeCanvasView.canonicalPortraitSize
        let dim = min(refSize.width, refSize.height)
        let freezeDate = editFreezeTime ?? Date()

        return ZStack {
            ForEach(dayCanvas.elements) { element in
                let center = GenerativeCanvasView.frozenElementCenter(element, size: refSize, at: freezeDate)
                let cx = center.x
                let cy = center.y
                let effectiveSize = element.userSize ?? element.size
                let diameter = effectiveSize * dim
                let isActive = activeElementId == element.id

                ZStack {
                    Circle()
                        .strokeBorder(
                            buttonColor.opacity(isActive ? 0.6 : 0.3),
                            lineWidth: isActive ? 1.5 : 0.75
                        )
                        .frame(width: diameter, height: diameter)

                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                rerollElement(optionId: element.optionId, category: element.category)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "dice")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(buttonColor.opacity(0.85))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .opacity(0.9)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(buttonColor.opacity(0.3), lineWidth: 0.5)
                                    )
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
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: activeElementId)
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
                .onTapGesture { location in
                    let hit = findClosestElement(to: location, canvasSize: refSize)
                    if let hit, hit.distance < 80 {
                        withAnimation(.spring(response: 0.2)) {
                            activeElementId = (activeElementId == hit.element.id) ? nil : hit.element.id
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } else {
                        withAnimation(.spring(response: 0.2)) { activeElementId = nil }
                    }
                }
        }
    }

    private func handleEditDrag(value: DragGesture.Value, canvasSize: CGSize) {
        if !isDraggingElement {
            if let id = activeElementId,
               let el = dayCanvas.elements.first(where: { $0.id == id }) {
                isDraggingElement = true
                dragStartBasePosition = el.basePosition
            } else {
                let hit = findClosestElement(to: value.startLocation, canvasSize: canvasSize)
                if let hit, hit.distance < 80 {
                    activeElementId = hit.element.id
                    isDraggingElement = true
                    dragStartBasePosition = hit.element.basePosition
                }
            }
        }

        guard let id = activeElementId,
              let startPos = dragStartBasePosition,
              let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }

        let dx = value.translation.width / canvasSize.width
        let dy = value.translation.height / canvasSize.height
        dayCanvas.elements[index].basePosition = CGPoint(
            x: min(0.95, max(0.05, startPos.x + dx)),
            y: min(0.95, max(0.05, startPos.y + dy))
        )
    }

    private func handleEditDragEnd() {
        isDraggingElement = false
        dragStartBasePosition = nil
        dayCanvas.lastModified = Date()
        saveCanvasLocally()
    }

    // MARK: - Edit Mode Hit Testing

    private func findClosestElement(to point: CGPoint, canvasSize: CGSize)
        -> (element: CanvasElement, distance: CGFloat)? {
        let freezeDate = editFreezeTime ?? Date()
        var closest: (element: CanvasElement, distance: CGFloat)? = nil
        for element in dayCanvas.elements {
            let center = GenerativeCanvasView.frozenElementCenter(element, size: canvasSize, at: freezeDate)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let dist = sqrt(dx * dx + dy * dy)
            if closest == nil || dist < (closest?.distance ?? .greatestFiniteMagnitude) {
                closest = (element, dist)
            }
        }
        return closest
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Export Canvas
    // ═══════════════════════════════════════════════════════════

    private func exportCanvas() {
        guard !isExporting else { return }
        isExporting = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))

            let canvasSize = GenerativeCanvasView.canonicalPortraitSize
            let composite = ZStack {
                EnergyGradientBackground(
                    stepsPoints: model.stepsPointsToday,
                    sleepPoints: model.sleepPointsToday,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData,
                    showGrain: false
                )

                GenerativeCanvasView(
                    elements: dayCanvas.elements,
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
                    fixedTime: Date()
                )
            }
            .frame(width: canvasSize.width, height: canvasSize.height)

            let renderer = ImageRenderer(content: composite)
            renderer.scale = 2.0
            renderer.proposedSize = .init(canvasSize)
            let image = renderer.uiImage

            isExporting = false
            if let image {
                shareImage = image
                showShareSheet = true
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Metric Popover Overlay
    // ═══════════════════════════════════════════════════════════

    private func metricPopover(kind: MetricOverlayKind) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { metricOverlay = nil }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(overlayTitle(for: kind))
                        .font(.headline)
                    Spacer()
                    Button { metricOverlay = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                overlayContent(for: kind)
            }
            .padding(16)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.backgroundSecondary.opacity(0.98))
                    .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
            )
            .padding(.horizontal, 24)
        }
    }

    private func overlayTitle(for kind: MetricOverlayKind) -> String {
        switch kind {
        case .steps: return String(localized: "Steps")
        case .sleep: return String(localized: "Sleep")
        case .category(let c):
            switch c {
            case .body: return String(localized: "Body", comment: "Energy category")
            case .mind: return String(localized: "Mind", comment: "Energy category")
            case .heart: return String(localized: "Heart", comment: "Energy category")
            }
        }
    }

    @ViewBuilder
    private func overlayContent(for kind: MetricOverlayKind) -> some View {
        switch kind {
        case .steps:
            stepsOverlayBody
        case .sleep:
            sleepOverlayBody
        case .category(let c):
            categoryOverlayBody(for: c)
        }
    }

    private func categoryAccentColor(_ category: EnergyCategory) -> Color {
        switch category {
        case .body:  return .orange
        case .mind:  return .purple
        case .heart: return .pink
        }
    }

    private func categoryOverlayBody(for category: EnergyCategory) -> some View {
        let maxPts = EnergyDefaults.maxSelectionsPerCategory * EnergyDefaults.selectionPoints
        let total: Int = {
            switch category {
            case .body: return model.activityPointsToday
            case .mind: return model.creativityPointsToday
            case .heart: return model.joysCategoryPointsToday
            }
        }()
        let titles = selectionTitles(for: category)
        let progress = maxPts > 0 ? Double(total) / Double(maxPts) : 0
        let accent = categoryAccentColor(category)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(total)")
                    .font(.title2.bold())
                Text("/\(maxPts)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(localized: "colors", comment: "Category overlay – unit"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accent)
                        .frame(width: max(4, w * progress), height: 8)
                }
            }
            .frame(height: 8)

            if titles.isEmpty {
                Text(String(localized: "No activities selected yet", comment: "Category overlay – empty hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(titles, id: \.self) { title in
                        Text(title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(accent.opacity(0.12)))
                            .foregroundColor(accent)
                    }
                }
            }
        }
    }

    private var stepsOverlayBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCompactNumber(Int(model.healthStore.stepsToday)))
                        .font(.title2.bold())
                    Text(String(localized: "steps today"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.stepsPointsToday)/\(EnergyDefaults.stepsMaxPoints)")
                        .font(.title3.bold())
                    Text(String(localized: "colors"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text(String(localized: "Target: \(formatCompactNumber(Int(userStepsTarget))) steps"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var sleepOverlayBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1fh", model.healthStore.dailySleepHours))
                        .font(.title2.bold())
                    Text(String(localized: "hours slept"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.sleepPointsToday)/\(EnergyDefaults.sleepMaxPoints)")
                        .font(.title3.bold())
                    Text(String(localized: "colors"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text(String(localized: "Target: \(String(format: "%.1f", userSleepTarget))h"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func breakdownText(for category: EnergyCategory) -> String {
        let maxPts = EnergyDefaults.maxSelectionsPerCategory * EnergyDefaults.selectionPoints
        switch category {
        case .body:
            let extras = selectionTitles(for: .body)
            let total = model.activityPointsToday
            if extras.isEmpty {
                return String(localized: "Body tracks physical activities you choose. Pick up to 4 cards for \(maxPts) colors (\(total) colors today).")
            }
            return String(localized: "Body tracks physical activities. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) colors for my body.")
        case .mind:
            let extras = selectionTitles(for: .mind)
            let total = model.creativityPointsToday
            if extras.isEmpty {
                return String(localized: "Mind tracks creativity and rest. Pick up to 4 cards for \(maxPts) colors (\(total) colors today).")
            }
            return String(localized: "Mind tracks creativity and rest. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) colors for my mind.")
        case .heart:
            let extras = selectionTitles(for: .heart)
            let total = model.joysCategoryPointsToday
            if extras.isEmpty {
                return String(localized: "Heart tracks joys and things that make you feel alive. Pick up to 4 cards for \(maxPts) colors (\(total) colors today).")
            }
            return String(localized: "Heart tracks joys and what makes you feel alive. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) colors for my heart.")
        }
    }

    private func selectionTitles(for category: EnergyCategory) -> [String] {
        let ids: [String]
        switch category {
        case .body: ids = model.dailyActivitySelections
        case .mind: ids = model.dailyRestSelections
        case .heart: ids = model.dailyJoysSelections
        }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return ids.map { id in
            EnergyDefaults.options.first(where: { $0.id == id })?.title(for: lang)
                ?? model.customOptionTitle(for: id, lang: lang)
                ?? id
        }
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

struct CanvasShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Day detail sheet (used by MeView)

struct CanvasDayDetailSheet: View {
    @ObservedObject var model: AppModel
    let dayKey: String
    let snapshot: PastDaySnapshot?
    let onDismiss: () -> Void
    @Environment(\.appTheme) private var theme

    private var dayLabel: String {
        guard let d = date(from: dayKey) else { return dayKey }
        return CachedFormatters.longDate.string(from: d)
    }

    private func date(from key: String) -> Date? {
        CachedFormatters.dayKey.date(from: key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let s = snapshot {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            statCard(icon: "figure.walk", value: "\(s.steps)", label: String(localized: "Steps"), color: .green)
                            statCard(icon: "bed.double.fill", value: String(format: "%.1f", s.sleepHours), label: String(localized: "Sleep hours"), color: .indigo)
                            statCard(icon: "plus.circle.fill", value: "\(s.inkEarned)", label: String(localized: "Gained"), color: .blue)
                            statCard(icon: "minus.circle.fill", value: "\(s.inkSpent)", label: String(localized: "Spent"), color: .orange)
                        }
                        canvasSection(s)
                    } else {
                        Text(String(localized: "No data for this day."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .background(theme.backgroundColor)
            .navigationTitle(dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func canvasSection(_ s: PastDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            canvasRow(title: String(localized: "Body", comment: "Energy category"), ids: s.bodyIds, color: theme.bodyColor)
            canvasRow(title: String(localized: "Mind", comment: "Energy category"), ids: s.mindIds, color: theme.mindColor)
            canvasRow(title: String(localized: "Heart", comment: "Energy category"), ids: s.heartIds, color: theme.heartColor)
        }
    }

    private func canvasRow(title: String, ids: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            if ids.isEmpty {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(ids, id: \.self) { id in
                        Text(model.resolveOptionTitle(for: id))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.15)))
                            .foregroundColor(color)
                    }
                }
            }
        }
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GalleryView(model: DIContainer.shared.makeAppModel(), metricOverlay: .constant(nil), isWideCanvas: .constant(false))
    }
}

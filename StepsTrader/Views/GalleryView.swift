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
    @Binding var isLabelMode: Bool

    @AppStorage("userStepsTarget") private var userStepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var userSleepTarget: Double = 8.0
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
    // Move mode state
    @State private var isMoveMode: Bool = false
    @State private var activeElementId: UUID? = nil
    @State private var dragStartBasePosition: CGPoint? = nil
    @State private var rotationGestureActive: Bool = false
    @State private var rotationAtGestureStart: Double = 0

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

    private var canvasSyncTrigger: [String] {
        [
            "\(model.sleepPointsToday)",
            "\(model.stepsPointsToday)",
            "\(model.baseEnergyToday)",
            "\(model.spentStepsToday)",
            "\(model.isBootstrapping)",
            model.dailyActivitySelections.joined(separator: ","),
            model.dailyRestSelections.joined(separator: ","),
            model.dailyJoysSelections.joined(separator: ","),
        ]
    }

    private var isCanvasEmpty: Bool { dayCanvas.elements.isEmpty }

    private var decayNorm: Double {
        guard dayCanvas.inkEarned > 0 else { return 0 }
        return min(1.0, Double(dayCanvas.inkSpent) / Double(dayCanvas.inkEarned))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Body
    // ═══════════════════════════════════════════════════════════

    var body: some View {
        ZStack {
            // Layer 0: Live animated gradient background
            EnergyGradientBackground(
                stepsPoints: model.stepsPointsToday,
                sleepPoints: model.sleepPointsToday,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Layer 1: Live animated generative canvas elements
            GenerativeCanvasView(
                elements: dayCanvas.elements,
                sleepPoints: model.sleepPointsToday,
                stepsPoints: model.stepsPointsToday,
                sleepColor: Color(hex: sleepColorHex),
                stepsColor: Color(hex: stepsColorHex),
                decayNorm: decayNorm,
                backgroundColor: canvasBackground,
                labelColor: labelColor,
                showLabelsOnCanvas: isLabelMode,
                showsBackgroundGradient: false,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Layer 2: Transparent Metal overlay — snapshots canvas on touch,
            // applies smudge distortion, then fades back to transparent.
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
            .ignoresSafeArea()
            .allowsHitTesting(!isMoveMode)

            // Layer 2b: Move/rotate gesture overlay (move mode only)
            if isMoveMode {
                moveGestureOverlay
                    .ignoresSafeArea()
            }

            // Layer 3: Interactive controls (respect safe area — stay above tab bar)
            canvasControls

            // Layer 4: Metric popover
            if let kind = metricOverlay {
                metricPopover(kind: kind)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: metricOverlay != nil)
        .animation(.easeInOut(duration: 0.35), value: isCanvasEmpty)
        .onAppear {
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
        .onChange(of: canvasSyncTrigger) {
            syncCanvasWithModel()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
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
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                CanvasShareSheet(items: [image])
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLabelMode)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Canvas Controls (respects safe area)
    // ═══════════════════════════════════════════════════════════

    /// All interactive overlays: date, share, empty state, category pills, + button.
    /// + is centered horizontally at the bottom (above tab bar); pills in bottom bar.
    /// Gradients are confined to top/bottom strips so the canvas stays visible in the center.
    private var canvasControls: some View {
        ZStack {
            // Center: empty state when needed (transparent, canvas shows through)
            if isCanvasEmpty && !isLabelMode {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Top-right: move button (label mode only)
            if isLabelMode {
                VStack {
                    HStack {
                        Spacer()
                        moveButton
                            .padding(.trailing, 24)
                            .padding(.top, 12)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // Bottom section
            VStack {
                Spacer(minLength: 0)
                HStack(alignment: .center) {
                    Spacer()
                    if !isLabelMode {
                        RadialHoldMenu(
                            labelColor: buttonColor,
                            onCategorySelected: { category in pickerCategory = category }
                        )
                        .transition(.opacity)
                    }
                    Spacer()
                }
                .overlay(alignment: .leading) {
                    labelToggleButton
                        .padding(.leading, 24)
                }
                .overlay(alignment: .trailing) {
                    if !isLabelMode {
                        shareButton
                            .padding(.trailing, 24)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, isLabelMode ? 32 : 96)
            }
        }
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
                    .opacity(0.5)
                    .frame(width: 56, height: 56)
                Circle()
                    .strokeBorder(buttonColor.opacity(0.3), lineWidth: 1)
                    .frame(width: 56, height: 56)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .ultraLight))
                    .foregroundStyle(buttonColor.opacity(0.85))
            }
            .frame(width: 56, height: 56)
            .contentShape(Circle().size(width: 72, height: 72))
        }
        .buttonStyle(.plain)
        .opacity(isCanvasEmpty ? 0.35 : 1.0)
        .disabled(isCanvasEmpty)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Label Toggle Button
    // ═══════════════════════════════════════════════════════════

    private var labelToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isLabelMode.toggle()
                if isLabelMode { metricOverlay = nil }
                if !isLabelMode { isMoveMode = false; activeElementId = nil }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
                    .frame(width: 56, height: 56)
                Circle()
                    .strokeBorder(buttonColor.opacity(isLabelMode ? 0.4 : 0.3), lineWidth: 1)
                    .frame(width: 56, height: 56)
                Image(systemName: isLabelMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 22, weight: .ultraLight))
                    .foregroundStyle(buttonColor.opacity(isLabelMode ? 0.9 : 0.85))
            }
            .frame(width: 56, height: 56)
            .contentShape(Circle().size(width: 72, height: 72))
        }
        .buttonStyle(.plain)
        .opacity(isCanvasEmpty ? 0.35 : 1.0)
        .disabled(isCanvasEmpty)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Empty State
    // ═══════════════════════════════════════════════════════════

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .ultraLight))
                .foregroundStyle(labelColor.opacity(0.25))

            Text("Hold + to begin")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(labelColor.opacity(0.3))
        }
        .multilineTextAlignment(.center)
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
            // No local data — try restoring from Supabase, fall back to empty canvas
            dayCanvas = DayCanvas(dayKey: dayKey)
            canvasLoaded = true
            syncCanvasWithModel()
            Task {
                if let remote = await SupabaseSyncService.shared.fetchDayCanvas(for: dayKey) {
                    await MainActor.run {
                        dayCanvas = remote
                        CanvasStorageService.shared.saveCanvas(remote)
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
            let before = dayCanvas.elements.count
            dayCanvas.elements.removeAll { !activeIds.contains($0.optionId) }
            if dayCanvas.elements.count != before {
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

    /// Save locally + sync to Supabase (debounced)
    private func saveCanvasLocally() {
        CanvasStorageService.shared.saveCanvas(dayCanvas)
        Task { await SupabaseSyncService.shared.syncDayCanvas(dayCanvas) }
    }

    private func spawnElement(optionId: String, category: EnergyCategory, color: String, assetVariant: Int? = nil) {
        if let index = dayCanvas.elements.firstIndex(where: { $0.optionId == optionId && $0.category == category }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dayCanvas.elements[index].hexColor = color
                if let variant = assetVariant {
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
                forcedVariant: assetVariant
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

    // ═══════════════════════════════════════════════════════════
    // MARK: - Move Mode
    // ═══════════════════════════════════════════════════════════

    private var moveButton: some View {
        let activeTint = AppColors.brandAccent
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isMoveMode.toggle()
                if !isMoveMode { activeElementId = nil }
            }
        } label: {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 18, weight: isMoveMode ? .regular : .ultraLight))
                .foregroundStyle(isMoveMode ? activeTint : buttonColor.opacity(0.7))
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(isMoveMode ? activeTint.opacity(0.6) : buttonColor.opacity(0.2), lineWidth: 1)
                )
                .background(isMoveMode ? Circle().fill(activeTint.opacity(0.15)) : nil)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isCanvasEmpty ? 0.35 : 1.0)
        .disabled(isCanvasEmpty)
    }

    private var moveGestureOverlay: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            handleMoveDrag(value: value, canvasSize: geo.size)
                        }
                        .onEnded { _ in
                            handleMoveDragEnd()
                        }
                )
                .simultaneousGesture(
                    RotationGesture()
                        .onChanged { angle in
                            handleRotation(angle: angle)
                        }
                        .onEnded { _ in
                            handleRotationEnd()
                        }
                )
        }
    }

    // MARK: - Drag to Move

    private func handleMoveDrag(value: DragGesture.Value, canvasSize: CGSize) {
        if activeElementId == nil {
            let t = Date().timeIntervalSinceReferenceDate
            if let hit = findClosestElement(to: value.startLocation, canvasSize: canvasSize, t: t),
               hit.distance < 80 {
                activeElementId = hit.element.id
                dragStartBasePosition = hit.element.basePosition
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

    private func handleMoveDragEnd() {
        activeElementId = nil
        dragStartBasePosition = nil
        dayCanvas.lastModified = Date()
        saveCanvasLocally()
    }

    // MARK: - Two-Finger Rotate

    private func handleRotation(angle: Angle) {
        guard let id = activeElementId,
              let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }

        if !rotationGestureActive {
            rotationGestureActive = true
            rotationAtGestureStart = dayCanvas.elements[index].userRotation
        }

        dayCanvas.elements[index].userRotation = rotationAtGestureStart + angle.radians
    }

    private func handleRotationEnd() {
        rotationGestureActive = false
        dayCanvas.lastModified = Date()
        saveCanvasLocally()
    }

    // MARK: - Hit Testing (mirrors GenerativeCanvasView positions)

    private func findClosestElement(to point: CGPoint, canvasSize: CGSize, t: TimeInterval)
        -> (element: CanvasElement, distance: CGFloat)? {
        var closest: (element: CanvasElement, distance: CGFloat)? = nil
        for element in dayCanvas.elements {
            let center = hitTestCenter(for: element, canvasSize: canvasSize, t: t)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let dist = sqrt(dx * dx + dy * dy)
            if closest == nil || dist < closest!.distance {
                closest = (element, dist)
            }
        }
        return closest
    }

    private func hitTestCenter(for e: CanvasElement, canvasSize: CGSize, t: TimeInterval) -> CGPoint {
        switch e.category {
        case .body:
            return CGPoint(
                x: e.basePosition.x * canvasSize.width,
                y: e.basePosition.y * canvasSize.height
            )
        case .mind:
            return mindHitPosition(e, canvasSize: canvasSize, t: t)
        case .heart:
            return heartHitPosition(e, canvasSize: canvasSize)
        }
    }

    private func mindHitPosition(_ e: CanvasElement, canvasSize: CGSize, t: TimeInterval) -> CGPoint {
        let p = e.phaseOffset
        let speed = 0.03 + e.driftSpeed * 0.06

        let nx = Double(e.basePosition.x)
            + sin(t * speed * 1.00 + p) * 0.34
            + sin(t * speed * 2.37 + p * 2.3) * 0.12
            + sin(t * speed * 4.13 + p * 4.1) * 0.04
            + sin(t * speed * 6.71 + p * 6.7) * 0.015

        let ny = Double(e.basePosition.y)
            + cos(t * speed * 0.83 + p * 1.7) * 0.32
            + cos(t * speed * 1.97 + p * 3.1) * 0.11
            + cos(t * speed * 3.61 + p * 5.3) * 0.04
            + cos(t * speed * 5.89 + p * 7.9) * 0.015

        let margin = 0.06
        return CGPoint(
            x: min(1.0 - margin, max(margin, nx)) * canvasSize.width,
            y: min(1.0 - margin, max(margin, ny)) * canvasSize.height
        )
    }

    private func heartHitPosition(_ e: CanvasElement, canvasSize: CGSize) -> CGPoint {
        let base = heartEdgeAnchor(e, canvasSize: canvasSize)
        let dim = Double(min(canvasSize.width, canvasSize.height))
        let radius = Double(e.size) * dim * 2.2

        // Must match GenerativeCanvasView.rayDrawCenter clamping exactly
        let center = CGPoint(
            x: min(max(Double(base.x), radius), Double(canvasSize.width) - radius),
            y: min(max(Double(base.y), radius), Double(canvasSize.height) - radius)
        )

        // Must match GenerativeCanvasView.elementCenter for .heart
        let dx = Double(canvasSize.width) * 0.5 - center.x
        let dy = Double(canvasSize.height) * 0.5 - center.y
        let baseAngle = atan2(dy, dx)
        let oriented = baseAngle + .pi / 2 + e.userRotation
        let outwardDist = radius * 0.55
        let tipX = center.x - outwardDist * sin(oriented)
        let tipY = center.y + outwardDist * cos(oriented)
        return CGPoint(
            x: min(max(tipX, 24), Double(canvasSize.width) - 24),
            y: min(max(tipY, 24), Double(canvasSize.height) - 24)
        )
    }

    private func heartEdgeAnchor(_ e: CanvasElement, canvasSize: CGSize) -> CGPoint {
        let nx = Double(e.basePosition.x)
        let ny = Double(e.basePosition.y)
        let edgeInset = 0.08
        let minN = edgeInset
        let maxN = 1.0 - edgeInset

        let dL = nx, dR = 1.0 - nx, dT = ny, dB = 1.0 - ny
        let minDist = min(dL, dR, dT, dB)
        var ax = nx, ay = ny
        if minDist == dL      { ax = minN; ay = min(max(ny, minN), maxN) }
        else if minDist == dR { ax = maxN; ay = min(max(ny, minN), maxN) }
        else if minDist == dT { ay = minN; ax = min(max(nx, minN), maxN) }
        else                  { ay = maxN; ax = min(max(nx, minN), maxN) }

        return CGPoint(x: ax * canvasSize.width, y: ay * canvasSize.height)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Export Canvas
    // ═══════════════════════════════════════════════════════════

    private func exportCanvas() {
        let view = GenerativeCanvasView(
            elements: dayCanvas.elements,
            sleepPoints: model.sleepPointsToday,
            stepsPoints: model.stepsPointsToday,
            sleepColor: Color(hex: sleepColorHex),
            stepsColor: Color(hex: stepsColorHex),
            decayNorm: decayNorm,
            backgroundColor: canvasBackground,
            labelColor: labelColor,
            showLabelsOnCanvas: true,
            showsOutlinedLabels: false,
            hasStepsData: model.hasStepsData,
            hasSleepData: model.hasSleepData
        )
        .frame(width: 390, height: 500)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
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
        case .steps: return "Steps"
        case .sleep: return "Sleep"
        case .category(let c):
            switch c {
            case .body: return "Body"
            case .mind: return "Mind"
            case .heart: return "Heart"
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
            Text(breakdownText(for: c))
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private var stepsOverlayBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatCompactNumber(Int(model.healthStore.stepsToday)))
                        .font(.title2.bold())
                    Text("steps today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.stepsPointsToday)/\(EnergyDefaults.stepsMaxPoints)")
                        .font(.title3.bold())
                    Text("rays")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("Target: \(formatCompactNumber(Int(userStepsTarget))) steps")
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
                    Text("hours slept")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.sleepPointsToday)/\(EnergyDefaults.sleepMaxPoints)")
                        .font(.title3.bold())
                    Text("rays")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("Target: \(String(format: "%.1f", userSleepTarget))h")
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
                return "Body tracks physical activities you choose. Pick up to 4 cards for \(maxPts) rays (\(total) rays today)."
            }
            return "Body tracks physical activities. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) rays for my body."
        case .mind:
            let extras = selectionTitles(for: .mind)
            let total = model.creativityPointsToday
            if extras.isEmpty {
                return "Mind tracks creativity and rest. Pick up to 4 cards for \(maxPts) rays (\(total) rays today)."
            }
            return "Mind tracks creativity and rest. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) rays for my mind."
        case .heart:
            let extras = selectionTitles(for: .heart)
            let total = model.joysCategoryPointsToday
            if extras.isEmpty {
                return "Heart tracks joys and things that make you feel alive. Pick up to 4 cards for \(maxPts) rays (\(total) rays today)."
            }
            return "Heart tracks joys and what makes you feel alive. Today I chose \(extras.joined(separator: ", ")). That's \(total)/\(maxPts) rays for my heart."
        }
    }

    private func selectionTitles(for category: EnergyCategory) -> [String] {
        let ids: [String]
        switch category {
        case .body: ids = model.dailyActivitySelections
        case .mind: ids = model.dailyRestSelections
        case .heart: ids = model.dailyJoysSelections
        }
        return ids.map { id in
            EnergyDefaults.options.first(where: { $0.id == id })?.title(for: "en")
                ?? model.customOptionTitle(for: id, lang: "en")
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
    let appLanguage: String = "en"
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
                            statCard(icon: "figure.walk", value: "\(s.steps)", label: "Steps", color: .green)
                            statCard(icon: "bed.double.fill", value: String(format: "%.1f", s.sleepHours), label: "Sleep hours", color: .indigo)
                            statCard(icon: "plus.circle.fill", value: "\(s.inkEarned)", label: "Gained", color: .blue)
                            statCard(icon: "minus.circle.fill", value: "\(s.inkSpent)", label: "Spent", color: .orange)
                        }
                        canvasSection(s)
                    } else {
                        Text("No data for this day.")
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
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func canvasSection(_ s: PastDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            canvasRow(title: "Body", ids: s.bodyIds, color: theme.bodyColor)
            canvasRow(title: "Mind", ids: s.mindIds, color: theme.mindColor)
            canvasRow(title: "Heart", ids: s.heartIds, color: theme.heartColor)
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
        GalleryView(model: DIContainer.shared.makeAppModel(), metricOverlay: .constant(nil), isLabelMode: .constant(false))
    }
}

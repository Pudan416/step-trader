import SwiftUI
import UIKit

enum HappeningPanelTextFieldAppearance {
    static let minimumHeight: CGFloat = 44
    static let fillOpacity: CGFloat = 0.12
    static let strokeOpacity: CGFloat = 0.22
}

private struct HappeningPanelTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minHeight: HappeningPanelTextFieldAppearance.minimumHeight)
            .background(
                Color.primary.opacity(HappeningPanelTextFieldAppearance.fillOpacity),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(HappeningPanelTextFieldAppearance.strokeOpacity),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func happeningPanelTextFieldStyle() -> some View {
        modifier(HappeningPanelTextFieldModifier())
    }
}

enum HappeningPaletteChromeLayout {
    private static let compactInset: CGFloat = 20
    private static let chromeSpacing: CGFloat = 12

    static func panelTopInset(topCardHeight: CGFloat, hidesSurroundingChrome: Bool) -> CGFloat {
        max(compactInset, topCardHeight + chromeSpacing)
    }

    static func panelBottomInset(tabBarHeight: CGFloat, hidesSurroundingChrome: Bool) -> CGFloat {
        max(compactInset, tabBarHeight + chromeSpacing)
    }

    static func hidesSurroundingChrome(isPalettePresented: Bool) -> Bool {
        isPalettePresented
    }

    /// The list and close controls remain in their original bottom-corner
    /// positions while the tab bar itself disappears.
    static func showsCanvasControls(isPalettePresented: Bool) -> Bool { true }
}

enum HappeningPalettePanel: Equatable {
    case chooser
    // Legacy presentation state; resolves to the selection-only chooser.
    case creator
}

enum HappeningPaletteCreationFeedback: Equatable {
    case invalidTitle
    case noReplaceableSlot
    case failed

    var message: String {
        switch self {
        case .invalidTitle:
            String(localized: "Enter a happening before adding it.")
        case .noReplaceableSlot:
            String(localized: "Remove a happening from Canvas before adding another.")
        case .failed:
            String(localized: "Couldn’t add happening. Try again.")
        }
    }
}

enum HappeningPaletteCreationOutcome: Equatable {
    case created
    case invalidTitle
    case noReplaceableSlot
    case failed

    var closesCreator: Bool { self == .created }

    var feedback: HappeningPaletteCreationFeedback? {
        switch self {
        case .created: nil
        case .invalidTitle: .invalidTitle
        case .noReplaceableSlot: .noReplaceableSlot
        case .failed: .failed
        }
    }
}

struct HappeningPaletteView: View {
    let happenings: [Happening]
    let assignments: [String: HappeningEditorialAssignment]
    let labelInks: [String: HappeningPaletteLabelInk]
    let catalog: [Happening]
    let selectedIDs: [String]
    let artwork: AnyView
    let compactLayout: HappeningFieldLayout.Layout?
    let usesCatalogField: Bool
    let artworkForLayout: ((HappeningFieldLayout.Layout, Bool, CGRect) -> AnyView)?
    @State private var modeTransition: HappeningFieldModeTransition?
    @State private var eventTransition: HappeningEventFieldTransition?
    @State private var eventLayout: HappeningFieldLayout.Layout?
    @State private var visibleFieldRect: CGRect = .zero
    @State private var isFieldScrolling = false
    @State private var scrollSettleTask: Task<Void, Never>?
    @Binding var activePanel: HappeningPalettePanel?
    let layout: HappeningFieldLayout.Layout
    let mode: HappeningPaletteMode
    let interaction: HappeningPaletteInteractionState
    let addedIDs: Set<String>
    let fixedIDs: Set<String>
    let instruction: HappeningPaletteInstruction?
    let onActivate: (Happening) -> Void
    let onSaveSelection: ([String]) -> Bool
    let onPanelPresentationChange: (Bool) -> Void
    let onReroll: () -> Void
    let dateHubCenter: CGPoint?
    let treeFocusID: String?
    let dateHubInk: HappeningPaletteLabelInk
    let addedEventCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        happenings: [Happening],
        assignments: [String: HappeningEditorialAssignment] = [:],
        labelInks: [String: HappeningPaletteLabelInk] = [:],
        catalog: [Happening]? = nil,
        selectedIDs: [String]? = nil,
        activePanel: Binding<HappeningPalettePanel?> = .constant(nil),
        artwork: AnyView = AnyView(Color.clear),
        layout: HappeningFieldLayout.Layout,
        mode: HappeningPaletteMode = .all,
        compactLayout: HappeningFieldLayout.Layout? = nil,
        usesCatalogField: Bool = false,
        artworkForLayout: ((HappeningFieldLayout.Layout, Bool, CGRect) -> AnyView)? = nil,
        interaction: HappeningPaletteInteractionState,
        addedIDs: Set<String>,
        fixedIDs: Set<String> = [],
        instruction: HappeningPaletteInstruction?,
        onActivate: @escaping (Happening) -> Void,
        // Ignored compatibility callbacks. Live panels only select catalog entries.
        onCreate: @escaping (String) -> HappeningPaletteCreationOutcome = { _ in .failed },
        onCreateReplacement: @escaping (String, String, [String]) -> HappeningPaletteCreationOutcome = { _, _, _ in .failed },
        onSaveSelection: @escaping ([String]) -> Bool = { _ in true },
        onPanelPresentationChange: @escaping (Bool) -> Void = { _ in },
        onReroll: @escaping () -> Void = {},
        dateHubCenter: CGPoint? = nil,
        treeFocusID: String? = nil,
        dateHubInk: HappeningPaletteLabelInk = .dark,
        addedEventCount: Int = 0
    ) {
        self.happenings = happenings
        self.assignments = assignments
        self.labelInks = labelInks
        self.catalog = catalog ?? happenings
        self.selectedIDs = selectedIDs ?? happenings.map(\.id)
        self.artwork = artwork
        self.compactLayout = compactLayout
        self.usesCatalogField = usesCatalogField
        self.artworkForLayout = artworkForLayout
        _activePanel = activePanel
        self.layout = layout
        self.mode = mode
        self.interaction = interaction
        self.addedIDs = addedIDs
        self.fixedIDs = fixedIDs
        self.instruction = instruction
        self.onActivate = onActivate
        self.onSaveSelection = onSaveSelection
        self.onPanelPresentationChange = onPanelPresentationChange
        self.onReroll = onReroll
        self.dateHubCenter = dateHubCenter
        self.treeFocusID = treeFocusID
        self.dateHubInk = dateHubInk
        self.addedEventCount = addedEventCount
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollViewReader { scroll in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        animatedField(viewport: proxy.size)
                    }
                    .coordinateSpace(name: "happeningViewport")
                    .defaultScrollAnchor(mode == .frequent && (compactLayout?.contentSize.height ?? 0) > proxy.size.height ? .top : .center)
                    .scrollDisabled(!usesCatalogField && compactLayout != nil && mode == .frequent && (compactLayout?.contentSize.height ?? 0) <= proxy.size.height)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .canvasTourAnchor("canvas.happenings")
                    .accessibilityIdentifier("happening_field_scroll")
                    .accessibilityHidden(activePanel != nil)
                    .allowsHitTesting(activePanel == nil && modeTransition == nil && eventTransition == nil)
                    .onChange(of: mode) { oldMode, newMode in
                        guard !usesCatalogField else { return }
                        guard compactLayout != nil else { return }
                        let now = Date()
                        let from = modeTransition?.value(at: now) ?? (oldMode == .all ? 1 : 0)
                        modeTransition = reduceMotion ? nil : .init(from: from, to: newMode == .all ? 1 : 0, startedAt: now)
                        if reduceMotion {
                            scroll.scrollTo(newMode.rawValue, anchor: .center)
                        } else {
                            withAnimation(.smooth(duration: HappeningFieldModeTransition.duration)) {
                                scroll.scrollTo(newMode.rawValue, anchor: .center)
                            }
                        }
                    }
                    .onAppear {
                        visibleFieldRect = .zero
                        modeTransition = nil
                        eventTransition = nil
                        eventLayout = usesCatalogField ? layout : nil
                    }
                    .onChange(of: layout) { oldLayout, newLayout in
                        guard usesCatalogField else { return }
                        let now = Date()
                        let origin = eventTransition?.layout(at: now) ?? eventLayout ?? oldLayout
                        eventLayout = newLayout
                        eventTransition = reduceMotion ? nil : .init(from: origin, to: newLayout, startedAt: now)
                    }
                    .onChange(of: reduceMotion) { _, reduced in
                        if reduced { eventTransition = nil; modeTransition = nil }
                    }
                    .task(id: eventTransition?.startedAt) {
                        guard usesCatalogField, eventTransition != nil else { return }
                        do { try await Task.sleep(for: .seconds(HappeningEventFieldTransition.duration + 0.05)) }
                        catch { return }
                        eventTransition = nil
                    }
                    .task(id: mode) {
                        guard modeTransition != nil else { return }
                        do { try await Task.sleep(for: .seconds(HappeningFieldModeTransition.duration + 0.05)) }
                        catch { return }
                        modeTransition = nil
                    }
                }

                // Actions live on the selected object. Keep only failures here;
                // the full state announcements remain available to VoiceOver.
                if let instruction, instruction.kind == .error {
                    HappeningPaletteInstructionView(instruction: instruction)
                        .frame(width: min(320, max(1, proxy.size.width - 48)))
                        .position(x: layout.dockAnchor.x, y: layout.dockAnchor.y - 68)
                        .accessibilityHidden(activePanel != nil)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sheet(isPresented: Binding(
            get: { activePanel != nil },
            set: { if !$0 { activePanel = nil } }
        )) {
            if let activePanel {
                panel(for: activePanel)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
        }
        .task {
            guard ProcessInfo.processInfo.environment["TASK7_SHAKE_PALETTE"] == "1" else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        .onShake {
            guard !CanvasTour.shared.isActive else { return }
            guard activePanel == nil else { return }
            if reduceMotion {
                onReroll()
            } else {
                withAnimation(.easeInOut(duration: 0.32)) { onReroll() }
            }
        }
        .onChange(of: activePanel) { _, panel in
            onPanelPresentationChange(panel != nil)
        }
        .onChange(of: instruction) { _, next in
            guard let next else { return }
            UIAccessibility.post(notification: .announcement, argument: next.announcement)
        }
        .onDisappear {
            scrollSettleTask?.cancel()
            isFieldScrolling = false
            onPanelPresentationChange(false)
        }
    }

    private func animatedField(viewport: CGSize) -> some View {
        let worldWidth = max(viewport.width, layout.contentSize.width, eventTransition?.from.contentSize.width ?? 0)
        let worldHeight = max(viewport.height, layout.contentSize.height,
            compactLayout?.contentSize.height ?? 0, eventTransition?.from.contentSize.height ?? 0)
        return TimelineView(.animation(minimumInterval: 1.0 / 60,
            paused: modeTransition == nil && eventTransition == nil)) { context in
            sampledField(viewport: viewport, at: context.date)
        }
        // Advertise the complete world to the native scroll surface.
        .frame(width: worldWidth, height: worldHeight)
    }

    private func sampledField(viewport: CGSize, at date: Date) -> some View {
        let progress = modeTransition?.value(at: date) ?? (mode == .all ? 1 : 0)
        let expanded = sampledLayout(viewport: viewport, progress: progress, at: date)
        let visibleRect = resolvedVisibleRect(layout: expanded, viewport: viewport)
        let edgeStrength: CGFloat = reduceMotion || artworkForLayout == nil || dateHubCenter != nil ? 0 : progress
        let displayed = HappeningFieldEdgeScale.apply(to: expanded, visibleRect: visibleRect, strength: edgeStrength)
        return fieldContent(layout: displayed, visibleRect: visibleRect, viewport: viewport,
            hubCenter: expanded.dateHubCenter ?? self.dateHubCenter, at: date)
            .frame(width: max(viewport.width, displayed.contentSize.width),
                   height: max(viewport.height, displayed.contentSize.height))
            // Cull in the same local coordinates used by Metal, labels and hits.
            // The outer Timeline can retain larger bounds during a transition.
            .onGeometryChange(for: CGRect.self) { content in
                let origin = content.frame(in: .named("happeningViewport")).origin
                return CGRect(x: -origin.x, y: -origin.y,
                              width: viewport.width, height: viewport.height)
            } action: { rect in
                updateVisibleFieldRect(rect)
            }
            .background { fieldScrollFocus(layout: expanded) }
            .transaction { $0.animation = nil }
    }

    private func sampledLayout(viewport: CGSize, progress: CGFloat, at date: Date) -> HappeningFieldLayout.Layout {
        if let compactLayout {
            return HappeningFieldExpansion.layout(compact: compactLayout, expanded: layout,
                viewport: viewport, progress: progress)
        }
        if usesCatalogField { return eventTransition?.layout(at: date) ?? eventLayout ?? layout }
        return layout
    }

    private func resolvedVisibleRect(layout: HappeningFieldLayout.Layout, viewport: CGSize) -> CGRect {
        if !visibleFieldRect.isEmpty { return visibleFieldRect }
        return CGRect(x: max(0, (layout.contentSize.width - viewport.width) / 2),
                      y: max(0, (layout.contentSize.height - viewport.height) / 2),
                      width: viewport.width, height: viewport.height)
    }

    private func fieldArtwork(layout: HappeningFieldLayout.Layout, visibleRect: CGRect) -> AnyView {
        let isMoving = modeTransition != nil || eventTransition != nil || isFieldScrolling
        return artworkForLayout?(layout, isMoving, visibleRect) ?? artwork
    }

    private func fieldContent(layout: HappeningFieldLayout.Layout, visibleRect: CGRect,
                              viewport: CGSize, hubCenter: CGPoint?, at date: Date) -> some View {
        ZStack(alignment: .topLeading) {
            fieldArtwork(layout: layout, visibleRect: visibleRect)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            HappeningShapeField(happenings: happenings, assignments: assignments, layout: layout,
                interaction: interaction, addedIDs: addedIDs, onActivate: onActivate,
                labelInks: labelInks,
                fitsCatalogLabels: usesCatalogField)
            if let hub = hubCenter {
                HappeningPaletteCountHub(count: addedEventCount, ink: dateHubInk.color)
                    .position(hub)
                    .opacity(Double(eventTransition?.hubOpacity(at: date) ?? 1))
                    .allowsHitTesting(false)
            }
            compactScrollTargets(layout: layout, viewport: viewport)
        }
    }

    @ViewBuilder
    private func compactScrollTargets(layout: HappeningFieldLayout.Layout, viewport: CGSize) -> some View {
        if let compactLayout {
            let compactHeight = max(viewport.height, compactLayout.contentSize.height)
            Color.clear.frame(width: viewport.width, height: viewport.height)
                .id(HappeningPaletteMode.frequent.rawValue)
                .position(x: layout.contentSize.width / 2,
                    y: (layout.contentSize.height - compactHeight + viewport.height) / 2)
                .allowsHitTesting(false).accessibilityHidden(true)
            Color.clear.frame(width: viewport.width, height: viewport.height)
                .id(HappeningPaletteMode.all.rawValue)
                .position(x: layout.contentSize.width / 2, y: layout.contentSize.height / 2)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func fieldScrollFocus(layout expanded: HappeningFieldLayout.Layout) -> some View {
        if usesCatalogField, mode == .all, eventTransition == nil {
            HappeningTreeScrollFocus(focusID: "event_field_all",
                center: expanded.dateHubCenter ?? self.dateHubCenter
                    ?? CGPoint(x: expanded.contentSize.width / 2, y: expanded.contentSize.height / 2),
                contentSize: expanded.contentSize, animated: !reduceMotion)
                .allowsHitTesting(false).accessibilityHidden(true)
        } else if let hub = expanded.dateHubCenter, eventTransition == nil {
            let focus = treeFocusCenter(layout: expanded, fallback: hub)
            HappeningTreeScrollFocus(focusID: treeFocusID ?? "event_field_tree_home",
                center: focus, contentSize: expanded.contentSize, animated: !reduceMotion)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func treeFocusCenter(layout: HappeningFieldLayout.Layout, fallback: CGPoint) -> CGPoint {
        guard let index = happenings.firstIndex(where: { $0.id == treeFocusID }),
              index < layout.sources.count else { return fallback }
        return layout.sources[index].center
    }

    // Observe size only; positions use ScrollView's native transform.
    private func updateVisibleFieldRect(_ rect: CGRect) {
        guard !rect.isEmpty, rect != visibleFieldRect else { return }
        let hasMoved = !visibleFieldRect.isEmpty
        visibleFieldRect = rect
        guard hasMoved else { return }
        isFieldScrolling = true
        scrollSettleTask?.cancel()
        scrollSettleTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            isFieldScrolling = false
        }
    }

    @ViewBuilder
    private func panel(for panel: HappeningPalettePanel) -> some View {
        switch panel {
        case .chooser, .creator:
            // Old creator state safely opens the selection-only chooser.
            HappeningChooserView(
                catalog: catalog,
                selected: selectedIDs,
                protectedIDs: addedIDs.union(fixedIDs),
                healthIDs: fixedIDs,
                onSave: { ids in
                    if onSaveSelection(ids) { activePanel = nil }
                },
                onCancel: { activePanel = nil }
            )
        }
    }

}

/// The field is an absolute-positioned lattice, so row-based scroll targets do
/// not describe its cells. Focus the native two-axis scroll surface only after
/// its content has laid out at the new size, keeping all world coordinates intact.
private struct HappeningTreeScrollFocus: UIViewRepresentable {
    let focusID: String
    let center: CGPoint
    let contentSize: CGSize
    let animated: Bool

    func makeUIView(context: Context) -> FocusProbe { FocusProbe() }

    func updateUIView(_ view: FocusProbe, context: Context) {
        view.request = self
        view.scheduleFocus()
    }

    final class FocusProbe: UIView {
        var request: HappeningTreeScrollFocus?
        private var appliedID: String?
        private var isScheduled = false
        private weak var observedScroll: UIScrollView?
        private var sizeObservation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                sizeObservation = nil
                observedScroll = nil
            }
            scheduleFocus()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleFocus()
        }

        func scheduleFocus() {
            guard !isScheduled, request?.focusID != appliedID else { return }
            isScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScheduled = false
                self.applyFocusIfReady()
            }
        }

        private func applyFocusIfReady() {
            guard let request, request.focusID != appliedID, window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            guard let scroll = ancestor as? UIScrollView else { return }
            if observedScroll !== scroll {
                observedScroll = scroll
                sizeObservation = scroll.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                    self?.scheduleFocus()
                }
            }
            guard scroll.contentSize.width >= request.contentSize.width - 1,
                  scroll.contentSize.height >= request.contentSize.height - 1 else { return }
            let point = HappeningEventTreeLayout.focusOffset(center: request.center,
                contentSize: scroll.contentSize, viewportSize: scroll.bounds.size)
            appliedID = request.focusID
            scroll.setContentOffset(point, animated: request.animated)
        }
    }
}

private struct HappeningPaletteCountHub: View {
    let count: Int
    let ink: Color
    private var countLabel: String {
        "\(count) / \(HappeningDefaults.maximumDailyAdditions)"
    }

    var body: some View {
        Text(countLabel)
            .font(.custom("NowhereDisplay10-Regular", size: 26))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(ink)
            .frame(width: 100, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) of \(HappeningDefaults.maximumDailyAdditions) events added")
            .accessibilityIdentifier("happening_palette_count_hub")
    }
}

/// Retained for the completion-state geometry contract used by older saved
/// snapshots and accessibility tests. The live palette now uses text only.
struct HappeningCompletionIslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.50, 0.23))
        path.addCurve(to: point(0.24, 0.08), control1: point(0.43, 0.14), control2: point(0.34, 0.06))
        path.addCurve(to: point(0.05, 0.50), control1: point(0.10, 0.10), control2: point(0.03, 0.28))
        path.addCurve(to: point(0.32, 0.89), control1: point(0.06, 0.74), control2: point(0.18, 0.92))
        path.addCurve(to: point(0.51, 0.76), control1: point(0.41, 0.88), control2: point(0.46, 0.80))
        path.addCurve(to: point(0.75, 0.87), control1: point(0.58, 0.80), control2: point(0.65, 0.89))
        path.addCurve(to: point(0.95, 0.43), control1: point(0.89, 0.84), control2: point(0.97, 0.65))
        path.addCurve(to: point(0.68, 0.11), control1: point(0.92, 0.22), control2: point(0.81, 0.07))
        path.addCurve(to: point(0.50, 0.23), control1: point(0.59, 0.12), control2: point(0.54, 0.19))
        path.closeSubpath()
        return path
    }
}

struct HappeningPaletteInstruction: Equatable {
    enum Kind: Equatable { case add, added, remove, error }
    let title: String
    let kind: Kind

    var announcement: String {
        let message: String = switch kind {
        case .add: String(localized: "Activate again to add to Canvas")
        case .added: String(localized: "On Canvas")
        case .remove: String(localized: "Activate again to remove from Canvas")
        case .error: String(localized: "Couldn’t update Canvas. Try again.")
        }
        return "\(title). \(message)"
    }
}

private struct HappeningPaletteInstructionView: View {
    let instruction: HappeningPaletteInstruction

    var body: some View {
        VStack(spacing: 4) {
            Text(instruction.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Group {
                switch instruction.kind {
                case .add: Text("Tap again to add to Canvas")
                case .added: Text("On Canvas")
                case .remove: Text("Tap again to remove from Canvas")
                case .error: Text("Couldn’t update Canvas. Try again.")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlassControl(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("happening_palette_instruction")
    }
}

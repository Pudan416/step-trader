import SwiftUI
import UIKit
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
    let artworkForLayout: ((HappeningFieldLayout.Layout, Bool) -> AnyView)?
    @State private var modeTransition: HappeningFieldModeTransition?
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
    let onCreate: (String) -> HappeningPaletteCreationOutcome
    let onCreateReplacement: (String, String, [String]) -> HappeningPaletteCreationOutcome
    let onSaveSelection: ([String]) -> Bool
    let onPanelPresentationChange: (Bool) -> Void
    let onReroll: () -> Void
    let dateHubCenter: CGPoint?
    let treeFocusID: String?
    let dateHubInk: HappeningPaletteLabelInk

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
        artworkForLayout: ((HappeningFieldLayout.Layout, Bool) -> AnyView)? = nil,
        interaction: HappeningPaletteInteractionState,
        addedIDs: Set<String>,
        fixedIDs: Set<String> = [],
        instruction: HappeningPaletteInstruction?,
        onActivate: @escaping (Happening) -> Void,
        onCreate: @escaping (String) -> HappeningPaletteCreationOutcome,
        onCreateReplacement: @escaping (String, String, [String]) -> HappeningPaletteCreationOutcome = { _, _, _ in .failed },
        onSaveSelection: @escaping ([String]) -> Bool = { _ in true },
        onPanelPresentationChange: @escaping (Bool) -> Void = { _ in },
        onReroll: @escaping () -> Void = {},
        dateHubCenter: CGPoint? = nil,
        treeFocusID: String? = nil,
        dateHubInk: HappeningPaletteLabelInk = .dark
    ) {
        self.happenings = happenings
        self.assignments = assignments
        self.labelInks = labelInks
        self.catalog = catalog ?? happenings
        self.selectedIDs = selectedIDs ?? happenings.map(\.id)
        self.artwork = artwork
        self.compactLayout = compactLayout
        self.artworkForLayout = artworkForLayout
        _activePanel = activePanel
        self.layout = layout
        self.mode = mode
        self.interaction = interaction
        self.addedIDs = addedIDs
        self.fixedIDs = fixedIDs
        self.instruction = instruction
        self.onActivate = onActivate
        self.onCreate = onCreate
        self.onCreateReplacement = onCreateReplacement
        self.onSaveSelection = onSaveSelection
        self.onPanelPresentationChange = onPanelPresentationChange
        self.onReroll = onReroll
        self.dateHubCenter = dateHubCenter
        self.treeFocusID = treeFocusID
        self.dateHubInk = dateHubInk
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollViewReader { scroll in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: modeTransition == nil)) { context in
                            let progress = modeTransition?.value(at: context.date) ?? (mode == .all ? 1 : 0)
                            let expanded = compactLayout.map {
                                HappeningFieldExpansion.layout(compact: $0, expanded: layout, viewport: proxy.size, progress: progress)
                            } ?? layout
                            let visibleRect = visibleFieldRect.isEmpty ? CGRect(
                                x: max(0, (expanded.contentSize.width - proxy.size.width) / 2),
                                y: max(0, (expanded.contentSize.height - proxy.size.height) / 2),
                                width: proxy.size.width, height: proxy.size.height
                            ) : visibleFieldRect
                            let displayed = HappeningFieldEdgeScale.apply(to: expanded, visibleRect: visibleRect,
                                strength: reduceMotion || artworkForLayout == nil || dateHubCenter != nil ? 0 : progress)
                            ZStack(alignment: .topLeading) {
                                (artworkForLayout?(displayed, modeTransition != nil || isFieldScrolling) ?? artwork)
                                    .accessibilityHidden(true)
                                    .allowsHitTesting(false)
                                HappeningShapeField(
                                    happenings: happenings, assignments: assignments, layout: displayed,
                                    interaction: interaction, addedIDs: addedIDs,
                                    onActivate: onActivate, labelInks: labelInks
                                )
                                if let dateHubCenter {
                                    HappeningPaletteDateHub(ink: dateHubInk.color)
                                        .position(dateHubCenter)
                                        .allowsHitTesting(false)
                                }
                                if let compactLayout {
                                    let compactHeight = max(proxy.size.height, compactLayout.contentSize.height)
                                    Color.clear.frame(width: proxy.size.width, height: proxy.size.height)
                                        .id(HappeningPaletteMode.frequent.rawValue)
                                        .position(x: displayed.contentSize.width / 2,
                                            y: (displayed.contentSize.height - compactHeight + proxy.size.height) / 2)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                    Color.clear.frame(width: proxy.size.width, height: proxy.size.height)
                                        .id(HappeningPaletteMode.all.rawValue)
                                        .position(x: displayed.contentSize.width / 2, y: displayed.contentSize.height / 2)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                            .frame(width: max(proxy.size.width, displayed.contentSize.width),
                                   height: max(proxy.size.height, displayed.contentSize.height))
                            .background {
                                if dateHubCenter != nil,
                                   let index = happenings.firstIndex(where: { $0.id == treeFocusID }),
                                   index < expanded.sources.count {
                                    HappeningTreeScrollFocus(
                                        focusID: treeFocusID ?? "",
                                        center: expanded.sources[index].center,
                                        contentSize: expanded.contentSize,
                                        animated: !reduceMotion
                                    )
                                    .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                            .transaction { $0.animation = nil }
                        }
                        // TimelineView must advertise the entire world to the
                        // native scroll surface, not just paint overflow inside it.
                        .frame(width: max(proxy.size.width, layout.contentSize.width),
                               height: max(proxy.size.height, layout.contentSize.height, compactLayout?.contentSize.height ?? 0))
                        .onGeometryChange(for: CGRect.self) { content in
                            let origin = content.frame(in: .named("happeningViewport")).origin
                            return CGRect(x: -origin.x, y: -origin.y,
                                width: proxy.size.width, height: proxy.size.height)
                        } action: { rect in
                            updateVisibleFieldRect(rect)
                        }
                    }
                    .coordinateSpace(name: "happeningViewport")
                    .defaultScrollAnchor(mode == .frequent && (compactLayout?.contentSize.height ?? 0) > proxy.size.height ? .top : .center)
                    .scrollDisabled(compactLayout != nil && mode == .frequent && (compactLayout?.contentSize.height ?? 0) <= proxy.size.height)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .canvasTourAnchor("canvas.happenings")
                    .accessibilityIdentifier("happening_field_scroll")
                    .accessibilityHidden(activePanel != nil)
                    .allowsHitTesting(activePanel == nil && modeTransition == nil)
                    .onChange(of: mode) { oldMode, newMode in
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
        case .chooser:
            HappeningChooserView(
                catalog: catalog,
                selected: selectedIDs,
                protectedIDs: addedIDs.union(fixedIDs),
                healthIDs: fixedIDs,
                onCreateNew: { title, replacementID, selection in
                    let outcome = onCreateReplacement(title, replacementID, selection)
                    if outcome.closesCreator { activePanel = nil }
                    return outcome
                },
                onSave: { ids in
                    if onSaveSelection(ids) { activePanel = nil }
                },
                onCancel: { activePanel = nil }
            )
        case .creator:
            HappeningCreatorPanel(
                onCreate: { title in
                    let outcome = onCreate(title)
                    if outcome.closesCreator { activePanel = nil }
                    return outcome
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

private struct HappeningPaletteDateHub: View {
    let ink: Color
    private var dateLabel: String {
        Date.now.formatted(.dateTime.locale(Locale(identifier: "en_US")).month(.abbreviated).day(.twoDigits)).lowercased()
    }

    var body: some View {
        Text(dateLabel)
            .font(.custom("NowhereDisplay091-Regular", size: 26))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(ink)
            .frame(width: 100, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dateLabel)
            .accessibilityIdentifier("happening_palette_date_hub")
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

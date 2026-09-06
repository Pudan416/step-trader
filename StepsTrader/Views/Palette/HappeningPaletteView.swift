import SwiftUI

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

struct HappeningPaletteView: View {
    let happenings: [Happening]
    let assignments: [String: HappeningEditorialAssignment]
    let catalog: [Happening]
    let selectedIDs: [String]
    @Binding var activePanel: HappeningPalettePanel?
    let onPick: (Happening, HappeningEditorialAssignment, CGPoint) -> Bool
    let onCreate: (String) -> Happening?
    let onSaveSelection: ([String]) -> Bool
    let onPanelPresentationChange: (Bool) -> Void
    let onDismiss: () -> Void
    let onReroll: () -> Void
    let dayKey: String
    let dockCenterY: CGFloat?

    @State private var presentation: HappeningFieldPresentationState
    @State private var highlightedID: String?
    @State private var highlightTask: Task<Void, Never>?

    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.tabBarHeight) private var tabBarHeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        happenings: [Happening],
        assignments: [String: HappeningEditorialAssignment] = [:],
        catalog: [Happening]? = nil,
        selectedIDs: [String]? = nil,
        activePanel: Binding<HappeningPalettePanel?> = .constant(nil),
        onPick: @escaping (Happening, HappeningEditorialAssignment, CGPoint) -> Bool,
        onCreate: @escaping (String) -> Happening?,
        onSaveSelection: @escaping ([String]) -> Bool = { _ in true },
        onPanelPresentationChange: @escaping (Bool) -> Void = { _ in },
        onDismiss: @escaping () -> Void,
        onReroll: @escaping () -> Void = {},
        dayKey: String,
        dockCenterY: CGFloat? = nil
    ) {
        self.happenings = happenings
        self.assignments = assignments
        self.catalog = catalog ?? happenings
        self.selectedIDs = selectedIDs ?? happenings.map(\.id)
        _activePanel = activePanel
        self.onPick = onPick
        self.onCreate = onCreate
        self.onSaveSelection = onSaveSelection
        self.onPanelPresentationChange = onPanelPresentationChange
        self.onDismiss = onDismiss
        self.onReroll = onReroll
        self.dayKey = dayKey
        self.dockCenterY = dockCenterY
        _presentation = State(initialValue: HappeningFieldPresentationState(happenings: happenings))
    }

    var body: some View {
        GeometryReader { proxy in
            let panelTopInset = proxy.safeAreaInsets.top
                + HappeningPaletteChromeLayout.panelTopInset(
                    topCardHeight: topCardHeight,
                    hidesSurroundingChrome: true
                )
            let panelBottomInset = proxy.safeAreaInsets.bottom
                + HappeningPaletteChromeLayout.panelBottomInset(
                    tabBarHeight: tabBarHeight,
                    hidesSurroundingChrome: true
                )
            let panelHeight = max(1, proxy.size.height - panelTopInset - panelBottomInset)
            let localDockY = resolvedDockCenterY(in: proxy)
            let layout = presentation.layout(
                in: proxy.size,
                safeInsets: proxy.safeAreaInsets,
                dynamicTypeSize: dynamicTypeSize,
                contentTopInset: panelTopInset + 10,
                dockCenterY: localDockY
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.20))
                    .frame(
                        width: proxy.size.width,
                        height: max(0, proxy.size.height - panelTopInset + 12)
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: panelTopInset - 12 + max(0, proxy.size.height - panelTopInset + 12) / 2
                    )
                    .allowsHitTesting(false)

                HappeningShapeField(
                    presentation: $presentation,
                    happenings: happenings,
                    assignments: assignments,
                    contentTopInset: panelTopInset + 10,
                    dockCenterY: layout.dockAnchor.y,
                    highlightedID: highlightedID,
                    onPick: onPick
                )
                .accessibilityHidden(activePanel != nil)
                .allowsHitTesting(activePanel == nil)

                if layout.completionBounds != nil {
                    Text("All added for today", comment: "Palette completion state")
                        .font(.geist(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.Night.textPrimary.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .accessibilityHidden(activePanel != nil)
                }

                if let activePanel {
                    ZStack {
                        Color.black.opacity(0.24)
                        Rectangle().fill(.ultraThinMaterial).opacity(0.34)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)

                    panel(for: activePanel)
                        .frame(maxWidth: max(1, proxy.size.width - 40), maxHeight: panelHeight)
                        .position(x: proxy.size.width / 2, y: panelTopInset + panelHeight / 2)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task {
            guard ProcessInfo.processInfo.environment["TASK7_SHAKE_PALETTE"] == "1" else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        .onShake {
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
        .onChange(of: selectedIDs) { presentation.reset(with: happenings) }
        .onChange(of: dayKey) { presentation.reset(with: happenings) }
        .onDisappear {
            onPanelPresentationChange(false)
            highlightTask?.cancel()
            highlightTask = nil
        }
    }

    @ViewBuilder
    private func panel(for panel: HappeningPalettePanel) -> some View {
        switch panel {
        case .chooser:
            HappeningChooserView(
                catalog: catalog,
                selected: selectedIDs,
                onCreateNew: { activePanel = .creator },
                onSave: { ids in
                    if onSaveSelection(ids) { activePanel = nil }
                },
                onCancel: { activePanel = nil }
            )
        case .creator:
            HappeningCreatorPanel(
                onCreate: { title in
                    guard let created = onCreate(title) else { return }
                    activePanel = nil
                    highlightedID = created.id
                    highlightTask?.cancel()
                    highlightTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(900))
                        guard !Task.isCancelled else { return }
                        highlightedID = nil
                    }
                },
                onCancel: { activePanel = nil }
            )
        }
    }

    private func resolvedDockCenterY(in proxy: GeometryProxy) -> CGFloat? {
        guard let dockCenterY else { return nil }
        let localY = dockCenterY - proxy.frame(in: .global).minY
        guard localY.isFinite, localY > 0 else { return nil }
        return localY
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

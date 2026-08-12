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

    static func panelTopInset(
        topCardHeight: CGFloat,
        hidesSurroundingChrome: Bool
    ) -> CGFloat {
        hidesSurroundingChrome
            ? compactInset
            : max(compactInset, topCardHeight + chromeSpacing)
    }

    static func panelBottomInset(
        tabBarHeight: CGFloat,
        hidesSurroundingChrome: Bool
    ) -> CGFloat {
        hidesSurroundingChrome
            ? compactInset
            : max(compactInset, tabBarHeight + chromeSpacing)
    }

    static func hidesSurroundingChrome(
        isPalettePresented: Bool,
        isPanelPresented: Bool,
        dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        isPalettePresented
            && (isPanelPresented || HappeningLiquidLayout.usesExpandedLayout(for: dynamicTypeSize))
    }

    static func showsCanvasControls(isPalettePresented: Bool) -> Bool {
        !isPalettePresented
    }
}

/// Palette container for the native Living-island field and catalog controls.
struct HappeningPaletteView: View {
    let happenings: [Happening]
    /// The figure each happening takes today. Passed in rather than derived
    /// here so the tile and the canvas element come from one roll.
    let figures: [String: HappeningShapeAssignment]
    let catalog: [Happening]
    let selectedIDs: [String]
    let onPick: (Happening, CGPoint) -> Bool
    let onCreate: (String) -> Happening?
    let onSaveSelection: ([String]) -> Bool
    let onPanelPresentationChange: (Bool) -> Void
    let onDismiss: () -> Void
    /// Shake. Nothing in the dock triggers this — the hint at the top of the
    /// overlay is the only thing that teaches the gesture.
    let onReroll: () -> Void
    let dayKey: String

    /// Global mid-Y of the canvas `+` this palette overlays. The dock sits on
    /// exactly that line, so opening the palette does not shift the controls.
    /// Nil only before the first layout pass reports it.
    let dockCenterY: CGFloat?

    @State private var presentation: HappeningLiquidPresentationState
    @State private var activePanel: Panel?
    @State private var highlightedID: String?
    @State private var highlightTask: Task<Void, Never>?

    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.tabBarHeight) private var tabBarHeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Panel {
        case chooser
        case creator
    }

    init(
        happenings: [Happening],
        figures: [String: HappeningShapeAssignment] = [:],
        catalog: [Happening]? = nil,
        selectedIDs: [String]? = nil,
        onPick: @escaping (Happening, CGPoint) -> Bool,
        onCreate: @escaping (String) -> Happening?,
        onSaveSelection: @escaping ([String]) -> Bool = { _ in true },
        onPanelPresentationChange: @escaping (Bool) -> Void = { _ in },
        onDismiss: @escaping () -> Void,
        onReroll: @escaping () -> Void = {},
        dayKey: String,
        dockCenterY: CGFloat? = nil
    ) {
        self.happenings = happenings
        self.figures = figures
        self.catalog = catalog ?? happenings
        self.selectedIDs = selectedIDs ?? happenings.map(\.id)
        self.onPick = onPick
        self.onCreate = onCreate
        self.onSaveSelection = onSaveSelection
        self.onPanelPresentationChange = onPanelPresentationChange
        self.onDismiss = onDismiss
        self.onReroll = onReroll
        self.dayKey = dayKey
        self.dockCenterY = dockCenterY
        _presentation = State(
            initialValue: HappeningLiquidPresentationState(happenings: happenings)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let computed = presentation.layout(
                in: proxy.size,
                safeInsets: proxy.safeAreaInsets,
                dynamicTypeSize: dynamicTypeSize
            )
            let hidesSurroundingChrome = HappeningPaletteChromeLayout.hidesSurroundingChrome(
                isPalettePresented: true,
                isPanelPresented: activePanel != nil,
                dynamicTypeSize: dynamicTypeSize
            )
            // Line the dock up with the canvas `+` it sits on top of — the
            // button reports its own position, so this never drifts from the
            // tab-bar height and paddings that place it.
            //
            // Only while that button is actually on screen. At accessibility
            // type sizes the palette hides the surrounding chrome, so there is
            // no `+` to line up with and the last reported position is stale;
            // the computed anchor is the right one there.
            let layout = hidesSurroundingChrome
                ? computed
                : alignedToCanvasControls(computed, in: proxy)
            let panelTopInset = proxy.safeAreaInsets.top
                + HappeningPaletteChromeLayout.panelTopInset(
                    topCardHeight: topCardHeight,
                    hidesSurroundingChrome: hidesSurroundingChrome
                )
            let panelBottomInset = proxy.safeAreaInsets.bottom
                + HappeningPaletteChromeLayout.panelBottomInset(
                    tabBarHeight: tabBarHeight,
                    hidesSurroundingChrome: hidesSurroundingChrome
                )
            let panelHeight = max(1, proxy.size.height - panelTopInset - panelBottomInset)

            ZStack(alignment: .topLeading) {
                // Frosted, not clear: the canvas stays visible and blurred
                // behind the field instead of being painted over.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard activePanel == nil else { return }
                        onDismiss()
                    }

                Text("Shake to change the shapes", comment: "Palette shake hint")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    // `textSecondary` is a deliberate alias of `textPrimary` in
                    // this theme — hierarchy comes from opacity, so without this
                    // the hint reads as loud as the tile labels.
                    .foregroundStyle(AppColors.Night.textSecondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .position(
                        x: proxy.size.width / 2,
                        y: panelTopInset + hintTopInset
                    )
                    .accessibilityHidden(activePanel != nil)

                HappeningShapeField(
                    presentation: $presentation,
                    happenings: happenings,
                    figures: figures,
                    bounds: fieldBounds(layout, topInset: panelTopInset, width: proxy.size.width),
                    highlightedID: highlightedID,
                    onPick: onPick
                )
                .accessibilityHidden(activePanel != nil)

                if let completionBounds = layout.completionBounds {
                    HappeningCompletionIsland()
                        .frame(width: completionBounds.width, height: completionBounds.height)
                        .position(x: completionBounds.midX, y: completionBounds.midY)
                        .accessibilityHidden(activePanel != nil)
                }

                dockButton(
                    systemImage: "xmark",
                    label: String(localized: "Close", comment: "Palette close button"),
                    anchor: layout.dockAnchor
                ) {
                    activePanel = nil
                    onDismiss()
                }
                .accessibilityHidden(activePanel != nil)

                dockButton(
                    systemImage: "checklist",
                    label: String(localized: "Choose happenings", comment: "Palette dock button"),
                    anchor: CGPoint(x: layout.dockAnchor.x - dockButtonSpacing, y: layout.dockAnchor.y)
                ) {
                    activePanel = .chooser
                }
                .accessibilityHidden(activePanel != nil)

                dockButton(
                    systemImage: "plus",
                    label: String(localized: "Add a happening", comment: "Palette dock button"),
                    anchor: CGPoint(x: layout.dockAnchor.x + dockButtonSpacing, y: layout.dockAnchor.y)
                ) {
                    activePanel = .creator
                }
                .accessibilityHidden(activePanel != nil)

                if let activePanel {
                    ZStack {
                        Color.black.opacity(0.24)
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.34)
                    }
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .transition(.opacity)

                    panel(for: activePanel)
                        .frame(
                            maxWidth: max(1, proxy.size.width - 40),
                            maxHeight: panelHeight
                        )
                        .position(
                            x: proxy.size.width / 2,
                            y: panelTopInset + panelHeight / 2
                        )
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .task {
            // XCUITest cannot synthesise a shake and a tappable trigger just
            // gets swallowed by the palette's own dismissing backdrop, so under
            // the fixture the palette shakes itself once after it appears.
            guard ProcessInfo.processInfo.environment["TASK7_SHAKE_PALETTE"] == "1" else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            NotificationCenter.default.post(
                name: UIDevice.deviceDidShakeNotification,
                object: nil
            )
        }
        .onShake {
            // Not while a panel is up: a shake behind the chooser or the
            // creator would re-roll a field the user cannot see.
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
        .onChange(of: selectedIDs) {
            presentation.reset(with: happenings)
        }
        .onChange(of: dayKey) {
            presentation.reset(with: happenings)
        }
        .onDisappear {
            onPanelPresentationChange(false)
            highlightTask?.cancel()
            highlightTask = nil
        }
    }

    @ViewBuilder
    private func panel(for panel: Panel) -> some View {
        switch panel {
        case .chooser:
            HappeningChooserView(
                catalog: catalog,
                selected: selectedIDs,
                onSave: { ids in
                    if onSaveSelection(ids) {
                        activePanel = nil
                    }
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

    /// Replaces the computed dock line with the canvas `+`'s actual one.
    /// Content is not re-flowed: the computed layout already guarantees the
    /// cluster clears its own dock line, and the two sit within a few points
    /// of each other.
    private func alignedToCanvasControls(
        _ layout: HappeningLiquidLayout.Layout,
        in proxy: GeometryProxy
    ) -> HappeningLiquidLayout.Layout {
        guard let dockCenterY else { return layout }
        let localY = dockCenterY - proxy.frame(in: .global).minY
        guard localY.isFinite, localY > 0 else { return layout }
        let shift = localY - layout.dockAnchor.y
        return HappeningLiquidLayout.Layout(
            sources: layout.sources,
            labelFrames: layout.labelFrames,
            contourBounds: layout.contourBounds,
            dockAnchor: CGPoint(x: layout.dockAnchor.x, y: localY),
            completionBounds: layout.completionBounds.map { $0.offsetBy(dx: 0, dy: shift) }
        )
    }

    /// Room for the hint below the top card, with enough left over for it to
    /// wrap to two lines at accessibility type sizes without reaching the
    /// first row of tiles.
    private var hintTopInset: CGFloat { 30 }

    /// The box the tiles lay out in: below the top card and the hint, above the
    /// dock.
    ///
    /// `topInset` is the same value the panels use, which already accounts for
    /// `topCardHeight` — measuring from the safe area instead put the whole
    /// first row behind the energy card.
    ///
    /// The bottom comes from the layout that used to bound the metaball
    /// contour, so the field keeps clearing the dock exactly as the cluster did.
    private func fieldBounds(
        _ layout: HappeningLiquidLayout.Layout,
        topInset: CGFloat,
        width: CGFloat
    ) -> CGRect {
        let top = topInset + hintTopInset + 34
        let bottom = layout.dockAnchor.y - 52
        return CGRect(
            x: 16,
            y: top,
            width: max(1, width - 32),
            height: max(1, bottom - top)
        )
    }

    /// Centre-to-centre gap between the three dock buttons. Wide enough that
    /// the 72pt hit areas below never overlap.
    private var dockButtonSpacing: CGFloat { 72 }

    /// Identical to the canvas's own bottom controls — same 56pt circle, same
    /// `liquidGlassControl` material, same icon weight and colour, same 72pt hit
    /// area. The palette overlays those controls, so anything that changed size,
    /// colour or material on open would read as a different set of buttons
    /// appearing rather than the same ones staying put.
    private func dockButton(
        systemImage: String,
        label: String,
        anchor: CGPoint,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.Night.textPrimary)
                .frame(width: 56, height: 56)
                .liquidGlassControl(in: Circle())
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(anchor)
        .accessibilityLabel(Text(label))
    }
}

struct HappeningCompletionIslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let width = rect.width
        let height = rect.height

        func point(_ unitX: CGFloat, _ unitY: CGFloat) -> CGPoint {
            CGPoint(x: x + width * unitX, y: y + height * unitY)
        }

        var path = Path()
        path.move(to: point(0.50, 0.23))
        path.addCurve(
            to: point(0.24, 0.08),
            control1: point(0.43, 0.14),
            control2: point(0.34, 0.06)
        )
        path.addCurve(
            to: point(0.05, 0.50),
            control1: point(0.10, 0.10),
            control2: point(0.03, 0.28)
        )
        path.addCurve(
            to: point(0.32, 0.89),
            control1: point(0.06, 0.74),
            control2: point(0.18, 0.92)
        )
        path.addCurve(
            to: point(0.51, 0.76),
            control1: point(0.41, 0.88),
            control2: point(0.46, 0.80)
        )
        path.addCurve(
            to: point(0.75, 0.87),
            control1: point(0.58, 0.80),
            control2: point(0.65, 0.89)
        )
        path.addCurve(
            to: point(0.95, 0.43),
            control1: point(0.89, 0.84),
            control2: point(0.97, 0.65)
        )
        path.addCurve(
            to: point(0.68, 0.11),
            control1: point(0.92, 0.22),
            control2: point(0.81, 0.07)
        )
        path.addCurve(
            to: point(0.50, 0.23),
            control1: point(0.59, 0.12),
            control2: point(0.54, 0.19)
        )
        path.closeSubpath()
        return path
    }
}

private struct HappeningCompletionIsland: View {
    @ScaledMetric(relativeTo: .body) private var messagePointSize: CGFloat = 15

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let contour = HappeningCompletionIslandShape()
                .path(in: CGRect(origin: .zero, size: size))

            ZStack {
                Canvas { context, _ in
                    context.addFilter(
                        .shadow(
                            color: .black.opacity(0.14),
                            radius: 10,
                            x: 0,
                            y: 6
                        )
                    )
                    context.fill(
                        contour,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(hex: "#E098A0").opacity(0.88),
                                Color(hex: "#D8AD6A").opacity(0.84),
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: size.height)
                        )
                    )
                    context.stroke(contour, with: .color(.white.opacity(0.18)), lineWidth: 0.75)
                }

                Text("All added for today")
                    .font(.system(size: messagePointSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 22)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Living island palette") {
    HappeningPaletteView(
        happenings: HappeningDefaults.builtIns,
        catalog: HappeningDefaults.builtIns + [
            Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)
        ],
        selectedIDs: HappeningDefaults.builtIns.map(\.id),
        onPick: { _, _ in true },
        onCreate: { _ in nil },
        onDismiss: {},
        dayKey: "2026-08-09"
    )
}

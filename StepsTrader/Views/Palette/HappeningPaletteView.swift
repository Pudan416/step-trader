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
    let catalog: [Happening]
    let selectedIDs: [String]
    @Binding var activePanel: HappeningPalettePanel?
    let layout: HappeningFieldLayout.Layout
    let interaction: HappeningPaletteInteractionState
    let addedIDs: Set<String>
    let instruction: HappeningPaletteInstruction?
    let onActivate: (Happening) -> Void
    let onCreate: (String) -> HappeningPaletteCreationOutcome
    let onSaveSelection: ([String]) -> Bool
    let onPanelPresentationChange: (Bool) -> Void
    let onReroll: () -> Void

    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.tabBarHeight) private var tabBarHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        happenings: [Happening],
        assignments: [String: HappeningEditorialAssignment] = [:],
        catalog: [Happening]? = nil,
        selectedIDs: [String]? = nil,
        activePanel: Binding<HappeningPalettePanel?> = .constant(nil),
        layout: HappeningFieldLayout.Layout,
        interaction: HappeningPaletteInteractionState,
        addedIDs: Set<String>,
        instruction: HappeningPaletteInstruction?,
        onActivate: @escaping (Happening) -> Void,
        onCreate: @escaping (String) -> HappeningPaletteCreationOutcome,
        onSaveSelection: @escaping ([String]) -> Bool = { _ in true },
        onPanelPresentationChange: @escaping (Bool) -> Void = { _ in },
        onReroll: @escaping () -> Void = {}
    ) {
        self.happenings = happenings
        self.assignments = assignments
        self.catalog = catalog ?? happenings
        self.selectedIDs = selectedIDs ?? happenings.map(\.id)
        _activePanel = activePanel
        self.layout = layout
        self.interaction = interaction
        self.addedIDs = addedIDs
        self.instruction = instruction
        self.onActivate = onActivate
        self.onCreate = onCreate
        self.onSaveSelection = onSaveSelection
        self.onPanelPresentationChange = onPanelPresentationChange
        self.onReroll = onReroll
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
            ZStack(alignment: .topLeading) {
                HappeningShapeField(
                    happenings: happenings,
                    assignments: assignments,
                    layout: layout,
                    interaction: interaction,
                    addedIDs: addedIDs,
                    onActivate: onActivate
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityHidden(activePanel != nil)
                .allowsHitTesting(activePanel == nil)

                // Actions live on the selected object. Keep only failures here;
                // the full state announcements remain available to VoiceOver.
                if let instruction, instruction.kind == .error {
                    HappeningPaletteInstructionView(instruction: instruction)
                        .frame(width: min(320, max(1, proxy.size.width - 48)))
                        .position(x: layout.dockAnchor.x, y: layout.dockAnchor.y - 68)
                        .accessibilityHidden(activePanel != nil)
                        .allowsHitTesting(false)
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
        .onChange(of: instruction) { _, next in
            guard let next else { return }
            UIAccessibility.post(notification: .announcement, argument: next.announcement)
        }
        .onDisappear {
            onPanelPresentationChange(false)
        }
    }

    @ViewBuilder
    private func panel(for panel: HappeningPalettePanel) -> some View {
        switch panel {
        case .chooser:
            HappeningChooserView(
                catalog: catalog,
                selected: selectedIDs,
                protectedIDs: addedIDs,
                onCreateNew: { activePanel = .creator },
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

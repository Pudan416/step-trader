import SwiftUI

/// Routes between the available canvas-overlay animations based on the
/// user's choice in Settings → Appearance. Smudge keeps its full
/// configuration; cosmic ignores it (it's a procedural standalone effect).
///
/// The active style is persisted via `SharedKeys.canvasOverlayStyle` in the
/// shared App-Group defaults, defaulting to `.smudge` so existing users see
/// no behaviour change after the update.
struct CanvasAnimationOverlay: View {

    let elements: [CanvasElement]
    let sleepPoints: Int
    let stepsPoints: Int
    let sleepColor: Color
    let stepsColor: Color
    let decayNorm: Double
    let backgroundColor: Color
    var labelColor: Color? = nil
    var hasStepsData: Bool = true
    var hasSleepData: Bool = true
    var overlayStyleOverride: String? = nil
    var onGestureBegan: @MainActor (CanvasTouchGestureSample) -> Void = { _ in }
    var onGestureUpdated: @MainActor (CanvasTouchGestureSample) -> Void = { _ in }
    var onGestureEnded: @MainActor () -> Void = {}

    @AppStorage(SharedKeys.canvasOverlayStyle, store: UserDefaults.nowhere())
    private var styleRaw: String = CanvasOverlayStyle.smudge.rawValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderingIsActive) private var renderingIsActive
    @Environment(\.scenePhase) private var scenePhase

    private var style: CanvasOverlayStyle {
        CanvasOverlayStyle(rawValue: overlayStyleOverride ?? styleRaw) ?? .smudge
    }

    private var isRenderingAllowed: Bool {
        RenderingActivity.shouldAnimate(
            isViewActive: renderingIsActive,
            sceneIsActive: scenePhase == .active,
            reduceMotion: reduceMotion
        )
    }

    private var isDirectInteractionAllowed: Bool {
        RenderingActivity.shouldAllowDirectInteraction(
            isViewActive: renderingIsActive,
            sceneIsActive: scenePhase == .active
        )
    }

    var body: some View {
        overlayContent.onChange(of: diagnosticState, initial: true) { _, state in
            AppLogger.ui.notice("[CANVAS_INPUT] route \(state, privacy: .public)")
        }
    }

    private var diagnosticState: String {
        "style=\(style.rawValue) viewActive=\(renderingIsActive) sceneActive=\(scenePhase == .active) interaction=\(isDirectInteractionAllowed)"
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch style.requiredResource {
        case .none:
            EmptyView()
                .allowsHitTesting(false)
        case .smudge:
            SmudgeOverlayView(
                elements: elements,
                sleepPoints: sleepPoints,
                stepsPoints: stepsPoints,
                sleepColor: sleepColor,
                stepsColor: stepsColor,
                decayNorm: decayNorm,
                backgroundColor: backgroundColor,
                labelColor: labelColor,
                hasStepsData: hasStepsData,
                hasSleepData: hasSleepData,
                isRenderingAllowed: isDirectInteractionAllowed,
                onGestureBegan: onGestureBegan,
                onGestureUpdated: onGestureUpdated,
                onGestureEnded: onGestureEnded
            )
        case .cosmic:
            ShaderParkOverlayView(isRenderingAllowed: isRenderingAllowed)
        }
    }
}

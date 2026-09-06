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

    @AppStorage(SharedKeys.canvasOverlayStyle, store: UserDefaults.stepsTrader())
    private var styleRaw: String = CanvasOverlayStyle.smudge.rawValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderingIsActive) private var renderingIsActive
    @Environment(\.scenePhase) private var scenePhase

    private var style: CanvasOverlayStyle {
        CanvasOverlayStyle(rawValue: styleRaw) ?? .smudge
    }

    private var isRenderingAllowed: Bool {
        RenderingActivity.shouldAnimate(
            isViewActive: renderingIsActive,
            sceneIsActive: scenePhase == .active,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
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
                isRenderingAllowed: isRenderingAllowed
            )
        case .cosmic:
            ShaderParkOverlayView(isRenderingAllowed: isRenderingAllowed)
        }
    }
}

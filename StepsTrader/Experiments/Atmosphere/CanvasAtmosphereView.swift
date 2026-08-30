import SwiftUI

/// The existing canvas, put into air and depth.
///
/// Nothing here replaces the current renderer: the gradient is the app's own
/// `EnergyGradientBackground` and the shapes are drawn by the unmodified
/// `GenerativeCanvasView`. The only additions are the two things the flat
/// version was missing — motes suspended in the light, and a plane of focus
/// that not everything sits on.
///
/// Cost is three canvas passes instead of one, plus three fullscreen shader
/// passes. Each canvas pass draws a third of the elements, so the drawing work
/// is roughly unchanged; what is new is the compositing.
struct CanvasAtmosphereView: View {
    let canvas: DayCanvas
    let atmosphere: CanvasAtmosphere
    /// A/B switch: off renders exactly what ships today.
    var showsAtmosphere: Bool = true

    private var planes: [CanvasDepthPlane: [CanvasElement]] {
        CanvasAtmosphere.split(canvas.elements, dayKey: canvas.dayKey)
    }

    private var dustTint: Color {
        Color(hex: canvas.stepsColorHex)
    }

    var body: some View {
        ZStack {
            EnergyGradientBackground(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: canvas.resolvedHasStepsData,
                hasSleepData: canvas.resolvedHasSleepData,
                showGrain: true,
                gradientStyleOverride: canvas.gradientStyle,
                gradientPaletteOverride: canvas.gradientPalette,
                textureOverride: canvas.textureRaw
            )

            if showsAtmosphere {
                let split = planes
                dust(.far)
                canvasLayer(elements: split[.far] ?? [], plane: .far)
                canvasLayer(elements: split[.mid] ?? [], plane: .mid)
                dust(.mid)
                canvasLayer(elements: split[.near] ?? [], plane: .near)
                dust(.near)
            } else {
                canvasLayer(elements: canvas.elements, plane: .mid, flat: true)
            }
        }
        .clipped()
    }

    // MARK: - Layers

    @ViewBuilder
    private func canvasLayer(
        elements: [CanvasElement],
        plane: CanvasDepthPlane,
        flat: Bool = false
    ) -> some View {
        GenerativeCanvasView(
            elements: elements,
            dayKey: canvas.dayKey,
            sleepPoints: canvas.sleepPoints,
            stepsPoints: canvas.stepsPoints,
            sleepColor: Color(hex: canvas.sleepColorHex),
            stepsColor: Color(hex: canvas.stepsColorHex),
            decayNorm: canvas.decayNorm,
            showLabelsOnCanvas: false,
            showsBackgroundGradient: false,
            hasStepsData: canvas.resolvedHasStepsData,
            hasSleepData: canvas.resolvedHasSleepData
        )
        .frame(
            width: GenerativeCanvasView.canonicalPortraitSize.width,
            height: GenerativeCanvasView.canonicalPortraitSize.height
        )
        .blur(radius: flat ? 0 : atmosphere.blurRadius(for: plane))
        .scaleEffect(flat ? 1 : plane.scale)
        .opacity(flat ? 1 : plane.opacity)
        .allowsHitTesting(false)
    }

    private func dust(_ plane: CanvasDepthPlane) -> some View {
        CanvasDustLayer(
            atmosphere: atmosphere,
            plane: plane,
            tint: dustTint
        )
    }
}

// MARK: - Dust

/// One plane of motes. Additive over whatever is beneath it, so dust in front
/// of a lit shape picks that light up instead of greying it out.
struct CanvasDustLayer: View {
    let atmosphere: CanvasAtmosphere
    let plane: CanvasDepthPlane
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderingIsActive) private var renderingIsActive
    @Environment(\.scenePhase) private var scenePhase

    private var shouldAnimate: Bool {
        RenderingActivity.shouldAnimate(
            isViewActive: renderingIsActive,
            sceneIsActive: scenePhase == .active,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !shouldAnimate)) { timeline in
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.canvasDust(
                        .float2(Float(geo.size.width), Float(geo.size.height)),
                        .float(Float(Self.shaderTime(timeline.date))),
                        .float(Float(atmosphere.dustScale(for: plane))),
                        .float(Float(atmosphere.dust)),
                        .float(Float(plane.scale)),
                        .color(tint.opacity(atmosphere.dustOpacity(for: plane)))
                    ))
            }
        }
        .blur(radius: atmosphere.dustBlurRadius(for: plane))
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Wrapped before narrowing to `Float`, for the same reason the ray shader
    /// wraps: `timeIntervalSinceReferenceDate` at 32-bit precision quantises to
    /// tens of milliseconds and the drift would visibly stutter.
    static func shaderTime(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
    }
}

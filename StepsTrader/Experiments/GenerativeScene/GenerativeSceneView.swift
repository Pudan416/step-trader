import SwiftUI

/// One day rendered as a single volumetric scene, with the date sitting on top.
///
/// Cost is controlled by `quality` — the march's step budget — and nothing else.
/// Rendering the shader into a half-size layer and scaling it back up was the
/// obvious second lever, but `drawingGroup()` + `scaleEffect` tiles the raster
/// and leaves visible seams along the edges, so it is not worth the artefacts
/// at prototype stage. If the step budget alone is not enough on device, the
/// fix is a real MTKView with a lower-resolution offscreen target, not a
/// SwiftUI scaling trick.
struct GenerativeSceneView: View {
    let params: GenerativeSceneParams
    var date: Date = Date()
    var quality: Double = 40
    var isAnimating: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                sceneLayer(size: geo.size)
                dateLabel
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(params.palette.deep)
    }

    // MARK: - Scene

    private func sceneLayer(size: CGSize) -> some View {
        let w = max(size.width, 1)
        let h = max(size.height, 1)

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.generativeScene(
                    .float2(Float(w), Float(h)),
                    .float(Float(Self.shaderTime(timeline.date))),
                    .float(Float(params.energy)),
                    .float(Float(params.clarity)),
                    .float(Float(params.events)),
                    .float(Float(params.seed)),
                    .float(Float(quality)),
                    .color(params.palette.deep),
                    .color(params.palette.mid),
                    .color(params.palette.glow)
                ))
                .frame(width: w, height: h)
        }
    }

    /// Wrapped before narrowing to `Float`: `timeIntervalSinceReferenceDate` is
    /// ~8e8 by now, which leaves a 32-bit float about 60 ms of precision — the
    /// animation would visibly quantise. An hour-long period is far longer than
    /// any motion in the scene, so the wrap is invisible.
    static func shaderTime(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
    }

    // MARK: - Date

    private var dateLabel: some View {
        VStack(spacing: 6) {
            Text(Self.dayString(date))
                .font(.unbounded(128, weight: .regular))
                .kerning(2)
            Text(Self.monthString(date))
                .font(.unbounded(19, weight: .light))
                .kerning(11)
                .padding(.leading, 11)   // compensate the trailing letter-space
        }
        .foregroundStyle(Self.inkColor)
        .shadow(color: params.palette.glow.opacity(0.35), radius: 26)
        .shadow(color: .black.opacity(0.35), radius: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.day().month(.wide)))
    }

    /// Warm ivory rather than white — pure white against a deep blue reads
    /// clinical, and the reference's date is lit by the same warm accent that
    /// the sparks use.
    private static let inkColor = Color(red: 1.0, green: 0.965, blue: 0.885)

    /// The short date lockup is a branded display moment, so it uses Unbounded.
    static func dayString(_ date: Date) -> String {
        date.formatted(.dateTime.day(.defaultDigits))
    }

    static func monthString(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }
}

#Preview {
    GenerativeSceneView(
        params: GenerativeSceneParams(
            energy: 0.62,
            clarity: 0.78,
            events: 0.4,
            seed: 0.31,
            palette: .ocean
        )
    )
    .ignoresSafeArea()
}

import SwiftUI

// MARK: - Energy Signature
//
// Five spotlight rays emanating from the centre — one per energy dimension.
// Each ray's length  = that dimension's weekly average score (0–20 pts).
// Each ray's colour  = the axis colour, with a white-hot gradient at the source.
// Grid rings at 5 / 10 / 15 / 20 provide an absolute visual reference.
// The entire star (rays + labels) slowly rotates clockwise at ~1°/sec.

struct EnergySignatureView: View {

    struct Axis: Identifiable {
        let id: String
        let score: Double    // 0..20
        let color: Color
        let label: String
        let angle: Double    // radians, screen coords (Y-down), base position
    }

    let axes: [Axis]             // exactly 5
    var canvasSize: CGFloat = 220
    /// Override to make the canvas taller than it is wide.
    var canvasHeight: CGFloat? = nil
    /// When `false` only the grid rings + axis labels are drawn.
    /// Spotlight cones, streaks, tip jewels and the centre starburst are omitted
    /// because MeView renders them in a full-screen background canvas (no clip bounds).
    var showSpotlights: Bool = true
    /// Called with the nearest axis when the user taps on the canvas (not on the centre).
    var onAxisTapped: ((Axis) -> Void)? = nil

    // Clockwise rotation speed — 1°/s → full turn in ~6 min
    private let rotationSpeed: Double = 1.0 * .pi / 180

    var body: some View {
        // Capped at 30 fps — animations here are intentionally slow (1°/s
        // rotation, ~11 s breath, ~23 s cone-breath), so there is no visual
        // benefit to redrawing at the display's native rate (60 Hz, or 120 Hz
        // on ProMotion). At 30 fps the GPU does ~4× less work on every blur
        // layer and the per-axis spotlight image draws.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                render(&ctx, size: size, t: t)
            }
            .frame(width: canvasSize, height: canvasHeight ?? canvasSize)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location)
            }
        }
    }

    // MARK: – Tap hit-test

    private func handleTap(at pt: CGPoint) {
        guard let cb = onAxisTapped else { return }
        let cx   = Double(canvasSize / 2)
        let cy   = Double((canvasHeight ?? canvasSize) / 2)   // centre accounts for tall canvas
        let dx   = Double(pt.x) - cx
        let dy   = Double(pt.y) - cy
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > Double(canvasSize) * 0.08 else { return }   // dead-zone at centre
        guard dist < Double(canvasSize) * 0.46 else { return }   // outside radar — ignore

        // Subtract current rotation to bring tap into the base-angle space
        let t = Date.now.timeIntervalSinceReferenceDate
        let tapAngle = atan2(dy, dx) - t * rotationSpeed
        if let best = axes.min(by: { angularDist($0.angle, tapAngle) < angularDist($1.angle, tapAngle) }) {
            cb(best)
        }
    }

    private func angularDist(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d < 0 { d += 2 * .pi }
        return min(d, 2 * .pi - d)
    }

    // MARK: – Geometry

    private let maxScore: Double = 20

    private func frac(_ score: Double) -> Double { max(0, min(1, score / maxScore)) }

    private func tipPt(_ axis: Axis, cx: Double, cy: Double, outerR: Double) -> CGPoint {
        let r = outerR * frac(axis.score)
        return CGPoint(x: cx + cos(axis.angle) * r, y: cy + sin(axis.angle) * r)
    }

    // MARK: – Render

    private func render(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        guard axes.count == 5 else { return }
        let cx = size.width  / 2
        let cy = size.height / 2
        // Outer ring at 70% of half-size — leaves room for labels + glow bleed
        let outerR = min(cx, cy) * 0.70

        // Build rotated axes — angle offset increases at rotationSpeed rad/s
        let rotOff = t * rotationSpeed
        let rotAxes = axes.map { ax in
            Axis(id: ax.id, score: ax.score, color: ax.color,
                 label: ax.label, angle: ax.angle + rotOff)
        }

        drawGrid(&ctx, cx: cx, cy: cy, outerR: outerR, axes: rotAxes)
        if showSpotlights {
            for (i, axis) in rotAxes.enumerated() {
                drawRay(&ctx, axis: axis, idx: i, cx: cx, cy: cy, outerR: outerR, t: t)
            }
            drawCenter(&ctx, cx: cx, cy: cy, outerR: outerR, t: t)
        }
        drawLabels(&ctx, cx: cx, cy: cy, outerR: outerR, axes: rotAxes)
    }

    // MARK: – Grid

    private func drawGrid(_ ctx: inout GraphicsContext,
                           cx: Double, cy: Double, outerR: Double,
                           axes rotAxes: [Axis]) {
        // Concentric rings (fixed — they don't rotate)
        let ringOpacities: [Double] = [0.10, 0.12, 0.14, 0.30]
        let ringWidths:    [Double] = [0.5,  0.5,  0.5,  0.75]
        for i in 1...4 {
            let r = outerR * Double(i) / 4.0
            var p = Path()
            p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.stroke(p,
                       with: .color(.white.opacity(ringOpacities[i - 1])),
                       lineWidth: ringWidths[i - 1])
        }
        // Subtle outer glow on the 20pt ring
        ctx.drawLayer { c in
            c.addFilter(.blur(radius: 2.5))
            c.opacity = 0.20
            var gp = Path()
            gp.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerR,
                                     width: outerR * 2, height: outerR * 2))
            c.stroke(gp, with: .color(.white), lineWidth: 1)
        }
        // 5 sector dividers — rotate with the axes
        for axis in rotAxes {
            var p = Path()
            p.move(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx + cos(axis.angle) * outerR,
                                   y: cy + sin(axis.angle) * outerR))
            ctx.stroke(p, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
        }
        // Ring score labels on the first (Steps) sector divider — also rotates
        let labelAxis = rotAxes[0]
        let ringLabels = ["5", "10", "15", "20"]
        for (i, lbl) in ringLabels.enumerated() {
            let r  = outerR * Double(i + 1) / 4.0 + 4
            let pt = CGPoint(x: cx + cos(labelAxis.angle) * r,
                             y: cy + sin(labelAxis.angle) * r)
            ctx.draw(
                Text(lbl)
                    .font(.system(size: 7.5, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.28)),
                at: pt
            )
        }
    }

    // Spotlight bitmap cache lives in RayShapeRenderer.cachedSpotlight so it can be
    // shared with MeView's full-screen background ray canvas.

    // MARK: – Ray  (RayShapeRenderer spotlight, source at canvas centre, beam along axis.angle)
    //
    // Gradient: white-hot at the source → full axis colour → dark at angular edges.
    // The spotlight bitmap is centred at (cx, cy) and the layer is rotated by
    // (axis.angle − naturalAngle) so the cone fans out along the axis direction.

    private func drawRay(
        _ ctx: inout GraphicsContext,
        axis: Axis, idx: Int,
        cx: Double, cy: Double, outerR: Double,
        t: Double
    ) {
        let f = frac(axis.score)
        guard f > 0.02 else { return }

        let phase   = Double(idx) * (2 * .pi / 5)
        let breathe = CGFloat(1.0 + 0.04 * sin(t * 0.55 + phase))

        // Gradient colours: saturated axis colour at source → full colour → dark edges
        let (r, g, b) = RayShapeRenderer.rgbComponents(axis.color)
        // Wrap before narrowing to Float — see RayShapeRenderer.shaderTimeWrap.
        let shaderTime = RayShapeRenderer.wrapShaderTime(t * 0.6 + phase * 0.4)
        guard let cgImg = RayShapeRenderer.cachedSpotlight(
            id: axis.id, time: shaderTime,
            near: (min(1.0, r * 1.55), min(1.0, g * 1.55), min(1.0, b * 1.55)),  // boosted axis colour at source
            mid:  (r, g, b),                            // axis colour through the beam
            far:  (r * 0.35, g * 0.35, b * 0.35)       // dark at angular edges
        ) else { return }

        let spotImg = Image(decorative: cgImg, scale: 1)

        // The visible cone tip sits at ~55 % of the image half-size from the image centre.
        // Scale up so the tip aligns with outerR × f in screen space.
        let beamR    = CGFloat(outerR * f) * breathe / 0.55
        let anchor   = CGPoint(x: cx, y: cy)
        let spotRect = CGRect(x: cx - beamR, y: cy - beamR, width: beamR * 2, height: beamR * 2)

        // Rotate the layer so the cone points along axis.angle
        let naturalAngle = atan2(Double(cosf(RayShapeRenderer.shaderAim)),
                                 Double(sinf(RayShapeRenderer.shaderAim)))   // ≈ 0.424 rad
        let rotation = Angle.radians(axis.angle - naturalAngle)

        // Pass 1 — wide blurred glow for the diffuse halo around the beam
        ctx.drawLayer { c in
            c.blendMode = .plusLighter
            c.opacity   = 0.40
            c.addFilter(.blur(radius: 10))
            c.translateBy(x: anchor.x, y: anchor.y)
            c.rotate(by: rotation)
            c.translateBy(x: -anchor.x, y: -anchor.y)
            c.draw(spotImg, in: spotRect.insetBy(dx: -beamR * 0.22, dy: -beamR * 0.22))
        }
        // Pass 2 — main spotlight at full brightness
        ctx.drawLayer { c in
            c.blendMode = .plusLighter
            c.opacity   = 1.0
            c.translateBy(x: anchor.x, y: anchor.y)
            c.rotate(by: rotation)
            c.translateBy(x: -anchor.x, y: -anchor.y)
            c.draw(spotImg, in: spotRect)
        }

        // Tip jewel at score endpoint
        let tPt   = tipPt(axis, cx: cx, cy: cy, outerR: outerR)
        let pulse = CGFloat(1.0 + 0.18 * sin(t * 0.9 + phase))
        let dotR  = CGFloat(3.2) * pulse * breathe
        ctx.drawLayer { c in
            c.blendMode = .plusLighter; c.opacity = 0.45
            c.addFilter(.blur(radius: 5))
            c.fill(Path(ellipseIn: CGRect(x: tPt.x - dotR * 2.2, y: tPt.y - dotR * 2.2,
                                          width: dotR * 4.4, height: dotR * 4.4)),
                   with: .color(axis.color))
        }
        ctx.drawLayer { c in
            c.blendMode = .plusLighter; c.opacity = 0.95
            c.fill(Path(ellipseIn: CGRect(x: tPt.x - dotR, y: tPt.y - dotR,
                                          width: dotR * 2, height: dotR * 2)),
                   with: .radialGradient(Gradient(colors: [.white, axis.color.opacity(0.6)]),
                                         center: tPt, startRadius: 0, endRadius: dotR))
        }
    }

    // MARK: – Centre starburst

    private func drawCenter(_ ctx: inout GraphicsContext,
                             cx: Double, cy: Double, outerR: Double, t: Double) {
        let avgF  = axes.reduce(0) { $0 + frac($1.score) } / Double(axes.count)
        let baseR = CGFloat(outerR * 0.07 * (0.3 + 0.7 * avgF))
        let pulse = CGFloat(1.0 + 0.07 * sin(t * 0.45))
        let r     = baseR * pulse

        // Soft coloured halo — each axis contributes its hue additively
        for axis in axes {
            ctx.drawLayer { c in
                c.blendMode = .plusLighter
                c.opacity   = 0.20
                c.addFilter(.blur(radius: 9))
                let gr = r * 5
                c.fill(
                    Path(ellipseIn: CGRect(x: cx - gr, y: cy - gr, width: gr * 2, height: gr * 2)),
                    with: .color(axis.color)
                )
            }
        }

        // Tight core — weighted-average axis colour, no white
        let totalW = max(0.001, axes.reduce(0.0) { $0 + frac($1.score) })
        var rSum = 0.0, gSum = 0.0, bSum = 0.0
        for axis in axes {
            let (ar, ag, ab) = RayShapeRenderer.rgbComponents(axis.color)
            let wt = frac(axis.score) / totalW
            rSum += Double(ar) * wt
            gSum += Double(ag) * wt
            bSum += Double(ab) * wt
        }
        // Scale so the brightest channel hits 1.0 → fully saturated
        let maxC = max(rSum, gSum, bSum, 0.001)
        let boost = min(1.0 / maxC, 2.5)
        let coreColor = Color(red: min(1, rSum * boost),
                              green: min(1, gSum * boost),
                              blue:  min(1, bSum * boost))

        ctx.drawLayer { c in
            c.blendMode = .plusLighter
            c.opacity   = 0.90
            c.fill(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [coreColor, coreColor.opacity(0.5)]),
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0, endRadius: r
                )
            )
        }
    }

    // MARK: – Labels
    //
    // Labels sit inside the outer ring, near each tip jewel.
    // Placement rules:
    //   • radial position = (tip radius − 18 pt), so the label
    //     is clearly inside the dot without being on top of it
    //   • min = 40 % outerR → always readable even at score = 0,
    //     and adjacent labels (72° apart) never overlap
    //   • max = 82 % outerR → text bounding box stays inside ring
    //     at every angle (widest label ~30 pt, half = 15 pt;
    //     0.82 × outerR + 15 < outerR ✓)

    private func drawLabels(_ ctx: inout GraphicsContext,
                             cx: Double, cy: Double, outerR: Double,
                             axes rotAxes: [Axis]) {
        let minLR = outerR * 0.40   // floor: readable even at score = 0
        let maxLR = outerR * 0.78   // ceiling: larger font needs a tighter cap so text
                                    // stays inside the ring (half-width ≈ 21 pt at 13 pt)

        let font = Font.system(size: 13, weight: .semibold)

        for axis in rotAxes {
            let f  = frac(axis.score)
            let r  = max(minLR, min(maxLR, outerR * f - 20))
            let pt = CGPoint(x: cx + cos(axis.angle) * r,
                             y: cy + sin(axis.angle) * r)

            // Pass 1 — dark drop-shadow for contrast over the bright centre glow
            ctx.draw(
                Text(axis.label).font(font)
                    .foregroundStyle(Color.black.opacity(0.65)),
                at: CGPoint(x: pt.x + 0.5, y: pt.y + 1.0)
            )
            // Pass 2 — white label
            ctx.draw(
                Text(axis.label).font(font)
                    .foregroundStyle(Color.white.opacity(0.95)),
                at: pt
            )
        }
    }
}

// MARK: - Static constants

extension EnergySignatureView {

    static let stepsColor = Color(red: 1.0,  green: 0.83, blue: 0.41)
    static let sleepColor = Color(red: 0.32, green: 0.42, blue: 0.82)
    static let bodyColor  = AppColors.Night.body
    static let heartColor = AppColors.Night.heart
    static let mindColor  = AppColors.Night.mind

    // Pentagon with Mind at bottom (screen Y-down coords)
    static let stepsAngle: Double = -54  * .pi / 180  // upper-right
    static let sleepAngle: Double = -126 * .pi / 180  // upper-left
    static let bodyAngle:  Double =  162 * .pi / 180  // lower-left
    static let heartAngle: Double =   18 * .pi / 180  // lower-right
    static let mindAngle:  Double =   90 * .pi / 180  // bottom
}

// MARK: - Factory

extension EnergySignatureView {

    static func makeAxes(
        from snaps: [PastDaySnapshot],
        avgSteps: Int,
        avgSleep: Double
    ) -> [Axis] {
        guard !snaps.isEmpty else { return zeroAxes() }
        let days  = Double(snaps.count)
        let snap0 = snaps[0]

        let stepsScore = min(20.0, Double(avgSteps) / max(1,   snap0.stepsTarget)       * 20)
        let sleepScore = min(20.0, avgSleep          / max(0.1, snap0.sleepTargetHours)  * 20)
        let bodyScore  = min(20.0, Double(snaps.flatMap(\.bodyIds).count)  / days * 5)
        let heartScore = min(20.0, Double(snaps.flatMap(\.heartIds).count) / days * 5)
        let mindScore  = min(20.0, Double(snaps.flatMap(\.mindIds).count)  / days * 5)

        return makeAxes(steps: stepsScore, sleep: sleepScore,
                        body: bodyScore, heart: heartScore, mind: mindScore)
    }

    static func makeAxes(
        steps: Double, sleep: Double,
        body: Double, heart: Double, mind: Double
    ) -> [Axis] {
        [
            Axis(id: "steps", score: steps, color: stepsColor, label: "Steps", angle: stepsAngle),
            Axis(id: "sleep", score: sleep, color: sleepColor, label: "Sleep", angle: sleepAngle),
            Axis(id: "body",  score: body,  color: bodyColor,  label: "Body",  angle: bodyAngle),
            Axis(id: "heart", score: heart, color: heartColor, label: "Heart", angle: heartAngle),
            Axis(id: "mind",  score: mind,  color: mindColor,  label: "Mind",  angle: mindAngle),
        ]
    }

    static func zeroAxes() -> [Axis] {
        makeAxes(steps: 0, sleep: 0, body: 0, heart: 0, mind: 0)
    }
}

// MARK: - Previews

#Preview("Balanced week") {
    ZStack {
        Color(red: 0.13, green: 0.16, blue: 0.19).ignoresSafeArea()
        EnergySignatureView(
            axes: EnergySignatureView.makeAxes(steps: 16, sleep: 15, body: 12, heart: 10, mind: 18),
            canvasSize: 300
        )
    }
}

#Preview("Steps + Body heavy") {
    ZStack {
        Color(red: 0.13, green: 0.16, blue: 0.19).ignoresSafeArea()
        EnergySignatureView(
            axes: EnergySignatureView.makeAxes(steps: 20, sleep: 14, body: 18, heart: 6, mind: 4),
            canvasSize: 300
        )
    }
}

#Preview("Mind week") {
    ZStack {
        Color(red: 0.13, green: 0.16, blue: 0.19).ignoresSafeArea()
        EnergySignatureView(
            axes: EnergySignatureView.makeAxes(steps: 8, sleep: 12, body: 4, heart: 14, mind: 20),
            canvasSize: 300
        )
    }
}

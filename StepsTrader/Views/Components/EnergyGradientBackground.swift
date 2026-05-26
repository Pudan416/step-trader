import SwiftUI

// MARK: - Shared Energy Gradient Renderer
/// Single source of truth for the energy gradient opacity model and drawing.
/// Referenced by both `EnergyGradientBackground` (view) and `GenerativeCanvasView` (canvas).
///
/// Spec: Data-Driven Energy Gradient (Steps + Sleep)
/// Palette (unchanged): Gold #FFBF65 → Coral #FD8973 → Navy #003A6C → Night #13181B
/// Inputs: stepsPoints (0…20), sleepPoints (0…20), hasStepsData, hasSleepData
enum EnergyGradientRenderer {

    // MARK: - Palette

    struct Palette {
        let bright: Color       // steps-driven (gold role)
        let warm: Color         // mid-warm (coral role)
        let cool: Color         // sleep-driven mid (navy role)
        let dark: Color         // sleep-driven edge (night role)
    }

    private static let palettes: [GradientPalette: Palette] = [
        .warmSunset: Palette(
            bright: Color(hex: "#FFBF65"),
            warm:   Color(hex: "#FD8973"),
            cool:   Color(hex: "#003A6C"),
            dark:   Color(hex: "#002646")
        ),
        .ocean: Palette(
            bright: Color(hex: "#7FDBDA"),
            warm:   Color(hex: "#3A9FBF"),
            cool:   Color(hex: "#1A4B6E"),
            dark:   Color(hex: "#0B1E33")
        ),
        .aurora: Palette(
            bright: Color(hex: "#C4B5FD"),
            warm:   Color(hex: "#7C6FBF"),
            cool:   Color(hex: "#1F6E5C"),
            dark:   Color(hex: "#0F1B2D")
        ),
        .dusk: Palette(
            bright: Color(hex: "#EEDDC9"),
            warm:   Color(hex: "#C0AC98"),
            cool:   Color(hex: "#5E7282"),
            dark:   Color(hex: "#384856")
        ),
        .dawn: Palette(
            bright: Color(hex: "#EBBFC8"),
            warm:   Color(hex: "#B87A92"),
            cool:   Color(hex: "#4A3568"),
            dark:   Color(hex: "#181430")
        ),
        .ember: Palette(
            bright: Color(hex: "#F07838"),
            warm:   Color(hex: "#D04428"),
            cool:   Color(hex: "#2E1858"),
            dark:   Color(hex: "#0C0A22")
        ),
        .horizon: Palette(
            bright: Color(hex: "#D0A440"),
            warm:   Color(hex: "#2898A8"),
            cool:   Color(hex: "#105868"),
            dark:   Color(hex: "#0A2832")
        ),
    ]

    static func palette(for scheme: GradientPalette) -> Palette {
        palettes[scheme] ?? palettes[.warmSunset] ?? Palette(
            bright: Color(hex: "#FFBF65"),
            warm:   Color(hex: "#FD8973"),
            cool:   Color(hex: "#003A6C"),
            dark:   Color(hex: "#002646")
        )
    }

    // Backward-compat statics (warmSunset default)
    static let gold  = Color(hex: "#FFBF65")
    static let coral = Color(hex: "#FD8973")
    static let navy  = Color(hex: "#003A6C")
    static let night = Color(hex: "#002646")

    // MARK: - Math Helpers

    /// Hermite smoothstep — avoids linear "dead" midrange.
    /// `smooth(x) = x² (3 − 2x)`
    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3.0 - 2.0 * t)
    }

    /// Linear interpolation: `a + (b − a) * t`
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    // MARK: - Blob Layout

    struct Blob {
        let x: Double      // normalized 0…1
        let y: Double
        let radius: Double  // fraction of maxReach
        let color: Color
        let opacity: Double
        var blendMode: GraphicsContext.BlendMode = .plusLighter
        var skewAngle: Double = 0
    }

    /// Day seed: same value all day, changes at midnight.
    static var daySeed: UInt64 {
        UInt64(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 1)
    }

    /// Generate organic blob layout from opacities + day seed.
    static func organicBlobs(
        opacities: Opacities,
        seed: UInt64,
        palette p: Palette? = nil
    ) -> [Blob] {
        let pal = p ?? palette(for: .warmSunset)
        var rng = SeededRNG(seed: seed)
        var blobs: [Blob] = []

        for _ in 0..<2 {
            blobs.append(Blob(
                x: rng.nextDouble(in: 0.0...1.0),
                y: rng.nextDouble(in: 0.0...1.0),
                radius: rng.nextDouble(in: 0.5...0.8),
                color: pal.dark,
                opacity: opacities.night * rng.nextDouble(in: 0.6...1.0)
            ))
        }

        for _ in 0..<2 {
            blobs.append(Blob(
                x: rng.nextDouble(in: 0.05...0.95),
                y: rng.nextDouble(in: 0.05...0.95),
                radius: rng.nextDouble(in: 0.35...0.6),
                color: pal.cool,
                opacity: opacities.navy * rng.nextDouble(in: 0.5...0.9)
            ))
        }

        for _ in 0..<2 {
            blobs.append(Blob(
                x: rng.nextDouble(in: 0.1...0.9),
                y: rng.nextDouble(in: 0.1...0.9),
                radius: rng.nextDouble(in: 0.25...0.5),
                color: pal.warm,
                opacity: opacities.coral * rng.nextDouble(in: 0.4...0.8)
            ))
        }

        for _ in 0..<2 {
            blobs.append(Blob(
                x: rng.nextDouble(in: 0.15...0.85),
                y: rng.nextDouble(in: 0.15...0.85),
                radius: rng.nextDouble(in: 0.2...0.4),
                color: pal.bright,
                opacity: opacities.gold * rng.nextDouble(in: 0.5...0.9)
            ))
        }

        return blobs
    }

    /// Generate a structured 4×3 grid of blobs that blend into a mesh-like gradient.
    /// Positions are deterministic per day (seed) but perturbed so each day feels unique.
    /// Colors are distributed across the grid with warm tones near center, cool at edges.
    static func meshBlobs(
        opacities: Opacities,
        seed: UInt64,
        palette p: Palette? = nil
    ) -> [Blob] {
        let pal = p ?? palette(for: .warmSunset)
        var rng = SeededRNG(seed: seed)
        var styleRng = SeededRNG(seed: seed &+ 0xCAFE_BABE)
        var blobs: [Blob] = []

        let meshBlendPool: [GraphicsContext.BlendMode] = [
            .plusLighter, .plusLighter, .plusLighter, .colorDodge, .softLight, .screen
        ]

        let cols = 3
        let rows = 4

        let sN = opacities.stepsNorm
        let lN = opacities.sleepNorm

        let colorPool: [Color] = [pal.bright, pal.warm, pal.cool, pal.dark]

        for row in 0..<rows {
            for col in 0..<cols {
                let baseX = Double(col) / Double(cols - 1)
                let baseY = Double(row) / Double(rows - 1)

                let px = baseX + rng.nextDouble(in: -0.14...0.14)
                let py = baseY + rng.nextDouble(in: -0.10...0.10)

                let distFromCenter = sqrt(pow(px - 0.5, 2) + pow(py - 0.5, 2))

                let roll = rng.nextDouble()
                let pick: Int
                if distFromCenter < 0.22 {
                    pick = roll < 0.65 ? 0 : 1
                } else if distFromCenter < 0.42 {
                    pick = roll < 0.35 ? 0 : (roll < 0.70 ? 1 : 2)
                } else {
                    pick = roll < 0.20 ? 0 : (roll < 0.50 ? 1 : (roll < 0.80 ? 2 : 3))
                }

                let color = colorPool[pick]
                let opacity: Double
                switch pick {
                case 0: opacity = (0.35 + sN * 0.60) * rng.nextDouble(in: 0.65...1.0)
                case 1: opacity = (0.35 + sN * 0.45 + lN * 0.10) * rng.nextDouble(in: 0.65...1.0)
                case 2: opacity = (0.25 + lN * 0.50 + sN * 0.05) * rng.nextDouble(in: 0.65...1.0)
                default: opacity = (0.20 + lN * 0.45) * rng.nextDouble(in: 0.65...1.0)
                }
                let radius = rng.nextDouble(in: 0.40...0.65)

                blobs.append(Blob(
                    x: px, y: py, radius: radius, color: color, opacity: opacity,
                    blendMode: meshBlendPool[Int(styleRng.next() % UInt64(meshBlendPool.count))],
                    skewAngle: styleRng.nextDouble(in: -0.5...0.5)
                ))
            }
        }

        return blobs
    }

    // MARK: - Opacity Model

    struct Opacities {
        let gold: Double
        let coral: Double
        let navy: Double
        let night: Double
        let glow: Double

        // Gradient stop locations — how much radius each color band occupies.
        let goldLoc: Double    // gold starts at 0.0, ends here
        let coralLoc: Double   // coral ends here
        let navyLoc: Double    // navy ends here (night fills the rest → 1.0)

        /// Raw smoothed norms (0…1) for styles that need continuous per-point response.
        let stepsNorm: Double
        let sleepNorm: Double
    }

    /// Compute per-stop opacities from **already-smoothed** normalized values.
    ///
    /// - Parameters:
    ///   - smoothedS: Smoothstep-curved normalized steps value (0…1).
    ///   - smoothedL: Smoothstep-curved normalized sleep value (0…1).
    ///   - hasStepsData: Whether HealthKit has returned step data (not inferred from points).
    ///   - hasSleepData: Whether HealthKit has returned sleep data (not inferred from points).
    static func computeOpacities(
        smoothedS Ss: Double,
        smoothedL Ls: Double,
        hasStepsData: Bool,
        hasSleepData: Bool
    ) -> Opacities {

        // ── Stop locations: each color's share of the radius ──────
        // Rebalanced: warm colors (gold+coral) take up to 65% of radius at full data,
        // so the dark ring no longer dominates due to radial area math (area ∝ r²).
        // Steps-only: warm colors push to ~80% of radius (mirror of sleep-only darkness).
        let stepsOnly = hasStepsData && !hasSleepData
        let goldShare  = stepsOnly ? Ss * 0.42 : Ss * 0.35
        let coralShare = stepsOnly ? 0.38 : 0.30
        let navyShare  = stepsOnly ? max(Ls * 0.20, 0.16) : max(Ls * 0.20, 0.08)

        let goldLoc  = goldShare
        let coralLoc = goldLoc + coralShare
        let navyLoc  = coralLoc + navyShare

        // ── Data-driven opacities ───────────────

        // ── 6.1  Gold (steps-driven, off when no steps data) ─────────
        let goldOp: Double
        if !hasStepsData {
            goldOp = 0
        } else {
            goldOp = lerp(0.55, 0.95, Ss)
        }

        // ── 6.2  Coral (brand warmth — sleep no longer crushes it) ──
        let coralOp: Double
        if !hasStepsData && !hasSleepData {
            coralOp = 0.68
        } else if hasSleepData && !hasStepsData {
            coralOp = lerp(0.35, 0.50, 1.0 - Ls)
        } else if hasStepsData && !hasSleepData {
            coralOp = lerp(0.55, 0.85, Ss)
        } else {
            coralOp = lerp(0.55, 0.85, Ss) * lerp(1.00, 0.92, Ls)
        }

        // ── 6.3  Navy (sleep-driven ring — pulled back so it doesn't dominate) ──
        let navyOp: Double
        if !hasStepsData && !hasSleepData {
            navyOp = 0.42
        } else if hasSleepData && !hasStepsData {
            navyOp = lerp(0.42, 0.55, Ls)
        } else if hasStepsData && !hasSleepData {
            navyOp = lerp(0.08, 0.14, Ss)
        } else {
            navyOp = lerp(0.28, 0.48, Ls)
        }

        // ── 6.4  Night (edge darkness — lighter so warm center breathes) ──
        var nightOp: Double
        if !hasSleepData {
            nightOp = !hasStepsData ? 0.08 : 0.03
        } else {
            nightOp = lerp(0.28, 0.45, Ls)
        }
        // Sleep-only: still darker but not as oppressive
        if hasSleepData && !hasStepsData {
            nightOp = lerp(0.40, 0.55, Ls)
        }

        // ── 7  Secondary center glow (boosted to punch through dark) ──
        let glowOp: Double
        if !hasStepsData && !hasSleepData {
            glowOp = 0.35
        } else if hasSleepData && !hasStepsData {
            glowOp = 0.25
        } else if hasStepsData && !hasSleepData {
            glowOp = lerp(0.50, 0.80, Ss)
        } else {
            glowOp = lerp(0.30, 0.60, Ss) * lerp(1.00, 0.85, Ls)
        }

        return Opacities(
            gold: goldOp,
            coral: coralOp,
            navy: navyOp,
            night: nightOp,
            glow: glowOp,
            goldLoc: goldLoc,
            coralLoc: coralLoc,
            navyLoc: navyLoc,
            stepsNorm: Ss,
            sleepNorm: Ls
        )
    }

    // MARK: - Drawing

    /// Draw the energy gradient into a `GraphicsContext`.
    /// Pass `time` (seconds since reference date) to enable drift animation for `.mesh`.
    /// Nil = static frame (used by ImageRenderer, widgets, thumbnails).
    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        opacities: Opacities,
        baseColor: Color = night,
        gradientStyle: GradientStyle = .radial,
        colorPalette: Palette? = nil,
        time: Double? = nil
    ) {
        let pal = colorPalette ?? palette(for: .warmSunset)
        let w = Double(size.width)
        let h = Double(size.height)
        let dim = min(w, h)
        let center = CGPoint(x: w * 0.5, y: h * 0.5)
        let maxReach = max(w, h)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        context.fill(Path(rect), with: .color(baseColor))

        let gradient = Gradient(stops: [
            .init(color: pal.bright.opacity(opacities.gold),  location: 0.00),
            .init(color: pal.warm.opacity(opacities.coral),   location: opacities.goldLoc),
            .init(color: pal.cool.opacity(opacities.navy),    location: opacities.coralLoc),
            .init(color: pal.dark.opacity(opacities.night),   location: opacities.navyLoc),
            .init(color: pal.dark.opacity(opacities.night),   location: 1.00),
        ])

        switch gradientStyle {
        case .radial:
            context.fill(
                Path(rect),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: maxReach * 0.85)
            )
        case .radialReversed:
            let reversed = Gradient(stops: [
                .init(color: pal.dark.opacity(opacities.night),   location: 0.00),
                .init(color: pal.cool.opacity(opacities.navy),    location: 1.0 - opacities.navyLoc),
                .init(color: pal.warm.opacity(opacities.coral),   location: 1.0 - opacities.goldLoc),
                .init(color: pal.bright.opacity(opacities.gold),  location: 1.00),
            ])
            context.fill(
                Path(rect),
                with: .radialGradient(reversed, center: center, startRadius: 0, endRadius: maxReach * 0.85)
            )
        case .linear:
            let lin = Gradient(stops: [
                .init(color: pal.dark.opacity(opacities.night),   location: 0.00),
                .init(color: pal.dark.opacity(opacities.night),   location: 1.0 - opacities.navyLoc),
                .init(color: pal.cool.opacity(opacities.navy),    location: 1.0 - opacities.coralLoc),
                .init(color: pal.warm.opacity(opacities.coral),   location: 1.0 - opacities.goldLoc),
                .init(color: pal.bright.opacity(opacities.gold),  location: 1.00),
            ])
            context.fill(
                Path(rect),
                with: .linearGradient(lin, startPoint: CGPoint(x: w * 0.5, y: 0), endPoint: CGPoint(x: w * 0.5, y: h))
            )
        case .linearReversed:
            let linR = Gradient(stops: [
                .init(color: pal.bright.opacity(opacities.gold),  location: 0.00),
                .init(color: pal.warm.opacity(opacities.coral),   location: opacities.goldLoc),
                .init(color: pal.cool.opacity(opacities.navy),    location: opacities.coralLoc),
                .init(color: pal.dark.opacity(opacities.night),   location: opacities.navyLoc),
                .init(color: pal.dark.opacity(opacities.night),   location: 1.00),
            ])
            context.fill(
                Path(rect),
                with: .linearGradient(linR, startPoint: CGPoint(x: w * 0.5, y: 0), endPoint: CGPoint(x: w * 0.5, y: h))
            )
        case .organic:
            let blobs = organicBlobs(opacities: opacities, seed: daySeed, palette: pal)
            for blob in blobs {
                let cx = blob.x * w
                let cy = blob.y * h
                let r = blob.radius * maxReach
                let blobGrad = Gradient(colors: [
                    blob.color.opacity(blob.opacity),
                    blob.color.opacity(blob.opacity * 0.4),
                    blob.color.opacity(0),
                ])
                context.drawLayer { ctx in
                    ctx.blendMode = .plusLighter
                    ctx.fill(
                        Ellipse().path(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(blobGrad, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r)
                    )
                }
            }
        case .angular:
            let t = time ?? 0
            var angRng = SeededRNG(seed: daySeed &+ 0xAA09)
            let segmentCount = 6 + angRng.nextInt(in: 0...2)

            let sN = opacities.stepsNorm
            let lN = opacities.sleepNorm

            var colors: [Color] = []
            for _ in 0..<segmentCount {
                let isWarm = angRng.next() % 2 == 0
                if isWarm {
                    let pick = angRng.next() % 2 == 0 ? pal.bright : pal.warm
                    colors.append(pick.opacity(0.35 + sN * 0.60))
                } else {
                    let pick = angRng.next() % 2 == 0 ? pal.cool : pal.dark
                    colors.append(pick.opacity(0.25 + lN * 0.50))
                }
            }
            colors.append(colors[0])

            let angle = Angle.degrees((t * 4).truncatingRemainder(dividingBy: 360))
            let maxR = max(w, h) * 0.9
            let sweepRect = CGRect(x: center.x - maxR, y: center.y - maxR, width: maxR * 2, height: maxR * 2)

            context.fill(
                Ellipse().path(in: sweepRect),
                with: .conicGradient(Gradient(colors: colors), center: center, angle: angle)
            )

            let glowStrength = 0.25 + sN * 0.35 + lN * 0.15
            let glow = Gradient(colors: [
                pal.bright.opacity(glowStrength),
                pal.warm.opacity(glowStrength * 0.5),
                pal.cool.opacity(lN * 0.25),
                .clear,
            ])
            context.drawLayer { ctx in
                ctx.blendMode = .plusLighter
                ctx.fill(
                    Ellipse().path(in: sweepRect),
                    with: .radialGradient(glow, center: center, startRadius: 0, endRadius: maxR * 0.65)
                )
            }
        case .mesh:
            let meshBlobs = meshBlobs(opacities: opacities, seed: daySeed, palette: pal)
            for (i, blob) in meshBlobs.enumerated() {
                let phase = Double(i) * 0.73
                let phase2 = Double(i) * 1.37
                let dx: Double
                let dy: Double
                let scalePulse: Double
                if let t = time {
                    dx = sin(t * 0.12 + phase) * 0.06
                        + sin(t * 0.07 + phase2) * 0.03
                    dy = cos(t * 0.10 + phase * 1.4) * 0.05
                        + cos(t * 0.06 + phase2 * 0.8) * 0.025
                    scalePulse = 1.0 + sin(t * 0.08 + phase) * 0.08
                } else {
                    dx = 0; dy = 0; scalePulse = 1.0
                }
                let cx = (blob.x + dx) * w
                let cy = (blob.y + dy) * h
                let r = blob.radius * maxReach * scalePulse
                let blobGrad = Gradient(colors: [
                    blob.color.opacity(blob.opacity),
                    blob.color.opacity(blob.opacity * 0.45),
                    blob.color.opacity(blob.opacity * 0.08),
                    blob.color.opacity(0),
                ])
                let stretchX = 1.0 + abs(blob.skewAngle) * 0.6
                let rotationDrift = time.map { t in blob.skewAngle + sin(t * 0.09 + phase) * 0.25 } ?? blob.skewAngle
                context.drawLayer { ctx in
                    ctx.blendMode = blob.blendMode
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: .radians(rotationDrift))
                    ctx.scaleBy(x: stretchX, y: 1.0)
                    ctx.fill(
                        Ellipse().path(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                        with: .radialGradient(blobGrad, center: .zero, startRadius: 0, endRadius: r)
                    )
                }
            }
        }

        if gradientStyle == .organic || gradientStyle == .mesh || gradientStyle == .angular { return }

        let secondaryGrad = Gradient(colors: [
            pal.bright.opacity(opacities.glow * 0.6),
            pal.warm.opacity(opacities.glow * 0.25),
            .clear,
        ])

        switch gradientStyle {
        case .radial:
            let glowRadius = dim * 0.5
            let shading = GraphicsContext.Shading.radialGradient(secondaryGrad, center: center, startRadius: 0, endRadius: glowRadius)
            context.drawLayer { ctx in
                ctx.fill(Ellipse().path(in: CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)), with: shading)
            }
        case .radialReversed:
            let ringGrad = Gradient(colors: [.clear, pal.warm.opacity(opacities.glow * 0.2), pal.bright.opacity(opacities.glow * 0.5)])
            let ringRadius = maxReach * 0.85
            let shading = GraphicsContext.Shading.radialGradient(ringGrad, center: center, startRadius: 0, endRadius: ringRadius)
            context.drawLayer { ctx in ctx.fill(Path(rect), with: shading) }
        case .linear:
            let glowH = h * 0.4
            let shading = GraphicsContext.Shading.linearGradient(secondaryGrad, startPoint: CGPoint(x: w * 0.5, y: h), endPoint: CGPoint(x: w * 0.5, y: h - glowH))
            context.drawLayer { ctx in ctx.fill(Path(CGRect(x: 0, y: h - glowH, width: w, height: glowH)), with: shading) }
        case .linearReversed:
            let glowH = h * 0.4
            let shading = GraphicsContext.Shading.linearGradient(secondaryGrad, startPoint: CGPoint(x: w * 0.5, y: 0), endPoint: CGPoint(x: w * 0.5, y: glowH))
            context.drawLayer { ctx in ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: glowH)), with: shading) }
        case .organic, .mesh, .angular:
            break
        }
    }
}

// MARK: - Animatable Modifier
/// Smoothly interpolates `stepsNorm` and `sleepNorm` frame-by-frame
/// using SwiftUI's `Animatable` protocol, so the Canvas redraws at every
/// intermediate value during a 0.8 s easeInOut transition.

private struct EnergyGradientAnimator: ViewModifier, Animatable {
    var stepsNorm: Double
    var sleepNorm: Double
    var hasStepsData: Bool
    var hasSleepData: Bool
    var gradientStyle: GradientStyle
    var gradientPalette: GradientPalette

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(stepsNorm, sleepNorm) }
        set {
            stepsNorm = newValue.first
            sleepNorm = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let pal = EnergyGradientRenderer.palette(for: gradientPalette)
        Canvas { context, size in
            let Ss = EnergyGradientRenderer.smoothstep(stepsNorm)
            let Ls = EnergyGradientRenderer.smoothstep(sleepNorm)
            let opacities = EnergyGradientRenderer.computeOpacities(
                smoothedS: Ss,
                smoothedL: Ls,
                hasStepsData: hasStepsData,
                hasSleepData: hasSleepData
            )
            EnergyGradientRenderer.draw(
                context: &context,
                size: size,
                opacities: opacities,
                baseColor: pal.dark,
                gradientStyle: gradientStyle,
                colorPalette: pal
            )
        }
    }
}

/// Dedicated animated gradient view for styles that need continuous TimelineView updates.
/// Separated from `EnergyGradientAnimator` because `Animatable` suppresses TimelineView redraws.
private struct AnimatedGradientView: View {
    let stepsNorm: Double
    let sleepNorm: Double
    let hasStepsData: Bool
    let hasSleepData: Bool
    let gradientStyle: GradientStyle
    let gradientPalette: GradientPalette

    @State private var stepsOrigin: Double = 0
    @State private var stepsTarget: Double = 0
    @State private var stepsTransStart: TimeInterval = 0

    @State private var sleepOrigin: Double = 0
    @State private var sleepTarget: Double = 0
    @State private var sleepTransStart: TimeInterval = 0

    private static let transDuration: Double = 0.8

    private func eased(_ origin: Double, _ target: Double, _ start: TimeInterval, _ now: TimeInterval) -> Double {
        guard now > start else { return target }
        let progress = min((now - start) / Self.transDuration, 1.0)
        let e = progress * progress * (3 - 2 * progress)
        return origin + (target - origin) * e
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let smoothSteps = eased(stepsOrigin, stepsTarget, stepsTransStart, t)
            let smoothSleep = eased(sleepOrigin, sleepTarget, sleepTransStart, t)
            let pal = EnergyGradientRenderer.palette(for: gradientPalette)
            Canvas { context, size in
                let Ss = EnergyGradientRenderer.smoothstep(smoothSteps)
                let Ls = EnergyGradientRenderer.smoothstep(smoothSleep)
                let opacities = EnergyGradientRenderer.computeOpacities(
                    smoothedS: Ss,
                    smoothedL: Ls,
                    hasStepsData: hasStepsData,
                    hasSleepData: hasSleepData
                )
                EnergyGradientRenderer.draw(
                    context: &context,
                    size: size,
                    opacities: opacities,
                    baseColor: pal.dark,
                    gradientStyle: gradientStyle,
                    colorPalette: pal,
                    time: t
                )
            }
        }
        .onAppear {
            stepsOrigin = stepsNorm
            stepsTarget = stepsNorm
            sleepOrigin = sleepNorm
            sleepTarget = sleepNorm
        }
        .onChange(of: stepsNorm) { _, newValue in
            let now = Date().timeIntervalSinceReferenceDate
            stepsOrigin = eased(stepsOrigin, stepsTarget, stepsTransStart, now)
            stepsTarget = newValue
            stepsTransStart = now
        }
        .onChange(of: sleepNorm) { _, newValue in
            let now = Date().timeIntervalSinceReferenceDate
            sleepOrigin = eased(sleepOrigin, sleepTarget, sleepTransStart, now)
            sleepTarget = newValue
            sleepTransStart = now
        }
    }
}

// MARK: - EnergyGradientBackground View
/// Shared energy gradient + grain background used by every tab.
///
/// Usage (preferred):
/// ```
/// ScrollView { ... }
///     .energyGradientBackground(model: model)
/// ```
struct EnergyGradientBackground: View {
    let stepsPoints: Int
    let sleepPoints: Int
    let hasStepsData: Bool
    let hasSleepData: Bool
    var showGrain: Bool = true
    var gradientStyleOverride: String? = nil
    var gradientPaletteOverride: String? = nil
    var textureOverride: String? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SharedKeys.gradientStyle) private var gradientStyleRaw: String = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette) private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue

    private var gradientStyle: GradientStyle {
        if let override = gradientStyleOverride, let style = GradientStyle(rawValue: override) {
            return style
        }
        return GradientStyle(rawValue: gradientStyleRaw) ?? .radial
    }

    private var gradientPaletteValue: GradientPalette {
        if let override = gradientPaletteOverride {
            return GradientPalette.normalized(rawValue: override)
        }
        return GradientPalette.normalized(rawValue: gradientPaletteRaw)
    }

    private var stepsNorm: Double {
        Double(min(max(stepsPoints, 0), 20)) / 20.0
    }
    private var sleepNorm: Double {
        Double(min(max(sleepPoints, 0), 20)) / 20.0
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        gradientContent
            .ignoresSafeArea()
            .overlay {
                if showGrain && !reduceTransparency {
                    let raw = textureOverride ?? canvasTextureRaw
                    let texture = CanvasTexture.fromStored(raw)
                    TextureOverlayView(texture: texture)
                }
            }
    }

    @ViewBuilder
    private var gradientContent: some View {
        if gradientStyle.isAnimated && !reduceMotion {
            AnimatedGradientView(
                stepsNorm: stepsNorm,
                sleepNorm: sleepNorm,
                hasStepsData: hasStepsData,
                hasSleepData: hasSleepData,
                gradientStyle: gradientStyle,
                gradientPalette: gradientPaletteValue
            )
        } else {
            Color.clear
                .modifier(EnergyGradientAnimator(
                    stepsNorm: stepsNorm,
                    sleepNorm: sleepNorm,
                    hasStepsData: hasStepsData,
                    hasSleepData: hasSleepData,
                    gradientStyle: gradientStyle,
                    gradientPalette: gradientPaletteValue
                ))
                .animation(.easeInOut(duration: 0.8), value: stepsPoints)
                .animation(.easeInOut(duration: 0.8), value: sleepPoints)
                .animation(.easeInOut(duration: 0.8), value: hasStepsData)
                .animation(.easeInOut(duration: 0.8), value: hasSleepData)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the shared energy gradient background behind this view.
    /// Replaces the repeated ZStack + EnergyGradientBackground boilerplate.
    func energyGradientBackground(model: AppModel, showGrain: Bool = true) -> some View {
        background {
            EnergyGradientBackground(
                stepsPoints: model.stepsPointsToday,
                sleepPoints: model.sleepPointsToday,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData,
                showGrain: showGrain
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Previews (4 required states)

#Preview("A) No Data") {
    EnergyGradientBackground(
        stepsPoints: 0,
        sleepPoints: 0,
        hasStepsData: false,
        hasSleepData: false
    )
}

#Preview("B) Sleep Only (20)") {
    EnergyGradientBackground(
        stepsPoints: 0,
        sleepPoints: 20,
        hasStepsData: false,
        hasSleepData: true
    )
}

#Preview("C) Steps Only (20)") {
    EnergyGradientBackground(
        stepsPoints: 20,
        sleepPoints: 0,
        hasStepsData: true,
        hasSleepData: false
    )
}

#Preview("D) Ideal (20 + 20)") {
    EnergyGradientBackground(
        stepsPoints: 20,
        sleepPoints: 20,
        hasStepsData: true,
        hasSleepData: true
    )
}

#Preview("E) Mesh Animated") {
    EnergyGradientBackground(
        stepsPoints: 15,
        sleepPoints: 10,
        hasStepsData: true,
        hasSleepData: true,
        gradientStyleOverride: GradientStyle.mesh.rawValue
    )
}

#Preview("F) Angular Animated") {
    EnergyGradientBackground(
        stepsPoints: 18,
        sleepPoints: 8,
        hasStepsData: true,
        hasSleepData: true,
        gradientStyleOverride: GradientStyle.angular.rawValue
    )
}

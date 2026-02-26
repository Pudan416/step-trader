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
        let daylightBase: Color // light-mode background tint
    }

    static func palette(for scheme: GradientPalette) -> Palette {
        switch scheme {
        case .warmSunset:
            return Palette(
                bright: Color(hex: "#FFBF65"),
                warm:   Color(hex: "#FD8973"),
                cool:   Color(hex: "#003A6C"),
                dark:   Color(hex: "#002646"),
                daylightBase: Color(hex: "#F2DCC8")
            )
        case .roseGarden:
            return Palette(
                bright: Color(hex: "#FFB0C4"),
                warm:   Color(hex: "#D4627A"),
                cool:   Color(hex: "#1B5E3B"),
                dark:   Color(hex: "#0C2318"),
                daylightBase: Color(hex: "#F5E0E6")
            )
        case .ember:
            return Palette(
                bright: Color(hex: "#FFF0A0"),
                warm:   Color(hex: "#E8864A"),
                cool:   Color(hex: "#7A1A1A"),
                dark:   Color(hex: "#2A0808"),
                daylightBase: Color(hex: "#FFF5E0")
            )
        case .dusk:
            return Palette(
                bright: Color(hex: "#EEDDC9"),
                warm:   Color(hex: "#C0AC98"),
                cool:   Color(hex: "#5E7282"),
                dark:   Color(hex: "#384856"),
                daylightBase: Color(hex: "#F2EAE0")
            )
        }
    }

    // Backward-compat statics (warmSunset default)
    static let gold  = Color(hex: "#FFBF65")
    static let coral = Color(hex: "#FD8973")
    static let navy  = Color(hex: "#003A6C")
    static let night = Color(hex: "#002646")
    static let daylightBase = Color(hex: "#F2DCC8")

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

    // MARK: - Seeded RNG (deterministic per-day)

    /// LCG-based PRNG — lightweight, deterministic, no framework deps.
    struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 1 : seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        mutating func nextDouble() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
        mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
            range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
        }
    }

    struct Blob {
        let x: Double      // normalized 0…1
        let y: Double
        let radius: Double  // fraction of maxReach
        let color: Color
        let opacity: Double
    }

    /// Day seed: same value all day, changes at midnight.
    static var daySeed: UInt64 {
        UInt64(Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 1)
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
    }

    /// Compute per-stop opacities from **already-smoothed** normalized values.
    ///
    /// - Parameters:
    ///   - smoothedS: Smoothstep-curved normalized steps value (0…1).
    ///   - smoothedL: Smoothstep-curved normalized sleep value (0…1).
    ///   - hasStepsData: Whether HealthKit has returned step data (not inferred from points).
    ///   - hasSleepData: Whether HealthKit has returned sleep data (not inferred from points).
    ///   - isDaylight: When true, all stops are fully opaque for vibrant saturated colors.
    static func computeOpacities(
        smoothedS Ss: Double,
        smoothedL Ls: Double,
        hasStepsData: Bool,
        hasSleepData: Bool,
        isDaylight: Bool = false
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

        // Daylight: warm center, darker edges for depth/contrast.
        if isDaylight {
            return Opacities(
                gold:  hasStepsData ? 0.85 : 0,
                coral: 0.9,
                navy:  0.82,
                night: 0.85,
                glow:  hasStepsData ? 0.65 : 0.4,
                goldLoc: goldLoc,
                coralLoc: coralLoc,
                navyLoc: navyLoc
            )
        }

        // ── Night mode: original data-driven opacities ───────────────

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
            navyLoc: navyLoc
        )
    }

    // MARK: - Drawing

    /// Draw the energy gradient into a `GraphicsContext`.
    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        opacities: Opacities,
        baseColor: Color = night,
        gradientStyle: GradientStyle = .radial,
        colorPalette: Palette? = nil
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
        }

        if gradientStyle == .organic { return }

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
        case .organic:
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
    var isDaylight: Bool
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
                hasSleepData: hasSleepData,
                isDaylight: isDaylight
            )
            EnergyGradientRenderer.draw(
                context: &context,
                size: size,
                opacities: opacities,
                baseColor: isDaylight ? pal.daylightBase : pal.dark,
                gradientStyle: gradientStyle,
                colorPalette: pal
            )
        }
    }
}

// MARK: - EnergyGradientBackground View
/// Shared energy gradient + grain background used by every tab.
///
/// Usage:
/// ```
/// EnergyGradientBackground(
///     stepsPoints: model.stepsPointsToday,
///     sleepPoints: model.sleepPointsToday,
///     hasStepsData: model.hasStepsData,
///     hasSleepData: model.hasSleepData
/// )
/// ```
struct EnergyGradientBackground: View {
    let stepsPoints: Int
    let sleepPoints: Int
    let hasStepsData: Bool
    let hasSleepData: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("gradientStyle_v1") private var gradientStyleRaw: String = GradientStyle.radial.rawValue
    @AppStorage("gradientPalette_v1") private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue

    private var isDaylight: Bool {
        switch theme {
        case .daylight: return true
        case .night: return false
        case .system: return colorScheme == .light
        }
    }

    private var gradientStyle: GradientStyle {
        GradientStyle(rawValue: gradientStyleRaw) ?? .radial
    }

    private var gradientPaletteValue: GradientPalette {
        GradientPalette(rawValue: gradientPaletteRaw) ?? .warmSunset
    }

    private var stepsNorm: Double {
        Double(min(max(stepsPoints, 0), 20)) / 20.0
    }
    private var sleepNorm: Double {
        Double(min(max(sleepPoints, 0), 20)) / 20.0
    }

    var body: some View {
        Color.clear
            .modifier(EnergyGradientAnimator(
                stepsNorm: stepsNorm,
                sleepNorm: sleepNorm,
                hasStepsData: hasStepsData,
                hasSleepData: hasSleepData,
                isDaylight: isDaylight,
                gradientStyle: gradientStyle,
                gradientPalette: gradientPaletteValue
            ))
            .animation(.easeInOut(duration: 0.8), value: stepsPoints)
            .animation(.easeInOut(duration: 0.8), value: sleepPoints)
            .animation(.easeInOut(duration: 0.8), value: hasStepsData)
            .animation(.easeInOut(duration: 0.8), value: hasSleepData)
            .animation(.easeInOut(duration: 0.8), value: isDaylight)
            .ignoresSafeArea()
            .overlay {
                Image("grain 1")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(0.4)
                    .blendMode(.overlay)
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

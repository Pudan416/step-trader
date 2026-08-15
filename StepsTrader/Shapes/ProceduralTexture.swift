import SwiftUI

// MARK: - Kind

/// How the inside of a form is filled.
///
/// Every element used to get the same radial gradient, which is why a full
/// canvas read as one object repeated. These five give a canvas forms that are
/// flat, graded, ringed, hatched or stippled — and `TextureSpec.uniformity`
/// lets each of them read as even or as strongly graded across the form.
enum TextureKind: String, Codable, CaseIterable, Hashable {
    case flat       // solid colour, no falloff — the contrast anchor
    case gradient   // the existing radial falloff
    case rings      // concentric copies of the contour, stroked
    case hatch      // parallel lines clipped to the contour
    case stipple    // Poisson dot field inside the contour
}

// MARK: - Spec

/// Parameters of a fill. Doubles as a cache key, so its `Hashable` conformance
/// quantises: raw `Double` equality would miss the cache on every slider tick.
struct TextureSpec: Codable, Hashable {
    var kind: TextureKind
    /// How much of the fill there is — line count, dot count, ring count.
    var density: Double
    /// `1` = even across the form, `0` = strongly graded by a noise field.
    var uniformity: Double
    /// Direction, used by `hatch` and by the gradient's offset.
    var angle: Double

    init(kind: TextureKind, density: Double, uniformity: Double, angle: Double) {
        self.kind = kind
        self.density = min(max(density, 0), 1)
        self.uniformity = min(max(uniformity, 0), 1)
        self.angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
            + (angle < 0 ? 2 * .pi : 0)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, density, uniformity, angle
    }

    /// Hand-written so decoded values still go through the clamping
    /// initialiser above — the synthesised `init(from:)` would assign the
    /// raw decoded Doubles directly and bypass it. Task 6 constructs specs
    /// from derived values (e.g. a slider position saved out of range by an
    /// older build), so this has to hold on decode, not just on construction.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(TextureKind.self, forKey: .kind),
            density: try container.decode(Double.self, forKey: .density),
            uniformity: try container.decode(Double.self, forKey: .uniformity),
            angle: try container.decode(Double.self, forKey: .angle)
        )
    }

    /// Sensible randomised parameters for a kind.
    static func seeded(kind: TextureKind, seed: UInt64) -> TextureSpec {
        var rng = SeededRNG.derived(from: seed, domain: "texture")
        return TextureSpec(
            kind: kind,
            density: rng.nextDouble(in: 0.3...1.0),
            uniformity: rng.nextDouble(in: 0.0...1.0),
            angle: rng.nextDouble(in: 0...(2 * .pi))
        )
    }

    // Quantise to 1e-4 so cache lookups survive floating-point drift.
    private var quantised: [Int] {
        [Int((density * 10_000).rounded()),
         Int((uniformity * 10_000).rounded()),
         Int((angle * 10_000).rounded())]
    }

    static func == (lhs: TextureSpec, rhs: TextureSpec) -> Bool {
        lhs.kind == rhs.kind && lhs.quantised == rhs.quantised
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(quantised)
    }
}

// MARK: - Geometry

struct RadialTextureProfile: Hashable {
    let center: CGPoint
    let outerRadius: Double
    let radii: [Double]

    init(center: CGPoint, sourceRadii: [CGFloat], rotation: Double) {
        precondition(sourceRadii.count >= 3)
        precondition(sourceRadii.allSatisfy { $0.isFinite && $0 > 0 })
        self.center = center

        let count = sourceRadii.count
        let resampled = (0..<count).map { index in
            let worldAngle = Double(index) / Double(count) * 2 * .pi
            var localAngle = (worldAngle - rotation)
                .truncatingRemainder(dividingBy: 2 * .pi)
            if localAngle < 0 { localAngle += 2 * .pi }
            let position = localAngle / (2 * .pi) * Double(count)
            let lower = Int(floor(position)) % count
            let upper = (lower + 1) % count
            let fraction = position - floor(position)
            let value = Double(sourceRadii[lower])
                + (Double(sourceRadii[upper]) - Double(sourceRadii[lower])) * fraction
            return value
        }
        let outer = resampled.max() ?? 1
        precondition(outer.isFinite && outer > 0)
        self.outerRadius = outer
        self.radii = resampled.map { $0 / outer }
    }

    static func circle(
        center: CGPoint,
        radius: Double,
        sampleCount: Int = 48
    ) -> RadialTextureProfile {
        RadialTextureProfile(
            center: center,
            sourceRadii: [CGFloat](repeating: CGFloat(radius), count: sampleCount),
            rotation: 0)
    }
}

/// The cacheable output of a fill, in **unit space**: the contour's radius is
/// `1.0`, so one cached texture serves the icon, the canvas and a 4K export.
struct TextureGeometry: Hashable {
    /// Normalised radii per nested ring, outermost first.
    var rings: [[Double]] = []
    /// Hatch segments, unit space.
    var lines: [Line] = []
    /// Stipple dots: centre and radius, unit space.
    var dots: [Dot] = []

    struct Line: Hashable {
        var start: CGPoint
        var end: CGPoint
    }

    struct Dot: Hashable {
        var center: CGPoint
        var radius: Double
    }
}

// MARK: - Generator

enum ProceduralTexture {

    // Budget ceilings, enforced by ProceduralTextureTests.
    private static let maxDots = 90
    private static let maxLines = 40
    private static let maxRings = 8

    /// Pure. `radii` is the element's contour from
    /// `ProceduralShapeGenerator.organicBlobRadiusFactor`.
    static func geometry(
        spec: TextureSpec,
        radii: [Double],
        seed: UInt64
    ) -> TextureGeometry {
        switch spec.kind {
        case .flat, .gradient:
            return TextureGeometry()
        case .rings:
            return TextureGeometry(rings: ringGeometry(spec: spec, radii: radii))
        case .hatch:
            return TextureGeometry(lines: hatchGeometry(spec: spec, radii: radii, seed: seed))
        case .stipple:
            return TextureGeometry(dots: stippleGeometry(spec: spec, radii: radii, seed: seed))
        }
    }

    // MARK: Rings

    /// Concentric copies of the contour, each strictly inside the last.
    /// `uniformity` controls the spacing: even rings versus rings that bunch
    /// towards the edge.
    private static func ringGeometry(spec: TextureSpec, radii: [Double]) -> [[Double]] {
        let count = max(3, min(maxRings, Int((spec.density * Double(maxRings)).rounded())))
        var rings = [[Double]]()
        rings.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i + 1) / Double(count + 1)
            // Even spacing at uniformity 1, edge-weighted at 0.
            let eased = spec.uniformity * t + (1 - spec.uniformity) * (t * t)
            let scale = 1.0 - eased * 0.85     // never reaches the centre
            rings.append(radii.map { $0 * scale })
        }
        return rings
    }

    // MARK: Hatch

    /// Parallel chords across the contour at `spec.angle`. Each scanline is
    /// clipped to the contour by walking the radius at both ends, which works
    /// because the contour is star-shaped (Task 2 guarantees a positive radius).
    private static func hatchGeometry(
        spec: TextureSpec,
        radii: [Double],
        seed: UInt64
    ) -> [TextureGeometry.Line] {
        let count = max(4, min(maxLines, Int((spec.density * Double(maxLines)).rounded())))
        let noise = SimplexNoise2D(seed: seed)

        let cosA = cos(spec.angle)
        let sinA = sin(spec.angle)

        // Offsets and spans cover the circumscribing circle, not the
        // inscribed one. Clipping the inscribed circle left hatch as a small
        // central patch inside a large low-opacity wash — with contour radii
        // spanning [0.68, 1.32] the covered fraction was ~40%. The
        // circumscribing radius guarantees every chord still fully covers
        // the star-shaped contour at its angle; `draw` clips the strokes to
        // the actual contour, the same way `stipple` already does.
        let outer = radii.max() ?? 1

        var lines = [TextureGeometry.Line]()
        lines.reserveCapacity(count)

        for i in 0..<count {
            let t = (Double(i) + 0.5) / Double(count)
            let offset = (t * 2 - 1) * outer

            // uniformity 1 → every line drawn; 0 → the noise field drops some,
            // so the hatch thins out across the form. Only thin a hatch that
            // has lines to spare: below 8 the dropout would leave too few to
            // read as a fill at all.
            if spec.uniformity < 1, count > 8 {
                let keep = (noise.value(offset * 1.7, 0.5) + 1) / 2
                if keep < (1 - spec.uniformity) * 0.5 { continue }
            }

            let span = (outer * outer - offset * offset).squareRoot()

            // The perpendicular axis carries the offset; the line runs along
            // `spec.angle`.
            let baseX = -sinA * offset
            let baseY = cosA * offset
            lines.append(TextureGeometry.Line(
                start: CGPoint(x: baseX - cosA * span, y: baseY - sinA * span),
                end:   CGPoint(x: baseX + cosA * span, y: baseY + sinA * span)
            ))
        }
        return lines
    }

    // MARK: Stipple

    /// A Poisson dot field inside the contour. `uniformity` decides whether the
    /// density is even or driven by a noise gradient across the form.
    private static func stippleGeometry(
        spec: TextureSpec,
        radii: [Double],
        seed: UInt64
    ) -> [TextureGeometry.Dot] {
        var rng = SeededRNG.derived(from: seed, domain: "stipple")
        let noise = SimplexNoise2D(seed: seed &+ 0x57)

        // Denser spec → smaller spacing → more dots.
        let spacing = 0.34 - spec.density * 0.22        // 0.34 … 0.12
        let bounds = CGRect(x: -1, y: -1, width: 2, height: 2)

        // `fill`'s weight is a Bernoulli accept gate on candidates, and the
        // loop keeps trying until the active list is exhausted or maxPoints
        // is hit — a rejected candidate only delays placement, since another
        // one lands nearby moments later. Final density there is governed by
        // `minDistance`, not by weight, so gating candidates during
        // generation cannot produce a density *gradient*. Containment is all
        // `fill`'s weight does here; the uniformity gradient is a second,
        // independent thinning pass below, applied after the point set
        // already exists.
        let raw = PoissonDiscSampler.fill(
            bounds: bounds,
            minDistance: spacing,
            maxPoints: maxDots,
            weight: { point in containsPoint(point, radii: radii) ? 1 : 0 },
            using: &rng
        )

        // A separate stream so thinning doesn't perturb the placement
        // sequence above.
        var thinRng = SeededRNG.derived(from: seed, domain: "stipple-thin")

        return raw
            .filter { containsPoint($0, radii: radii) }
            .compactMap { point -> TextureGeometry.Dot? in
                if spec.uniformity < 1 {
                    // A dot where the noise field is low survives rarely; one
                    // where it is high survives outright — this is what
                    // actually makes the field bunch to one side, which
                    // gating during generation could not do. The frequency is
                    // low (0.4, not the 1.3 used elsewhere) on purpose: the
                    // stipple domain is only ~2 units across, and at 1.3 that
                    // fits several noise lobes per half, so a left/right split
                    // averages them out — over 18 calibration seeds it never
                    // produced a visible bunch. At 0.4 one lobe dominates the
                    // whole form, which is what "bunches to one side" means.
                    let n = (noise.value(Double(point.x) * 0.4, Double(point.y) * 0.4) + 1) / 2
                    let survive = spec.uniformity + (1 - spec.uniformity) * n
                    guard thinRng.nextDouble() < survive else { return nil }
                }
                // Dots shrink towards the rim so the fill has an interior.
                let distance = Double(hypot(point.x, point.y))
                let falloff = 1.0 - min(1.0, distance) * 0.55
                return TextureGeometry.Dot(
                    center: point,
                    radius: max(0.008, spacing * 0.28 * falloff)
                )
            }
    }

    /// Star-shaped containment test: compare the point's radius against the
    /// contour's radius at the point's angle.
    private static func containsPoint(_ point: CGPoint, radii: [Double]) -> Bool {
        guard !radii.isEmpty else { return false }
        let angle = atan2(Double(point.y), Double(point.x))
        let normalised = angle < 0 ? angle + 2 * .pi : angle
        let index = Int(normalised / (2 * .pi) * Double(radii.count)) % radii.count
        return Double(hypot(point.x, point.y)) <= radii[index]
    }

    // MARK: - Drawing

    /// Draws a cached texture into a context. Scaling happens here, so one
    /// cached `TextureGeometry` serves every size.
    static func draw(
        _ geometry: TextureGeometry,
        spec: TextureSpec,
        contour: Path,
        context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        color: Color,
        color2: Color?,
        gradientCenter: CGPoint
    ) {
        let second = color2 ?? color

        switch spec.kind {
        case .flat:
            context.fill(contour, with: .color(color.opacity(0.72)))

        case .gradient:
            let stops = color2 == nil
                ? [color.opacity(0.8), color.opacity(0.3), color.opacity(0)]
                : [color.opacity(0.8), second.opacity(0.4), second.opacity(0)]
            context.fill(contour, with: .radialGradient(
                Gradient(colors: stops), center: gradientCenter,
                startRadius: 0, endRadius: radius))

        case .rings:
            // A soft base so the rings read as structure on a body, not as
            // floating outlines.
            context.fill(contour, with: .color(color.opacity(0.18)))
            for (index, ring) in geometry.rings.enumerated() {
                let path = ProceduralShapeGenerator.closedPath(
                    radii: ring, center: center, radius: radius)
                let fade = 1.0 - Double(index) / Double(max(1, geometry.rings.count)) * 0.5
                context.stroke(
                    path,
                    with: .color((index.isMultiple(of: 2) ? color : second)
                        .opacity(0.55 * fade)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }

        case .hatch:
            context.fill(contour, with: .color(color.opacity(0.14)))
            var strokes = Path()
            for line in geometry.lines {
                strokes.move(to: CGPoint(
                    x: center.x + line.start.x * radius,
                    y: center.y + line.start.y * radius))
                strokes.addLine(to: CGPoint(
                    x: center.x + line.end.x * radius,
                    y: center.y + line.end.y * radius))
            }
            // Scanlines span the circumscribing circle (see `hatchGeometry`),
            // so clip to the contour here, the same way `stipple` clips its
            // dot field below. Scoped to a nested layer so the clip cannot
            // leak onto the caller's later drawing.
            context.drawLayer { strokeCtx in
                strokeCtx.clip(to: contour)
                strokeCtx.stroke(strokes, with: .color(second.opacity(0.6)),
                                 style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }

        case .stipple:
            context.fill(contour, with: .color(color.opacity(0.12)))
            // One accumulated Path, one fill — 90 separate fills would blow
            // the frame budget.
            var field = Path()
            for dot in geometry.dots {
                let r = dot.radius * radius
                field.addEllipse(in: CGRect(
                    x: center.x + dot.center.x * radius - r,
                    y: center.y + dot.center.y * radius - r,
                    width: r * 2, height: r * 2))
            }
            // A rim dot's centre is inside the contour but its own radius
            // can still push part of the ellipse outside it — clip so the
            // fill never spills past the form. Scoped to a nested layer so
            // the clip doesn't leak onto the stroke drawn after this call
            // returns.
            context.drawLayer { fieldCtx in
                fieldCtx.clip(to: contour)
                fieldCtx.fill(field, with: .color(second.opacity(0.75)))
            }
        }
    }
}

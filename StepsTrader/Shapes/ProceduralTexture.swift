import SwiftUI

// MARK: - Kind

/// How the inside of a form is filled.
///
/// Every element used to get the same radial gradient, which is why a full
/// canvas read as one object repeated. These four let forms read as flat,
/// graded, ringed or hatched — and `TextureSpec.uniformity`
/// lets each of them read as even or as strongly graded across the form.
enum TextureKind: String, Codable, CaseIterable, Hashable {
    case flat       // solid colour, no falloff — the contrast anchor
    case gradient   // the existing radial falloff
    case rings      // concentric copies of the contour, stroked
    case hatch      // parallel lines clipped to the contour
}

// MARK: - Spec

/// Parameters of a fill. Doubles as a cache key, so its `Hashable` conformance
/// quantises: raw `Double` equality would miss the cache on every slider tick.
struct TextureSpec: Codable, Hashable {
    var kind: TextureKind
    /// How much of the fill there is — line count or ring count.
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
    /// The immutable source contour's maximum radius.
    let outerRadius: Double
    /// World-angle samples divided by `outerRadius`. Every value is in
    /// `(0, 1]`; the sampled maximum can be below `1` when fractional rotation
    /// places the source peak between two fixed world-angle samples.
    let radii: [Double]

    init(center: CGPoint, outerRadius: Double, radii: [Double]) {
        precondition(center.x.isFinite && center.y.isFinite)
        precondition(outerRadius.isFinite && outerRadius > 0)
        precondition(radii.count >= 3)
        precondition(radii.allSatisfy { $0.isFinite && $0 > 0 })
        precondition((radii.max() ?? .infinity) <= 1 + 1e-12)

        self.center = center
        self.outerRadius = outerRadius
        self.radii = radii
    }

    init(center: CGPoint, sourceRadii: [CGFloat], rotation: Double) {
        precondition(rotation.isFinite)
        precondition(sourceRadii.count >= 3)
        precondition(sourceRadii.allSatisfy { $0.isFinite && $0 > 0 })
        let sourceOuterRadius = Double(sourceRadii.max() ?? 0)

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
        self.init(
            center: center,
            outerRadius: sourceOuterRadius,
            radii: resampled.map { $0 / sourceOuterRadius })
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

/// Separates cached geometry belonging to different radial shape families.
enum TextureGeometryFamily: UInt8, Hashable {
    case organicBlob
    case circle
    case snowflake
}

/// The cacheable output of a fill, in **unit space**: the contour's radius is
/// `1.0`, so one cached texture serves the icon, the canvas and a 4K export.
struct TextureGeometry: Hashable {
    /// Normalised radii per nested ring, outermost first.
    var rings: [[Double]] = []
    /// Hatch segments, unit space.
    var lines: [Line] = []

    struct Line: Hashable {
        var start: CGPoint
        var end: CGPoint
    }

}

// MARK: - Generator

enum ProceduralTexture {

    // Budget ceilings, enforced by ProceduralTextureTests.
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
        // the actual contour.
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
            // so clip to the contour here. Scoped to a nested layer so it cannot
            // leak onto the caller's later drawing.
            context.drawLayer { strokeCtx in
                strokeCtx.clip(to: contour)
                strokeCtx.stroke(strokes, with: .color(second.opacity(0.6)),
                                 style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }

        }
    }
}

import SwiftUI

enum FloaterKind { case body, mind, heart }

struct OnboardingFloater: Identifiable {
    let id: Int
    let asset: String?
    let kind: FloaterKind
    let baseX: CGFloat
    let baseY: CGFloat
    let size: CGFloat
    let phase: Double
    let speed: Double
    let rotation: Double
    let tintColor: Color
    let appearsAtSlide: Int
    let shapeSeed: UInt64
}

func generateFloaters(count: Int, totalSlides: Int) -> [OnboardingFloater] {
    let mindAssets = CanvasImageCatalog.mind
    let heartAssets = CanvasImageCatalog.heart

    let kinds: [FloaterKind] = [.body, .heart, .body, .mind, .body, .heart, .mind, .body, .heart]
    let bodyTints: [Color] = [
        Color(red: 0.30, green: 0.80, blue: 0.50),
        Color(red: 1.00, green: 0.75, blue: 0.30),
        Color(red: 0.60, green: 0.40, blue: 0.90),
        Color(red: 0.30, green: 0.75, blue: 0.85),
        Color(red: 1.00, green: 0.45, blue: 0.55),
        Color(red: 0.85, green: 0.55, blue: 0.90),
        Color(red: 0.50, green: 0.90, blue: 0.60),
        Color(red: 0.40, green: 0.60, blue: 1.00),
        Color(red: 0.95, green: 0.55, blue: 0.35),
    ]

    let maxAppearSlide = min(7, totalSlides)

    var floaters: [OnboardingFloater] = []
    var seed: UInt64 = 42

    let nextRandom: () -> Double = {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
    }

    var mindIdx = 0
    var heartIdx = 0
    var bodyColorIdx = 0

    for i in 0..<count {
        let slide = (i % maxAppearSlide) + 2
        let kind = kinds[i % kinds.count]
        let asset: String?
        let tint: Color
        switch kind {
        case .body:
            asset = nil
            tint = bodyTints[bodyColorIdx % bodyTints.count]
            bodyColorIdx += 1
        case .mind:
            asset = mindAssets[mindIdx % mindAssets.count]
            mindIdx += 1
            tint = .clear
        case .heart:
            asset = heartAssets[heartIdx % heartAssets.count]
            heartIdx += 1
            tint = .clear
        }

        let positions: [(CGFloat, CGFloat)] = [
            (0.15, 0.18), (0.82, 0.35), (0.25, 0.65),
            (0.75, 0.12), (0.50, 0.80), (0.10, 0.42),
            (0.88, 0.60), (0.35, 0.25), (0.65, 0.72),
        ]
        let pos = positions[i % positions.count]
        let shapeSeed = UInt64(i * 7919 + 42)

        floaters.append(OnboardingFloater(
            id: i,
            asset: asset,
            kind: kind,
            baseX: pos.0,
            baseY: pos.1,
            size: CGFloat(120 + nextRandom() * 140),
            phase: nextRandom() * .pi * 2,
            speed: 0.3 + nextRandom() * 0.5,
            rotation: nextRandom() * .pi * 2,
            tintColor: tint,
            appearsAtSlide: slide,
            shapeSeed: shapeSeed
        ))
    }
    return floaters.sorted { $0.appearsAtSlide < $1.appearsAtSlide }
}

// MARK: - Body: procedural blob with bubble rim (matches canvas)

private func bodyBlobPath(seed: UInt64, size: CGFloat, phase: Double, t: Double) -> Path {
    let pointCount = 20
    let cx = size / 2
    let cy = size / 2
    let r = size / 2
    let timeOffset = t * 0.05

    var hashState = seed
    func nextNoise() -> Double {
        hashState = hashState &* 6364136223846793005 &+ 1442695040888963407
        return Double(hashState >> 11) / Double(1 << 53)
    }

    var points = [CGPoint]()
    for i in 0..<pointCount {
        let angle = (Double(i) / Double(pointCount)) * 2 * .pi
        let n1 = sin(angle * 3.0 + timeOffset + Double(nextNoise()) * 6.28) * 0.12
        let n2 = sin(angle * 5.0 + timeOffset * 1.3 + phase) * 0.06
        let displacement = 1.0 + n1 + n2
        let x = cx + CGFloat(cos(angle) * displacement) * r
        let y = cy + CGFloat(sin(angle) * displacement) * r
        points.append(CGPoint(x: x, y: y))
    }

    var path = Path()
    guard points.count >= 3 else { return path }
    path.move(to: CGPoint(
        x: (points.last!.x + points[0].x) / 2,
        y: (points.last!.y + points[0].y) / 2
    ))
    for i in 0..<points.count {
        let next = points[(i + 1) % points.count]
        let mid = CGPoint(x: (points[i].x + next.x) / 2, y: (points[i].y + next.y) / 2)
        path.addQuadCurve(to: mid, control: points[i])
    }
    path.closeSubpath()
    return path
}

// MARK: - Mind: Lissajous drift position (matches canvas mind movement)

private func mindDriftPosition(f: OnboardingFloater, size: CGSize, t: Double) -> CGPoint {
    let s = 0.03 + f.speed * 0.04
    let p = f.phase
    let freq = (
        fx1: 1.0  + sin(p * 1000.0 * 0.11) * 0.15,
        fx2: 2.2  + sin(p * 1000.0 * 0.23) * 0.3,
        fy1: 0.85 + cos(p * 1000.0 * 0.17) * 0.15,
        fy2: 2.0  + cos(p * 1000.0 * 0.31) * 0.3
    )
    let mod = sin(t * s * 0.13 + p * 3.7) * sin(t * s * 0.07 + p * 1.3)
    let env = 0.7 + 0.3 * mod

    let nx = Double(f.baseX)
        + sin(t * s * freq.fx1 + p) * 0.18 * env
        + sin(t * s * freq.fx2 + p * 2.3) * 0.07 * env
    let ny = Double(f.baseY)
        + cos(t * s * freq.fy1 + p * 1.7) * 0.16 * env
        + cos(t * s * freq.fy2 + p * 3.1) * 0.06 * env

    let margin = 0.06
    return CGPoint(
        x: min(1.0 - margin, max(margin, nx)) * size.width,
        y: min(1.0 - margin, max(margin, ny)) * size.height
    )
}

private func mindDriftRotation(f: OnboardingFloater, size: CGSize, t: Double) -> Angle {
    let s = 0.03 + f.speed * 0.04
    let p = f.phase
    let vx = cos(t * s + p) * s
    let vy = cos(t * s * 0.83 + p * 1.7) * (-s * 0.83)
    return Angle.radians(atan2(vy, vx) + .pi)
}

// MARK: - Rendering

@ViewBuilder
func floaterView(f: OnboardingFloater, t: Double, size: CGSize) -> some View {
    switch f.kind {
    case .body:
        let breathe = 1.0 + sin(t * (0.3 + f.speed * 0.3) + f.phase) * 0.04
        let s = f.size * breathe
        Canvas { context, canvasSize in
            let path = bodyBlobPath(seed: f.shapeSeed, size: canvasSize.width, phase: f.phase, t: t)
            let r = canvasSize.width / 2
            let innerR = max(0, r - 30)
            let edgeLoc = r > 0 ? innerR / r : 0
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            let rimGrad = Gradient(stops: [
                .init(color: f.tintColor.opacity(0.04), location: 0),
                .init(color: f.tintColor.opacity(0.04), location: Double(edgeLoc)),
                .init(color: f.tintColor.opacity(0.30), location: Double(edgeLoc) + (1.0 - Double(edgeLoc)) * 0.5),
                .init(color: f.tintColor.opacity(0.50), location: 1.0),
            ])
            context.drawLayer { ctx in
                ctx.blendMode = .plusLighter
                ctx.fill(path, with: .radialGradient(rimGrad, center: center, startRadius: 0, endRadius: r))
            }
        }
        .frame(width: s, height: s)
        .position(
            x: f.baseX * size.width,
            y: f.baseY * size.height
        )

    case .mind:
        if let asset = f.asset {
            let pos = mindDriftPosition(f: f, size: size, t: t)
            let rot = mindDriftRotation(f: f, size: size, t: t)
            let breathe = sin(t * (0.25 + f.phase * 0.1) + f.phase * 3.7)
            let opacity = 0.76 + breathe * 0.04

            let trailCount = 3
            let trailSpacing = 1.5
            ForEach(0..<trailCount, id: \.self) { i in
                let pastT = t - Double(trailCount - i) * trailSpacing
                let ghostPos = mindDriftPosition(f: f, size: size, t: pastT)
                let progress = Double(trailCount - i) / Double(trailCount)
                let ghostOpacity = 0.30 * (1.0 - progress)
                let ghostScale = 1.0 - progress * 0.15

                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: f.size * ghostScale, height: f.size * ghostScale)
                    .opacity(ghostOpacity)
                    .rotationEffect(rot)
                    .position(ghostPos)
            }

            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: f.size, height: f.size)
                .opacity(opacity)
                .rotationEffect(rot)
                .position(pos)
        }

    case .heart:
        if let asset = f.asset {
            let cx = f.baseX * size.width
            let cy = f.baseY * size.height
            let wobbleX = sin(t * 0.012 + f.phase) * size.width * 0.004
                + sin(t * 0.007 + f.phase * 2.3) * size.width * 0.002
            let wobbleY = cos(t * 0.010 + f.phase * 1.3) * size.height * 0.004
                + cos(t * 0.006 + f.phase * 0.7) * size.height * 0.002
            let anchor = CGPoint(x: cx + wobbleX, y: cy + wobbleY)

            let canvasCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let dx = canvasCenter.x - anchor.x
            let dy = canvasCenter.y - anchor.y
            let inwardAngle = Angle.radians(atan2(Double(dy), Double(dx)))

            let sweepRange = 10.0 + f.speed * 5.0
            let sweep = Angle.degrees(sin(t * 0.012 + f.phase * 2.1) * sweepRange)
            let rotation = inwardAngle + .degrees(90) + sweep

            let breathe = 0.92 + sin(t * f.speed * 0.5 + f.phase) * 0.06
            let raySize = f.size * 2.0

            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: raySize, height: raySize)
                .opacity(breathe)
                .rotationEffect(rotation)
                .position(anchor)
        }
    }
}

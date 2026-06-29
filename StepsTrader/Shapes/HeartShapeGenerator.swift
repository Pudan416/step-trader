import SwiftUI
import UIKit

extension ProceduralShapeGenerator {

    struct HeartRay {
        let path: Path
        let tipPoint: CGPoint
    }

    /// Generates 3-4 soft tapered ray shapes fanning out from `origin` toward
    /// `direction`. Each ray is a filled wedge with curved edges.
    static func heartRays(
        seed: UInt64,
        complexity: Double = 0.0,
        time: Double = 0,
        origin: CGPoint,
        direction: CGPoint,
        reach: CGFloat
    ) -> [HeartRay] {
        var rng = SeededRNG(seed: seed)
        let count = 3 + rng.nextInt(in: 0...1)

        let totalSpread = 0.5 + complexity * 0.3
        let startAngle = atan2(Double(direction.y), Double(direction.x))

        var rays = [HeartRay]()
        rays.reserveCapacity(count)

        for i in 0..<count {
            let t = count == 1 ? 0.5 : Double(i) / Double(count - 1)
            let angle = startAngle + (t - 0.5) * totalSpread
            let jitter = rng.nextDouble(in: -0.06...0.06)
            let rayAngle = angle + jitter

            let lengthFactor = rng.nextCGFloat(in: 0.7...1.0)
            let rayLength = reach * lengthFactor

            let baseHalfWidth = rayLength * rng.nextCGFloat(in: 0.10...0.18)

            let wobblePhase = rng.nextDouble(in: 0...(2 * .pi))
            let wobbleAmount = CGFloat(sin(time * 0.4 + wobblePhase)) * rayLength * 0.015

            let cosA = CGFloat(cos(rayAngle))
            let sinA = CGFloat(sin(rayAngle))
            let normX = -sinA
            let normY = cosA

            let tip = CGPoint(
                x: origin.x + cosA * rayLength + normX * wobbleAmount,
                y: origin.y + sinA * rayLength + normY * wobbleAmount
            )

            let baseL = CGPoint(
                x: origin.x + normX * baseHalfWidth,
                y: origin.y + normY * baseHalfWidth
            )
            let baseR = CGPoint(
                x: origin.x - normX * baseHalfWidth,
                y: origin.y - normY * baseHalfWidth
            )

            let midT: CGFloat = 0.45
            let midWidth = baseHalfWidth * 0.45
            let midPoint = CGPoint(
                x: origin.x + cosA * rayLength * midT + normX * wobbleAmount * midT,
                y: origin.y + sinA * rayLength * midT + normY * wobbleAmount * midT
            )
            let midL = CGPoint(x: midPoint.x + normX * midWidth, y: midPoint.y + normY * midWidth)
            let midR = CGPoint(x: midPoint.x - normX * midWidth, y: midPoint.y - normY * midWidth)

            var path = Path()
            path.move(to: baseL)
            path.addQuadCurve(to: midL, control: CGPoint(
                x: (baseL.x + midL.x) / 2 + normX * baseHalfWidth * 0.15,
                y: (baseL.y + midL.y) / 2 + normY * baseHalfWidth * 0.15
            ))
            path.addQuadCurve(to: tip, control: CGPoint(
                x: (midL.x + tip.x) / 2 + normX * midWidth * 0.2,
                y: (midL.y + tip.y) / 2 + normY * midWidth * 0.2
            ))
            path.addQuadCurve(to: midR, control: CGPoint(
                x: (tip.x + midR.x) / 2 - normX * midWidth * 0.2,
                y: (tip.y + midR.y) / 2 - normY * midWidth * 0.2
            ))
            path.addQuadCurve(to: baseR, control: CGPoint(
                x: (midR.x + baseR.x) / 2 - normX * baseHalfWidth * 0.15,
                y: (midR.y + baseR.y) / 2 - normY * baseHalfWidth * 0.15
            ))
            path.closeSubpath()

            rays.append(HeartRay(path: path, tipPoint: tip))
        }
        return rays
    }

    static func heartGradientColors(seed: UInt64, baseHex: String) -> [Color] {
        var rng = SeededRNG(seed: seed &+ 0xBEEF)
        let base = UIColor(Color(hex: baseHex))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let count = 3 + rng.nextInt(in: 0...1)
        var colors = [Color]()
        colors.reserveCapacity(count)

        for i in 0..<count {
            let hueShift = rng.nextCGFloat(in: -0.12...0.12)
            let satShift = rng.nextCGFloat(in: -0.15...0.1)
            let briShift = rng.nextCGFloat(in: -0.1...0.15)

            let newH = (h + hueShift).truncatingRemainder(dividingBy: 1.0)
            let newS = min(1, max(0.15, s + satShift))
            let newB = min(1, max(0.3, b + briShift))

            let opacity = i == 0 ? 0.75 : rng.nextCGFloat(in: 0.45...0.7)
            colors.append(
                Color(hue: Double(newH < 0 ? newH + 1 : newH),
                      saturation: Double(newS),
                      brightness: Double(newB))
                .opacity(Double(opacity))
            )
        }
        return colors
    }

    /// Picks 3 distinct colors from anywhere in the palette for a spotlight element.
    static func spotlightColors(seed: UInt64) -> (near: Color, mid: Color, far: Color) {
        let (near, mid, far) = CanvasColorPalette.seededColorTriple(seed: seed ^ 0xBEEF)
        return (Color(hex: near), Color(hex: mid), Color(hex: far))
    }
}

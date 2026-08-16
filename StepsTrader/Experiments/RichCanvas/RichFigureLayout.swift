import Foundation

struct RichFigureLayoutSpec: Equatable {
    let center: CGPoint
    let targetDiameterFraction: CGFloat
    let opticalScale: CGFloat
    let overscanFraction: CGFloat
}

struct RichFigureEffectMetrics: Equatable {
    let lineWidth: CGFloat
    let outerGlowBlur: CGFloat
    let coreGlowDiameter: CGFloat
    let coreGlowBlur: CGFloat
    let highlightRadius: CGFloat
    let particleRadius: CGFloat
    let overscanRadius: CGFloat

    var reserve: CGFloat {
        max(
            overscanRadius,
            lineWidth * 1.5 + outerGlowBlur,
            coreGlowDiameter * 0.5 + coreGlowBlur,
            highlightRadius,
            particleRadius
        )
    }
}

struct RichFigureEdgeEnvelope: Equatable {
    let sourceCenter: CGPoint
    let effectiveTargetDiameter: CGFloat
    let maximumContentRadius: CGFloat
    let effectReserve: CGFloat
    let canvasSize: CGSize

    var totalRadius: CGFloat {
        maximumContentRadius + effectReserve
    }

    func constrainedCenter(_ proposedCenter: CGPoint) -> CGPoint {
        let proposed = CGPoint(
            x: proposedCenter.x.isFinite ? proposedCenter.x : sourceCenter.x,
            y: proposedCenter.y.isFinite ? proposedCenter.y : sourceCenter.y
        )
        let minimumX = totalRadius
        let maximumX = max(minimumX, canvasSize.width - totalRadius)
        let minimumY = totalRadius
        let maximumY = max(minimumY, canvasSize.height - totalRadius)
        return CGPoint(
            x: min(maximumX, max(minimumX, proposed.x)),
            y: min(maximumY, max(minimumY, proposed.y))
        )
    }
}

enum RichFigureLayout {
    private static let maximumAnimatedScale: CGFloat = 1.04
    private static let maximumRotationExpansion = CGFloat(2).squareRoot()

    static func make(
        elements: [CanvasElement],
        styles: [UUID: RichFigureStyleSpec]
    ) -> [UUID: RichFigureLayoutSpec] {
        let sorted = elements.sorted { lhs, rhs in
            let lhsSize = lhs.userSize ?? CGFloat(lhs.size)
            let rhsSize = rhs.userSize ?? CGFloat(rhs.size)
            return lhsSize == rhsSize ? lhs.id.uuidString < rhs.id.uuidString : lhsSize < rhsSize
        }

        let diameters = targetDiameters(for: sorted)
        return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { index, element in
            let family = styles[element.id]?.family ?? .circle
            return (element.id, RichFigureLayoutSpec(
                center: element.basePosition,
                targetDiameterFraction: diameters[index],
                opticalScale: opticalScale(for: family),
                overscanFraction: 0.14
            ))
        })
    }

    static func opticalScale(for family: RichFigureFamily) -> CGFloat {
        switch family {
        case .circle: 1.00
        case .luminousOrganic: 0.92
        case .crystallineStar: 1.12
        case .rays: 1.00
        case .orbitalSpirograph: 1.08
        }
    }

    static func fittedScale(
        canonicalBounds: CGRect,
        targetDiameter: CGFloat,
        opticalScale: CGFloat
    ) -> CGFloat {
        guard canonicalBounds.width.isFinite, canonicalBounds.height.isFinite else {
            return targetDiameter * 0.5
        }
        let extent = max(canonicalBounds.width, canonicalBounds.height)
        guard extent.isFinite, extent > 0 else { return targetDiameter * 0.5 }
        return targetDiameter / extent * opticalScale
    }

    static func edgeSafeEnvelope(
        for layout: RichFigureLayoutSpec,
        canvasSize: CGSize
    ) -> RichFigureEdgeEnvelope {
        let width = canvasSize.width.isFinite ? max(0, canvasSize.width) : 0
        let height = canvasSize.height.isFinite ? max(0, canvasSize.height) : 0
        let safeCanvasSize = CGSize(width: width, height: height)
        let normalizedX = layout.center.x.isFinite ? layout.center.x : 0.5
        let normalizedY = layout.center.y.isFinite ? layout.center.y : 0.5
        let sourceCenter = CGPoint(
            x: normalizedX * width,
            y: normalizedY * height
        )
        let minimumDimension = min(width, height)
        let requestedTarget = layout.targetDiameterFraction.isFinite
            ? max(0, layout.targetDiameterFraction * minimumDimension)
            : 0
        let overscanFraction = layout.overscanFraction.isFinite
            ? max(0, layout.overscanFraction)
            : 0
        let edgeDistance = max(0, min(
            sourceCenter.x,
            width - sourceCenter.x,
            sourceCenter.y,
            height - sourceCenter.y
        ))
        let effectiveTarget = edgeSafeTargetDiameter(
            requested: requestedTarget,
            edgeDistance: edgeDistance,
            overscanFraction: overscanFraction
        )
        let metrics = effectMetrics(
            targetDiameter: effectiveTarget,
            overscanFraction: overscanFraction
        )

        return RichFigureEdgeEnvelope(
            sourceCenter: sourceCenter,
            effectiveTargetDiameter: effectiveTarget,
            maximumContentRadius: effectiveTarget * maximumContentScale * 0.5,
            effectReserve: metrics.reserve,
            canvasSize: safeCanvasSize
        )
    }

    static func effectMetrics(
        targetDiameter: CGFloat,
        overscanFraction: CGFloat
    ) -> RichFigureEffectMetrics {
        let target = targetDiameter.isFinite ? max(0, targetDiameter) : 0
        let overscan = overscanFraction.isFinite ? max(0, overscanFraction) : 0
        guard target > 0 else {
            return RichFigureEffectMetrics(
                lineWidth: 0,
                outerGlowBlur: 0,
                coreGlowDiameter: 0,
                coreGlowBlur: 0,
                highlightRadius: 0,
                particleRadius: 0,
                overscanRadius: 0
            )
        }

        let lineWidth = max(0.65, min(2.2, target * 0.008))
        let outerGlowBlur = min(10, max(2, target * overscan * 0.18))
        let coreGlowDiameter = min(18, max(5, target * 0.08))
        return RichFigureEffectMetrics(
            lineWidth: lineWidth,
            outerGlowBlur: outerGlowBlur,
            coreGlowDiameter: coreGlowDiameter,
            coreGlowBlur: min(7, coreGlowDiameter * 0.35),
            highlightRadius: min(7, max(1.8, target * 0.018)),
            particleRadius: min(2.4, max(0.7, target * 0.007)),
            overscanRadius: target * overscan * 0.5
        )
    }

    private static var maximumContentScale: CGFloat {
        let maximumOpticalScale = RichFigureFamily.allCases.reduce(CGFloat(1)) {
            max($0, opticalScale(for: $1))
        }
        return maximumOpticalScale
            * maximumAnimatedScale
            * maximumRotationExpansion
    }

    private static func edgeSafeTargetDiameter(
        requested: CGFloat,
        edgeDistance: CGFloat,
        overscanFraction: CGFloat
    ) -> CGFloat {
        guard requested > 0, edgeDistance > 0 else { return 0 }
        if requiredRadius(
            targetDiameter: requested,
            overscanFraction: overscanFraction
        ) <= edgeDistance {
            return requested
        }

        var lower: CGFloat = 0
        var upper = requested
        for _ in 0..<48 {
            let candidate = (lower + upper) * 0.5
            if requiredRadius(
                targetDiameter: candidate,
                overscanFraction: overscanFraction
            ) <= edgeDistance {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return lower
    }

    private static func requiredRadius(
        targetDiameter: CGFloat,
        overscanFraction: CGFloat
    ) -> CGFloat {
        targetDiameter * maximumContentScale * 0.5
            + effectMetrics(
                targetDiameter: targetDiameter,
                overscanFraction: overscanFraction
            ).reserve
    }

    private static func targetDiameters(for elements: [CanvasElement]) -> [CGFloat] {
        let sizes = elements.map { $0.userSize ?? CGFloat($0.size) }
        if let smallest = sizes.first, let largest = sizes.last,
           largest - smallest < 0.02 {
            return Array(repeating: 0.26, count: elements.count)
        }

        switch elements.count {
        case 0:
            return []
        case 1:
            return [0.26]
        case 2:
            return [0.22, 0.30]
        default:
            return elements.indices.map { index in
                guard index > 0 else { return 0.19 }
                let progress = CGFloat(index - 1) / CGFloat(elements.count - 2)
                return 0.22 + 0.12 * progress
            }
        }
    }
}

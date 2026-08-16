import Foundation

struct RichFigureLayoutSpec: Equatable {
    let center: CGPoint
    let targetDiameterFraction: CGFloat
    let opticalScale: CGFloat
    let overscanFraction: CGFloat
}

struct RichFigureLabelCandidate: Equatable {
    let id: UUID
    let preferredCenter: CGPoint
    let estimatedWidth: CGFloat
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
        let effectiveTarget = edgeSafeTargetDiameter(
            requested: requestedTarget,
            canvasSize: safeCanvasSize,
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
        let outerGlowBlur = min(14, max(3, target * 0.045))
        let coreGlowDiameter = min(72, max(14, target * 0.36))
        return RichFigureEffectMetrics(
            lineWidth: lineWidth,
            outerGlowBlur: outerGlowBlur,
            coreGlowDiameter: coreGlowDiameter,
            coreGlowBlur: min(18, max(5, coreGlowDiameter * 0.24)),
            highlightRadius: min(7, max(1.8, target * 0.018)),
            particleRadius: min(2.4, max(0.7, target * 0.007)),
            overscanRadius: target * overscan * 0.5
        )
    }

    static func labelCenter(
        figureCenter: CGPoint,
        contentRadius: CGFloat,
        canvasSize: CGSize,
        bottomReservedInset: CGFloat = 80
    ) -> CGPoint {
        let radius = contentRadius.isFinite ? max(0, contentRadius) : 0
        let width = canvasSize.width.isFinite ? max(0, canvasSize.width) : 0
        let height = canvasSize.height.isFinite ? max(0, canvasSize.height) : 0
        let gap = max(12, min(20, radius * 0.16))
        let labelHalfHeight: CGFloat = 10
        let usableHeight = max(0, height - max(0, bottomReservedInset))
        let below = figureCenter.y + radius + gap
        let above = figureCenter.y - radius - gap
        let y = below + labelHalfHeight <= usableHeight
            ? below
            : max(labelHalfHeight, above)
        let horizontalMargin = min(width * 0.5, CGFloat(54))
        return CGPoint(
            x: min(max(horizontalMargin, figureCenter.x), width - horizontalMargin),
            y: y
        )
    }

    static func resolvedLabelCenters(
        candidates: [RichFigureLabelCandidate],
        canvasSize: CGSize,
        bottomReservedInset: CGFloat = 80
    ) -> [UUID: CGPoint] {
        let width = canvasSize.width.isFinite ? max(0, canvasSize.width) : 0
        let height = canvasSize.height.isFinite ? max(0, canvasSize.height) : 0
        let usableHeight = max(0, height - max(0, bottomReservedInset))
        let labelHeight: CGFloat = 16
        let offsets: [CGFloat] = [0, 20, -20, 40, -40, 60, -60]
        var occupied: [CGRect] = []
        var result: [UUID: CGPoint] = [:]

        for candidate in candidates {
            let labelWidth = min(
                max(32, candidate.estimatedWidth.isFinite
                    ? candidate.estimatedWidth : 32),
                max(32, width - 12)
            )
            let halfWidth = labelWidth * 0.5
            let x = min(max(halfWidth + 6, candidate.preferredCenter.x),
                        max(halfWidth + 6, width - halfWidth - 6))
            let baseY = min(max(labelHeight * 0.5, candidate.preferredCenter.y),
                            max(labelHeight * 0.5, usableHeight - labelHeight * 0.5))
            var chosen = CGPoint(x: x, y: baseY)

            for offset in offsets {
                let y = min(max(labelHeight * 0.5, baseY + offset),
                            max(labelHeight * 0.5, usableHeight - labelHeight * 0.5))
                let proposed = CGPoint(x: x, y: y)
                let rect = CGRect(
                    x: proposed.x - halfWidth,
                    y: proposed.y - labelHeight * 0.5,
                    width: labelWidth,
                    height: labelHeight
                ).insetBy(dx: -3, dy: -2)
                if occupied.allSatisfy({ !$0.intersects(rect) }) {
                    chosen = proposed
                    break
                }
            }

            let chosenRect = CGRect(
                x: chosen.x - halfWidth,
                y: chosen.y - labelHeight * 0.5,
                width: labelWidth,
                height: labelHeight
            ).insetBy(dx: -3, dy: -2)
            occupied.append(chosenRect)
            result[candidate.id] = chosen
        }
        return result
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
        canvasSize: CGSize,
        overscanFraction: CGFloat
    ) -> CGFloat {
        let availableRadius = min(canvasSize.width, canvasSize.height) * 0.5
        guard requested > 0, availableRadius > 0 else { return 0 }
        if requiredRadius(
            targetDiameter: requested,
            overscanFraction: overscanFraction
        ) <= availableRadius {
            return requested
        }

        var lower: CGFloat = 0
        var upper = requested
        for _ in 0..<48 {
            let candidate = (lower + upper) * 0.5
            if requiredRadius(
                targetDiameter: candidate,
                overscanFraction: overscanFraction
            ) <= availableRadius {
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
        let compositionalScale: [CGFloat] = [
            0.14, 0.16, 0.17, 0.18,
            0.21, 0.23, 0.25,
            0.29, 0.32,
            0.38
        ]
        guard !elements.isEmpty else { return [] }
        guard elements.count > 1 else { return [compositionalScale.last ?? 0.38] }

        return elements.indices.map { index in
            let scaledIndex = CGFloat(index)
                * CGFloat(compositionalScale.count - 1)
                / CGFloat(elements.count - 1)
            let lowerIndex = Int(floor(scaledIndex))
            let upperIndex = min(compositionalScale.count - 1, lowerIndex + 1)
            let interpolation = scaledIndex - CGFloat(lowerIndex)
            return compositionalScale[lowerIndex]
                + (compositionalScale[upperIndex] - compositionalScale[lowerIndex])
                * interpolation
        }
    }
}

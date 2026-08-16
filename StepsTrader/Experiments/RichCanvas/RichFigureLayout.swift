import Foundation

struct RichFigureLayoutSpec: Equatable {
    let center: CGPoint
    let targetDiameterFraction: CGFloat
    let opticalScale: CGFloat
    let overscanFraction: CGFloat
}

enum RichFigureLayout {
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

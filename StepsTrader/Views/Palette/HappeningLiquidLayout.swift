import SwiftUI

/// Deterministic geometry for the palette's Living-island field.
///
/// The templates intentionally describe relative placement only. The renderer
/// supplies the visual material and interpolates between returned layouts;
/// this type keeps the field stable, testable, and safe-area-aware.
enum HappeningLiquidLayout {

    struct Source: Equatable {
        /// Stable position in the caller's ordered happening collection.
        let index: Int
        let center: CGPoint
        let radius: CGFloat
    }

    struct Layout: Equatable {
        let sources: [Source]
        /// Rectangular, independent hit regions. They never overlap even when
        /// the rendered liquid sources do.
        let labelFrames: [CGRect]
        /// The renderer's intended outer extent, leaving free canvas around it.
        let contourBounds: CGRect
        /// Centre point for the attached three-control dock.
        let dockAnchor: CGPoint
        /// The intentional residual island shown after the final happening is used.
        let completionBounds: CGRect?
    }

    private struct UnitPoint {
        let x: CGFloat
        let y: CGFloat
    }

    private static let edgeClearance: CGFloat = 16
    private static let dockTouchDistance: CGFloat = 28

    /// Each array is hand-tuned in unit space for one visible-item count.
    /// Their ordering is identity ordering: removing an item never reorders
    /// the survivors, even though their visual positions can reflow.
    private static let templates: [[UnitPoint]] = [
        [],
        [.init(x: 0.50, y: 0.50)],
        [.init(x: 0.34, y: 0.48), .init(x: 0.67, y: 0.52)],
        [.init(x: 0.18, y: 0.52), .init(x: 0.50, y: 0.30), .init(x: 0.82, y: 0.54)],
        [.init(x: 0.31, y: 0.28), .init(x: 0.68, y: 0.30), .init(x: 0.31, y: 0.72), .init(x: 0.68, y: 0.70)],
        [.init(x: 0.18, y: 0.35), .init(x: 0.50, y: 0.16), .init(x: 0.82, y: 0.34), .init(x: 0.33, y: 0.72), .init(x: 0.69, y: 0.76)],
        [.init(x: 0.18, y: 0.31), .init(x: 0.50, y: 0.16), .init(x: 0.82, y: 0.31), .init(x: 0.18, y: 0.69), .init(x: 0.50, y: 0.85), .init(x: 0.82, y: 0.69)],
        [.init(x: 0.18, y: 0.24), .init(x: 0.50, y: 0.14), .init(x: 0.82, y: 0.27), .init(x: 0.18, y: 0.60), .init(x: 0.50, y: 0.48), .init(x: 0.82, y: 0.62), .init(x: 0.50, y: 0.86)],
        [.init(x: 0.18, y: 0.20), .init(x: 0.50, y: 0.12), .init(x: 0.82, y: 0.23), .init(x: 0.18, y: 0.49), .init(x: 0.50, y: 0.40), .init(x: 0.82, y: 0.51), .init(x: 0.30, y: 0.79), .init(x: 0.70, y: 0.80)],
        [.init(x: 0.18, y: 0.18), .init(x: 0.50, y: 0.10), .init(x: 0.82, y: 0.20), .init(x: 0.18, y: 0.46), .init(x: 0.50, y: 0.38), .init(x: 0.82, y: 0.48), .init(x: 0.18, y: 0.75), .init(x: 0.50, y: 0.86), .init(x: 0.82, y: 0.75)],
        [.init(x: 0.18, y: 0.16), .init(x: 0.50, y: 0.09), .init(x: 0.82, y: 0.18), .init(x: 0.18, y: 0.42), .init(x: 0.50, y: 0.34), .init(x: 0.82, y: 0.44), .init(x: 0.18, y: 0.69), .init(x: 0.50, y: 0.80), .init(x: 0.82, y: 0.69), .init(x: 0.50, y: 0.98)]
    ]

    static func layout(
        count: Int,
        in size: CGSize,
        safeInsets: EdgeInsets,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> Layout {
        let safeBounds = safeBounds(in: size, safeInsets: safeInsets)
        guard !safeBounds.isEmpty else {
            return Layout(
                sources: [],
                labelFrames: [],
                contourBounds: .zero,
                dockAnchor: .zero,
                completionBounds: nil
            )
        }

        let itemCount = min(max(count, 0), templates.count - 1)
        guard itemCount > 0 else {
            let typeScale = min(
                1.35,
                HappeningLiquidLabelTypography.scaledUIFont(
                    for: dynamicTypeSize
                ).pointSize / HappeningLiquidLabelTypography.pointSize
            )
            let completionSize = CGSize(
                width: min(216 * typeScale, safeBounds.width - edgeClearance * 2),
                height: 92 * (1 + (typeScale - 1) * 0.72)
            )
            let preferredCenterY = safeBounds.midY + min(44, safeBounds.height * 0.07)
            let maximumCenterY = safeBounds.maxY - 120 - dockTouchDistance - completionSize.height / 2
            let completionBounds = CGRect(
                x: safeBounds.midX - completionSize.width / 2,
                y: min(preferredCenterY, maximumCenterY) - completionSize.height / 2,
                width: completionSize.width,
                height: completionSize.height
            )
            return Layout(
                sources: [],
                labelFrames: [],
                contourBounds: .zero,
                dockAnchor: CGPoint(
                    x: safeBounds.midX,
                    y: completionBounds.maxY + dockTouchDistance
                ),
                completionBounds: completionBounds
            )
        }

        if dynamicTypeSize > .large {
            return expandedLayout(
                itemCount: itemCount,
                safeBounds: safeBounds,
                dynamicTypeSize: dynamicTypeSize
            )
        }

        let contourWidth = min(safeBounds.width * 0.84, 360)
        let maximumHeight = max(
            44,
            safeBounds.height - edgeClearance * 2 - dockTouchDistance - edgeClearance
        )
        let contourHeight = min(maximumHeight, min(safeBounds.height * 0.50, 390))
        let desiredOriginY = safeBounds.midY - contourHeight * 0.48
        let originY = min(
            max(desiredOriginY, safeBounds.minY + edgeClearance),
            safeBounds.maxY - edgeClearance - dockTouchDistance - contourHeight
        )
        let templateBounds = CGRect(
            x: safeBounds.midX - contourWidth / 2,
            y: originY,
            width: contourWidth,
            height: contourHeight
        )
        let labelSize = CGSize(
            width: min(94, max(72, contourWidth * 0.27)),
            height: min(68, max(56, contourHeight * 0.17))
        )

        let sources = templates[itemCount].enumerated().map { index, point in
            Source(
                index: index,
                center: CGPoint(
                    x: templateBounds.minX + point.x * templateBounds.width,
                    y: templateBounds.minY + point.y * templateBounds.height
                ),
                radius: min(templateBounds.width, templateBounds.height)
                    * (0.135 + CGFloat(index % 3) * 0.012)
            )
        }
        let labelFrames = sources.map { source in
            CGRect(
                x: source.center.x - labelSize.width / 2,
                y: source.center.y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
        }
        let contourBounds = sources.reduce(CGRect.null) { bounds, source in
            bounds.union(
                CGRect(
                    x: source.center.x - source.radius,
                    y: source.center.y - source.radius,
                    width: source.radius * 2,
                    height: source.radius * 2
                )
            )
        }
        .insetBy(dx: -12, dy: -12)

        return Layout(
            sources: sources,
            labelFrames: labelFrames,
            contourBounds: contourBounds,
            dockAnchor: CGPoint(x: contourBounds.midX, y: contourBounds.maxY + dockTouchDistance),
            completionBounds: nil
        )
    }

    private static func expandedLayout(
        itemCount: Int,
        safeBounds: CGRect,
        dynamicTypeSize: DynamicTypeSize
    ) -> Layout {
        let rows = Int(ceil(Double(itemCount) / 2))
        let font = HappeningLiquidLabelTypography.scaledUIFont(for: dynamicTypeSize)
        let labelSize = CGSize(
            width: min(164, (safeBounds.width - 50) / 2),
            height: min(122, max(78, ceil(font.lineHeight * 3.25 / 0.80)))
        )
        let radius = min(72, max(64, labelSize.height * 0.62))
        let maximumContourHeight = max(
            44,
            safeBounds.height
                - edgeClearance * 2
                - dockTouchDistance
                - 44
        )
        let contourEndcaps = (radius + 12) * 2
        let preferredStep = labelSize.height + 10
        let verticalStep = rows > 1
            ? min(
                preferredStep,
                max(labelSize.height, (maximumContourHeight - contourEndcaps) / CGFloat(rows - 1))
            )
            : 0
        let contourHeight = contourEndcaps + verticalStep * CGFloat(max(0, rows - 1))
        let preferredTop = safeBounds.midY - contourHeight / 2 - 12
        let maximumTop = safeBounds.maxY
            - edgeClearance
            - dockTouchDistance
            - 44
            - contourHeight
        let contourTop = min(
            max(preferredTop, safeBounds.minY + edgeClearance),
            maximumTop
        )
        let firstCenterY = contourTop + radius + 12
        let columnOffset = min(94, safeBounds.width * 0.235)

        let sources = (0..<itemCount).map { index in
            let row = index / 2
            let isUnpairedLastItem = itemCount.isMultiple(of: 2) == false
                && index == itemCount - 1
            let centerX: CGFloat
            if itemCount == 1 || isUnpairedLastItem {
                centerX = safeBounds.midX
            } else {
                centerX = safeBounds.midX + (index.isMultiple(of: 2) ? -columnOffset : columnOffset)
            }
            return Source(
                index: index,
                center: CGPoint(
                    x: centerX,
                    y: firstCenterY + CGFloat(row) * verticalStep
                ),
                radius: radius
            )
        }
        let labelFrames = sources.map { source in
            CGRect(
                x: source.center.x - labelSize.width / 2,
                y: source.center.y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
        }
        let contourBounds = sources.reduce(CGRect.null) { bounds, source in
            bounds.union(
                CGRect(
                    x: source.center.x - source.radius,
                    y: source.center.y - source.radius,
                    width: source.radius * 2,
                    height: source.radius * 2
                )
            )
        }
        .insetBy(dx: -12, dy: -12)

        return Layout(
            sources: sources,
            labelFrames: labelFrames,
            contourBounds: contourBounds,
            dockAnchor: CGPoint(
                x: contourBounds.midX,
                y: contourBounds.maxY + dockTouchDistance
            ),
            completionBounds: nil
        )
    }

    private static func safeBounds(in size: CGSize, safeInsets: EdgeInsets) -> CGRect {
        CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: max(0, size.width - safeInsets.leading - safeInsets.trailing),
            height: max(0, size.height - safeInsets.top - safeInsets.bottom)
        )
    }
}

#if DEBUG
private struct HappeningLiquidLayoutDebugPreview: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            let layout = HappeningLiquidLayout.layout(
                count: count, in: proxy.size, safeInsets: EdgeInsets()
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 32)
                    .stroke(.mint, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(width: layout.contourBounds.width, height: layout.contourBounds.height)
                    .position(x: layout.contourBounds.midX, y: layout.contourBounds.midY)

                ForEach(layout.sources, id: \.index) { source in
                    Circle()
                        .fill(.blue.opacity(0.22))
                        .overlay { Circle().stroke(.blue.opacity(0.7)) }
                        .frame(width: source.radius * 2, height: source.radius * 2)
                        .position(source.center)
                }

                ForEach(Array(layout.labelFrames.enumerated()), id: \.offset) { index, frame in
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: frame.width, height: frame.height)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.8)) }
                        .position(x: frame.midX, y: frame.midY)
                }

                Circle()
                    .fill(.orange)
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "xmark").foregroundStyle(.black) }
                    .position(layout.dockAnchor)
            }
        }
        .frame(height: 340)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topLeading) {
            Text("\(count) remaining")
                .font(.caption.weight(.semibold))
                .padding(8)
        }
    }
}

#Preview("Liquid layout grid") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach([10, 9, 6, 3, 0], id: \.self) { count in
                HappeningLiquidLayoutDebugPreview(count: count)
            }
        }
        .padding()
    }
    .background(.gray.opacity(0.25))
}

#Preview("Liquid layout grid — Accessibility") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach([10, 9, 6, 3, 0], id: \.self) { count in
                HappeningLiquidLayoutDebugPreview(count: count)
            }
        }
        .padding()
    }
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
    .background(.gray.opacity(0.25))
}
#endif

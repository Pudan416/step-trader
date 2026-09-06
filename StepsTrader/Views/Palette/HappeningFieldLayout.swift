import SwiftUI

/// Deterministic constellation for the remaining happenings.
///
/// The palette has no containing blob. Each source is a real, independent
/// circle placed between the persistent energy bar and the bottom dock.
enum HappeningFieldLayout {
    struct Source: Equatable {
        let index: Int
        let center: CGPoint
        let radius: CGFloat
    }

    struct Layout: Equatable {
        let sources: [Source]
        let labelFrames: [CGRect]
        let contourBounds: CGRect
        let dockAnchor: CGPoint
        let completionBounds: CGRect?
    }

    private static let edgeClearance: CGFloat = 17
    private static let dockHitRadius: CGFloat = 36
    private static let dockContentGap: CGFloat = 52
    private static let completionDockGap: CGFloat = 24
    private static let contactGap: CGFloat = 0.1
    private static let targetRadius: CGFloat = 64

    /// Symmetric close-packed rows for every possible remaining count. The
    /// full palette uses the approved 3·2·3·2 rhythm.
    private static let rowPatterns: [[Int]] = [
        [], [1], [2], [3], [2, 2], [3, 2], [3, 3], [2, 3, 2],
        [3, 2, 3], [3, 3, 3], [3, 2, 3, 2],
    ]

    static func usesExpandedLayout(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize > .large
    }

    static func layout(
        count: Int,
        in size: CGSize,
        safeInsets: EdgeInsets,
        dynamicTypeSize: DynamicTypeSize = .large,
        contentTopInset: CGFloat? = nil,
        dockCenterY: CGFloat? = nil
    ) -> Layout {
        let safeBounds = safeBounds(in: size, safeInsets: safeInsets)
        guard !safeBounds.isEmpty else {
            return Layout(
                sources: [], labelFrames: [], contourBounds: .zero,
                dockAnchor: .zero, completionBounds: nil
            )
        }

        let defaultDockY = safeBounds.maxY - dockHitRadius
        let resolvedDockY = min(
            safeBounds.maxY - dockHitRadius,
            max(safeBounds.midY, dockCenterY ?? defaultDockY)
        )
        let dockAnchor = CGPoint(x: safeBounds.midX, y: resolvedDockY)
        let itemCount = min(max(count, 0), rowPatterns.count - 1)
        let contentTop = min(
            dockAnchor.y - dockContentGap - 44,
            max(safeBounds.minY + edgeClearance, contentTopInset ?? safeBounds.minY + edgeClearance)
        )
        let contentBottom = dockAnchor.y - dockContentGap

        guard itemCount > 0 else {
            let typeScale = min(
                1.35,
                HappeningFieldLabelTypography.scaledUIFont(for: dynamicTypeSize).pointSize
                    / HappeningFieldLabelTypography.pointSize
            )
            let completionSize = CGSize(
                width: min(216 * typeScale, safeBounds.width - edgeClearance * 2),
                height: 92 * (1 + (typeScale - 1) * 0.72)
            )
            return Layout(
                sources: [],
                labelFrames: [],
                contourBounds: .zero,
                dockAnchor: dockAnchor,
                completionBounds: CGRect(
                    x: safeBounds.midX - completionSize.width / 2,
                    y: dockAnchor.y - completionDockGap - completionSize.height,
                    width: completionSize.width,
                    height: completionSize.height
                )
            )
        }

        if usesExpandedLayout(for: dynamicTypeSize) {
            return expandedLayout(
                itemCount: itemCount,
                safeBounds: safeBounds,
                contentTop: contentTop,
                contentBottom: contentBottom,
                dockAnchor: dockAnchor
            )
        }
        return standardLayout(
            itemCount: itemCount,
            safeBounds: safeBounds,
            contentTop: contentTop,
            contentBottom: contentBottom,
            dockAnchor: dockAnchor
        )
    }

    private static func standardLayout(
        itemCount: Int,
        safeBounds: CGRect,
        contentTop: CGFloat,
        contentBottom: CGFloat,
        dockAnchor: CGPoint
    ) -> Layout {
        let fieldWidth = safeBounds.width - edgeClearance * 2
        let fieldHeight = max(88, contentBottom - contentTop)
        let rows = rowPatterns[itemCount]
        let widestRow = rows.max() ?? 1
        let rowFactors = zip(rows, rows.dropFirst()).map { current, next in
            current == next ? CGFloat(1) : sqrt(3) / 2
        }
        let factorSum = rowFactors.reduce(0, +)
        let widthRadius = (
            fieldWidth - CGFloat(max(0, widestRow - 1)) * contactGap
        ) / CGFloat(widestRow * 2)
        let heightRadius = (
            fieldHeight - factorSum * contactGap
        ) / (2 + 2 * factorSum)
        let radius = min(targetRadius, max(32, min(widthRadius, heightRadius)))
        let centerStep = radius * 2 + contactGap
        let rowSteps = rowFactors.map { $0 * centerStep }
        let clusterHeight = radius * 2 + rowSteps.reduce(0, +)
        var centerY = contentTop + max(0, fieldHeight - clusterHeight) / 2 + radius
        var sourceIndex = 0
        var sources: [Source] = []

        for (rowIndex, rowCount) in rows.enumerated() {
            let rowWidth = radius * 2 * CGFloat(rowCount)
                + contactGap * CGFloat(max(0, rowCount - 1))
            let firstCenterX = safeBounds.midX - rowWidth / 2 + radius
            for column in 0..<rowCount {
                sources.append(
                    Source(
                        index: sourceIndex,
                        center: CGPoint(
                            x: firstCenterX + CGFloat(column) * centerStep,
                            y: centerY
                        ),
                        radius: radius
                    )
                )
                sourceIndex += 1
            }
            if rowIndex < rowSteps.count {
                centerY += rowSteps[rowIndex]
            }
        }

        return makeLayout(sources: sources, dockAnchor: dockAnchor)
    }

    private static func expandedLayout(
        itemCount: Int,
        safeBounds: CGRect,
        contentTop: CGFloat,
        contentBottom: CGFloat,
        dockAnchor: CGPoint
    ) -> Layout {
        let rows = Int(ceil(Double(itemCount) / 2))
        let availableHeight = max(44, contentBottom - contentTop)
        let radius = min(
            54,
            max(22, min((safeBounds.width - 76) / 4, (availableHeight / CGFloat(rows) - 8) / 2))
        )
        let firstY = contentTop + radius
        let lastY = contentBottom - radius
        let step = rows > 1 ? (lastY - firstY) / CGFloat(rows - 1) : 0
        let columnOffset = min(92, safeBounds.width * 0.23)
        let sources = (0..<itemCount).map { index in
            let row = index / 2
            let unpaired = !itemCount.isMultiple(of: 2) && index == itemCount - 1
            return Source(
                index: index,
                center: CGPoint(
                    x: unpaired
                        ? safeBounds.midX
                        : safeBounds.midX + (index.isMultiple(of: 2) ? -columnOffset : columnOffset),
                    y: firstY + CGFloat(row) * step
                ),
                radius: radius
            )
        }
        return makeLayout(sources: sources, dockAnchor: dockAnchor)
    }

    private static func makeLayout(sources: [Source], dockAnchor: CGPoint) -> Layout {
        let frames = sources.map {
            CGRect(
                x: $0.center.x - $0.radius,
                y: $0.center.y - $0.radius,
                width: $0.radius * 2,
                height: $0.radius * 2
            )
        }
        let bounds = frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }
        return Layout(
            sources: sources,
            labelFrames: frames,
            contourBounds: bounds,
            dockAnchor: dockAnchor,
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
private struct HappeningFieldLayoutDebugPreview: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            let layout = HappeningFieldLayout.layout(
                count: count,
                in: proxy.size,
                safeInsets: EdgeInsets(),
                contentTopInset: 36
            )
            ZStack {
                ForEach(layout.sources, id: \.index) { source in
                    Circle()
                        .fill(.pink.opacity(0.72))
                        .frame(width: source.radius * 2, height: source.radius * 2)
                        .position(source.center)
                }
                Circle().fill(.orange).frame(width: 44, height: 44).position(layout.dockAnchor)
            }
        }
        .frame(height: 720)
        .background(.black)
    }
}

#Preview("Circle constellation") {
    HappeningFieldLayoutDebugPreview(count: 10)
}
#endif

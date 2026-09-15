import SwiftUI

/// Stable circle positions for the happening field. Larger catalogs extend
/// beyond the viewport in both directions instead of shrinking their targets.
enum HappeningFieldLayout {
    struct Source: Equatable {
        let index: Int
        let center: CGPoint
        let radius: CGFloat
        var appearanceScale: CGFloat = 1
    }

    struct Layout: Equatable {
        let sources: [Source]
        let labelFrames: [CGRect]
        let contourBounds: CGRect
        let dockAnchor: CGPoint
        let completionBounds: CGRect?
        var contentSize: CGSize = .zero

        /// Metal receives screen coordinates; ScrollView keeps the same sources
        /// in content coordinates for labels, hit testing and accessibility.
        func translated(by offset: CGPoint) -> Layout {
            Layout(
                sources: sources.map { Source(index: $0.index, center: CGPoint(x: $0.center.x - offset.x, y: $0.center.y - offset.y), radius: $0.radius, appearanceScale: $0.appearanceScale) },
                labelFrames: labelFrames.map { $0.offsetBy(dx: -offset.x, dy: -offset.y) },
                contourBounds: contourBounds.offsetBy(dx: -offset.x, dy: -offset.y),
                dockAnchor: dockAnchor, completionBounds: completionBounds, contentSize: contentSize
            )
        }
    }

    private static let edgeClearance: CGFloat = 17
    private static let dockHitRadius: CGFloat = 36
    private static let dockContentGap: CGFloat = 120
    private static let completionDockGap: CGFloat = 24
    private static let contactGap: CGFloat = 8
    private static let targetRadius: CGFloat = 64

    /// Symmetric close-packed rows for every configured count. The
    /// full palette uses the approved 3·2·3·2 rhythm.
    private static let rowPatterns: [[Int]] = [
        [], [1], [2], [3], [2, 2], [3, 2], [3, 3], [2, 3, 2],
        [3, 2, 3], [3, 3, 3], [3, 2, 3, 2],
    ]

    /// Creator-panel actions may stack at larger text sizes; slot geometry stays fixed.
    static func usesExpandedLayout(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize > .large
    }

    static func layout(
        count: Int,
        in size: CGSize,
        safeInsets: EdgeInsets,
        dynamicTypeSize: DynamicTypeSize = .large,
        contentTopInset: CGFloat? = nil,
        dockCenterY: CGFloat? = nil,
        allowsAccessibleScrolling: Bool = false
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

        if count > 10 {
            let radius = max(68, min(96, HappeningFieldLabelTypography.scaledUIFont(for: dynamicTypeSize).pointSize / 14 * 68))
            let gap: CGFloat = 8
            let step = radius * 2 + gap
            var rows: [Int] = []
            var remaining = count
            while remaining > 0 {
                let rowCount = min(remaining, rows.count.isMultiple(of: 2) ? 4 : 5)
                rows.append(rowCount)
                remaining -= rowCount
            }
            let width = max(size.width, edgeClearance * 2 + radius * 10 + gap * 4)
            let rowSteps = zip(rows, rows.dropFirst()).map { previous, next in
                previous.isMultiple(of: 2) == next.isMultiple(of: 2) ? step : step * sqrt(3) / 2
            }
            let clusterHeight = radius * 2 + rowSteps.reduce(0, +)
            // Symmetric padding makes the scroll view's centre the field's centre.
            let padding = max(contentTop, size.height - dockAnchor.y + 80)
            let height = max(size.height, clusterHeight + padding * 2)
            var sources: [Source] = []
            var centerY = (height - clusterHeight) / 2 + radius
            for (rowIndex, rowCount) in rows.enumerated() {
                let firstX = width / 2 - CGFloat(rowCount - 1) * step / 2
                for column in 0..<rowCount {
                    sources.append(Source(index: sources.count, center: CGPoint(
                        x: firstX + CGFloat(column) * step,
                        y: centerY
                    ), radius: radius))
                }
                if rowIndex < rowSteps.count { centerY += rowSteps[rowIndex] }
            }
            var result = makeLayout(sources: sources, dockAnchor: dockAnchor)
            result.contentSize = CGSize(width: width, height: height)
            return result
        }

        if allowsAccessibleScrolling, dynamicTypeSize.isAccessibilitySize {
            let radius = max(88, min(132, (safeBounds.width - edgeClearance * 2) / 2))
            let step = radius * 2 + 16
            let sources = (0..<itemCount).map { index in
                Source(index: index, center: CGPoint(x: safeBounds.midX,
                    y: contentTop + radius + CGFloat(index) * step), radius: radius)
            }
            var result = makeLayout(sources: sources, dockAnchor: dockAnchor)
            result.contentSize = CGSize(width: size.width,
                height: max(size.height, contentTop + CGFloat(itemCount) * step + size.height - dockAnchor.y + 80))
            return result
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

    static func makeLayout(sources: [Source], dockAnchor: CGPoint) -> Layout {
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


/// Both the renderer and labels consume this exact sampled geometry. The world
/// size stays constant, so changing modes never replaces the scroll surface.
enum HappeningFieldExpansion {
    static func layout(compact: HappeningFieldLayout.Layout, expanded: HappeningFieldLayout.Layout,
                       viewport: CGSize, progress: CGFloat) -> HappeningFieldLayout.Layout {
        let p = min(1, max(0, progress))
        let compactHeight = max(viewport.height, compact.contentSize.height)
        let world = CGSize(width: max(viewport.width, expanded.contentSize.width),
            height: max(compactHeight, expanded.contentSize.height))
        let compactOffset = CGPoint(x: (world.width - viewport.width) / 2, y: (world.height - compactHeight) / 2)
        let expandedOffset = CGPoint(x: (world.width - expanded.contentSize.width) / 2,
            y: (world.height - expanded.contentSize.height) / 2)
        let ordered = orderedSources(expanded.sources, homeCount: compact.sources.count)
        let smooth = p * p * (3 - 2 * p)
        let center = CGPoint(x: world.width / 2, y: world.height / 2)
        var sources: [HappeningFieldLayout.Source] = []
        for (index, destination) in ordered.enumerated() {
            let target = CGPoint(x: destination.center.x + expandedOffset.x, y: destination.center.y + expandedOffset.y)
            if index < compact.sources.count {
                let source = compact.sources[index]
                let start = CGPoint(x: source.center.x + compactOffset.x, y: source.center.y + compactOffset.y)
                sources.append(HappeningFieldLayout.Source(index: index,
                    center: CGPoint(x: start.x + (target.x - start.x) * smooth,
                                    y: start.y + (target.y - start.y) * smooth),
                    radius: source.radius + (destination.radius - source.radius) * smooth))
                continue
            }
            let distance = hypot(target.x - center.x, target.y - center.y)
            let delay = min(0.22, distance / max(world.width, world.height) * 0.35)
            let phase = min(1, max(0, (p - delay) / (1 - delay)))
            var scale = phase == 0 ? 0 : phase == 1 ? 1 : min(1.04, 1 - pow(1 - phase, 3) * cos(phase * .pi * 2))
            let position = CGPoint(x: target.x + (center.x - target.x) * (1 - phase) * 0.12,
                                   y: target.y + (center.y - target.y) * (1 - phase) * 0.12)
            if p > 0 && p < 1 {
                // Inflate only into available space as the central ten spread.
                // This also prevents the spring overshoot from merging contours.
                for neighbor in sources where neighbor.radius > 0 {
                    let available = max(0, hypot(position.x - neighbor.center.x, position.y - neighbor.center.y) - neighbor.radius - 8)
                    scale = min(scale, available / max(1, destination.radius))
                }
            }
            sources.append(HappeningFieldLayout.Source(index: index, center: position,
                radius: destination.radius * scale, appearanceScale: scale))
        }
        var result = HappeningFieldLayout.makeLayout(sources: sources, dockAnchor: compact.dockAnchor)
        result.contentSize = world
        return result
    }

    private static func orderedSources(_ sources: [HappeningFieldLayout.Source], homeCount: Int) -> [HappeningFieldLayout.Source] {
        guard sources.count > homeCount else { return sources }
        let rows = Dictionary(grouping: sources, by: { $0.center.y }).sorted { $0.key < $1.key }.map { $0.value.sorted { $0.center.x < $1.center.x } }
        // Central 3/2/3/2 cells preserve the Frequent reading order inside the
        // full 4/5 staggered lattice; all remaining cells surround that cluster.
        let starts = rows.indices.filter { $0 + 3 < rows.count && rows[$0].count == 5 && rows[$0 + 1].count == 4 && rows[$0 + 2].count == 5 && rows[$0 + 3].count == 4 }
        var home: [HappeningFieldLayout.Source] = []
        if homeCount == 10, let start = starts.min(by: { abs(Double($0) + 1.5 - Double(rows.count - 1) / 2) < abs(Double($1) + 1.5 - Double(rows.count - 1) / 2) }) {
            for row in start..<(start + 4) { home += rows[row].count == 5 ? Array(rows[row][1...3]) : Array(rows[row][1...2]) }
        } else {
            let center = CGPoint(x: sources.map { $0.center.x }.reduce(0, +) / CGFloat(sources.count),
                                 y: sources.map { $0.center.y }.reduce(0, +) / CGFloat(sources.count))
            home = Array(sources.sorted { hypot($0.center.x - center.x, $0.center.y - center.y) < hypot($1.center.x - center.x, $1.center.y - center.y) }.prefix(homeCount))
                .sorted { $0.center.y == $1.center.y ? $0.center.x < $1.center.x : $0.center.y < $1.center.y }
        }
        let chosen = Set(home.map(\.index))
        return home + sources.filter { !chosen.contains($0.index) }
    }
}

struct HappeningFieldModeTransition {
    static let duration: TimeInterval = 0.58
    let from: CGFloat
    let to: CGFloat
    let startedAt: Date

    func value(at date: Date) -> CGFloat {
        let fraction = min(1, max(0, date.timeIntervalSince(startedAt) / Self.duration))
        return from + (to - from) * fraction
    }
}

import SwiftUI

/// Stable circle positions for the happening field. The catalog constellation
/// uses a day-seeded spiral so large catalogs grow in two dimensions.
enum HappeningFieldLayout {
    private struct GridPoint {
        let x: Int
        let y: Int
    }

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
        var dateHubCenter: CGPoint? = nil

        /// Metal receives screen coordinates; ScrollView keeps the same sources
        /// in content coordinates for labels, hit testing and accessibility.
        func translated(by offset: CGPoint) -> Layout {
            Layout(
                sources: sources.map { Source(index: $0.index, center: CGPoint(x: $0.center.x - offset.x, y: $0.center.y - offset.y), radius: $0.radius, appearanceScale: $0.appearanceScale) },
                labelFrames: labelFrames.map { $0.offsetBy(dx: -offset.x, dy: -offset.y) },
                contourBounds: contourBounds.offsetBy(dx: -offset.x, dy: -offset.y),
                dockAnchor: dockAnchor, completionBounds: completionBounds, contentSize: contentSize,
                dateHubCenter: dateHubCenter.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
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

    /// A catalog constellation: the first items stay near the day centre and
    /// the rest spiral outward across a pannable two-dimensional field.
    /// Unlike the legacy event tree, it has no fixed node count or atlas.
    static func catalogLayout(
        count: Int,
        in size: CGSize,
        safeInsets: EdgeInsets,
        dynamicTypeSize: DynamicTypeSize = .large,
        dockCenterY: CGFloat? = nil
    ) -> Layout {
        let safeBounds = safeBounds(in: size, safeInsets: safeInsets)
        guard !safeBounds.isEmpty, count > 0 else {
            return Layout(sources: [], labelFrames: [], contourBounds: .zero,
                          dockAnchor: CGPoint(x: safeBounds.midX, y: safeBounds.maxY - dockHitRadius),
                          completionBounds: nil, contentSize: size)
        }

        let defaultDockY = safeBounds.maxY - dockHitRadius
        let dockAnchor = CGPoint(
            x: safeBounds.midX,
            y: min(safeBounds.maxY - dockHitRadius,
                   max(safeBounds.midY, dockCenterY ?? defaultDockY))
        )
        let typeScale = HappeningFieldLabelTypography.scaledUIFont(for: dynamicTypeSize).pointSize / 14
        let radius = min(78, max(60, targetRadius * typeScale))
        let step = radius * 2 + contactGap
        // Reserve the origin for the day-count hub; event one begins on the
        // first ring and the six roots naturally gather around it.
        let coordinates = Array(spiralCoordinates(count: count + 1).dropFirst())
        let minX = coordinates.map(\.x).min() ?? 0
        let maxX = coordinates.map(\.x).max() ?? 0
        let minY = coordinates.map(\.y).min() ?? 0
        let maxY = coordinates.map(\.y).max() ?? 0
        let padding = radius + edgeClearance
        let width = max(size.width, CGFloat(maxX - minX) * step + padding * 2)
        let height = max(size.height, CGFloat(maxY - minY) * step + padding * 2)
        let middleX = CGFloat(minX + maxX) / 2
        let middleY = CGFloat(minY + maxY) / 2
        let sources = coordinates.enumerated().map { index, point in
            Source(index: index, center: CGPoint(
                x: width / 2 + (CGFloat(point.x) - middleX) * step,
                y: height / 2 + (CGFloat(point.y) - middleY) * step
            ), radius: radius)
        }
        var result = makeLayout(sources: sources, dockAnchor: dockAnchor)
        result.contentSize = CGSize(width: width, height: height)
        result.dateHubCenter = CGPoint(x: width / 2, y: height / 2)
        return result
    }

    private static func spiralCoordinates(count: Int) -> [GridPoint] {
        var points: [GridPoint] = []
        points.reserveCapacity(count)
        var x = 0
        var y = 0
        var dx = 0
        var dy = -1
        for _ in 0..<count {
            points.append(GridPoint(x: x, y: y))
            if x == y || (x < 0 && x == -y) || (x > 0 && x == 1 - y) {
                (dx, dy) = (-dy, dx)
            }
            x += dx
            y += dy
        }
        return points
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

/// The tree uses identity-based hex cells rather than a count-based row packer.
/// Expanding the scroll surface adds the same offset to the date and every node.
enum HappeningEventTreeLayout {
    struct Field {
        let layout: HappeningFieldLayout.Layout
        let hubCenter: CGPoint
    }

    static func layout(
        nodes: [HappeningEventTreeState.PlacedEvent],
        in size: CGSize,
        safeInsets: EdgeInsets,
        contentTopInset: CGFloat,
        dockCenterY: CGFloat?
    ) -> Field {
        let width = max(1, size.width - safeInsets.leading - safeInsets.trailing)
        let gap: CGFloat = 10
        let radius = max(32, min(56, (width - 32 - gap * 2) / 6))
        let step = radius * 2 + gap
        let dockY = dockCenterY ?? (size.height - safeInsets.bottom - 36)
        let top = max(safeInsets.top + 16, contentTopInset)
        let bottom = max(top + step * sqrt(3) + radius * 2, dockY - 110)
        let initialHubY = (top + bottom) / 2
        let relative = nodes.map { node in
            CGPoint(x: step * (CGFloat(node.cell.q) + CGFloat(node.cell.r) / 2),
                    y: step * sqrt(3) / 2 * CGFloat(node.cell.r))
        }
        let extentX = relative.map { abs($0.x) + radius + 16 }.max() ?? 0
        let extentY = relative.map { abs($0.y) + radius }.max() ?? 0
        // Outer branches need scroll room below the top card and above the dock.
        let verticalPadding = max(top, size.height - dockY + 110)
        let verticalOffset = initialHubY - size.height / 2
        let world = CGSize(width: max(size.width, extentX * 2),
                           height: max(size.height, (extentY + verticalPadding + abs(verticalOffset)) * 2))
        let hub = CGPoint(x: world.width / 2, y: world.height / 2 + verticalOffset)
        let sources = relative.enumerated().map { index, point in
            HappeningFieldLayout.Source(index: index,
                center: CGPoint(x: hub.x + point.x, y: hub.y + point.y), radius: radius)
        }
        var result = HappeningFieldLayout.makeLayout(sources: sources,
            dockAnchor: CGPoint(x: size.width / 2, y: dockY))
        result.contentSize = world
        result.dateHubCenter = hub
        return Field(layout: result, hubCenter: hub)
    }

    static func focusOffset(center: CGPoint, contentSize: CGSize, viewportSize: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, center.x - viewportSize.width / 2), max(0, contentSize.width - viewportSize.width)),
                y: min(max(0, center.y - viewportSize.height / 2), max(0, contentSize.height - viewportSize.height)))
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

/// Viewport-relative size only; scrolling remains the native content transform.
enum HappeningFieldEdgeScale {
    static func factor(at center: CGPoint, visibleRect: CGRect) -> CGFloat {
        guard visibleRect.width > 0, visibleRect.height > 0 else { return 1 }
        let horizontal = abs(center.x - visibleRect.midX) / (visibleRect.width / 2)
        let vertical = abs(center.y - visibleRect.midY) / (visibleRect.height / 2)
        // Preserve a broad central area; use the same minimum at corners so
        // diagonal motion does not compound the shrink or compromise legibility.
        let edge = min(1, max(0, (max(horizontal, vertical) - 0.45) / 0.55))
        let smooth = edge * edge * (3 - 2 * edge)
        return 1 - 0.16 * smooth
    }

    static func apply(to layout: HappeningFieldLayout.Layout, visibleRect: CGRect, strength: CGFloat) -> HappeningFieldLayout.Layout {
        let amount = min(1, max(0, strength))
        guard amount > 0, !visibleRect.isEmpty else { return layout }
        let sources = layout.sources.map { source in
            let scale = 1 + (factor(at: source.center, visibleRect: visibleRect) - 1) * amount
            return HappeningFieldLayout.Source(index: source.index, center: source.center,
                radius: source.radius * scale, appearanceScale: source.appearanceScale * scale)
        }
        var result = HappeningFieldLayout.makeLayout(sources: sources, dockAnchor: layout.dockAnchor)
        result.contentSize = layout.contentSize
        return result
    }
}

/// Identity order is the complete event catalog in both modes. One sampled
/// layout drives Metal, titles and hit targets, including newly revealed cells.
struct HappeningEventFieldTransition {
    static let duration: TimeInterval = 0.58
    let from: HappeningFieldLayout.Layout
    let to: HappeningFieldLayout.Layout
    let startedAt: Date

    func progress(at date: Date) -> CGFloat {
        CGFloat(min(1, max(0, date.timeIntervalSince(startedAt) / Self.duration)))
    }

    func layout(at date: Date) -> HappeningFieldLayout.Layout {
        let phase = progress(at: date)
        let p = phase * phase * (3 - 2 * phase)
        // Keep one world for the duration of a transition. Once settled, the
        // tree returns to its own bounds rather than paying for the All surface.
        let world = CGSize(width: max(from.contentSize.width, to.contentSize.width),
                           height: max(from.contentSize.height, to.contentSize.height))
        func offset(_ layout: HappeningFieldLayout.Layout) -> CGPoint {
            CGPoint(x: (world.width - layout.contentSize.width) / 2,
                    y: (world.height - layout.contentSize.height) / 2)
        }
        let a = offset(from), b = offset(to)
        let sources = to.sources.enumerated().map { index, destination in
            let origin = index < from.sources.count ? from.sources[index] : destination
            let target = CGPoint(x: destination.center.x + b.x, y: destination.center.y + b.y)
            // A new tree neighbor grows in its own cell, keeping the stable
            // lattice clear; mode changes move already visible events too.
            let start = origin.appearanceScale <= 0.001 ? target
                : CGPoint(x: origin.center.x + a.x, y: origin.center.y + a.y)
            let end = destination.appearanceScale <= 0.001 ? start : target
            let scale = origin.appearanceScale + (destination.appearanceScale - origin.appearanceScale) * p
            let originRadius = origin.appearanceScale > 0.001 ? origin.radius / origin.appearanceScale
                : destination.radius / max(0.001, destination.appearanceScale)
            let targetRadius = destination.appearanceScale > 0.001 ? destination.radius / destination.appearanceScale : originRadius
            return HappeningFieldLayout.Source(index: index,
                center: CGPoint(x: start.x + (end.x - start.x) * p, y: start.y + (end.y - start.y) * p),
                radius: (originRadius + (targetRadius - originRadius) * p) * scale,
                appearanceScale: scale)
        }
        var result = HappeningFieldLayout.makeLayout(sources: sources, dockAnchor: to.dockAnchor)
        result.contentSize = world
        if let hub = to.dateHubCenter ?? from.dateHubCenter {
            let shift = to.dateHubCenter != nil ? b : a
            result.dateHubCenter = CGPoint(x: hub.x + shift.x, y: hub.y + shift.y)
        }
        return result
    }

    func hubOpacity(at date: Date) -> CGFloat {
        let p = progress(at: date)
        if from.dateHubCenter != nil, to.dateHubCenter != nil { return 1 }
        return to.dateHubCenter == nil ? 1 - p : p
    }
}

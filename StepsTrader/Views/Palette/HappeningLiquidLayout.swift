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
        [.init(x: 0.18, y: 0.16), .init(x: 0.50, y: 0.09), .init(x: 0.82, y: 0.18), .init(x: 0.18, y: 0.42), .init(x: 0.50, y: 0.34), .init(x: 0.82, y: 0.44), .init(x: 0.18, y: 0.69), .init(x: 0.50, y: 0.80), .init(x: 0.82, y: 0.69), .init(x: 0.50, y: 0.94)]
    ]

    static func layout(count: Int, in size: CGSize, safeInsets: EdgeInsets) -> Layout {
        let safeBounds = safeBounds(in: size, safeInsets: safeInsets)
        guard !safeBounds.isEmpty else {
            return Layout(sources: [], labelFrames: [], contourBounds: .zero, dockAnchor: .zero)
        }

        let itemCount = min(max(count, 0), templates.count - 1)
        guard itemCount > 0 else {
            return Layout(
                sources: [],
                labelFrames: [],
                contourBounds: .zero,
                dockAnchor: CGPoint(x: safeBounds.midX, y: safeBounds.maxY - 44)
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
            width: min(80, max(44, contourWidth * 0.20)),
            height: min(60, max(44, contourHeight * 0.14))
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
            dockAnchor: CGPoint(x: contourBounds.midX, y: contourBounds.maxY + dockTouchDistance)
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

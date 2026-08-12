import SwiftUI

/// The palette field: one tile per happening, each drawn as the figure that
/// happening will become on the canvas.
///
/// Replaces the metaball cluster, which drew a single iso-contour over ten
/// summed point fields — by construction that has no per-item silhouette to
/// show, only the outline of a merged mass.
struct HappeningShapeField: View {
    @Binding var presentation: HappeningLiquidPresentationState
    let happenings: [Happening]
    let figures: [String: HappeningShapeAssignment]
    let bounds: CGRect
    let highlightedID: String?
    let onPick: (Happening, CGPoint) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Three columns have to fit the field's width at the layout's pitch, and
    /// the label below needs room under each tile. 92 is the cap; narrow
    /// screens get whatever the width allows.
    private var tileSide: CGFloat {
        max(44, min(92, (bounds.width - 40) / 3))
    }

    var body: some View {
        let presented = presentation.presentedHappenings
        let frames = HappeningTileLayout.frames(
            count: presented.count,
            in: bounds,
            tileSide: tileSide
        )

        ZStack(alignment: .topLeading) {
            ForEach(Array(presented.enumerated()), id: \.element.id) { index, happening in
                if index < frames.count, let figure = figures[happening.id] {
                    tile(happening, figure: figure, frame: frames[index])
                }
            }
        }
        .onChange(of: happenings) { _, next in
            presentation.receiveParent(next, whileTransitioning: false)
        }
    }

    private func tile(
        _ happening: Happening,
        figure: HappeningShapeAssignment,
        frame: CGRect
    ) -> some View {
        VStack(spacing: 4) {
            HappeningShapeTile(
                element: HappeningShapeTile.previewElement(
                    optionId: happening.id,
                    label: happening.localizedTitle(),
                    shapeType: figure.shapeType,
                    colorHex: figure.colorHex,
                    seed: figure.seed,
                    rotation: figure.rotation
                ),
                side: tileSide
            )
            Text(happening.localizedTitle())
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppColors.Night.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: frame.width + 24)
        }
        // `contentShape` before `.position()`, never after: `.position()`
        // expands a view to fill its parent, so a shape applied afterwards
        // covers the whole field and the topmost tile swallows every tap.
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture { pick(happening, at: frame) }
        .position(x: frame.midX, y: frame.midY)
        .scaleEffect(highlightedID == happening.id ? 1.08 : 1)
        .animation(.easeInOut(duration: 0.28), value: highlightedID)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(happening.localizedTitle()))
    }

    /// The tile leaves the field only once the canvas has actually taken the
    /// happening. A tile that vanished on tap and then failed to spawn would
    /// lose the happening for the rest of the day.
    private func pick(_ happening: Happening, at frame: CGRect) {
        guard onPick(happening, CGPoint(x: frame.midX, y: frame.midY)) else { return }
        if reduceMotion {
            _ = presentation.remove(id: happening.id)
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                _ = presentation.remove(id: happening.id)
            }
        }
    }
}

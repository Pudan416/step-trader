import SwiftUI

/// One metric line in the data sheet.
struct CanvasDataRow: Identifiable, Equatable {
    let kind: MetricOverlayKind
    let title: String
    let systemImage: String
    let value: Int
    let maxValue: Int

    var id: String { kind.id }

    var fill: Double {
        guard maxValue > 0 else { return 0 }
        return min(1, Double(value) / Double(maxValue))
    }
}

/// The data behind today's canvas, as a sheet over the canvas rather than a
/// card that pushes it down.
///
/// Steps and Sleep come from HealthKit and are read-only here — the exploratory
/// mockups' small trailing `+` glyphs are not part of the product. Adding
/// something remains the single yellow `+` on Canvas.
struct CanvasDataPanel: View {
    let rows: [CanvasDataRow]
    let onSelect: (MetricOverlayKind) -> Void
    let onHide: () -> Void
    /// Space actually available for the panel between the chrome above it
    /// (status pill, suggestion banner) and the bottom action row below it.
    /// `nil` (previews, and defensively before the host has measured its own
    /// viewport) leaves the panel unconstrained — today's "hug the content"
    /// behavior, unchanged. This is deliberately not a fraction of the
    /// screen; the product owner retired the old 40%-of-available-height
    /// clamp, so this is literally "what's left" once the chrome above and
    /// the action row below are accounted for.
    var availableHeight: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether to cap-and-scroll instead of hugging content, decided from the
    /// environment rather than a measured row-stack height. This screen's
    /// canvas redraws continuously (the generative animation), which
    /// reconstructs this view on every frame and was found — empirically,
    /// via logging — to reset any `@State` used to remember a
    /// `GeometryReader`-measured height back to its default before
    /// `onPreferenceChange` ever got a chance to persist the real value.
    /// `dynamicTypeSize` carries no such risk: it's read fresh from the
    /// environment every render, so there's nothing to lose between renders.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dragOffset: CGFloat = 0

    /// Dismiss thresholds: a deliberate pull, or a flick that clearly meant it.
    private static let dismissDistance: CGFloat = 60
    private static let dismissVelocity: CGFloat = 700

    private var ink: Color { AppColors.Night.textPrimary }

    /// Room left for the rows once the handle, its spacing, and the panel's
    /// own vertical padding are accounted for.
    private var rowsMaxHeight: CGFloat? {
        guard let availableHeight else { return nil }
        let handleHeight: CGFloat = 4
        let headerToRowsSpacing: CGFloat = 12
        let verticalPadding: CGFloat = 10 + 16
        let overhead = handleHeight + headerToRowsSpacing + verticalPadding
        return max(80, availableHeight - overhead)
    }

    /// Whether the rows might outgrow the space actually available. At every
    /// ordinary Dynamic Type size — including the largest non-accessibility
    /// size, xxxLarge — this stays false and the panel renders exactly as it
    /// always has: no `ScrollView`, no cap. Only accessibility text sizes
    /// (AX1–AX5), where an unwrapped row `Text` can grow past the 52pt row
    /// minimum enough to matter, switch it on.
    private var isOverflowing: Bool {
        rowsMaxHeight != nil && dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            rowsStack
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        // No `maxHeight` clamp on the panel itself: it constrained the
        // proposal, not the render, so the rows drew outside the glass that
        // was supposed to contain them. The panel is sized by its content —
        // `rowsStack` below is what actually stops the rows from growing
        // past `availableHeight`, by switching to an internally scrolling
        // `ScrollView` once they measure taller than `rowsMaxHeight`.
        .frame(maxWidth: .infinity, alignment: .top)
        .glassCard(cornerRadius: 24, style: .lens)
        .offset(y: max(0, dragOffset))
        // At ordinary text sizes there is no `ScrollView` anywhere in this
        // tree (see `rowsStack`), so this is the only thing that can claim a
        // vertical drag and it fires no matter where on the panel the user
        // starts — a drag on the rows and a drag on the handle are the same
        // gesture landing on the same recognizer.
        //
        // Once accessibility text sizes push the rows past `rowsMaxHeight`,
        // `rowsStack` switches to a real `ScrollView`, and a vertical drag
        // over the rows becomes ambiguous between "scroll" and "dismiss".
        // `including: .subviews` resolves that explicitly: while overflowing,
        // this gesture recognizer steps aside entirely so the `ScrollView`'s
        // own pan gesture owns vertical drags over the rows. Dismissal still
        // works — via the bottom action row's "Hide data" button, which was
        // already the panel's second way to close per the `header` doc
        // comment below — it just isn't a body-wide drag while scrolling is
        // live, which is exactly what avoids fighting the `ScrollView` for
        // the same touch.
        .gesture(dismissDrag, including: isOverflowing ? .subviews : .all)
        // `.contain` keeps this container's own identifier addressable while
        // still exposing its children (each metric row) as their own
        // accessibility elements. Without it, SwiftUI collapses the panel
        // into a single accessibility element and every descendant reports
        // this identifier instead of its own, making the rows unreachable to
        // automation even though real touches still land correctly on the
        // visible controls.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_data_panel")
        .coachMarkAnchor(.categoriesRevealed)
    }

    @ViewBuilder
    private var rowsStack: some View {
        if isOverflowing, let rowsMaxHeight {
            ScrollView {
                rowsList
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: rowsMaxHeight)
        } else {
            rowsList
        }
    }

    private var rowsList: some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                rowView(row)
            }
        }
    }

    /// The bottom action row already carries `Hide data`; a second copy inside
    /// the panel was the same control twice on one screen. The handle stays —
    /// it is what makes the sheet feel draggable.
    private var header: some View {
        Capsule()
            .fill(ink.opacity(0.45))
            .frame(width: 36, height: 4)
            .accessibilityHidden(true)
    }

    private func rowView(_ row: CanvasDataRow) -> some View {
        Button {
            onSelect(row.kind)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.systemImage)
                    .font(.footnote)
                Text(row.title)
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(row.value)/\(row.maxValue)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.brandAccent.opacity(0.85))
                        .frame(width: max(0, proxy.size.width * row.fill))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ink.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.title), \(row.value) of \(row.maxValue)")
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Downward only — dragging up must not detach the sheet.
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let flicked = value.velocity.height > Self.dismissVelocity
                let pulled = value.translation.height > Self.dismissDistance
                if flicked || pulled {
                    // The ancestor's removal transition owns the exit from here.
                    // Springing `dragOffset` back at the same time would fight it
                    // and read as a rubber-band on the way out.
                    onHide()
                } else {
                    withAnimation(
                        reduceMotion
                            ? .easeInOut(duration: 0.15)
                            : .interactiveSpring(response: 0.32, dampingFraction: 0.86)
                    ) {
                        dragOffset = 0
                    }
                }
            }
    }
}

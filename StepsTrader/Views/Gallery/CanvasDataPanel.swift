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
    let onExplain: (MetricOverlayKind) -> Void
    let onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    /// Dismiss thresholds: a deliberate pull, or a flick that clearly meant it.
    private static let dismissDistance: CGFloat = 60
    private static let dismissVelocity: CGFloat = 700

    private var ink: Color { AppColors.Night.textPrimary }

    var body: some View {
        VStack(spacing: 12) {
            header
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        // No `maxHeight` clamp: it constrained the proposal, not the render, so
        // the rows drew outside the glass that was supposed to contain them.
        // The panel is sized by its content and the host gives it room.
        .frame(maxWidth: .infinity, alignment: .top)
        .glassCard(cornerRadius: 24, style: .lens)
        .offset(y: max(0, dragOffset))
        .gesture(dismissDrag)
        // `.contain` keeps this container's own identifier addressable while
        // still exposing its children (each metric row and its help button)
        // as their own accessibility elements. Without it, SwiftUI collapses
        // the panel into a single accessibility element and every descendant
        // reports this identifier instead of its own, making the rows
        // unreachable to automation even though real touches still land
        // correctly on the visible controls.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_data_panel")
        .coachMarkAnchor(.categoriesRevealed)
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
        HStack(spacing: 8) {
            Button {
                onExplain(row.kind)
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ink.opacity(0.35))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(localized: "What counts as \(row.title)?",
                       comment: "Canvas data panel – per-row explanation button")
            )
            .accessibilityIdentifier("canvas_row_help_\(row.kind.id)")

            rowButton(row)
        }
    }

    private func rowButton(_ row: CanvasDataRow) -> some View {
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

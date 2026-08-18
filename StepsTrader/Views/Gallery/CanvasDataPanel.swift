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
    let maxHeight: CGFloat
    let onSelect: (MetricOverlayKind) -> Void
    let onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    /// Dismiss thresholds: a deliberate pull, or a flick that clearly meant it.
    private static let dismissDistance: CGFloat = 60
    private static let dismissVelocity: CGFloat = 700

    private var ink: Color { AppColors.Night.textPrimary }

    /// A ceiling for growth, not a promise for today's three rows.
    ///
    /// SwiftUI's `.frame(maxHeight:)` constrains the PROPOSAL, not the render: a
    /// child whose own minimum exceeds it simply draws larger. Three 52 pt rows
    /// plus the header need ~266 pt, which is above 40% of the available space on
    /// every current iPhone, so the panel is content-sized in practice. The cap
    /// starts to bite once the row list grows past three.
    static func maxHeight(
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        max(0, (viewportHeight - topInset - bottomInset)) * 0.4
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .top)
        .glassCard(cornerRadius: 24, style: .lens)
        .offset(y: max(0, dragOffset))
        .gesture(dismissDrag)
        .accessibilityIdentifier("canvas_data_panel")
        .coachMarkAnchor(.categoriesRevealed)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(ink.opacity(0.45))
                .frame(width: 36, height: 4)
                .accessibilityHidden(true)

            Button(action: onHide) {
                HStack(spacing: 4) {
                    Text(String(localized: "Hide data", comment: "Canvas – collapse the data panel"))
                    Image(systemName: "chevron.down")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("canvas_hide_data_button")
        }
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

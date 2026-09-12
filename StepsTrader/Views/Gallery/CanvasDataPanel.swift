import SwiftUI

private struct DrawerSurface: ViewModifier {
    let isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVisible {
            content.canvasChromeSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            content
        }
    }
}

enum CanvasDataPanelSelection {
    static func toggling(
        _ tapped: MetricOverlayKind,
        current: MetricOverlayKind?
    ) -> MetricOverlayKind? {
        current == tapped ? nil : tapped
    }
}

private enum CanvasMetricDisclosure {
    static func explanation(for kind: MetricOverlayKind) -> String {
        switch kind {
        case .steps:
            return String(localized: "This part grows with your steps. As you move toward your daily goal, it adds up to 20 colors to the canvas.", comment: "Canvas data panel – inline steps explanation")
        case .sleep:
            return String(localized: "This part grows with your sleep. As you move toward your sleep goal, it adds up to 20 colors to the canvas. When sleep data is missing, Nowhere leaves room for it instead of calling it zero.", comment: "Canvas data panel – inline sleep explanation")
        case .happenings:
            return String(localized: "This part is shaped by the things you chose to notice today. Each different happening adds color once, up to 60 colors.", comment: "Canvas data panel – inline happenings explanation")
        }
    }

    static func researchURL(for kind: MetricOverlayKind) -> URL {
        switch kind {
        case .steps:
            return URL(string: "https://pubmed.ncbi.nlm.nih.gov/24749966/")!
        case .sleep:
            return URL(string: "https://www.nature.com/articles/nrn2762")!
        case .happenings:
            return URL(string: "https://www.sciencedirect.com/science/article/pii/S0022103112000212")!
        }
    }
}

enum CanvasDataPanelGesture {
    static let toggleDistance: CGFloat = 60
    static let toggleVelocity: CGFloat = 700

    static func shouldOpen(translation: CGFloat, velocity: CGFloat) -> Bool {
        velocity > toggleVelocity || translation > toggleDistance
    }

    static func shouldClose(translation: CGFloat, velocity: CGFloat) -> Bool {
        velocity < -toggleVelocity || translation < -toggleDistance
    }

    static func revealProgress(
        isExpanded: Bool,
        expandedHeight: CGFloat,
        externalPullDistance: CGFloat,
        handleDragDistance: CGFloat
    ) -> CGFloat {
        let height = max(expandedHeight, 1)
        if isExpanded {
            return max(0, 1 - handleDragDistance / height)
        }
        let pull = max(externalPullDistance, handleDragDistance)
        return min(1, max(0, pull / height))
    }
}

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

/// The data behind today's canvas. Its grabber is always the drawer's lower
/// edge: collapsed it rests just under the energy pill; pulling down stretches
/// the panel and carries the grabber to the bottom of the revealed rows.
struct CanvasDataPanel: View {
    let isExpanded: Bool
    let rows: [CanvasDataRow]
    /// A drag that started on the energy pill, owned by `MainTabView` because
    /// the pill lives above the tab content. A drag that starts on the grabber
    /// is tracked locally; both feed the same reveal geometry.
    var externalPullDistance: CGFloat = 0
    let selectedKind: MetricOverlayKind?
    let onSelect: (MetricOverlayKind) -> Void
    let onToggle: () -> Void
    var availableHeight: CGFloat? = nil

    @ScaledMetric(relativeTo: .body) private var minimumRowHeight: CGFloat = 62
    @ScaledMetric(relativeTo: .body) private var rowIconWidth: CGFloat = 18
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var localDragDistance: CGFloat = 0

    private static let rowSpacing: CGFloat = 6
    private static let topPadding: CGFloat = 14
    private static let rowsToHandleSpacing: CGFloat = 8
    private static let handleVisualHeight: CGFloat = 16
    private static let handleHitHeight: CGFloat = 44
    private static let handleHitExtension = handleHitHeight - handleVisualHeight

    @Environment(\.canvasChromePalette) private var palette
    private var ink: Color { palette.textColor }

    private var rowsMaxHeight: CGFloat? {
        guard let availableHeight else { return nil }
        let overhead = Self.topPadding + Self.rowsToHandleSpacing + Self.handleVisualHeight
        return max(80, availableHeight - overhead)
    }

    private var isOverflowing: Bool {
        guard let rowsMaxHeight else { return false }
        return dynamicTypeSize.isAccessibilitySize || estimatedRowsHeight > rowsMaxHeight
    }

    private var estimatedRowsHeight: CGFloat {
        let rowHeight = minimumRowHeight
        let gaps = CGFloat(max(0, rows.count - 1)) * Self.rowSpacing
        let disclosureHeight: CGFloat
        if selectedKind == nil {
            disclosureHeight = 0
        } else {
            disclosureHeight = dynamicTypeSize.isAccessibilitySize ? 240 : 126
        }
        return CGFloat(rows.count) * rowHeight + gaps + disclosureHeight
    }

    private var expandedRowsHeight: CGFloat {
        if isOverflowing, let rowsMaxHeight {
            return rowsMaxHeight
        }
        return estimatedRowsHeight
    }

    private var expandedHeight: CGFloat {
        Self.topPadding
            + expandedRowsHeight
            + Self.rowsToHandleSpacing
            + Self.handleVisualHeight
    }

    private var revealProgress: CGFloat {
        CanvasDataPanelGesture.revealProgress(
            isExpanded: isExpanded,
            expandedHeight: expandedHeight,
            externalPullDistance: externalPullDistance,
            handleDragDistance: localDragDistance
        )
    }

    private var currentHeight: CGFloat {
        Self.handleVisualHeight
            + (expandedHeight - Self.handleVisualHeight) * revealProgress
    }

    private var rowsOpacity: Double {
        Double(min(1, max(0, (revealProgress - 0.12) / 0.55)))
    }

    var body: some View {
        Group {
            if isExpanded {
                drawerContent
                    .accessibilityIdentifier("canvas_data_panel")
                    .coachMarkAnchor(.categoriesRevealed)
            } else {
                drawerContent
            }
        }
    }

    private var drawerContent: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: currentHeight)
            .background {
                Color.clear
                    .modifier(DrawerSurface(isVisible: revealProgress > 0.001))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                rowsStack
                    .padding(.horizontal, 14)
                    .padding(.top, Self.topPadding)
                    .frame(
                        height: max(0, currentHeight - Self.handleVisualHeight),
                        alignment: .top
                    )
                    .clipped()
                    .opacity(rowsOpacity)
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
            .overlay(alignment: .bottom) {
                handle
            }
            // The visible footer stays 16pt, while transparent padding below
            // it makes the physical target 44pt without covering the last row.
            .padding(.bottom, Self.handleHitExtension)
            .contentShape(Rectangle())
            // The recognizer observes the stable outer container. It only
            // updates for drags beginning in the footer target, and remains
            // simultaneous so row buttons and accessibility ScrollViews keep
            // their own gestures.
            .simultaneousGesture(toggleDrag)
            .accessibilityElement(children: .contain)
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
        VStack(spacing: Self.rowSpacing) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 0) {
                    rowView(row)

                    if selectedKind == row.kind {
                        metricDisclosure(for: row.kind)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    /// Visually this is only a 16pt footer, about one third of the former
    /// empty header. The negative inset preserves a forgiving 44pt gesture
    /// target without making the panel look thick.
    private var handle: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(palette.secondaryColor)
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.handleVisualHeight)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            isExpanded
                ? String(localized: "Hide canvas data", comment: "Canvas – data panel VoiceOver label")
                : String(localized: "Show canvas data", comment: "Canvas – data panel VoiceOver label")
        )
        .accessibilityValue(
            isExpanded
                ? String(localized: "Expanded", comment: "Canvas – data panel VoiceOver value")
                : String(localized: "Collapsed", comment: "Canvas – data panel VoiceOver value")
        )
        .accessibilityHint(
            isExpanded
                ? String(localized: "Double-tap or pull up to collapse", comment: "Canvas – data panel VoiceOver hint")
                : String(localized: "Double-tap or pull down to expand", comment: "Canvas – data panel VoiceOver hint")
        )
        .accessibilityAction {
            onToggle()
        }
        .accessibilityAction(
            named: isExpanded
                ? String(localized: "Collapse canvas data", comment: "Canvas – data panel VoiceOver action")
                : String(localized: "Expand canvas data", comment: "Canvas – data panel VoiceOver action")
        ) {
            onToggle()
        }
        .accessibilityIdentifier("canvas_show_data_button")
        .coachMarkAnchor(.expandChevron)
    }

    private func rowTitle(_ row: CanvasDataRow) -> some View {
        Text(row.title)
            .font(.geist(.body).weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rowValue(_ row: CanvasDataRow) -> some View {
        Text("\(row.value)/\(row.maxValue)")
            .font(.geist(.body).weight(.medium))
            .monospacedDigit()
            .fixedSize()
    }

    private func rowView(_ row: CanvasDataRow) -> some View {
        Button {
            onSelect(row.kind)
        } label: {
            VStack(spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: row.systemImage)
                        .font(.geist(16, weight: .medium, relativeTo: .body))
                        .frame(width: rowIconWidth)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 6) {
                            rowTitle(row)
                            rowValue(row)
                        }
                        Spacer(minLength: 8)
                    } else {
                        rowTitle(row)
                        Spacer(minLength: 8)
                        rowValue(row)
                    }
                    Image(systemName: selectedKind == row.kind ? "chevron.up" : "chevron.down")
                        .font(.geist(.caption2).weight(.medium))
                        .foregroundStyle(palette.secondaryColor)
                }
                .foregroundStyle(ink)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.trackColor)
                        Capsule().fill(palette.accentColor)
                            .frame(width: max(0, proxy.size.width * row.fill))
                    }
                }
                .frame(height: 4)
                .padding(.leading, rowIconWidth + 10)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: minimumRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.title), \(row.value) of \(row.maxValue)")
        .accessibilityValue(
            selectedKind == row.kind
                ? String(localized: "Expanded", comment: "Canvas metric disclosure – VoiceOver value")
                : String(localized: "Collapsed", comment: "Canvas metric disclosure – VoiceOver value")
        )
        .accessibilityHint(
            selectedKind == row.kind
                ? String(localized: "Double-tap to hide how this part is formed", comment: "Canvas metric disclosure – VoiceOver hint")
                : String(localized: "Double-tap to learn how this part is formed", comment: "Canvas metric disclosure – VoiceOver hint")
        )
    }

    private func metricDisclosure(for kind: MetricOverlayKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CanvasMetricDisclosure.explanation(for: kind))
                .font(.geist(.footnote))
                .foregroundStyle(palette.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: CanvasMetricDisclosure.researchURL(for: kind)) {
                HStack(spacing: 4) {
                    Text(String(localized: "Why this matters", comment: "Canvas metric disclosure – research link"))
                    Image(systemName: "arrow.up.right")
                }
                .font(.geist(.caption).weight(.medium))
                .foregroundStyle(palette.accentColor)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("canvas_metric_research_link_\(kind.id)")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityIdentifier("canvas_metric_disclosure_\(kind.id)")
    }

    private var toggleDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($localDragDistance) { value, distance, _ in
                guard dragStartsOnHandle(at: value.startLocation.y) else { return }
                distance = isExpanded
                    ? max(0, -value.translation.height)
                    : max(0, value.translation.height)
            }
            .onEnded { value in
                guard dragStartsOnHandle(at: value.startLocation.y) else { return }
                let crossedThreshold = isExpanded
                    ? CanvasDataPanelGesture.shouldClose(
                        translation: value.translation.height,
                        velocity: value.velocity.height
                    )
                    : CanvasDataPanelGesture.shouldOpen(
                        translation: value.translation.height,
                        velocity: value.velocity.height
                    )

                if crossedThreshold {
                    onToggle()
                }
            }
    }

    private func dragStartsOnHandle(at localY: CGFloat) -> Bool {
        let restingHeight = isExpanded ? expandedHeight : Self.handleVisualHeight
        return localY >= restingHeight - Self.handleVisualHeight
            && localY <= restingHeight + Self.handleHitExtension
    }
}

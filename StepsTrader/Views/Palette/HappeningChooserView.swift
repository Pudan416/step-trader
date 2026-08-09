import SwiftUI
import UIKit

/// The explicit reading order for the floating panels. The values below are
/// consumed by SwiftUI's sort priorities so the contract is testable without
/// relying on pixel- or accessibility-server inspection.
enum HappeningPanelAccessibilityOrder {
    enum Role: Equatable {
        case heading
        case status
        case search
        case rows
        case input
        case actions
    }

    static let chooser: [Role] = [.heading, .status, .search, .rows, .actions]
    static let creator: [Role] = [.heading, .input, .actions]

    static func priority(for role: Role, in order: [Role]) -> Double {
        guard let index = order.firstIndex(of: role) else { return 0 }
        return Double(order.count - index)
    }
}

/// A transactional editor for the palette's fixed ten happening slots.
/// Closing it with Cancel leaves its parent selection untouched; only Done
/// sends the complete draft back to the owner for persistence.
struct HappeningChooserView: View {
    let catalog: [Happening]
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    @State private var draft: HappeningPaletteSelectionDraft
    @State private var query = ""

    init(
        catalog: [Happening],
        selected: [String],
        onSave: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.catalog = catalog
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: HappeningPaletteSelectionDraft(selected: selected, catalog: catalog))
    }

    private var filteredCatalog: [Happening] {
        guard !query.isEmpty else { return catalog }
        return catalog.filter { happening in
            happening.localizedTitle().localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose happenings")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(
                        HappeningPanelAccessibilityOrder.priority(
                            for: .heading,
                            in: HappeningPanelAccessibilityOrder.chooser
                        )
                    )

                Text("\(draft.ids.count) of \(HappeningPaletteSelection.slotCount) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilitySortPriority(
                        HappeningPanelAccessibilityOrder.priority(
                            for: .status,
                            in: HappeningPanelAccessibilityOrder.chooser
                        )
                    )

                TextField(
                    "Search happenings",
                    text: $query,
                    prompt: Text("Search happenings").foregroundStyle(.secondary)
                )
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .happeningPanelTextFieldStyle()
                    .accessibilitySortPriority(
                        HappeningPanelAccessibilityOrder.priority(
                            for: .search,
                            in: HappeningPanelAccessibilityOrder.chooser
                        )
                    )

                LazyVStack(spacing: 2) {
                    ForEach(filteredCatalog) { happening in
                        chooserRow(for: happening)
                    }
                }
                .accessibilitySortPriority(
                    HappeningPanelAccessibilityOrder.priority(
                        for: .rows,
                        in: HappeningPanelAccessibilityOrder.chooser
                    )
                )

                HStack {
                    Button("Cancel") {
                        draft.cancel()
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Done") {
                        onSave(draft.ids)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave)
                }
                .accessibilitySortPriority(
                    HappeningPanelAccessibilityOrder.priority(
                        for: .actions,
                        in: HappeningPanelAccessibilityOrder.chooser
                    )
                )
            }
            .padding(20)
        }
        .scrollIndicators(.visible)
        .frame(maxHeight: 560)
        .frame(maxWidth: 440, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func chooserRow(for happening: Happening) -> some View {
        let isSelected = draft.ids.contains(happening.id)

        Button {
            switch draft.toggle(id: happening.id) {
            case .limitReached:
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Ten happenings are already selected. Deselect one before choosing another."
                )
            case .added, .removed, .unavailable:
                break
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)

                Text(happening.localizedTitle())
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(happening.localizedTitle())
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(
            isSelected
                ? "Double tap to remove from the palette."
                : draft.ids.count == HappeningPaletteSelection.slotCount
                    ? "Deselect a happening before choosing another."
                    : "Double tap to add to the palette."
        )
    }
}

#Preview("Chooser — Accessibility") {
    HappeningChooserView(
        catalog: HappeningDefaults.builtIns + [
            Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false),
            Happening(id: "legacy_yoga", title: "Yoga", isBuiltIn: false)
        ],
        selected: HappeningDefaults.builtIns.map(\.id),
        onSave: { _ in },
        onCancel: {}
    )
    .padding()
    .dynamicTypeSize(.accessibility1)
    .frame(height: 360)
}

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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose happenings")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(
                        HappeningPanelAccessibilityOrder.priority(
                            for: .heading,
                            in: HappeningPanelAccessibilityOrder.chooser
                        )
                    )

                Text("\(draft.ids.count)/\(HappeningPaletteSelection.slotCount)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        draft.ids.count == HappeningPaletteSelection.slotCount
                            ? AppColors.brandAccent
                            : Color.secondary
                    )
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredCatalog) { happening in
                        chooserRow(for: happening)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .accessibilitySortPriority(
                    HappeningPanelAccessibilityOrder.priority(
                        for: .rows,
                        in: HappeningPanelAccessibilityOrder.chooser
                    )
                )
            }
            .scrollIndicators(.visible)

            Divider()

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
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .accessibilitySortPriority(
                HappeningPanelAccessibilityOrder.priority(
                    for: .actions,
                    in: HappeningPanelAccessibilityOrder.chooser
                )
            )
        }
        .frame(maxHeight: 560)
        .frame(maxWidth: 440, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            // Name on the left, its mark on the right. A leading checkbox reads
            // as a settings table; the eye should land on what the happening is
            // called first and on whether it is in the palette second.
            HStack(spacing: 12) {
                Text(happening.localizedTitle())
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(isSelected ? AppColors.brandAccent : Color.clear)
                        .overlay {
                            Circle().strokeBorder(
                                isSelected
                                    ? Color.clear
                                    : Color.primary.opacity(0.25),
                                lineWidth: 1.5
                            )
                        }
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.8))
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
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

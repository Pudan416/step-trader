import SwiftUI

/// Transparent labels and hit targets over the renderer's fixed ten actors.
struct HappeningShapeField: View {
    let happenings: [Happening]
    let assignments: [String: HappeningEditorialAssignment]
    let layout: HappeningFieldLayout.Layout
    let interaction: HappeningPaletteInteractionState
    let addedIDs: Set<String>
    let onActivate: (Happening) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(happenings.prefix(10).enumerated()), id: \.element.id) { index, happening in
                if index < layout.sources.count {
                    happeningButton(happening, source: layout.sources[index])
                }
            }
        }
    }

    private func happeningButton(
        _ happening: Happening,
        source: HappeningFieldLayout.Source
    ) -> some View {
        let state = interaction.visualState(for: happening.id, addedIDs: addedIDs)
        let locked = assignments[happening.id] == nil || interaction.pendingMutation != nil
        let side = max(44, source.radius * 2)

        return ZStack {
            Button {
                onActivate(happening)
            } label: {
                ZStack {
                    Text(happening.localizedTitle())
                        .font(.geist(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: side * 0.80)

                    if state == .additionPreview || state == .removalPreview {
                        Text(state == .additionPreview ? LocalizedStringKey("Add") : LocalizedStringKey("Delete"))
                            .font(.geist(size: 12, weight: .medium))
                            .accessibilityIdentifier("happening_action_\(happening.id)")
                            .offset(y: side * 0.30)
                    }
                }
                    .foregroundStyle(.white)
                    // Local contrast stays behind the glyphs, not a label plate.
                    .shadow(color: .black.opacity(0.65), radius: 1.5, y: 0.5)
                    .frame(width: side * 0.80, height: side * 0.76)
                    .frame(width: side, height: side)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .accessibilityLabel(happening.localizedTitle())
            .accessibilityValue(HappeningPaletteAccessibility.value(for: state))
            .accessibilityHint(hint(for: state, locked: locked))
            .accessibilityIdentifier("happening_choice_\(happening.id)")

            if state == .added {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .liquidGlassControl(in: Circle())
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("happening_status_added_\(happening.id)")
                    .allowsHitTesting(false)
                    .offset(x: side * 0.30, y: -side * 0.30)
            }
        }
        .frame(width: side, height: side)
        .position(source.center)
    }

    private func hint(for state: HappeningPaletteSlotVisualState, locked: Bool) -> String {
        if locked { return String(localized: "This happening is temporarily unavailable. Try again.") }
        switch state {
        case .available: return String(localized: "Activate to preview adding to Canvas")
        case .additionPreview: return String(localized: "Activate again to add to Canvas")
        case .added: return String(localized: "Activate to preview removing from Canvas")
        case .removalPreview: return String(localized: "Activate again to remove from Canvas")
        }
    }
}

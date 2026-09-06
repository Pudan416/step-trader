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
                Text(happening.localizedTitle())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    // A tiny crisp edge plus a soft glyph halo keeps white type
                    // readable over the yellow sphere without adding a label plate.
                    .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: 0.75)
                    .shadow(color: .black.opacity(0.7), radius: 1.25)
                    .frame(width: side * 0.80, height: side * 0.76)
                    .frame(width: side, height: side)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .accessibilityLabel(happening.localizedTitle())
            .accessibilityValue(addedIDs.contains(happening.id)
                ? String(localized: "On Canvas") : String(localized: "Available"))
            .accessibilityHint(hint(for: state, locked: locked))
            .accessibilityIdentifier("happening_choice_\(happening.id)")

            if state == .added || state == .removalPreview {
                Image(systemName: state == .removalPreview ? "minus" : "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .liquidGlassControl(in: Circle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "On Canvas"))
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

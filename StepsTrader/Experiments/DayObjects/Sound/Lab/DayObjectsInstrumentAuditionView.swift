#if DEBUG || INTERNAL_BUILD
import SwiftUI

struct DayObjectsInstrumentAuditionView: View {
    @ObservedObject var controller: DayObjectsInstrumentAuditionController
    var beforeAudition: @MainActor () async -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instrument audition")
                .font(.geist(.caption).weight(.semibold))

            Picker("Category", selection: Binding(
                get: { controller.selectedCategory },
                set: { controller.selectCategory($0) }
            )) {
                ForEach(DayObjectsInstrumentCategory.allCases, id: \.self) { category in
                    Text(category.rawValue.capitalized).tag(category)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("dayObjects.audition.category")
            .accessibilityValue(controller.selectedCategory.rawValue.capitalized)

            if !controller.presets.isEmpty {
                Picker("Preset", selection: Binding(
                    get: { controller.selectedDescriptor?.id },
                    set: { if let id = $0 { controller.selectPreset(id) } }
                )) {
                    ForEach(controller.presets, id: \.id) { preset in
                        Text(preset.displayName).tag(Optional(preset.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("dayObjects.audition.preset")
                .accessibilityValue("\(controller.presets.count) presets")
            }

            HStack(spacing: 8) {
                Button("Note") {
                    Task {
                        await beforeAudition()
                        await controller.auditionNote()
                    }
                }
                    .buttonStyle(.bordered)
                    .disabled(!controller.allowsNote || controller.soundState == .starting)
                    .accessibilityIdentifier("dayObjects.audition.note")
                    .accessibilityValue(actionAvailability(controller.allowsNote))
                Button("Chord") {
                    Task {
                        await beforeAudition()
                        await controller.auditionChord()
                    }
                }
                    .buttonStyle(.bordered)
                    .disabled(!controller.allowsChord || controller.soundState == .starting)
                    .accessibilityIdentifier("dayObjects.audition.chord")
                    .accessibilityValue(actionAvailability(controller.allowsChord))
                Button("Hit") {
                    Task {
                        await beforeAudition()
                        await controller.auditionHit()
                    }
                }
                    .buttonStyle(.bordered)
                    .disabled(!controller.allowsHit || controller.soundState == .starting)
                    .accessibilityIdentifier("dayObjects.audition.hit")
                    .accessibilityValue(actionAvailability(controller.allowsHit))
            }
            .controlSize(.small)

            Text(controller.attribution)
                .font(.geist(.caption2))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dayObjects.audition.attribution")
            Text(controller.diagnostics)
                .font(.geist(.caption2).monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dayObjects.audition.diagnostics")
        }
        .accessibilityElement(children: .contain)
    }

    private func actionAvailability(_ allowedForCategory: Bool) -> String {
        if !allowedForCategory {
            return "disabled for \(controller.selectedCategory.rawValue.capitalized)"
        }
        return controller.soundState == .starting ? "disabled while loading" : "enabled"
    }
}
#endif

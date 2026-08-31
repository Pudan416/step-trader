#if DEBUG || INTERNAL_BUILD
import SwiftUI

struct DayObjectsInstrumentAuditionView: View {
    @ObservedObject var controller: DayObjectsInstrumentAuditionController

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
            }

            Toggle("Sound", isOn: Binding(
                get: { controller.soundState == .on || controller.soundState == .starting },
                set: { enabled in
                    Task {
                        if enabled { await controller.turnSoundOn() }
                        else { await controller.stop() }
                    }
                }
            ))
            .accessibilityIdentifier("dayObjects.audition.sound")

            HStack(spacing: 8) {
                Button("Note", action: controller.auditionNote)
                    .buttonStyle(.bordered)
                    .disabled(!controller.allowsNote || controller.soundState != .on)
                    .accessibilityIdentifier("dayObjects.audition.note")
                Button("Chord", action: controller.auditionChord)
                    .buttonStyle(.bordered)
                    .disabled(!controller.allowsChord || controller.soundState != .on)
                    .accessibilityIdentifier("dayObjects.audition.chord")
                Button("Hit", action: controller.auditionHit)
                    .buttonStyle(.bordered)
                    .disabled(!controller.allowsHit || controller.soundState != .on)
                    .accessibilityIdentifier("dayObjects.audition.hit")
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
}
#endif

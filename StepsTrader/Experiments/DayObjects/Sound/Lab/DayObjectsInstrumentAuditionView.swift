#if DEBUG || INTERNAL_BUILD
import SwiftUI

struct DayObjectsInstrumentAuditionView: View {
    @ObservedObject var controller: DayObjectsInstrumentAuditionController
    @ObservedObject var musicController: DayObjectsMusicLabController
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

            diagnosticMixControls

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

    private var diagnosticMixControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Mix mode", selection: Binding(
                get: { musicController.auditionMode },
                set: { musicController.selectAuditionMode($0) }
            )) {
                Text("Full composition").tag(DayObjectsAuditionMode.fullComposition)
                ForEach(DayObjectsRoleBus.allCases, id: \.self) { role in
                    Text("Solo \(role.name)").tag(DayObjectsAuditionMode.isolatedBus(role))
                }
            }
            .pickerStyle(.menu)
            .disabled(!canvasSoundIsOn)
            .accessibilityIdentifier("dayObjects.audition.mode")
            .accessibilityValue(canvasSoundIsOn ? modeLabel : "requires Sound")

            HStack(spacing: 5) {
                ForEach(DayObjectsRoleBus.allCases, id: \.self) { role in
                    Button(role.name) {
                        musicController.selectAuditionMode(.isolatedBus(role))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canvasSoundIsOn)
                    .accessibilityIdentifier("dayObjects.audition.bus.\(role.identifier)")
                }
            }
            .controlSize(.mini)

            Button("Kick + Bass") {
                Task {
                    await beforeAudition()
                    await controller.auditionKickBassSidechain()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!canvasSoundIsOn || controller.soundState == .starting)
            .accessibilityIdentifier("dayObjects.audition.sidechain")
            .accessibilityValue(canvasSoundIsOn ? sidechainValue : "requires Sound")

            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                meterRows()
                    .task(id: context.date) {
                        musicController.refreshDiagnosticMeters(now: context.date)
                    }
            }
        }
    }

    @ViewBuilder
    private func meterRows() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(musicController.busMeterRows, id: \.role) { row in
                Text("\(row.role.name)  P \(decibels(row.peakDBFS))  R \(decibels(row.rmsDBFS))  V \(row.activeVoiceCount)")
            }
            Text("Master  P \(decibels(musicController.masterMeterRow.peakDBFS))  Lim \(musicController.masterMeterRow.estimatedLimiterReductionDB.formatted(.number.precision(.fractionLength(1)))) dB")
                .accessibilityIdentifier("dayObjects.audition.masterMeter")
        }
        .font(.geist(.caption2).monospaced())
        .foregroundStyle(.secondary)
    }

    private var canvasSoundIsOn: Bool { musicController.soundState == .on }

    private var modeLabel: String {
        switch musicController.auditionMode {
        case .fullComposition: "Full composition"
        case let .isolatedBus(role): "Solo \(role.name)"
        case .kickBassSidechain: "Kick + Bass"
        }
    }

    private var sidechainValue: String {
        guard controller.displayedSidechainReductionDB > 0 else { return "ready" }
        return "\(controller.displayedSidechainReductionDB.formatted(.number.precision(.fractionLength(1)))) dB reduction"
    }

    private func decibels(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func actionAvailability(_ allowedForCategory: Bool) -> String {
        if !allowedForCategory {
            return "disabled for \(controller.selectedCategory.rawValue.capitalized)"
        }
        return controller.soundState == .starting ? "disabled while loading" : "enabled"
    }
}

private extension DayObjectsRoleBus {
    var name: String {
        switch self {
        case .rhythm: "Rhythm"
        case .bass: "Bass"
        case .harmony: "Harmony"
        case .happenings: "Happenings"
        case .lead: "Lead"
        }
    }

    var identifier: String {
        switch self {
        case .rhythm: "rhythm"
        case .bass: "bass"
        case .harmony: "harmony"
        case .happenings: "happenings"
        case .lead: "lead"
        }
    }
}
#endif

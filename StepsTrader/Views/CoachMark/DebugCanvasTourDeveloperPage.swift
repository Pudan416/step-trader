#if DEBUG
import SwiftUI

struct DebugCanvasTourDeveloperPage: View {
    @ObservedObject var model: AppModel
    @State private var jumpStep: CanvasTourStep = .welcome
    @State private var prerequisite: String?
    @State private var jumpGroupID = ""
    private var tour: DebugCanvasTour { .shared }

    var body: some View {
        @Bindable var tour = tour
        Form {
            Section("Live") {
                Text("This tour uses the real app. Happenings, app groups and color spending are saved normally. Restart resets only the tour.")
                    .font(.geist(.callout))
                Button("Start from welcome") { tour.start() }
                    .accessibilityIdentifier("canvas_tour.debug.start")
                Button("Restart tour") { tour.start(source: "restart") }
                    .accessibilityIdentifier("canvas_tour.debug.restart")
                Button("Resume") { tour.resume(groupIDs: Set(model.ticketGroups.map(\.id))) }
                    .disabled(!tour.canResume)
                    .accessibilityIdentifier("canvas_tour.debug.resume")
                Button("Stop tour") { tour.stop() }
                    .disabled(!tour.isActive)
                    .accessibilityIdentifier("canvas_tour.debug.stop")
            }
            Section("Start from step") {
                Picker("Step", selection: $jumpStep) {
                    ForEach(CanvasTourStep.allCases) { step in Text(step.rawValue).tag(step) }
                }
                if [.selectionResult, .selectFeed, .chooseDuration].contains(jumpStep) {
                    Picker("Existing group", selection: $jumpGroupID) {
                        Text("Choose a group").tag("")
                        ForEach(model.ticketGroups.filter { $0.selection.hasGroupTargets }) { group in
                            Text(group.name.isEmpty ? group.displayIdentity.title : group.name).tag(group.id)
                        }
                    }
                }
                Button("Start selected step") {
                    prerequisite = missingPrerequisite(for: jumpStep)
                    if prerequisite == nil { tour.start(at: jumpStep, source: "jump", selectedGroupID: jumpGroupID.isEmpty ? nil : jumpGroupID) }
                }.accessibilityIdentifier("canvas_tour.debug.jump")
                if let prerequisite { Text(prerequisite).font(.geist(.caption)) }
            }
            Section("Quiet controls") {
                Picker("Quiet controls", selection: $tour.quietMode) {
                    ForEach(CanvasTourQuietMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented)
            }
            Section("Diagnostics") {
                LabeledContent("Flow", value: "\(tour.flowVersion) · Live")
                LabeledContent("Session", value: tour.sessionID.uuidString)
                LabeledContent("Step", value: tour.step.rawValue)
                LabeledContent("Entry source", value: tour.entrySource)
                LabeledContent("Completed", value: tour.completedSteps.map(\.rawValue).sorted().joined(separator: ", "))
                LabeledContent("Skipped", value: tour.skippedBranches.sorted().joined(separator: ", "))
                LabeledContent("Status", value: tour.status.rawValue)
                LabeledContent("Expected event", value: tour.step.expectedEvent)
                LabeledContent("Target", value: tour.targetID ?? "none")
                LabeledContent("Target visible", value: tour.targetVisible ? "yes" : "no")
                LabeledContent("Frame", value: tour.targetFrameDescription)
                LabeledContent("Sheet", value: tour.presentedSheet ?? "none")
                LabeledContent("Return context", value: tour.returnContext)
                LabeledContent("Operation", value: tour.operation.map { "\($0.name) \($0.id)" } ?? "none")
                LabeledContent("Group", value: tour.selectedGroupID ?? "none")
                LabeledContent("Entry", value: tour.addedEntryID ?? "none")
                LabeledContent("Colors available", value: model.totalStepsBalance.formatted())
                LabeledContent("Steps query", value: model.healthStore.debugStepsQueryOutcome.rawValue)
                LabeledContent("Sleep query", value: model.healthStore.debugSleepQueryOutcome.rawValue)
                LabeledContent("App access", value: model.blockingStore.isAuthorized ? "authorized" : "needed")
                LabeledContent("Prerequisite", value: missingPrerequisite(for: jumpStep) ?? "available")
                Button("Copy local log") {
                    UIPasteboard.general.string = tour.transitions.joined(separator: "\n")
                }.accessibilityIdentifier("canvas_tour.debug.copyLog")
                ForEach(Array(tour.transitions.suffix(30).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.geist(.caption2)).textSelection(.enabled)
                }
            }
        }
        .font(.geist(.body))
        .navigationTitle("Canvas onboarding (Debug)")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func missingPrerequisite(for step: CanvasTourStep) -> String? {
        switch step {
        case .happening: return "Start at Add and open the palette with +."
        case .healthValue, .healthResult: return "Start at Balance and open the panel by tapping or dragging."
        case .chooseDuration: return "Start at Select feed, then tap the real group to open its duration choices."
        case .selectionResult, .selectFeed:
            return model.ticketGroups.contains { $0.id == jumpGroupID && $0.selection.hasGroupTargets }
                ? nil : "Choose an existing valid group, or start at Add apps to save one."
        default: return nil
        }
    }
}
#endif

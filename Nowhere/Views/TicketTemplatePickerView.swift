import SwiftUI
import FamilyControls
#if DEBUG && targetEnvironment(simulator)
import ManagedSettings
#endif

/// Shared form and commit validation. Only one application can use its system title.
enum AppGroupNamePolicy {
    static func canSave(selection: FamilyActivitySelection, name: String) -> Bool {
        selection.hasGroupTargets && (selection.isSingleApplication || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

/// A local draft survives moving between steps; dismissal never commits it.
struct AppGroupEditorDraft {
    enum Step { case selection, details }
    var selection: FamilyActivitySelection
    var name: String
    var launchTarget: String
    var step: Step
    private var suggestedName: String? = nil

    init(selection: FamilyActivitySelection, name: String, launchTarget: String?, isEditing: Bool) {
        self.selection = selection
        self.name = name
        self.launchTarget = launchTarget ?? ""
        step = isEditing ? .details : .selection
    }

    mutating func updateSelection(_ updated: FamilyActivitySelection) {
        if updated != selection {
            launchTarget = ""
            if name == suggestedName { name = "" }
            suggestedName = nil
        }
        selection = updated
    }

    mutating func chooseLaunchTarget(_ target: String) {
        launchTarget = target
        guard !target.isEmpty else {
            if name == suggestedName { name = "" }
            suggestedName = nil
            return
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == suggestedName {
            name = TargetResolver.displayName(for: target)
            suggestedName = name
        }
    }

    mutating func editName(_ updated: String) {
        name = updated
        suggestedName = nil
    }
}

struct NewAppGroupSheet: View {
    let onSave: (FamilyActivitySelection, String, String?) -> Void
    let isEditing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppGroupEditorDraft
    @State private var hasSaved = false
    @FocusState private var nameFocused: Bool

    init(selection: FamilyActivitySelection = FamilyActivitySelection(), name: String = "",
         templateApp: String? = nil, isEditing: Bool = false,
         onSave: @escaping (FamilyActivitySelection, String, String?) -> Void) {
        var draftSelection = selection
        #if DEBUG && targetEnvironment(simulator)
        // The simulator picker cannot produce authorized tokens. Fixtures exercise
        // our steps and persistence while the actual picker remains visible.
        let arguments = ProcessInfo.processInfo.arguments
        if !isEditing, arguments.contains("ui-testing"), arguments.contains("ui-testing-feed-selection"),
           let token = try? JSONDecoder().decode(ApplicationToken.self, from: Data(#"{"data":"AQ=="}"#.utf8)) {
            draftSelection.applicationTokens = [token]
            if arguments.contains("ui-testing-feed-multiple"),
               let second = try? JSONDecoder().decode(ApplicationToken.self, from: Data(#"{"data":"Ag=="}"#.utf8)) {
                draftSelection.applicationTokens.insert(second)
            }
        }
        #endif
        _draft = State(initialValue: AppGroupEditorDraft(selection: draftSelection, name: name,
            launchTarget: templateApp, isEditing: isEditing))
        self.isEditing = isEditing
        self.onSave = onSave
    }

    private var pickerSelection: Binding<FamilyActivitySelection> {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("ui-testing"), arguments.contains("ui-testing-feed-selection") {
            return .constant(draft.selection)
        }
        #endif
        return Binding(get: { draft.selection }, set: { draft.updateSelection($0) })
    }

    private var launchOptions: [String] {
        AppGroupIdentity.applicationNames.keys.filter { TargetResolver.canOpen(bundleId: $0) }
            .sorted { TargetResolver.displayName(for: $0) < TargetResolver.displayName(for: $1) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if draft.step == .selection {
                    VStack(spacing: 0) {
                        Text(String(localized: "Choose apps to unlock with your colors."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        FamilyActivityPicker(selection: pickerSelection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    details
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(draft.step == .selection ? String(localized: "Choose apps to block") :
                (isEditing ? String(localized: "Edit feed") : String(localized: "New feed")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .accessibilityIdentifier("feed.selection.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if draft.step == .selection {
                        Button(String(localized: "Continue")) { draft.step = .details }
                            .disabled(!draft.selection.hasGroupTargets)
                            .accessibilityIdentifier("feed.selection.continue")
                    } else {
                        Button(isEditing ? String(localized: "Save changes") : String(localized: "Add to Feeds")) { save() }
                            .disabled(!AppGroupNamePolicy.canSave(selection: draft.selection, name: draft.name) || hasSaved)
                            .accessibilityIdentifier("feed.selection.create")
                    }
                }
            }
        }
    }

    private var details: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(draft.selection.applicationTokens.prefix(3)), id: \.self) { token in
                        Label(token).labelStyle(.titleAndIcon)
                    }
                    ForEach(Array(draft.selection.categoryTokens.prefix(max(0, 3 - draft.selection.applicationTokens.count))), id: \.self) { token in
                        Label(token).labelStyle(.titleAndIcon)
                    }
                    ForEach(Array(draft.selection.webDomainTokens.prefix(max(0, 3 - draft.selection.applicationTokens.count - draft.selection.categoryTokens.count))), id: \.self) { token in
                        Label(token).labelStyle(.titleAndIcon)
                    }
                    let remaining = draft.selection.applicationTokens.count + draft.selection.categoryTokens.count + draft.selection.webDomainTokens.count - 3
                    if remaining > 0 {
                        Text(String(localized: "\(remaining) more"))
                            .foregroundStyle(.secondary)
                    }
                    Button(String(localized: "Change apps")) {
                        nameFocused = false
                        draft.step = .selection
                    }
                    .accessibilityIdentifier("feed.selection.change")
                }
            } header: {
                Text(AppGroupIdentity(name: draft.name, templateApp: nil, applicationCount: draft.selection.applicationTokens.count, categoryCount: draft.selection.categoryTokens.count, webDomainCount: draft.selection.webDomainTokens.count).detail)
            }
            Section {
                TextField(String(localized: "e.g. Social"),
                    text: Binding(get: { draft.name }, set: { draft.editName($0) }))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
                    .accessibilityIdentifier("feed.name")
            } header: {
                Text(draft.selection.isSingleApplication ? String(localized: "Name (optional)") : String(localized: "Group name"))
            } footer: {
                Text(draft.selection.isSingleApplication ? String(localized: "Leave blank to use the app’s name.") :
                    String(localized: "Give this group a name for Feeds and widgets."))
            }
            if draft.selection.isSingleApplication {
                Section {
                    Picker("Open from widget", selection: Binding(get: { draft.launchTarget }, set: { draft.chooseLaunchTarget($0) })) {
                        Text("Nowhere").tag("")
                        ForEach(launchOptions, id: \.self) { bundleID in
                            Text(TargetResolver.displayName(for: bundleID)).tag(bundleID)
                        }
                    }
                    .accessibilityIdentifier("feed.launchTarget")
                } footer: {
                    Text("Choose the same app you selected. Used after unlocking.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() {
        guard !hasSaved, AppGroupNamePolicy.canSave(selection: draft.selection, name: draft.name) else { return }
        hasSaved = true
        let confirmedTarget = AppGroupIdentity.widgetLaunchBundleId(
            templateApp: draft.launchTarget,
            selectionData: try? JSONEncoder().encode(draft.selection)
        )
        onSave(draft.selection, draft.name.trimmingCharacters(in: .whitespacesAndNewlines), confirmedTarget)
        dismiss()
    }
}

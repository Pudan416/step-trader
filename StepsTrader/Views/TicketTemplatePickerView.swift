import SwiftUI
import FamilyControls
#if DEBUG && targetEnvironment(simulator)
import ManagedSettings
#endif

/// Name and selection stay local until Save. Cancel (including swipe dismissal)
/// never creates a group or changes an existing one.
struct NewAppGroupSheet: View {
    let onSave: (FamilyActivitySelection, String) -> Void
    let isEditing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: FamilyActivitySelection
    @State private var name: String
    @State private var showSelection = false
    @State private var hasSaved = false
    @FocusState private var nameFocused: Bool

    init(selection: FamilyActivitySelection = FamilyActivitySelection(), name: String = "",
         isEditing: Bool = false, onSave: @escaping (FamilyActivitySelection, String) -> Void) {
        var draftSelection = selection
        #if DEBUG && targetEnvironment(simulator)
        // Native simulator picker UI cannot supply a real authorized app token.
        // Seed a single-app draft only for persistence/navigation UI tests.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("ui-testing"), arguments.contains("ui-testing-feed-selection"),
           let token = try? JSONDecoder().decode(ApplicationToken.self, from: Data(#"{"data":"AQ=="}"#.utf8)) {
            draftSelection.applicationTokens = [token]
        }
        #endif
        _selection = State(initialValue: draftSelection)
        _name = State(initialValue: name)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var pickerSelection: Binding<FamilyActivitySelection> {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("ui-testing"), arguments.contains("ui-testing-feed-selection") {
            // The system picker rejects synthetic tokens. Preserve the fixture
            // while testing our form's Back, Cancel and persistence behavior.
            return .constant(selection)
        }
        #endif
        return $selection
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "e.g. X, Social, Games"), text: $name)
                        .focused($nameFocused)
                        .submitLabel(.next)
                        .onSubmit { continueToSelection() }
                        .accessibilityLabel(String(localized: "Name your group"))
                        .accessibilityIdentifier("feed.name")
                } footer: {
                    Text(String(localized: "This name appears on the card and in widgets. Next, choose the apps for this group."))
                }
            }
            .navigationTitle(String(localized: "Name your group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Next")) { continueToSelection() }
                        .disabled(trimmedName.isEmpty || hasSaved)
                        .accessibilityIdentifier("feed.name.next")
                }
            }
            .onAppear { nameFocused = true }
            .navigationDestination(isPresented: $showSelection) {
                FamilyActivityPicker(selection: pickerSelection)
                    .navigationTitle(String(localized: "Select Apps"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel(String(localized: "Cancel"))
                                .accessibilityIdentifier("feed.selection.cancel")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isEditing ? String(localized: "Save") : String(localized: "Create")) { save() }
                                .disabled(trimmedName.isEmpty || !selection.hasGroupTargets || hasSaved)
                                .accessibilityIdentifier("feed.selection.create")
                        }
                    }
            }
        }
    }

    private var cancelButton: some View {
        Button(String(localized: "Cancel")) { dismiss() }
            .accessibilityIdentifier("feed.selection.cancel")
    }

    private func continueToSelection() {
        guard !trimmedName.isEmpty, !hasSaved else { return }
        nameFocused = false
        showSelection = true
    }

    private func save() {
        guard !hasSaved, selection.hasGroupTargets, !trimmedName.isEmpty else { return }
        hasSaved = true
        onSave(selection, trimmedName)
        dismiss()
    }
}

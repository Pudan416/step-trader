import SwiftUI
import FamilyControls
#if DEBUG && targetEnvironment(simulator)
import ManagedSettings
#endif

/// Name and selection stay local until Done. Cancel (including swipe dismissal)
/// never creates a group or changes an existing one.
struct NewAppGroupSheet: View {
    let onSave: (FamilyActivitySelection, String) -> Void
    let isEditing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: FamilyActivitySelection
    @State private var name: String
    @State private var hasSaved = false
    @FocusState private var nameFocused: Bool

    init(selection: FamilyActivitySelection = FamilyActivitySelection(), name: String = "",
         isEditing: Bool = false, onSave: @escaping (FamilyActivitySelection, String) -> Void) {
        var draftSelection = selection
        #if DEBUG && targetEnvironment(simulator)
        // Native simulator picker UI cannot supply a real authorized app token.
        // Seed a single-app draft only for validation/persistence UI tests.
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
            // while testing our form's validation, Cancel and persistence behavior.
            return .constant(selection)
        }
        #endif
        return $selection
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Name your group"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. X, Social, Games"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFocused = false }
                        .accessibilityLabel(String(localized: "Name your group"))
                        .accessibilityIdentifier("feed.name")
                    Text(String(localized: "This name appears on the card and in widgets."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                FamilyActivityPicker(selection: pickerSelection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(isEditing ? String(localized: "Edit group") : String(localized: "New group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { save() }
                        .disabled(trimmedName.isEmpty || !selection.hasGroupTargets || hasSaved)
                        .accessibilityIdentifier("feed.selection.create")
                }
            }
        }
    }

    private var cancelButton: some View {
        Button(String(localized: "Cancel")) { dismiss() }
            .accessibilityIdentifier("feed.selection.cancel")
    }

    private func save() {
        guard !hasSaved, selection.hasGroupTargets, !trimmedName.isEmpty else { return }
        hasSaved = true
        onSave(selection, trimmedName)
        dismiss()
    }
}

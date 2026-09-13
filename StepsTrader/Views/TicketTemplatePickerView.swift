import SwiftUI
import FamilyControls

/// Selection stays local until Save. Cancel (including swipe dismissal) never
/// creates a group or changes an existing one.
struct NewAppGroupSheet: View {
    let onSave: (FamilyActivitySelection, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: FamilyActivitySelection
    @State private var name: String
    @State private var showName = false
    @FocusState private var nameFocused: Bool

    init(selection: FamilyActivitySelection = FamilyActivitySelection(), name: String = "",
         onSave: @escaping (FamilyActivitySelection, String) -> Void) {
        _selection = State(initialValue: selection)
        _name = State(initialValue: name)
        self.onSave = onSave
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle(String(localized: "Select Apps"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) {
                            if selection.isSingleApplication || !trimmedName.isEmpty {
                                save()
                            } else {
                                showName = true
                            }
                        }
                        .disabled(!selection.hasGroupTargets)
                        .accessibilityIdentifier("feed.selection.done")
                    }
                }
                .navigationDestination(isPresented: $showName) {
                    Form {
                        TextField(String(localized: "e.g. Social, Games…"), text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { if !trimmedName.isEmpty { save() } }
                            .accessibilityLabel(String(localized: "Name your feed"))
                            .accessibilityIdentifier("feed.name")
                    }
                    .navigationTitle(String(localized: "Name your feed"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Create")) { save() }
                                .disabled(trimmedName.isEmpty)
                        }
                    }
                    .onAppear { nameFocused = true }
                }
        }
    }

    private func save() {
        guard selection.hasGroupTargets,
              selection.isSingleApplication || !trimmedName.isEmpty else { return }
        onSave(selection, trimmedName)
        dismiss()
    }
}

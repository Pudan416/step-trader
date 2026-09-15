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
    #if DEBUG
    @State private var hasSaved = false
    #endif
    @FocusState private var nameFocused: Bool

    init(selection: FamilyActivitySelection = FamilyActivitySelection(), name: String = "",
         onSave: @escaping (FamilyActivitySelection, String) -> Void) {
        _selection = State(initialValue: selection)
        _name = State(initialValue: name)
        self.onSave = onSave
    }

    private var saveBlocked: Bool {
        #if DEBUG
        return hasSaved
        #else
        return false
        #endif
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
                            .accessibilityIdentifier("feed.selection.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) {
                            if selection.isSingleApplication || !trimmedName.isEmpty {
                                save()
                            } else {
                                showName = true
                            }
                        }
                        .disabled(!selection.hasGroupTargets || saveBlocked)
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
                                .disabled(trimmedName.isEmpty || saveBlocked)
                                .accessibilityIdentifier("feed.selection.create")
                        }
                    }
                    .onAppear { nameFocused = true }
                }
        }
    }

    private func save() {
        guard !saveBlocked, selection.hasGroupTargets,
              selection.isSingleApplication || !trimmedName.isEmpty else { return }
        #if DEBUG
        hasSaved = true
        #endif
        onSave(selection, trimmedName)
        dismiss()
    }
}

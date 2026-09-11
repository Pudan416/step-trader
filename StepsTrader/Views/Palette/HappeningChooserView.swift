import SwiftUI
import UIKit

/// The explicit reading order for the floating panels. The values below are
/// consumed by SwiftUI's sort priorities so the contract is testable without
/// relying on pixel- or accessibility-server inspection.
enum HappeningPanelAccessibilityOrder {
    enum Role: Equatable {
        case heading
        case status
        case search
        case rows
        case input
        case actions
    }

    static let chooser: [Role] = [.heading, .status, .search, .rows, .actions]
    static let creator: [Role] = [.heading, .input, .actions]

    static func priority(for role: Role, in order: [Role]) -> Double {
        guard let index = order.firstIndex(of: role) else { return 0 }
        return Double(order.count - index)
    }
}

/// Edits a fixed set of slots. Existing replacements remain a draft until Done;
/// creating a new item commits the same draft into the explicitly chosen slot.
struct HappeningChooserView: View {
    let catalog: [Happening]
    let protectedIDs: Set<String>
    let onCreateNew: (String, String, [String]) -> HappeningPaletteCreationOutcome
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    @State private var draft: HappeningPaletteSelectionDraft
    @State private var replacementID: String?
    @State private var query = ""
    @State private var isCreating = false
    @State private var name = ""
    @State private var feedback: HappeningPaletteCreationFeedback?
    @State private var showsProtectedMessage = false
    @FocusState private var nameFocused: Bool

    private let surface = Color(hex: "F4F5EF")
    private let ink = Color(hex: "24372B")

    init(
        catalog: [Happening], selected: [String], protectedIDs: Set<String> = [],
        onCreateNew: @escaping (String, String, [String]) -> HappeningPaletteCreationOutcome = { _, _, _ in .failed },
        onSave: @escaping ([String]) -> Void, onCancel: @escaping () -> Void
    ) {
        self.catalog = catalog
        self.protectedIDs = protectedIDs
        self.onCreateNew = onCreateNew
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: HappeningPaletteSelectionDraft(
            selected: selected, catalog: catalog, protectedIDs: protectedIDs
        ))
    }

    private var selected: [Happening] {
        draft.ids.compactMap { id in catalog.first { $0.id == id } }
    }

    private var hasAlternatives: Bool {
        catalog.contains { !draft.ids.contains($0.id) }
    }

    private var replacements: [Happening] {
        catalog.filter {
            !draft.ids.contains($0.id)
                && (query.isEmpty || $0.localizedTitle().localizedCaseInsensitiveContains(query))
        }
    }

    private var targetTitle: String {
        catalog.first { $0.id == replacementID }?.localizedTitle() ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isCreating {
                        creator
                    } else if replacementID != nil {
                        replacementList
                    } else {
                        currentList
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(surface)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if replacementID == nil || isCreating {
                    Button {
                        if isCreating { create() } else { onSave(draft.ids) }
                    } label: {
                        Text("Done")
                            .font(.geist(.body).weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(ink, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreating ? name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !draft.canSave)
                    .opacity(isCreating && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .accessibilityIdentifier("happening_editor_done")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(surface)
                }
            }
            .navigationTitle(isCreating ? String(localized: "New happening") : replacementID == nil ? String(localized: "Happenings") : String(localized: "Replace"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        nameFocused = false
                        feedback = nil
                        if isCreating {
                            isCreating = false
                            if !hasAlternatives { replacementID = nil }
                        } else if replacementID != nil {
                            replacementID = nil
                        } else {
                            onCancel()
                        }
                    } label: {
                        Image(systemName: replacementID == nil ? "xmark" : "chevron.left")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(replacementID == nil ? String(localized: "Cancel") : String(localized: "Back"))
                    .accessibilityIdentifier("happening_editor_back")
                }
            }
        }
        .font(.geist(.body))
        .foregroundStyle(ink)
        .tint(ink)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(draft.hasChanges || !name.isEmpty)
        .alert("Already on Canvas", isPresented: $showsProtectedMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Remove this happening from Canvas before replacing it.")
        }
    }

    private var currentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tap to replace")
                Spacer()
                Text(draft.ids.count, format: .number).monospacedDigit()
            }
            .font(.geist(.subheadline))
            .foregroundStyle(ink.opacity(0.7))

            VStack(spacing: 0) {
                ForEach(selected) { happening in
                    Button {
                        if protectedIDs.contains(happening.id) {
                            showsProtectedMessage = true
                        } else {
                            replacementID = happening.id
                            query = ""
                            name = ""
                            // With no saved alternatives, go straight to naming the replacement.
                            isCreating = !hasAlternatives
                            nameFocused = isCreating
                        }
                    } label: {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(happening.localizedTitle())
                                if protectedIDs.contains(happening.id) {
                                    Text("On Canvas")
                                        .font(.geist(.caption))
                                        .foregroundStyle(ink.opacity(0.7))
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: protectedIDs.contains(happening.id) ? "checkmark" : "chevron.right")
                                .font(.geist(.footnote).weight(.semibold))
                                .foregroundStyle(ink.opacity(0.65))
                        }
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("happening_editor_row_\(happening.id)")
                    if happening.id != draft.ids.last { Divider().overlay(ink.opacity(0.08)) }
                }
            }
        }
    }

    private var replacementList: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(targetTitle)
                .font(.geist(.title2).weight(.medium))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(ink.opacity(0.65)))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("happening_editor_search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))

            Button {
                name = query.trimmingCharacters(in: .whitespacesAndNewlines)
                isCreating = true
                feedback = nil
                nameFocused = true
            } label: {
                Label("New happening", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("happening_editor_new")

            if replacements.isEmpty {
                Text("No matches")
                    .font(.geist(.subheadline))
                    .foregroundStyle(ink.opacity(0.7))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(replacements) { happening in
                        Button {
                            guard let replacementID, draft.replace(id: replacementID, with: happening.id) else { return }
                            self.replacementID = nil
                        } label: {
                            Text(happening.localizedTitle())
                                .multilineTextAlignment(.leading)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("happening_replacement_\(happening.id)")
                        Divider()
                    }
                }
            }
        }
    }

    private var creator: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Replaces \(targetTitle)")
                .font(.geist(.subheadline))
                .foregroundStyle(ink.opacity(0.7))
            TextField("Name", text: $name, prompt: Text("Name").foregroundStyle(ink.opacity(0.65)))
                .padding(16)
                .frame(minHeight: 56)
                .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit(create)
                .onChange(of: name) { _, _ in feedback = nil }
                .accessibilityIdentifier("happening_editor_name")
            if let feedback {
                Text(feedback.message)
                    .font(.geist(.subheadline))
                    .foregroundStyle(Color(red: 0.65, green: 0.12, blue: 0.08))
                    .accessibilityIdentifier("happening_editor_error")
            }
        }
    }

    private func create() {
        guard let replacementID else { return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            feedback = .invalidTitle
            return
        }
        let outcome = onCreateNew(name, replacementID, draft.ids)
        feedback = outcome.feedback
        if let feedback {
            UIAccessibility.post(notification: .announcement, argument: feedback.message)
        }
    }
}

#Preview {
    HappeningChooserView(
        catalog: HappeningDefaults.builtIns,
        selected: HappeningDefaults.builtIns.map(\.id),
        protectedIDs: ["walk"], onSave: { _ in }, onCancel: {}
    )
}

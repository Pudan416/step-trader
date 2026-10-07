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

/// Edits a fixed set of slots using only the reviewed catalog.
/// Existing replacements remain a draft until Done.
struct HappeningChooserView: View {
    let catalog: [Happening]
    let protectedIDs: Set<String>
    let healthIDs: Set<String>
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    @State private var draft: HappeningPaletteSelectionDraft
    @State private var replacementID: String?
    @State private var query = ""
    @State private var showsProtectedMessage = false
    @State private var protectedHealth = false

    private let surface = Color(hex: "F4F5EF")
    private let ink = Color(hex: "24372B")

    init(
        catalog: [Happening], selected: [String], protectedIDs: Set<String> = [], healthIDs: Set<String> = [],
        // Ignored compatibility argument for older callers; creation has no UI path.
        onCreateNew: @escaping (String, String, [String]) -> HappeningPaletteCreationOutcome = { _, _, _ in .failed },
        onSave: @escaping ([String]) -> Void, onCancel: @escaping () -> Void
    ) {
        self.catalog = catalog
        self.protectedIDs = protectedIDs
        self.healthIDs = healthIDs
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: HappeningPaletteSelectionDraft(
            selected: selected, catalog: catalog, protectedIDs: protectedIDs
        ))
    }

    private var selected: [Happening] {
        draft.ids.compactMap { id in catalog.first { $0.id == id } }
    }

    private var replacements: [Happening] {
        HappeningPaletteSelection.alternatives(catalog: catalog, selected: draft.ids, query: query)
    }

    private var targetTitle: String {
        catalog.first { $0.id == replacementID }?.localizedTitle() ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if replacementID != nil {
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
                if replacementID == nil {
                    Button {
                        onSave(draft.ids)
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
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("happening_editor_done")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(surface)
                }
            }
            .navigationTitle(replacementID == nil ? String(localized: "Happenings") : String(localized: "Replace"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if replacementID != nil {
                            replacementID = nil
                        } else if draft.hasChanges {
                            guard draft.canSave else { return }
                            onSave(draft.ids)
                        } else {
                            onCancel()
                        }
                    } label: {
                        Image(systemName: toolbarSymbol)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(toolbarAccessibilityLabel)
                    .accessibilityIdentifier("happening_editor_back")
                }
            }
        }
        .font(.geist(.body))
        .foregroundStyle(ink)
        .tint(ink)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(draft.hasChanges)
        .alert(protectedHealth ? "Health happenings stay in Personal" : String(localized: "Already on Canvas"), isPresented: $showsProtectedMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(protectedHealth ? String(localized: "Health activities are always close at hand. You can replace another happening.") : String(localized: "Remove this happening from Canvas before replacing it."))
        }
    }

    private var toolbarSymbol: String {
        if replacementID != nil { return "chevron.left" }
        return draft.hasChanges ? "checkmark" : "xmark"
    }

    private var toolbarAccessibilityLabel: String {
        if replacementID != nil { return String(localized: "Back") }
        return draft.hasChanges ? String(localized: "Save changes") : String(localized: "Cancel")
    }

    private var currentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These happenings appear first in the field.")
                .font(.geist(.footnote))
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
                            protectedHealth = healthIDs.contains(happening.id)
                            showsProtectedMessage = true
                        } else {
                            replacementID = happening.id
                            query = ""
                        }
                    } label: {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(happening.localizedTitle())
                                if protectedIDs.contains(happening.id) {
                                    Text(healthIDs.contains(happening.id) ? String(localized: "Health") : String(localized: "On Canvas"))
                                        .font(.geist(.caption))
                                        .foregroundStyle(ink.opacity(0.7))
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: healthIDs.contains(happening.id) ? "pin.fill" : protectedIDs.contains(happening.id) ? "checkmark" : "chevron.right")
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
}

#Preview {
    HappeningChooserView(
        catalog: HappeningDefaults.builtIns,
        selected: Array(HappeningDefaults.builtIns.prefix(10)).map(\.id),
        protectedIDs: ["walk"], onSave: { _ in }, onCancel: {}
    )
}

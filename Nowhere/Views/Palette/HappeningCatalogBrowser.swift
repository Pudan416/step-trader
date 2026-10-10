import SwiftUI

/// Text browsing does not allocate hundreds of Metal preview actors. Every add
/// uses Gallery's existing durable Canvas transaction and daily-limit checks.
struct HappeningCatalogBrowser: View {
    let catalog: [Happening]
    let recommendations: [PersonalHappeningRecommendation]
    let addedIDs: Set<String>
    let addedCount: Int
    let onAdd: (String) -> Bool
    let onClose: () -> Void
    @ObservedObject var profileStore: PersonalHappeningProfileStore
    @State private var mode: HappeningPaletteMode
    @State private var query = ""
    @State private var category: HappeningCatalogCategory?
    @State private var showsAddError = false
    @State private var personalWasReset = false

    init(catalog: [Happening], recommendations: [PersonalHappeningRecommendation],
         addedIDs: Set<String>, addedCount: Int, profileStore: PersonalHappeningProfileStore,
         initialMode: HappeningPaletteMode = .frequent,
         onAdd: @escaping (String) -> Bool, onClose: @escaping () -> Void) {
        self.catalog = catalog
        self.recommendations = recommendations
        self.addedIDs = addedIDs
        self.addedCount = addedCount
        self.profileStore = profileStore
        self.onAdd = onAdd
        self.onClose = onClose
        _mode = State(initialValue: initialMode)
    }

    private let surface = Color(hex: "F4F5EF")
    private let ink = Color(hex: "24372B")
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isBrowsingAll: Bool { mode == .all || isSearching || category != nil }
    private var isFull: Bool { addedCount >= HappeningDefaults.maximumDailyAdditions }

    private var rows: [Happening] {
        if isBrowsingAll {
            return catalog.filter { HappeningCatalog.matches($0, query: query, category: category) }
        }
        guard !personalWasReset else { return [] }
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return recommendations.compactMap { recommendation in
            guard !profileStore.profile.hiddenIDs.contains(recommendation.id),
                  HappeningCatalog.byID[recommendation.id] != nil
            else { return nil }
            return byID[recommendation.id]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Happenings", selection: $mode) {
                        Text("Personal").tag(HappeningPaletteMode.frequent)
                        Text("All").tag(HappeningPaletteMode.all)
                    }
                    .pickerStyle(.segmented)
                    TextField("Search all happenings", text: $query)
                        .happeningPanelTextFieldStyle()
                        .submitLabel(.search)
                        .accessibilityIdentifier("happening_catalog_search")
                    HStack {
                        Menu {
                            Button("All categories") { category = nil }
                            ForEach(HappeningCatalogCategory.allCases) { item in
                                Button(item.title) { category = item }
                            }
                        } label: {
                            Label(category?.title ?? "All categories", systemImage: "line.3.horizontal.decrease")
                                .font(.geist(.subheadline))
                                .frame(minHeight: 44)
                        }
                        Spacer()
                        Text("\(addedCount) / \(HappeningDefaults.maximumDailyAdditions) today")
                            .font(.geist(.subheadline)).monospacedDigit()
                    }
                    if isFull {
                        Text("Your ten happenings are on Canvas. You can keep browsing.")
                            .font(.geist(.footnote))
                    } else if !isBrowsingAll {
                        Text("Close at hand, based on your choices and recorded days. Add only what happened.")
                            .font(.geist(.footnote))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if rows.isEmpty {
                            Text(isBrowsingAll ? "No matching happenings." : "Choose interests or pin happenings from All to shape Personal.")
                                .font(.geist(.body)).padding(.vertical, 24)
                        }
                        ForEach(rows) { happening in
                            catalogRow(happening)
                            Divider().overlay(ink.opacity(0.08))
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(surface)
            .navigationTitle("Happenings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PersonalHappeningSettingsView(store: profileStore, catalog: catalog)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Personal settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
        }
        .font(.geist(.body))
        .foregroundStyle(ink)
        .tint(ink)
        .preferredColorScheme(.light)
        .onChange(of: profileStore.profile.historyStartsAt) { _, _ in
            personalWasReset = true
        }
        .alert("Couldn’t add this happening", isPresented: $showsAddError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The day may have changed or Canvas is still loading. Close the catalog and try again.")
        }
    }

    private func catalogRow(_ happening: Happening) -> some View {
        let added = addedIDs.contains(happening.id)
        return HStack(spacing: 8) {
            Button {
                if !onAdd(happening.id) { showsAddError = true }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(happening.localizedTitle()).font(.geist(.body))
                        Text(subtitle(for: happening)).font(.geist(.caption))
                            .foregroundStyle(ink.opacity(0.65))
                        if added { Text("On Canvas").font(.geist(.caption)) }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: added ? "checkmark" : "plus")
                        .font(.geist(.body).weight(.medium))
                        .opacity(added || !isFull ? 1 : 0.3)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(added || isFull)
            .accessibilityLabel(happening.localizedTitle())
            .accessibilityValue(added ? "On Canvas" : isFull ? "Daily limit reached" : subtitle(for: happening))
            .accessibilityHint(added || isFull ? "" : "Add this happening to Canvas")
            .accessibilityIdentifier("catalog_add_" + happening.id)

            NavigationLink {
                PersonalHappeningDetailView(happening: happening, store: profileStore)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.geist(.body)).frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Personal settings for \(happening.localizedTitle())")
        }
    }

    private func subtitle(for happening: Happening) -> String {
        let profile = profileStore.profile
        if profile.hiddenIDs.contains(happening.id) { return "Hidden from Personal" }
        if let intention = profile.intentions[happening.id] {
            return PersonalHappeningRecommendation.Reason.intention(intention).title
        }
        if profile.pinnedIDs.contains(happening.id) { return "Pinned by you" }
        if !isBrowsingAll, let recommendation = recommendations.first(where: { $0.id == happening.id }) {
            // Preferences can change deliberately, without reordering the open list.
            switch recommendation.reason {
            case .pinned, .intention: return "Available to log"
            case let .interest(category) where !profile.interests.contains(category.rawValue):
                return "Available to log"
            default: return recommendation.reason.title
            }
        }
        return HappeningCatalog.byID[happening.id]?.category.title ?? ""
    }
}

private struct PersonalHappeningSettingsView: View {
    @ObservedObject var store: PersonalHappeningProfileStore
    let catalog: [Happening]
    @State private var confirmsReset = false

    private var configured: [Happening] {
        let ids = store.profile.pinnedIDs.union(store.profile.hiddenIDs).union(store.profile.intentions.keys)
        return catalog.filter { ids.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                Text("Choose what you’re interested in. You can leave this empty and change it anytime.")
                ForEach(HappeningCatalogCategory.interests) { category in
                    Button { store.toggleInterest(category) } label: {
                        HStack {
                            Text(category.title)
                            Spacer()
                            if store.profile.interests.contains(category.rawValue) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityAddTraits(store.profile.interests.contains(category.rawValue) ? .isSelected : [])
                }
            } header: { Text("Interests") } footer: {
                Text("Personal updates when you open it again. An open field keeps its positions.")
            }
            if !configured.isEmpty {
                Section("Your choices") {
                    ForEach(configured) { happening in
                        NavigationLink {
                            PersonalHappeningDetailView(happening: happening, store: store)
                        } label: {
                            Text(happening.localizedTitle())
                        }
                    }
                }
            }
            Section {
                Button("Reset Personal", role: .destructive) { confirmsReset = true }
            } footer: {
                Text("Interests, pins, hidden choices and intentions stay on this device. Reset clears them and stops using older days for recommendations. Your saved days stay in the archive.")
            }
        }
        .font(.geist(.body))
        .navigationTitle("Personal")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset Personal?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Personal", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct PersonalHappeningDetailView: View {
    let happening: Happening
    @ObservedObject var store: PersonalHappeningProfileStore

    var body: some View {
        Form {
            Section {
                Toggle("Pin in Personal", isOn: Binding(
                    get: { store.profile.pinnedIDs.contains(happening.id) },
                    set: { store.setPinned($0, id: happening.id) }
                ))
                Toggle("Hide from Personal", isOn: Binding(
                    get: { store.profile.hiddenIDs.contains(happening.id) },
                    set: { store.setHidden($0, id: happening.id) }
                ))
            } footer: {
                Text("Hiding keeps this choice out of Personal. You can still find it in All and keep existing Canvas entries.")
            }
            Section {
                intentionButton(nil, title: "No intention")
                ForEach(HappeningIntention.allCases) { intention in
                    intentionButton(intention, title: intention.title)
                }
            } header: { Text("My intention") } footer: {
                Text("An intention helps keep the record close at hand. It doesn’t mark an event as happened. “Less often” is a tracking choice.")
            }
        }
        .font(.geist(.body))
        .navigationTitle(happening.localizedTitle())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func intentionButton(_ intention: HappeningIntention?, title: String) -> some View {
        Button { store.setIntention(intention, id: happening.id) } label: {
            HStack {
                Text(title)
                Spacer()
                if store.profile.intentions[happening.id] == intention { Image(systemName: "checkmark") }
            }
        }
        .accessibilityAddTraits(store.profile.intentions[happening.id] == intention ? .isSelected : [])
    }
}

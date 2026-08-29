import SwiftUI

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme

    @State private var readTracker = NoteReadTracker()
    @State private var currentIndex: Int = 0
    @State private var showAllNotes = false

    private var notes: [Note] { NoteCatalog.all }

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                TabView(selection: $currentIndex) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        noteCard(note)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.top, 20)

                Spacer(minLength: 20)

                bottomButtons
                    // Was 100 to clear the floating tab bar. Notes is reached
                    // from the settings sheet now, where there is no tab bar and
                    // that reserve is just a hole at the bottom of the page.
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 0)
        }
        .settingsDetailPage(title: String(localized: "Notes from Kosta", comment: "ManualsPage – page title"))
        .sheet(isPresented: $showAllNotes) {
            AllNotesListView(readTracker: readTracker) { note in
                if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                    currentIndex = idx
                }
                readTracker.markRead(note)
                showAllNotes = false
            }
            .choicesSheetPresentationBackground()
        }
        .onChange(of: currentIndex) { _, newValue in
            readTracker.markRead(notes[newValue])
        }
        .onAppear {
            if let firstUnread = notes.firstIndex(where: { !readTracker.isRead($0) }) {
                currentIndex = firstUnread
            }
            readTracker.markRead(notes[currentIndex])
        }
    }

    // MARK: - Note card

    private func noteCard(_ note: Note) -> some View {
        // The card keeps the same size on every page so swiping doesn't make it
        // jump, which leaves short notes with room to spare — centre them in it
        // rather than pinning them to the top. Long ones still scroll.
        GeometryReader { proxy in
            SettingsGroupedSurface {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(note.topic)
                            .font(.geist(13, weight: .medium, relativeTo: .caption))
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.textSecondary.opacity(0.5))
                            .padding(.bottom, 20)

                        Text(note.body)
                            .font(.geist(20, weight: .light, relativeTo: .title3))
                            .italic()
                            .foregroundStyle(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(6)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.notes.card")
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<notes.count, id: \.self) { i in
                Circle()
                    .fill(i == currentIndex ? theme.textPrimary : theme.textPrimary.opacity(0.15))
                    .frame(width: i == currentIndex ? 6 : 5, height: i == currentIndex ? 6 : 5)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }

    // MARK: - Bottom buttons

    private var bottomButtons: some View {
        HStack(spacing: 14) {
            Button {
                showAllNotes = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.geist(13, weight: .medium, relativeTo: .caption))
                    Text(String(localized: "all", comment: "ManualsPage – filter showing all notes"))
                        .font(.geist(13, weight: .medium, relativeTo: .caption))

                    if readTracker.unreadCount > 0 {
                        Circle()
                            .fill(AppColors.brandAccent)
                            .frame(width: 6, height: 6)
                    }
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .settingsCardSurface()
            }
            .buttonStyle(MattePressStyle())
            .accessibilityIdentifier("settings.notes.all")
        }
    }
}

// MARK: - All notes list

struct AllNotesListView: View {
    var readTracker: NoteReadTracker
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var onSelect: (Note) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                SettingsGroupedSurface {
                    LazyVStack(spacing: 0) {
                        ForEach(NoteCatalog.all) { note in
                            Button {
                                onSelect(note)
                            } label: {
                                HStack(spacing: 14) {
                                    if !readTracker.isRead(note) {
                                        Circle()
                                            .fill(AppColors.brandAccent)
                                            .frame(width: 8, height: 8)
                                    } else {
                                        Circle()
                                            .fill(Color.secondary.opacity(0.15))
                                            .frame(width: 8, height: 8)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(note.topic)
                                            .font(.geist(
                                                15,
                                                weight: readTracker.isRead(note) ? .regular : .medium,
                                                relativeTo: .subheadline
                                            ))
                                            .foregroundStyle(.primary)

                                        Text(note.body)
                                            .font(.geist(13, weight: .light, relativeTo: .footnote))
                                            .italic()
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 0)

                                    Image(systemName: "chevron.right")
                                        .font(.geist(12, weight: .light, relativeTo: .caption))
                                        .foregroundStyle(.secondary.opacity(0.4))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.notes.item.\(note.id)")

                            if note.id != NoteCatalog.all.last?.id {
                                DetailDivider(inset: 38)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .accessibilityIdentifier("settings.notes.allList")
            .navigationTitle(String(localized: "all notes", comment: "ManualsPage – accessibility label for all filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", comment: "ManualsPage – dismiss button")) {
                        dismiss()
                    }
                    .font(.geist(15, weight: .regular, relativeTo: .subheadline))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("settings.notes.done")
                }
            }
        }
    }
}

#Preview {
    ManualsPage(model: DIContainer.shared.makeAppModel())
}

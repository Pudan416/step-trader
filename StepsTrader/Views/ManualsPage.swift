import SwiftUI

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight

    @StateObject private var readTracker = NoteReadTracker()
    @State private var currentIndex: Int = 0
    @State private var showAllNotes = false

    private var notes: [Note] { NoteCatalog.all }

    var body: some View {
        NavigationStack {
            ZStack {
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
                        .padding(.bottom, 100)
                }
                .padding(.horizontal, 0)
            }
            .energyGradientBackground(model: model)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAllNotes) {
                AllNotesListView(readTracker: readTracker) { note in
                    if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                        currentIndex = idx
                    }
                    readTracker.markRead(note)
                    showAllNotes = false
                }
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
    }

    // MARK: - Note card

    private func noteCard(_ note: Note) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(note.topic)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundColor(theme.textSecondary.opacity(0.5))
                    .padding(.bottom, 20)

                Text(note.body)
                    .font(.system(size: 20, weight: .thin, design: .serif))
                    .italic()
                    .foregroundColor(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.backgroundSecondary.opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(theme.stroke.opacity(theme.strokeOpacity * 0.5), lineWidth: 0.5)
        )
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
                        .font(.system(size: 13, weight: .medium))
                    Text(String(localized: "all", comment: "ManualsPage – filter showing all notes"))
                        .font(.system(size: 13, weight: .medium))

                    if readTracker.unreadCount > 0 {
                        Circle()
                            .fill(AppColors.brandAccent)
                            .frame(width: 6, height: 6)
                    }
                }
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(theme.backgroundSecondary.opacity(0.7))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.stroke.opacity(theme.strokeOpacity * 0.5), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - All notes list

struct AllNotesListView: View {
    @ObservedObject var readTracker: NoteReadTracker
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var onSelect: (Note) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 1) {
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
                                        .font(.system(size: 15, weight: readTracker.isRead(note) ? .regular : .medium))
                                        .foregroundColor(.primary)

                                    Text(note.body)
                                        .font(.system(size: 13, weight: .light))
                                        .italic()
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if note.id != NoteCatalog.all.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "all notes", comment: "ManualsPage – accessibility label for all filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", comment: "ManualsPage – dismiss button")) {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .regular))
                }
            }
        }
    }
}

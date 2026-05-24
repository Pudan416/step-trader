import SwiftUI

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight

    @State private var readTracker = NoteReadTracker()
    @State private var currentIndex: Int = 0
    @State private var showAllNotes = false

    private var notes: [Note] { NoteCatalog.all }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            VStack(spacing: 0) {
                DetailHeader(title: String(localized: "Notes from Kosta", comment: "ManualsPage – page title"))
                    .padding(.horizontal, 16)

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
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
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
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Text(note.topic)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.textSecondary.opacity(0.5))
                    .padding(.bottom, 20)

                Text(note.body)
                    .font(.system(size: 20, weight: .thin, design: .serif))
                    .italic()
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .glassCard(cornerRadius: 20, style: .lensTinted)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.stroke.opacity(theme.strokeOpacity * 0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
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
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .modifier(NotesCapsuleChrome(theme: theme))
            }
            .buttonStyle(.plain)
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
                                        .font(.system(size: 15, weight: readTracker.isRead(note) ? .regular : .medium))
                                        .foregroundStyle(.primary)

                                    Text(note.body)
                                        .font(.system(size: 13, weight: .light))
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundStyle(.secondary.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if note.id != NoteCatalog.all.last?.id {
                            Divider()
                                .padding(.leading, 38)
                        }
                    }
                }
                .glassCard(cornerRadius: 16, style: .lensTinted)
                .padding(.horizontal, 16)
                .padding(.top, 8)
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

// MARK: - Chrome (Liquid Glass on iOS 26+, matte fill before)

private struct NotesCapsuleChrome: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.liquidGlassControl(in: Capsule(style: .continuous), style: .frosted, tint: .off)
        } else {
            content
                .background(theme.backgroundSecondary.opacity(0.7), in: Capsule())
                .overlay(Capsule().stroke(theme.stroke.opacity(theme.strokeOpacity * 0.5), lineWidth: 0.5))
        }
    }
}

#Preview {
    ManualsPage(model: DIContainer.shared.makeAppModel())
}

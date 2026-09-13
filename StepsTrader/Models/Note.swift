import Foundation
import Observation

struct Note: Identifiable, Codable, Equatable {
    let id: String
    let topic: String
    let body: String

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
}

// MARK: - Read-state manager

@Observable
@MainActor
final class NoteReadTracker {
    // App-only data — .standard is intentional (no extension needs note read state)
    private(set) var readIDs: Set<String>

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: SharedKeys.readNoteIDs) ?? []
        self.readIDs = Set(stored)
    }

    func markRead(_ note: Note) {
        guard !readIDs.contains(note.id) else { return }
        readIDs.insert(note.id)
        persist()
    }

    func isRead(_ note: Note) -> Bool {
        readIDs.contains(note.id)
    }

    var unreadCount: Int {
        NoteCatalog.all.count - readIDs.intersection(NoteCatalog.all.map(\.id)).count
    }

    private func persist() {
        UserDefaults.standard.set(Array(readIDs), forKey: SharedKeys.readNoteIDs)
    }
}

// MARK: - Catalog

enum NoteCatalog {
    static let all: [Note] = [
        Note(id: "about_canvas",
             topic: String(localized: "About the Canvas", comment: "Note topic"),
             body: String(localized: "Every day leaves a different trace. The canvas is not a score, and it isn't proof that you lived enough. It holds what Nowhere could notice: sleep, steps, and the happenings you chose to name. Some things will always be missing. At the end of your day, the live canvas makes room for another. The trace can stay.", comment: "Note body: about_canvas")),
        // Keep the legacy id: it is persisted in NoteReadTracker, and renaming it
        // would make this already-read note appear unread after an update.
        Note(id: "about_body_mind_heart",
             topic: String(localized: "About Happenings", comment: "Note topic"),
             body: String(localized: "I used to slice the day into three — body, mind, heart. Borrowed from Tibetan Buddhism, which I know almost nothing about. It felt right, and that was enough.\n\nIt wasn't. Nobody who just called their mother wants to decide whether that was mind or heart.\n\nNow there is one word. A happening is anything a day is made of, and each counts once a day.", comment: "Note body: about_happenings")),
        Note(id: "about_shapes",
             topic: String(localized: "About Shapes", comment: "Note topic"),
             body: String(localized: "Circles, snowflakes, rays, organic blobs. Four families. You decide which ones the canvas may use — in Settings, under Appearance.\n\nEvery happening takes a shape from the ones you left on, a color from the day, and a place on the canvas. If the place feels wrong, you can move it.\n\nNo fixed meanings. Just forms that felt true.", comment: "Note body: about_shapes")),
        Note(id: "about_sleep",
             topic: String(localized: "About Sleep", comment: "Note topic"),
             body: String(localized: "Sleep is the frame around every day. Everything else fits inside it. Sleep lays down the dark. As the night approaches the goal you set, it brings up to 20 colors.\n\nSleep comes from the Health app. Apple can be slow to finish the night, so the canvas may catch up later.", comment: "Note body: about_sleep")),
        Note(id: "about_steps",
             topic: String(localized: "About Steps", comment: "Note topic"),
             body: String(localized: "Steps are not a fitness score. They are proof that the body moved through the world today. As you move toward the target you set, they bring up to 20 colors and brighten the canvas. It doesn't have to be 10k. It's your number.", comment: "Note body: about_steps")),
        Note(id: "about_feeds",
             topic: String(localized: "About Feeds", comment: "Note topic"),
             body: String(localized: "Feeds are not evil. They're just expensive. When you choose to open one, you spend some of the colors the day gave you. The balance falls. The canvas changes.\n\nThe choice stays yours. Nowhere only makes the trade visible.", comment: "Note body: about_feeds")),
        Note(id: "about_wallpaper",
             topic: String(localized: "About Wallpaper", comment: "Note topic"),
             body: String(localized: "I made a shortcut that puts the canvas on the Lock Screen. Close Nowhere, and the wallpaper catches up with the day.\n\nYou still have to open Nowhere for it to change. That small inconvenience became part of the point: look at the day, then leave again.", comment: "Note body: about_wallpaper")),
        Note(id: "about_widgets",
             topic: String(localized: "About Widgets", comment: "Note topic"),
             body: String(localized: "I wanted less reason to open Nowhere, not more. So the widgets carry the useful parts to the Home Screen: the day's colors, the feeds you closed, and the choice to open one.\n\nApple decides when widgets wake up. If one falls behind, the refresh button is there.", comment: "Note body: about_widgets")),
        Note(id: "about_colors",
             topic: String(localized: "About Colors", comment: "Note topic"),
             body: String(localized: "Colors are not quite a currency. They are a limited material the day gives you. Up to 100: some from sleep and steps, the rest from happenings you add yourself.\n\nYou can spend them to open a feed, and the canvas carries that choice too. You can't buy colors. That would undo the whole idea.", comment: "Note body: about_colors")),
        Note(id: "about_me",
             topic: String(localized: "About Me", comment: "Note topic"),
             body: String(localized: "I am not my job title\nI am not a designer\nI am not a developer\nI am not a manager\nI am not good\nI am not happy\nI am not sad\nI am not what I post\nI am not who I was yesterday\nI am not who I'll be tomorrow\nI am not nowhere\nI am now here\n\nHey. Thank you for using Nowhere. If you're reading this, I hope you found something in it that matters.\nMy name is Kosta.\nI spent years working on creative projects for brands — winning awards, getting recognition. It made me feel successful, creative, whatever. But recently I realized I was living inside my work, hiding in it. I didn't really know myself anymore. Could I do something on my own? For myself? Was I capable of something else? The classic midlife corporate crisis. It felt like I was nowhere.\nSo I started building this — at first just for myself, to learn. Over time it became something personal. It's not perfect. Neither am I. I don't think it needs to be.\nI'm trying to accept myself and find meaning beyond work. And if you ever feel burned out, lost, or stuck in that same nowhere — you are here, now. That matters most.\nFeel free to text me. All the contacts are in the settings. Thank you.", comment: "Note body: about_me")),
    ]

    static func random() -> Note {
        all.randomElement() ?? all[0]
    }

    static func random(excluding current: Note?) -> Note {
        guard all.count > 1, let current else { return random() }
        let filtered = all.filter { $0.id != current.id }
        return filtered.randomElement() ?? random()
    }
}

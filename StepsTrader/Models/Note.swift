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

// MARK: - Catalog (placeholder bodies — we'll fill these in next)

enum NoteCatalog {
    static let all: [Note] = [
        Note(id: "about_canvas",
             topic: String(localized: "About the Canvas", comment: "Note topic"),
             body: String(localized: "Every day is 24 hours. But no two are the same. The canvas is proof of that — a record of what actually happened, not what you planned. The more you lived, the more it shows. It reacts to your sleep and steps. The more you sleep, the darker it gets. The more you walk, the brighter. Your actions throughout the day shape it, and every 24 hours the canvas resets — unique, every single time.", comment: "Note body: about_canvas")),
        // Keep the legacy id: it is persisted in NoteReadTracker, and renaming it
        // would make this already-read note appear unread after an update.
        Note(id: "about_body_mind_heart",
             topic: String(localized: "About Happenings", comment: "Note topic"),
             body: String(localized: "I used to slice the day into three — body, mind, heart. Borrowed from Tibetan Buddhism, which I know almost nothing about. It felt right, and that was enough.\n\nIt wasn't. Nobody who just called their mother wants to decide whether that was mind or heart.\n\nNow there is one word. A happening is anything a day is made of, and each counts once a day.", comment: "Note body: about_happenings")),
        Note(id: "about_shapes",
             topic: String(localized: "About Shapes", comment: "Note topic"),
             body: String(localized: "Circles, snowflakes, rays, organic blobs. Four families, and you decide which of them the canvas is allowed to use — in Settings, under Appearance.\n\nThey used to be assigned: one family per category, whether you liked it or not. Now nothing is assigned. Every happening takes a shape from the ones you left on, a color from the day, and a place it keeps until midnight.\n\nNo metaphors. Just things that felt true.", comment: "Note body: about_shapes")),
        Note(id: "about_sleep",
             topic: String(localized: "About Sleep", comment: "Note topic"),
             body: String(localized: "Sleep is the frame around every day. Everything else fits inside it. Set your desired sleep time, and if you hit it — you earn 20 colors. Data comes from the Health app. Sometimes Apple is slow to sync. Not my fault.", comment: "Note body: about_sleep")),
        Note(id: "about_steps",
             topic: String(localized: "About Steps", comment: "Note topic"),
             body: String(localized: "Steps are not a fitness metric. They are proof that your body moved through the world today. The more you moved, the brighter everything gets. Set your own step goal and earn 20 colors when you reach it. You don't have to do 10k. It's your number.", comment: "Note body: about_steps")),
        Note(id: "about_feeds",
             topic: String(localized: "About Feeds", comment: "Note topic"),
             body: String(localized: "Feeds are not evil. They're just expensive. Every minute inside them drains color from the day. That's the deal — open your banned apps, watch the canvas fade. The choice is always yours. I just made it visible. You can unlock apps through the notification that pops up when you try to open a blocked one, through this app, or through the widget.", comment: "Note body: about_feeds")),
        Note(id: "about_wallpaper",
             topic: String(localized: "About Wallpaper", comment: "Note topic"),
             body: String(localized: "I made a shortcut that sets the canvas as your wallpaper. It changed something — you see your day every time you unlock your phone. The downside: you have to open the app to refresh it. The upside: once you've blocked enough apps here, you'll be opening it anyway. Seemed fair.", comment: "Note body: about_wallpaper")),
        Note(id: "about_widgets",
             topic: String(localized: "About Widgets", comment: "Note topic"),
             body: String(localized: "You can add widgets to your home screen. They bring the app's mechanics right to your lock screen and desktop. Large widget for unlocking apps, medium one for tracking the day. They don't always update automatically — Apple limits that — so sometimes you'll want to tap “refresh” to check the latest status.", comment: "Note body: about_widgets")),
        Note(id: "about_colors",
             topic: String(localized: "About Colors", comment: "Note topic"),
             body: String(localized: "Colors are not a currency. Well — kind of. You can earn up to 100 per day. Steps and sleep give them to you automatically — 20 each. The other 60 are happenings, and you add those yourself. You can spend colors to unlock apps. But the more you spend, the less colorful your canvas becomes. Because doomscrolling takes color out of life. Literally, here.\n\nI'm not selling them through microtransactions. Colors are yours. You earn them, you deserve them, you can always add more. Within limits.", comment: "Note body: about_colors")),
        Note(id: "about_me",
             topic: String(localized: "About Me", comment: "Note topic"),
             body: String(localized: "I am not my job title\nI am not a designer\nI am not a developer\nI am not a manager\nI am not good\nI am not happy\nI am not sad\nI am not what I post\nI am not who I was yesterday\nI am not who I'll be tomorrow\nI am not nowhere\nI am now here\n\nHey. Thank you for using this app. If you're reading this, I hope you found something in it that matters.\nMy name is Kosta.\nI spent years working on creative projects for brands — winning awards, getting recognition. It made me feel successful, creative, whatever. But recently I realized I was living inside my work, hiding in it. I didn't really know myself anymore. Could I do something on my own? For myself? Was I capable of something else? The classic midlife corporate crisis. It felt like I was nowhere.\nSo I started building this app — at first just for myself, to learn. Over time it became something personal. It's not perfect. Neither am I. Neither are you.\nI'm trying to accept myself and find meaning beyond work. And if you ever feel burned out, lost, or stuck in that same nowhere — you are here, now. That matters most.\nFeel free to text me. All the contacts are in the settings. Thank you.", comment: "Note body: about_me")),
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

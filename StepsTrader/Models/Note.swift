import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: String
    let topic: String
    let body: String

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
}

// MARK: - Read-state manager

@MainActor
final class NoteReadTracker: ObservableObject {
    // App-only data — .standard is intentional (no extension needs note read state)
    @Published private(set) var readIDs: Set<String>

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
             body: String(localized: "The canvas is a reflection of each day. How full and colorful it was. I like the idea that even though each day is limited by 24 hours, there are so many little things that make them different. And to distinguish one day from another we need to notice them.", comment: "Note body")),
        Note(id: "about_body_mind_heart",
             topic: String(localized: "About Body, Mind, and Heart", comment: "Note topic"),
             body: String(localized: "I spent a long time thinking about these categories and there is no one way to categorize a human being. But I liked the Tibetan Buddhism, which sees a human as a harmony of body (physical form), mind (thoughts and perceptions), and heart (pure awareness, emotions, and compassion center). I don't know much about Buddhism, but this idea resonates with me. Maybe I should start digging deeper one day.", comment: "Note body")),
        Note(id: "about_shapes",
             topic: String(localized: "About Shapes", comment: "Note topic"),
             body: String(localized: "Thinking about the body, mind and heart, I was looking for the best objects to represent them on the canvas. The body is represented by big constant breathing shapes. For the mind I chose drifting circles, that fly around like ideas. And the heart is represented by beams of light, that light the way and look around.", comment: "Note body")),
        Note(id: "about_sleep",
             topic: String(localized: "About Sleep", comment: "Note topic"),
             body: String(localized: "Sleep is what we all have. This is the beginning and the end of the day. And its amount and quality influence us the most. On the canvas the more you sleep, the darker it becomes. That's not a bad thing, it just shows that rest today is a priority. Oh, btw, it is taken from the Health app and sometimes it is slow to upload. Thanks, Apple.", comment: "Note body")),
        Note(id: "about_steps",
             topic: String(localized: "About Steps", comment: "Note topic"),
             body: String(localized: "Steps are not a fitness metric. They're proof the body moved through the world. The more you walk, the brighter the canvas becomes.", comment: "Note body: about_steps")),
        Note(id: "about_feeds",
             topic: String(localized: "About Feeds", comment: "Note topic"),
             body: String(localized: "Feeds are where minutes disappear. Not evil, not good — just expensive. But the fact is that they drain the color from the day. In this app, the more you open your banned apps, the less colorful your canvas becomes. Note that.", comment: "Note body")),
        Note(id: "about_limits",
             topic: String(localized: "About Limits", comment: "Note topic"),
             body: String(localized: "Sleeping for 8 hours or making 10k steps a day is not a must. It's personal, you set your own threshold. But setting it gives a bit more motivation to get there.", comment: "Note body: about_limits")),
        Note(id: "about_wallpaper",
             topic: String(localized: "About Wallpaper", comment: "Note topic"),
             body: String(localized: "I actually liked how the canvases look. And I tried setting one as a wallpaper. It made me see my day constantly and think, what can I add to it. The sad part is that you need to open the app to update the wallpaper. But once you set enough apps in the Feeds section, you'll be opening it anyway. Seemed like a good compromise.", comment: "Note body: about_wallpaper")),
        Note(id: "about_colors",
             topic: String(localized: "About Colors", comment: "Note topic"),
             body: String(localized: "I like green. But that's just me. I tried to find the colors most people like and want to see and came up with this set. Hopefully you'll find what fits your liking. You can always change them if you don't.", comment: "Note body: about_colors")),
        Note(id: "about_colors",
             topic: String(localized: "About Colors", comment: "Note topic"),
             body: String(localized: "Colors are not a currency. I mean they are, but I'm not planning to sell them in microtransactions or whatever. Colors are yours. You deserve them, you earn them, you can always add more. Within limits, of course.", comment: "Note body: about_colors")),
        Note(id: "about_kosta",
             topic: String(localized: "About Kosta", comment: "Note topic"),
             body: String(localized: "Hey, thank you for using this app. If you’re reading this, I hope you’ve found something meaningful in it. My name is Kosta, nice to meet you. I’ve spent years working on creative projects for brands — winning awards, getting recognition. It made me feel successful, creative, whatever. But recently I realized I was living inside my work, hiding in it. I didn’t really know myself anymore. Could I do something on my own? For myself? Was I capable of something else? You know… the classic midlife corporate crisis. It felt like I was nowhere. That’s the word — nowhere.\nSo I started building this app — at first just for myself, to learn. Over time it became something deeply personal. It’s not perfect, but neither am I — and neither are you. I’m trying to accept myself and find meaning beyond work. And if you ever feel burned out, lost, or stuck in that same nowhere, remember — you are here, now. And that’s what matters most.\nFeel free to text me. IDK why, but all the contacts are in the settings. Thank you.", comment: "Note body: about_kosta")),

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

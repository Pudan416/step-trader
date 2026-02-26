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
    private let key = "readNoteIDs_v1"

    @Published private(set) var readIDs: Set<String>

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: "readNoteIDs_v1") ?? []
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
        UserDefaults.standard.set(Array(readIDs), forKey: key)
    }
}

// MARK: - Catalog (placeholder bodies — we'll fill these in next)

enum NoteCatalog {
    static let all: [Note] = [
        Note(id: "on_canvas",
             topic: "on canvas",
             body: "The canvas reflects of the day. I like the idea that even though the day is limited by 24 hours, there are so many little things that make them different. And if noticed, they color up the day."),
        Note(id: "on_body_mind_heart",
             topic: "on body, mind and heart",
             body: "I spent a long time thinking about these categories and there is no one way to categorize a human being. But I liked the Tibetan Buddhism, which sees a human as a harmony of body (physical form), mind (thoughts and perceptions), and heart (pure awareness, emotions, and compassion center). I don't know much about Buddhism, but this idea resonates with me. Maybe I should start digging deeper one day."),
        Note(id: "on_objects",
             topic: "on objects",
             body: "Thinking about the body, mind and heart, I was looking for the best objects to represent them on the canvas. The body is represented by big constant breathing shapes. For the mind I chose drifting circles, that fly around like ideas. And the heart is represented by rays, that light the way and look around."),
        Note(id: "on_sleep",
             topic: "on sleep",
             body: "Sleep is what we all have. This is the beginning and the end of the day. And its amount and quality influence us the most. On the canvas the more you sleep, the darker it becomes. That's not a bad thing, it just shows that rest today is a priority. Oh, btw, it is taken from the Health app and sometimes it is slow to upload. Thanks, Apple."),
        Note(id: "on_steps",
             topic: "on steps",
             body: "Steps are not a fitness metric. They're proof the body moved through the world. The more you walk, the brighter the canvas becomes."),
        Note(id: "on_feeds",
             topic: "on feeds",
             body: "Feeds are where minutes disappear. Not evil, not good — just expensive. But the fact is that they drain the color from the day. In this app, the more you open your banned apps, the less colorful your canvas becomes. Note that."),
        Note(id: "on_limits",
             topic: "on limits",
             body: "Sleeping for 8 hours or making 10k steps a day is not a must. It's personal, you set your own threshold. But setting it gives a bit more motivation to get there."),
        Note(id: "on_wallpaper",
             topic: "on wallpaper",
             body: "I actually liked how the canvases look. And I tried setting one as a wallpaper. It made me see my day constantly and think, what can I add to it. The sad part is that you need to open the app to update the wallpaper. But once you set enough apps in the Feeds section, you'll be opening it anyway. Seemed like a good compromise."),
        Note(id: "on_colors",
             topic: "on colors",
             body: "I like green. But that's just me. I tried to find the colors most people like and want to see and came up with this set. Hopefully you'll find what fits your liking. You can always change them if you don't."),
        Note(id: "on_rays",
             topic: "on rays",
             body: "Rays are not a currency. I mean they are, but I'm not planning to sell them in microtransactions or whatever. Rays are yours. You deserve them, you earn them, you can always add more. Within limits, of course."),
    ]

    static func random() -> Note {
        all.randomElement()!
    }

    static func random(excluding current: Note?) -> Note {
        guard all.count > 1, let current else { return random() }
        let filtered = all.filter { $0.id != current.id }
        return filtered.randomElement() ?? random()
    }
}

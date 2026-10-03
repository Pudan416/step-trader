import Foundation

struct HappeningEventNode: Identifiable, Hashable {
    let id: String
    let title: String
    let children: [HappeningEventNode]

    init(_ id: String, _ title: String, _ children: [HappeningEventNode] = []) {
        self.id = id
        self.title = title
        self.children = children
    }
}

enum HappeningEventTree {
    static let spheres: [HappeningEventNode] = [
        .init("work", "Work & study", [
            .init("work", "Worked", [.init("computer", "Worked at a desk"), .init("tasks", "Did my tasks"), .init("email", "Checked email"), .init("made", "Made something"), .init("meeting", "Went to a meeting"), .init("workcall", "Had a work call"), .init("deadline", "Felt deadline heat"), .init("bored", "Was bored at work"), .init("avoidedwork", "Avoided my work"), .init("nothingwork", "Got nothing done")]),
            .init("study", "Studied", [.init("class", "Went to class"), .init("solo", "Studied alone"), .init("group", "Studied with others")]),
            .init("job", "Looked for work", [.init("listings", "Browsed job ads"), .init("application", "Sent an application"), .init("interview", "Had an interview")])
        ]),
        .init("body", "Body & wellbeing", [
            .init("move", "Moved around", [.init("walk", "Went for a walk"), .init("run", "Went for a run"), .init("workout", "Worked out"), .init("gym", "Went to the gym"), .init("errands", "Ran errands"), .init("stayedin", "Stayed indoors")]),
            .init("food", "Ate & drank", [.init("ate", "Ate a meal"), .init("alonefood", "Ate alone"), .init("snack", "Had a snack"), .init("coffee", "Had coffee"), .init("tea", "Had some tea"), .init("wasted", "Got wasted"), .init("hangover", "Had a hangover")]),
            .init("rest", "Rested", [.init("slept", "Slept"), .init("nap", "Took a nap"), .init("bed", "Stayed in bed"), .init("shower", "Took a shower")])
        ]),
        .init("people", "People & connection", [
            .init("talk", "Talked with people", [.init("friend", "Saw a friend"), .init("family", "Saw family"), .init("colleague", "Saw a colleague"), .init("texted", "Texted someone"), .init("peoplecall", "Called someone"), .init("snapped", "Snapped at someone"), .init("avoidedpeople", "Avoided everyone")]),
            .init("care", "Cared for someone", [.init("helped", "Helped a friend"), .init("child", "Looked after a kid"), .init("pet", "Cared for a pet")]),
            .init("solitude", "Spent time alone", [.init("alonepeople", "Kept to myself"), .init("leftout", "Felt left out")])
        ]),
        .init("home", "Home & everyday", [
            .init("chores", "Did housework", [.init("cooked", "Cooked a meal"), .init("cleaned", "Cleaned up"), .init("laundry", "Did the laundry"), .init("fixed", "Fixed something"), .init("plants", "Watered plants"), .init("ignored", "Ignored the mess")]),
            .init("out", "Went out", [.init("shopping", "Went shopping"), .init("paperwork", "Did paperwork"), .init("appointment", "Had an appointment")]),
            .init("home", "Stayed at home", [.init("relaxed", "Chilled at home"), .init("guests", "Had people over"), .init("doomscroll", "Doomscrolled")])
        ]),
        .init("travel", "Getting around", [
            .init("commute", "Got to work", [.init("transit", "Took the bus"), .init("train", "Took the train"), .init("car", "Drove to work"), .init("bike", "Biked to work"), .init("walked", "Walked to work")]),
            .init("places", "Went places", [.init("cafe", "Went to a café"), .init("bar", "Went to a bar"), .init("store", "Went to a store"), .init("nature", "Went outdoors")]),
            .init("changed", "Changed plans", [.init("lost", "Got lost"), .init("detour", "Took a detour"), .init("new", "Went somewhere new")])
        ]),
        .init("play", "Rest & play", [
            .init("watch", "Watched things", [.init("videos", "Watched videos"), .init("movie", "Watched a movie"), .init("show", "Watched a show"), .init("scroll", "Scrolled for hours"), .init("losttime", "Lost track of time")]),
            .init("read", "Read something", [.init("book", "Read a book"), .init("news", "Read the news"), .init("articles", "Read some posts")]),
            .init("play", "Played a game", [.init("videogame", "Played video games"), .init("boardgame", "Played a board game"), .init("withkid", "Played with a kid")]),
            .init("unwind", "Did my own thing", [.init("music", "Listened to music"), .init("hobby", "Did a hobby"), .init("nothingplay", "Did nothing much")])
        ]),
        .init("feelings", "Feelings", [.init("rage", "Raged"), .init("happy", "Felt happy"), .init("tired", "Felt tired"), .init("anxious", "Felt anxious"), .init("angry", "Felt angry"), .init("calm", "Felt calm"), .init("lonely", "Felt lonely"), .init("curious", "Felt curious"), .init("okay", "Felt okay"), .init("mixed", "Felt mixed")])
    ]

    // All six starting choices are complete, loggable events.
    static let startingEvents: [HappeningEventNode] = [
        .init("root_worked", "Worked"), .init("root_chilled", "Chilled"),
        .init("root_wentout", "Went out"), .init("root_people", "Saw people"),
        .init("root_ate", "Ate"), .init("root_home", "Stayed home")
    ]

    static let all = startingEvents + spheres.flatMap { $0.children.flatMap(leaves) }

    // These are associations between whole events, not steps in a classification.
    // A route stays available as each newly revealed event opens its own neighbors.
    private static let routes: [[String]] = [
        ["root_worked", "computer", "made", "nothingwork", "tasks", "email", "meeting", "workcall", "deadline", "bored", "avoidedwork", "class", "solo", "group", "listings", "application", "interview", "tired", "rage"],
        ["root_chilled", "music", "doomscroll", "nap", "videos", "movie", "show", "scroll", "losttime", "book", "news", "articles", "videogame", "boardgame", "withkid", "hobby", "nothingplay", "slept", "bed", "calm", "okay", "mixed"],
        ["root_wentout", "walk", "cafe", "lost", "run", "workout", "gym", "errands", "transit", "train", "car", "bike", "walked", "bar", "store", "nature", "detour", "new", "shopping", "appointment", "curious"],
        ["root_people", "friend", "wasted", "snapped", "family", "colleague", "texted", "peoplecall", "avoidedpeople", "helped", "child", "pet", "guests", "happy", "angry", "lonely", "leftout"],
        ["root_ate", "coffee", "ate", "cooked", "alonefood", "snack", "tea", "hangover", "wasted"],
        ["root_home", "cleaned", "shower", "ignored", "laundry", "fixed", "plants", "paperwork", "relaxed", "stayedin", "alonepeople", "anxious"]
    ]

    static func event(_ id: String) -> HappeningEventNode? {
        all.first { $0.id == id }
    }

    static func leaves(_ node: HappeningEventNode) -> [HappeningEventNode] {
        node.children.isEmpty ? [node] : node.children.flatMap(leaves)
    }

    static func suggestions(for selected: HappeningEventNode, alreadyVisible: Set<String>) -> [HappeningEventNode] {
        guard let route = routes.first(where: { $0.contains(selected.id) }),
              let index = route.firstIndex(of: selected.id) else { return [] }
        let ordered = Array(route.dropFirst(index + 1)) + Array(route.prefix(index))
        return ordered.filter { !alreadyVisible.contains($0) }.compactMap(event)
    }
}

/// A shared lattice for the date, labels, renderer and hit targets. The origin
/// is reserved for the date; existing events never change cells as the tree grows.
struct HappeningEventTreeState: Equatable {
    struct Cell: Hashable {
        let q: Int
        let r: Int
        static let origin = Cell(q: 0, r: 0)
        static let directions = [
            Cell(q: -1, r: 0), Cell(q: 0, r: -1), Cell(q: 1, r: -1),
            Cell(q: 1, r: 0), Cell(q: 0, r: 1), Cell(q: -1, r: 1)
        ]
        var neighbors: [Cell] { Self.directions.map { Cell(q: q + $0.q, r: r + $0.r) } }
        var distanceSquared: Int { q * q + q * r + r * r }
    }

    struct PlacedEvent: Identifiable, Equatable {
        let event: HappeningEventNode
        let cell: Cell
        let parentID: String?
        var id: String { event.id }
    }

    private(set) var nodes: [PlacedEvent]
    private(set) var expandedIDs: [String] = []

    init(expandedIDs: [String] = []) {
        nodes = zip(HappeningEventTree.startingEvents, Cell.directions).map {
            PlacedEvent(event: $0.0, cell: $0.1, parentID: nil)
        }
        for id in expandedIDs { expand(id) }
    }

    @discardableResult
    mutating func expand(_ id: String) -> Int {
        guard !expandedIDs.contains(id), let parent = nodes.first(where: { $0.id == id }) else { return 0 }
        let occupied = Set(nodes.map(\.cell)).union([Cell.origin])
        let spaces = parent.cell.neighbors.filter { !occupied.contains($0) }.sorted {
            if $0.distanceSquared != $1.distanceSquared { return $0.distanceSquared > $1.distanceSquared }
            if $0.r != $1.r { return $0.r < $1.r }
            return $0.q < $1.q
        }
        let events = HappeningEventTree.suggestions(for: parent.event, alreadyVisible: Set(nodes.map(\.id)))
        let children = zip(events.prefix(3), spaces.prefix(3)).map {
            PlacedEvent(event: $0.0, cell: $0.1, parentID: parent.id)
        }
        expandedIDs.append(id)
        nodes.append(contentsOf: children)
        return children.count
    }

}

enum HappeningDayTitle {
    static func make(from titles: [String], dayKey: String) -> String {
        let values = titles.map { $0.lowercased() }
        let work = values.contains { $0.contains("work") || $0.contains("desk") }
        let coffee = values.contains { $0.contains("coffee") }
        let outside = values.contains { $0.contains("walk") || $0.contains("outdoors") }
        let screen = values.contains { $0.contains("scroll") || $0.contains("videos") }
        if work && coffee && outside { return "Coffee, Work & Air" }
        if work && outside { return "Work, Then Outside" }
        if work && screen { return "Work & Open Tabs" }
        if coffee && screen { return "Coffee & Scrolling" }
        if values.contains(where: { $0.contains("rage") || $0.contains("angry") }) { return "A Day with Edges" }
        return "A Day in the Making"
    }
}

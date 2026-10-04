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
            .init("work", "Worked", [.init("email", "Checked email"), .init("wrote", "Wrote"), .init("made", "Made something"), .init("meeting", "Went to a meeting"), .init("workcall", "Had a work call"), .init("deadline", "Felt deadline stress"), .init("bored", "Was bored at work"), .init("avoidedwork", "Avoided my work"), .init("nothingwork", "Got nothing done")]),
            .init("study", "Studied", [.init("class", "Went to class"), .init("solo", "Studied alone"), .init("group", "Studied with others")]),
            .init("job", "Looked for work", [.init("listings", "Browsed job ads"), .init("application", "Sent an application"), .init("interview", "Had an interview")])
        ]),
        .init("body", "Body & wellbeing", [
            .init("move", "Moved around", [.init("walk", "Went for a walk"), .init("run", "Went for a run"), .init("workout", "Worked out"), .init("swam", "Swam"), .init("stretched", "Stretched"), .init("errands", "Ran errands")]),
            .init("food", "Ate & drank", [.init("snack", "Had a snack"), .init("meal_breakfast", "Had breakfast"), .init("meal_lunch", "Had lunch"), .init("meal_dinner", "Had dinner"), .init("coffee", "Had coffee"), .init("tea", "Had tea"), .init("wasted", "Got wasted"), .init("hangover", "Had a hangover")]),
            .init("rest", "Rested", [.init("slept", "Slept"), .init("nap", "Took a nap"), .init("bed", "Stayed in bed"), .init("shower", "Took a shower")])
        ]),
        .init("people", "People & connection", [
            .init("talk", "Talked with people", [.init("friend", "Saw a friend"), .init("family", "Saw family"), .init("colleague", "Saw a colleague"), .init("texted", "Texted someone"), .init("peoplecall", "Called someone"), .init("snapped", "Snapped at someone"), .init("avoidedpeople", "Avoided everyone")]),
            .init("care", "Cared for someone", [.init("helped", "Helped a friend"), .init("askedhelp", "Asked for help"), .init("saidno", "Said no"), .init("child", "Looked after a kid"), .init("pet", "Cared for a pet")]),
            .init("solitude", "Spent time alone", [.init("alonepeople", "Kept to myself"), .init("leftout", "Felt left out")])
        ]),
        .init("home", "Home & everyday", [
            .init("chores", "Did housework", [.init("cooked", "Cooked"), .init("cleaned", "Cleaned up"), .init("laundry", "Did the laundry"), .init("fixed", "Fixed something"), .init("plants", "Watered plants"), .init("ignored", "Ignored the mess")]),
            .init("out", "Went out", [.init("shopping", "Went shopping"), .init("paperwork", "Did paperwork"), .init("appointment", "Had an appointment")]),
            .init("home", "Stayed at home", [.init("guests", "Had people over"), .init("doomscroll", "Doomscrolled")])
        ]),
        .init("travel", "Getting around", [
            .init("commute", "Got to work", [.init("transit", "Took the bus"), .init("train", "Took the train"), .init("car", "Drove to work"), .init("bike", "Biked to work"), .init("walked", "Walked to work")]),
            .init("places", "Went places", [.init("cafe", "Went to a café"), .init("bar", "Went to a bar"), .init("nature", "Spent time outside")]),
            .init("changed", "Changed plans", [.init("lost", "Got lost"), .init("detour", "Took a detour"), .init("new", "Went somewhere new")])
        ]),
        .init("play", "Rest & play", [
            .init("watch", "Watched things", [.init("videos", "Watched videos"), .init("movie", "Watched a movie"), .init("show", "Watched a show"), .init("losttime", "Lost track of time")]),
            .init("read", "Read something", [.init("book", "Read a book"), .init("news", "Read the news"), .init("articles", "Read posts")]),
            .init("play", "Played a game", [.init("videogame", "Played video games"), .init("boardgame", "Played a board game"), .init("withkid", "Played with a kid")]),
            .init("unwind", "Did my own thing", [.init("music", "Listened to music"), .init("hobby", "Did hobby stuff"), .init("drew", "Drew"), .init("sang", "Sang"), .init("danced", "Danced"), .init("photos", "Took photos"), .init("nothingplay", "Did nothing much")])
        ]),
        .init("feelings", "Feelings", [.init("rage", "Raged"), .init("happy", "Felt happy"), .init("tired", "Felt tired"), .init("anxious", "Felt anxious"), .init("angry", "Felt angry"), .init("calm", "Felt calm"), .init("lonely", "Felt lonely"), .init("curious", "Felt curious"), .init("okay", "Felt okay"), .init("mixed", "Had mixed feelings")])
    ]

    // Six independently loggable shortcuts into the same reviewed catalog.
    static let startingEvents: [HappeningEventNode] = [
        .init("root_worked", "Worked"), .init("root_chilled", "Chilled"),
        .init("root_home", "Stayed home"), .init("meal_breakfast", "Had breakfast"),
        .init("walk", "Went for a walk"), .init("friend", "Saw a friend")
    ]

    static let all: [HappeningEventNode] = {
        let roots = Set(startingEvents.map(\.id))
        return startingEvents + [.init("break", "Took a break")]
            + spheres.flatMap { $0.children.flatMap(leaves) }.filter { !roots.contains($0.id) }
    }()

    // These are associations between whole events, not classifications.
    // All permits any direct addition without logging an ancestor first.
    static let routes: [[String]] = [
        ["root_worked", "email", "made", "nothingwork", "meeting", "workcall", "deadline", "bored", "avoidedwork", "class", "solo", "group", "listings", "application", "interview", "tired", "rage", "wrote"],
        ["root_chilled", "music", "doomscroll", "nap", "videos", "movie", "show", "losttime", "book", "news", "articles", "videogame", "boardgame", "withkid", "hobby", "nothingplay", "slept", "bed", "calm", "okay", "mixed", "drew", "sang", "danced", "photos"],
        ["walk", "cafe", "lost", "run", "workout", "errands", "transit", "train", "car", "bike", "walked", "bar", "nature", "detour", "new", "shopping", "appointment", "curious", "swam", "stretched"],
        ["friend", "wasted", "snapped", "family", "colleague", "texted", "peoplecall", "avoidedpeople", "helped", "askedhelp", "saidno", "child", "pet", "guests", "happy", "angry", "lonely", "leftout"],
        ["meal_breakfast", "coffee", "meal_lunch", "meal_dinner", "cooked", "snack", "tea", "hangover", "wasted"],
        ["root_home", "cleaned", "shower", "ignored", "laundry", "fixed", "plants", "paperwork", "alonepeople", "anxious"]
    ]

    static func eventID(forHappeningID id: String) -> String? {
        let canonical = HappeningDefaults.canonicalID(id)
        guard canonical.hasPrefix("event_") else { return nil }
        let sourceID = String(canonical.dropFirst(6))
        return event(sourceID) == nil ? nil : sourceID
    }

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
        var ring: Int { max(abs(q), abs(r), abs(q + r)) }
        func projection(on direction: Cell) -> Int {
            2 * q * direction.q + q * direction.r + r * direction.q + 2 * r * direction.r
        }
    }

    struct PlacedEvent: Identifiable, Equatable {
        let event: HappeningEventNode
        let cell: Cell
        let parentID: String?
        var id: String { event.id }
    }

    private(set) var nodes: [PlacedEvent]
    private(set) var expandedIDs: [String] = []

    // A single editorial map is used by Tree and All. The six intersections
    // belong to both neighboring roots; placement never depends on click order.
    private static let outwardIDs = ["email", "music", "cleaned", "meal_lunch", "run", "family"]
    private static let intersectionIDs = ["break", "nap", "cooked", "cafe", "peoplecall", "workcall"]
    static let allNodes: [PlacedEvent] = makeAtlas()
    private static let byID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })

    init(expandedIDs: [String] = []) {
        nodes = Array(Self.allNodes.prefix(6))
        for id in expandedIDs { expand(id) }
    }

    /// Keep directly added All events visible when returning to Tree, including
    /// the path from the hub. This does not log or remove any additional event.
    mutating func reveal(_ id: String) {
        guard !nodes.contains(where: { $0.id == id }), let placed = Self.byID[id] else { return }
        if let parentID = placed.parentID { reveal(parentID) }
        nodes.append(placed)
    }

    @discardableResult
    mutating func expand(_ id: String) -> Int {
        guard !expandedIDs.contains(id), let parent = Self.byID[id] else { return 0 }
        reveal(id)
        let visible = Set(nodes.map(\.id))
        let children = Self.children(of: parent).filter { !visible.contains($0.id) }.map {
            PlacedEvent(event: $0.event, cell: $0.cell, parentID: id)
        }
        expandedIDs.append(id)
        nodes.append(contentsOf: children)
        return children.count
    }

    private static func children(of parent: PlacedEvent) -> [PlacedEvent] {
        if let index = HappeningEventTree.startingEvents.firstIndex(where: { $0.id == parent.id }) {
            let ids = [outwardIDs[index], intersectionIDs[(index + 5) % 6], intersectionIDs[index]]
            return ids.compactMap { byID[$0] }
        }
        let neighbors = Set(parent.cell.neighbors)
        return Array(allNodes.filter { neighbors.contains($0.cell) && $0.cell.ring > parent.cell.ring }
            .sorted {
                if $0.cell.distanceSquared != $1.cell.distanceSquared { return $0.cell.distanceSquared > $1.cell.distanceSquared }
                if $0.cell.r != $1.cell.r { return $0.cell.r < $1.cell.r }
                return $0.cell.q < $1.cell.q
            }.prefix(3))
    }

    private static func makeAtlas() -> [PlacedEvent] {
        let roots = HappeningEventTree.startingEvents
        let events = Dictionary(uniqueKeysWithValues: HappeningEventTree.all.map { ($0.id, $0) })
        var placed = zip(roots, Cell.directions).map {
            PlacedEvent(event: $0.0, cell: $0.1, parentID: nil)
        }
        var contexts = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, Set([$0.id])) })
        var usedIDs = Set(roots.map(\.id))
        var occupied = Set(Cell.directions).union([Cell.origin])
        func place(_ id: String, at cell: Cell, parentID: String, relatedRoots: Set<String>) {
            guard let event = events[id], !usedIDs.contains(id) else { return }
            placed.append(PlacedEvent(event: event, cell: cell, parentID: parentID))
            contexts[id] = relatedRoots
            usedIDs.insert(id)
            occupied.insert(cell)
        }
        for index in roots.indices {
            let direction = Cell.directions[index]
            place(outwardIDs[index], at: Cell(q: direction.q * 2, r: direction.r * 2),
                parentID: roots[index].id, relatedRoots: [roots[index].id])
        }
        for index in roots.indices {
            let next = (index + 1) % 6
            let a = Cell.directions[index], b = Cell.directions[next]
            place(intersectionIDs[index], at: Cell(q: a.q + b.q, r: a.r + b.r),
                parentID: roots[index].id, relatedRoots: [roots[index].id, roots[next].id])
        }

        let routes = roots.map { root in
            HappeningEventTree.routes.first(where: { $0.first == root.id }) ?? []
        }
        var cursors = Array(repeating: 0, count: roots.count)
        var hasRemaining = true
        while hasRemaining {
            hasRemaining = false
            for index in roots.indices {
                let route = routes[index]
                while cursors[index] < route.count, usedIDs.contains(route[cursors[index]]) {
                    cursors[index] += 1
                }
                guard cursors[index] < route.count else { continue }
                hasRemaining = true
                let rootID = roots[index].id, direction = Cell.directions[index]
                let parents = placed.filter { contexts[$0.id]?.contains(rootID) == true }
                let candidates = Set(parents.flatMap { parent in
                    parent.cell.neighbors.filter { cell in
                        guard !occupied.contains(cell), cell.ring > parent.cell.ring else { return false }
                        let projections = Cell.directions.map { cell.projection(on: $0) }
                        return cell.projection(on: direction) == projections.max()
                    }
                })
                let cell = candidates.min { a, b in
                    if a.ring != b.ring { return a.ring < b.ring }
                    let aa = Double(a.projection(on: direction)) / sqrt(Double(a.distanceSquared))
                    let bb = Double(b.projection(on: direction)) / sqrt(Double(b.distanceSquared))
                    if aa != bb { return aa > bb }
                    if a.r != b.r { return a.r < b.r }
                    return a.q < b.q
                }
                guard let cell, let parent = parents.first(where: {
                    $0.cell.ring < cell.ring && $0.cell.neighbors.contains(cell)
                }) else { preconditionFailure("Event sector has no outward cell") }
                place(route[cursors[index]], at: cell, parentID: parent.id, relatedRoots: [rootID])
                cursors[index] += 1
            }
        }
        precondition(usedIDs == Set(events.keys), "Every event needs a fixed map position")
        return placed
    }
}

enum HappeningDayTitle {
    static func make(from titles: [String], dayKey: String) -> String {
        let values = titles.map { $0.lowercased() }
        let work = values.contains { $0.contains("work") || $0.contains("desk") }
        let coffee = values.contains { $0.contains("coffee") }
        let outside = values.contains { $0.contains("walk") || $0.contains("outside") || $0.contains("outdoors") }
        let screen = values.contains { $0.contains("scroll") || $0.contains("videos") }
        if work && coffee && outside { return "Coffee, Work & Air" }
        if work && outside { return "Work, Then Outside" }
        if work && screen { return "Work & Open Tabs" }
        if coffee && screen { return "Coffee & Scrolling" }
        if values.contains(where: { $0.contains("rage") || $0.contains("angry") }) { return "A Day with Edges" }
        return "A Day in the Making"
    }
}

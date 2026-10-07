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
        // Tags enrich current event records. Legacy IDs remain historical
        // records and must not be rewritten when the catalog is reloaded.
        guard id.hasPrefix("event_") else { return nil }
        let canonical = id
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

    private static let sphereTags = [
        "work": "work_study", "body": "body_wellbeing", "people": "people_connection",
        "home": "home_everyday", "travel": "getting_around", "play": "rest_play",
        "feelings": "feelings"
    ]

    private static let eventTags: [String: [String]] = [
        "root_worked": ["work_activity"], "root_chilled": [], "root_home": [], "break": ["rest"],
        "email": ["screen_use", "digital_admin"], "wrote": ["making"], "made": ["making"],
        "meeting": ["meeting", "in_person"], "workcall": ["phone_call", "work_activity"],
        "deadline": ["pressure", "stress"], "bored": ["boredom"], "avoidedwork": ["avoidance"],
        "nothingwork": ["work_activity"], "study": ["learning"], "class": ["learning"],
        "solo": ["learning", "alone"], "group": ["learning", "with_others"],
        "job": ["job_search"], "listings": ["job_search", "screen_use"],
        "application": ["job_search"], "interview": ["job_search", "conversation"],
        "walk": ["movement", "outdoors"], "run": ["movement", "exercise"],
        "workout": ["movement", "exercise"], "swam": ["movement", "exercise"],
        "stretched": ["movement", "exercise"], "errands": ["errands"],
        "snack": ["food_drink"], "meal_breakfast": ["food_drink", "meal"],
        "meal_lunch": ["food_drink", "meal"], "meal_dinner": ["food_drink", "meal"],
        "coffee": ["food_drink", "caffeine"], "tea": ["food_drink", "caffeine"],
        "wasted": ["food_drink"], "hangover": ["tiredness"], "slept": ["sleep"],
        "nap": ["sleep", "rest"], "bed": ["rest"], "shower": ["personal_care"],
        "talk": ["conversation", "in_person"], "friend": ["social_context", "with_others"],
        "family": ["social_context", "with_others"], "colleague": ["social_context", "with_others"],
        "texted": ["communication"], "peoplecall": ["phone_call"], "snapped": ["anger"],
        "avoidedpeople": ["avoidance"], "care": ["care"], "helped": ["care", "with_others"],
        "askedhelp": ["care"], "saidno": ["boundaries"], "child": ["care", "childcare"],
        "pet": ["care", "pet"], "alonepeople": ["alone"], "leftout": ["loneliness"],
        "chores": ["domestic"], "cooked": ["cooking", "food_drink"], "cleaned": ["domestic"],
        "laundry": ["domestic", "laundry"], "fixed": ["repair"], "plants": ["care", "plants"],
        "ignored": ["domestic"], "shopping": ["shopping", "errands"], "paperwork": ["errands"],
        "appointment": ["errands"], "guests": ["social_context", "with_others"],
        "doomscroll": ["screen_use", "social_media", "time_slip"], "commute": ["commute"],
        "transit": ["public_transit", "commute"], "train": ["public_transit", "commute"],
        "car": ["car_travel", "commute"], "bike": ["movement", "commute"],
        "walked": ["movement", "commute"], "cafe": ["cafe_or_bar"], "bar": ["cafe_or_bar"],
        "nature": ["outdoors"], "lost": ["time_slip"], "detour": ["location_change"],
        "new": ["location_change", "new_place"], "videos": ["screen_use", "media"],
        "movie": ["screen_use", "media"], "show": ["screen_use", "media"],
        "losttime": ["screen_use", "time_slip"], "book": ["reading"],
        "news": ["reading", "news"], "articles": ["reading"], "videogame": ["screen_use", "play_or_hobby"],
        "boardgame": ["play_or_hobby"], "withkid": ["play_or_hobby", "with_others"],
        "music": ["music"], "hobby": ["play_or_hobby"], "drew": ["making"],
        "sang": ["music", "making"], "danced": ["movement", "music"],
        "photos": ["making"], "nothingplay": ["unstructured_time"],
        "rage": ["anger"], "happy": ["happiness"], "tired": ["tiredness"],
        "anxious": ["anxiety"], "angry": ["anger"], "calm": ["calm"],
        "lonely": ["loneliness"], "curious": ["curiosity"], "okay": ["okayness"],
        "mixed": ["mixed_emotions"]
    ]

    static func tags(for nodeID: String) -> [String] {
        if let special = ["root_worked": "work_study", "root_chilled": "rest_play", "root_home": "home_everyday"][nodeID] {
            return [special] + (eventTags[nodeID] ?? [])
        }
        func root(for nodes: [HappeningEventNode], trail: [String]) -> String? {
            for node in nodes {
                let next = trail + [node.id]
                if node.id == nodeID { return next.first }
                if let found = root(for: node.children, trail: next) { return found }
            }
            return nil
        }
        guard let rootID = root(for: spheres, trail: []), let sphere = sphereTags[rootID] else {
            return eventTags[nodeID] ?? []
        }
        return Array(Set([sphere] + (eventTags[nodeID] ?? []))).sorted()
    }

    static func tags(forStoredHappeningID id: String) -> [String]? {
        let canonical = HappeningDefaults.canonicalID(id)
        guard canonical.hasPrefix("event_") else { return nil }
        let eventID = String(canonical.dropFirst("event_".count))
        guard event(eventID) != nil else { return nil }
        return tags(for: eventID)
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

    // The default atlas retains the six roots and their shared intersections.
    // Personal can promote a recommendation within its own sector; its atlas
    // is then shared with All and stays frozen for the open field.
    private static let outwardIDs = ["email", "music", "cleaned", "meal_lunch", "run", "family"]
    private static let intersectionIDs = ["break", "nap", "cooked", "cafe", "peoplecall", "workcall"]
    static let allNodes: [PlacedEvent] = makeAtlas()
    private static let defaultByID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
    let atlasNodes: [PlacedEvent]
    private var byID: [String: PlacedEvent] {
        Dictionary(uniqueKeysWithValues: atlasNodes.map { ($0.id, $0) })
    }

    init(expandedIDs: [String] = [], recommendedHappeningIDs: [String] = []) {
        atlasNodes = Self.personalAtlas(recommendedHappeningIDs)
        nodes = Array(atlasNodes.prefix(6))
        // Replay the same starting field before its taps, including pre-revealed
        // recommendations, so reopening preserves node order and parent links.
        revealHappenings(recommendedHappeningIDs)
        for id in expandedIDs { expand(id) }
    }

    /// Every addition path, including Health and restore, reveals the same ID.
    mutating func revealHappenings(_ ids: [String]) {
        for id in ids {
            if let eventID = HappeningEventTree.eventID(forHappeningID: id) { reveal(eventID) }
        }
    }

    /// Keep directly added All events visible when returning to Personal, including
    /// the path from the hub. This does not log or remove any additional event.
    mutating func reveal(_ id: String) {
        guard !nodes.contains(where: { $0.id == id }), let placed = byID[id] else { return }
        if let parentID = placed.parentID { reveal(parentID) }
        nodes.append(placed)
    }

    @discardableResult
    mutating func expand(_ id: String) -> Int {
        guard !expandedIDs.contains(id), let parent = byID[id] else { return 0 }
        reveal(id)
        let visible = Set(nodes.map(\.id))
        let children = children(of: parent).filter { !visible.contains($0.id) }.map {
            PlacedEvent(event: $0.event, cell: $0.cell, parentID: id)
        }
        expandedIDs.append(id)
        nodes.append(contentsOf: children)
        return children.count
    }

    private func children(of parent: PlacedEvent) -> [PlacedEvent] {
        if let index = HappeningEventTree.startingEvents.firstIndex(where: { $0.id == parent.id }) {
            let direction = Cell.directions[index]
            let outwardCell = Cell(q: direction.q * 2, r: direction.r * 2)
            let outwardID = atlasNodes.first { $0.cell == outwardCell }?.id
            let ids = [outwardID, Self.intersectionIDs[(index + 5) % 6], Self.intersectionIDs[index]].compactMap { $0 }
            return ids.compactMap { byID[$0] }
        }
        let neighbors = Set(parent.cell.neighbors)
        return Array(atlasNodes.filter { neighbors.contains($0.cell) && $0.cell.ring > parent.cell.ring }
            .sorted {
                if $0.cell.distanceSquared != $1.cell.distanceSquared { return $0.cell.distanceSquared > $1.cell.distanceSquared }
                if $0.cell.r != $1.cell.r { return $0.cell.r < $1.cell.r }
                return $0.cell.q < $1.cell.q
            }.prefix(3))
    }

    private static func personalAtlas(_ happeningIDs: [String]) -> [PlacedEvent] {
        let roots = HappeningEventTree.startingEvents.map(\.id)
        let anchored = Set(roots + intersectionIDs)
        var promotedSectors = Set<String>()
        var occupants = allNodes.map(\.event)
        for happeningID in happeningIDs {
            guard let id = HappeningEventTree.eventID(forHappeningID: happeningID),
                  !anchored.contains(id),
                  // A shared intersection can have the neighboring root as its
                  // primary parent. Use the event's editorial route for its sector.
                  let rootID = HappeningEventTree.routes.first(where: { $0.contains(id) })?.first,
                  let sector = roots.firstIndex(of: rootID),
                  promotedSectors.insert(rootID).inserted,
                  let from = allNodes.firstIndex(where: { $0.id == id }),
                  let to = allNodes.firstIndex(where: { $0.id == outwardIDs[sector] }) else { continue }
            occupants.swapAt(from, to)
        }
        let newIDAtCell = Dictionary(uniqueKeysWithValues: zip(allNodes, occupants).map { ($0.0.cell, $0.1.id) })
        return zip(allNodes, occupants).map { slot, event in
            // Parents follow the immutable cell graph, avoiding an ID cycle
            // when an outer event trades places with its former ancestor.
            let parentID = slot.parentID.flatMap { defaultByID[$0]?.cell }.flatMap { newIDAtCell[$0] }
            return PlacedEvent(event: event, cell: slot.cell, parentID: parentID)
        }
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

/// Familiar events are recommended without replacing the six starting roots.
/// Count is one successful-use day; recency decay lets a changed routine emerge.
enum PersonalHappeningRecommendations {
    static let maximumCount = 3

    static func ranked(catalog: [Happening], historyByDay: [String: [String]] = [:],
                       todayIDs: [String] = [], dayKey: String? = nil, at date: Date) -> [String] {
        let roots = Set(HappeningEventTree.startingEvents.map { "event_" + $0.id })
        var usedDays: [String: Set<String>] = [:]
        var lastSeen: [String: Date] = [:]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        for (day, ids) in historyByDay {
            guard let seen = formatter.date(from: day), formatter.string(from: seen) == day,
                  seen <= date else { continue }
            for id in Set(ids.map(HappeningDefaults.canonicalID)) where HappeningDefaults.builtInIds.contains(id) {
                usedDays[id, default: []].insert(day)
                lastSeen[id] = max(lastSeen[id] ?? .distantPast, seen)
            }
        }
        if let dayKey {
            for id in Set(todayIDs.map(HappeningDefaults.canonicalID)) where HappeningDefaults.builtInIds.contains(id) {
                usedDays[id, default: []].insert(dayKey)
                lastSeen[id] = max(lastSeen[id] ?? .distantPast, date)
            }
        }
        let familiar = catalog.map { stored in
            var value = stored
            // Catalog tracking and snapshots overlap. Count their maximum,
            // never their sum, and count repeat additions only once per day.
            value.useCount = max(stored.useCount, usedDays[stored.id]?.count ?? 0)
            value.lastUsedAt = [stored.lastUsedAt, lastSeen[stored.id]].compactMap { $0 }.max()
            return value
        }
        return familiar.filter {
            HappeningDefaults.builtInIds.contains($0.id) && !roots.contains($0.id)
                && $0.useCount >= 2 && $0.lastUsedAt != nil
        }.sorted { left, right in
            func score(_ happening: Happening) -> Double {
                let days = max(0, date.timeIntervalSince(happening.lastUsedAt!) / 86_400)
                return log1p(Double(happening.useCount)) * pow(0.5, days / 21)
            }
            let a = score(left), b = score(right)
            if a != b { return a > b }
            if left.lastUsedAt != right.lastUsedAt { return left.lastUsedAt! > right.lastUsedAt! }
            return left.id < right.id
        }.prefix(maximumCount).map(\.id)
    }
}

enum HappeningDayTitle {
    private static let sphereOrder = [
        "work_study", "body_wellbeing", "people_connection", "home_everyday",
        "getting_around", "rest_play", "feelings"
    ]

    private static let sphereTitles: [String: [String]] = [
        "work_study": ["Office Hours After Dark", "Fluorescent Reprise"],
        "body_wellbeing": ["Body in Motion", "After the Long Walk"],
        "people_connection": ["Kitchen Table Sessions", "Voices Through the Glass"],
        "home_everyday": ["Domestic Frequencies", "The Long Version at Home"],
        "getting_around": ["Rooms Between Stations", "Transit Interlude"],
        "rest_play": ["One More Scroll", "Side B: No Plans"],
        "feelings": ["Weather Inside", "Several Keys at Once"]
    ]

    private static let pairTitles: [String: [String]] = [
        "body_wellbeing|work_study": ["Concrete & Open Air", "The Walk Between Shifts"],
        "people_connection|work_study": ["Meeting Room Echoes", "Voices Through the Glass"],
        "home_everyday|work_study": ["Inbox at the Kitchen Table", "Home Office, Side B"],
        "getting_around|work_study": ["Rooms Between Stations", "Commute in Minor Keys"],
        "rest_play|work_study": ["One More Tab", "Channels Changing"],
        "feelings|work_study": ["Work and Weather Within", "Fluorescent Hours"],
        "body_wellbeing|people_connection": ["Walks & Voices", "Movement and Company"],
        "body_wellbeing|home_everyday": ["Home Body Sessions", "Body, Then Home"],
        "body_wellbeing|getting_around": ["Footnotes in Transit", "A Day on Foot"],
        "body_wellbeing|rest_play": ["After the Long Walk", "Out, Then In"],
        "body_wellbeing|feelings": ["Pulse & Weather", "Moving Through Moods"],
        "home_everyday|people_connection": ["Kitchen Table Sessions", "Dinner, Then the Long Version"],
        "getting_around|people_connection": ["Calls Between Stations", "Passing Conversations"],
        "people_connection|rest_play": ["Late Conversation, Side B", "People, Then Playback"],
        "feelings|people_connection": ["Voices Under Weather", "Contact and Quiet"],
        "getting_around|home_everyday": ["Leaving the Lights On", "Home with Detours"],
        "home_everyday|rest_play": ["Domestic Frequencies", "Side B: No Plans"],
        "feelings|home_everyday": ["Rooms with Weather", "Home and Inner Weather"],
        "getting_around|rest_play": ["Interlude at the Last Stop", "Outings and Downtime"],
        "feelings|getting_around": ["Passing Weather", "In Motion, A Mind Elsewhere"],
        "feelings|rest_play": ["Restless, Side A", "Media and Moods"]
    ]

    private static let experienceTitles: [String: [String]] = [
        "anger": ["Static in the Wires", "A Room Full of Feedback"],
        "anxiety": ["Restless, Side A", "Quiet with the Lights On"],
        "pressure": ["Fluorescent Hours", "Under a Tight Refrain"],
        "stress": ["Fluorescent Hours", "Under a Tight Refrain"],
        "boredom": ["Long Loop", "The Same Four Bars"],
        "tiredness": ["Low Battery Reprise", "After the Last Note"],
        "distraction": ["Channels Changing", "A Signal from Somewhere Else"],
        "avoidance": ["Out of Range", "The Unanswered Side"],
        "time_slip": ["One More Scroll", "The Loop Goes On"],
        "loneliness": ["The Quiet Channel", "Room Tone"],
        "mixed_emotions": ["Weather Inside", "Several Keys at Once"],
        "calm": ["Room Tone", "Still Frequencies"],
        "curiosity": ["Unknown Frequencies", "In Search of a New Sound"],
        "happiness": ["Open Window Sessions", "A Brighter Room"],
        "excitement": ["High Frequency", "A Live Signal"],
        "okayness": ["No Major Changes", "Steady Frequencies"]
    ]

    /// Chooses a pre-authored release-style title from a stable day tag profile.
    /// The key includes the day so a saved snapshot always resolves the same way.
    static func releaseTitle(tagCounts: [String: Int], dayKey: String) -> String? {
        let experiences = experienceTitles.keys
            .filter { (tagCounts[$0] ?? 0) > 0 }
            .sorted {
                let left = tagCounts[$0] ?? 0
                let right = tagCounts[$1] ?? 0
                if left != right { return left > right }
                return $0 < $1
            }
        if let experience = experiences.first, let options = experienceTitles[experience] {
            return choose(options, seed: "\(dayKey)|\(experience)")
        }

        let rankedSpheres = sphereOrder
            .filter { (tagCounts[$0] ?? 0) > 0 }
            .sorted {
                let left = tagCounts[$0] ?? 0
                let right = tagCounts[$1] ?? 0
                if left != right { return left > right }
                return sphereOrder.firstIndex(of: $0)! < sphereOrder.firstIndex(of: $1)!
            }
        guard let primary = rankedSpheres.first else { return nil }
        let signature: String
        if rankedSpheres.count > 1 {
            signature = [primary, rankedSpheres[1]].sorted().joined(separator: "|")
            if let options = pairTitles[signature] {
                return choose(options, seed: "\(dayKey)|\(signature)")
            }
        }
        guard let options = sphereTitles[primary] else { return nil }
        return choose(options, seed: "\(dayKey)|\(primary)")
    }

    private static func choose(_ options: [String], seed: String) -> String? {
        guard !options.isEmpty else { return nil }
        let hash = seed.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return options[Int(hash % UInt64(options.count))]
    }

    static func make(from titles: [String], dayKey: String) -> String {
        let normalized = titles.map { $0.lowercased() }
        guard normalized.count >= 2 else { return "A Day in the Making" }
        let work = normalized.contains { $0.contains("work") || $0.contains("computer") }
        let coffee = normalized.contains { $0.contains("coffee") || $0.contains("tea") }
        let outside = normalized.contains { $0.contains("walk") || $0.contains("nature") || $0.contains("outside") }
        let screen = normalized.contains { $0.contains("social media") || $0.contains("videos") || $0.contains("email") }
        if work && coffee && outside { return "Coffee, Work, and Air" }
        if work && outside { return "Between Work and Air" }
        if coffee && screen { return "Between Tabs and Coffee" }
        if work && screen { return "Between Tasks and Tabs" }
        if outside && screen { return "Between Screens and Sky" }
        if outside { return "A Little Room to Roam" }
        let date = dayKey.split(separator: "-").suffix(2).joined(separator: ".")
        return date.isEmpty ? "A Day in the Making" : "A Day in the Making · \(date)"
    }
}

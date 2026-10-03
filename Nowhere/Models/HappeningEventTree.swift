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
            .init("move", "Moved around", [.init("walk", "Went for a walk"), .init("run", "Went for a run"), .init("workout", "Worked out"), .init("gym", "Went to the gym"), .init("errands", "Ran errands"), .init("stayedin", "Stayed in bed")]),
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

    static let all = spheres.flatMap { sphere in
        sphere.children.flatMap { category in
            category.children.flatMap { leaves($0) }
        }
    }
    static let startingEvents: [HappeningEventNode] = [
        event("computer"), event("walk"), event("coffee"), event("friend"), event("cooked"), event("doomscroll")
    ]

    static func event(_ id: String) -> HappeningEventNode {
        all.first { $0.id == id } ?? HappeningEventNode(id, "Unknown event")
    }

    static func category(containing event: HappeningEventNode) -> HappeningEventNode? {
        spheres.lazy.flatMap(\.children).first { category in
            category.children.contains { leaves($0).contains(where: { $0.id == event.id }) }
        }
    }

    static func flatten(_ node: HappeningEventNode) -> [HappeningEventNode] { [node] + node.children.flatMap(flatten) }
    static func leaves(_ node: HappeningEventNode) -> [HappeningEventNode] {
        node.children.isEmpty ? [node] : node.children.flatMap(leaves)
    }
    static func suggestions(for selected: HappeningEventNode, alreadyVisible: Set<String>) -> [HappeningEventNode] {
        let category = category(containing: selected)
        let events = category?.children.flatMap(leaves) ?? []
        return events.filter { !alreadyVisible.contains($0.id) && $0.id != selected.id }.prefix(10).map { $0 }
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

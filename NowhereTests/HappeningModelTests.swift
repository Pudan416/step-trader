import XCTest
@testable import Nowhere

/// The fixed catalog and durable behavior for current and historical events.
final class HappeningModelTests: XCTestCase {

    // MARK: - Built-in set

    func testBuiltInSetMatchesTheReviewedCatalogCount() {
        XCTAssertEqual(HappeningDefaults.builtIns.count, 106)
        XCTAssertEqual(HappeningDefaults.builtIns.count, HappeningDefaults.maximumCatalogCount)
    }

    func testBuiltInIdsAreUnique() {
        let ids = HappeningDefaults.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate built-in happening id")
    }

    func testBuiltInCopyIsCompleteDistinctAndFitsTheField() throws {
        let titles = HappeningDefaults.builtIns.map { $0.localizedTitle() }
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty && $0.count <= Happening.titleCharacterLimit })
        XCTAssertEqual(Set(titles.map { $0.lowercased() }).count, titles.count, "Duplicate titles")
        XCTAssertEqual(titles, HappeningDefaults.builtIns.map(\.title), "Fixed catalog copy is English")
    }

    func testRestoredCustomNamesKeepTheirDistinctLongSuffixes() throws {
        let data = Data(#"[{"id":"user_a","title":"Coffee with my sister","isBuiltIn":false,"useCount":4},{"id":"user_b","title":"Coffee with my brother","isBuiltIn":false,"useCount":2}]"#.utf8)
        let restored = try JSONDecoder().decode([Happening].self, from: data)
        XCTAssertEqual(restored.map { $0.localizedTitle() }, ["Coffee with my sister", "Coffee with my brother"])
        let roundTrip = try JSONDecoder().decode([Happening].self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(roundTrip, restored)
    }

    func testBuiltInsStartUnused() {
        for happening in HappeningDefaults.builtIns {
            XCTAssertTrue(happening.isBuiltIn, "\(happening.id) must be built-in")
            XCTAssertEqual(happening.useCount, 0, "\(happening.id) must start at 0")
            XCTAssertNil(happening.lastUsedAt, "\(happening.id) must start unused")
        }
    }

    func testBuiltInIdsSetMatchesList() {
        XCTAssertEqual(
            HappeningDefaults.builtInIds,
            Set(HappeningDefaults.builtIns.map(\.id))
        )
    }

    /// Current choices use event IDs; legacy category IDs remain historical.
    func testBuiltInIdsUseTheEventNamespace() {
        for id in HappeningDefaults.builtInIds {
            XCTAssertTrue(
                id.hasPrefix("event_"),
                "\(id) must use the event_ namespace"
            )
        }
    }

    // MARK: - Economy constants

    func testThreePartFormulaStillTotalsOneHundred() {
        XCTAssertEqual(
            EnergyDefaults.activityMaxPoints
            + EnergyDefaults.sleepMaxPoints
            + HappeningDefaults.happeningsMaxPoints,
            EnergyDefaults.maxBaseEnergy,
            "steps(20) + sleep(20) + happenings(60) = 100"
        )
    }

    func testAdditionPointsReachTheCapAtTen() {
        XCTAssertEqual(
            HappeningDefaults.pointsPerAddition * 10,
            HappeningDefaults.happeningsMaxPoints,
            "Ten additions must exactly reach the ceiling"
        )
    }

    // MARK: - Model behaviour

    func testRoundTripsThroughCodable() throws {
        let original = Happening(
            id: "user_1", title: "Rooftop coffee", isBuiltIn: false,
            useCount: 3, lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Happening.self, from: data), original)
    }

    func testRecordUseIncrementsAndStamps() {
        var happening = HappeningDefaults.builtIns[0]
        let when = Date(timeIntervalSince1970: 500)
        happening.recordUse(at: when)

        XCTAssertEqual(happening.useCount, 1)
        XCTAssertEqual(happening.lastUsedAt, when)
    }

    func testRecordUseAccumulates() {
        var happening = HappeningDefaults.builtIns[0]
        happening.recordUse(at: Date(timeIntervalSince1970: 100))
        happening.recordUse(at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(happening.useCount, 2)
        XCTAssertEqual(happening.lastUsedAt, Date(timeIntervalSince1970: 200))
    }

    /// User happenings carry their title directly — it is already in whatever
    /// language they typed. Only built-ins resolve through the string catalog.
    func testUserHappeningTitleIsUsedVerbatim() {
        let happening = Happening(
            id: "user_1", title: "Крыша, кофе", isBuiltIn: false
        )
        XCTAssertEqual(happening.localizedTitle(), "Крыша, кофе")
    }

    /// Built-ins resolve through `option.title.<id>`, falling back to the
    /// English source string when the key is missing from the catalog.
    func testBuiltInTitleResolvesOrFallsBack() {
        for happening in HappeningDefaults.builtIns {
            XCTAssertFalse(
                happening.localizedTitle().isEmpty,
                "\(happening.id) resolved to an empty title"
            )
        }
    }
}


final class HappeningPersonalizationRegressionTests: XCTestCase {
    func testEverySurveyChoiceUsesASyntheticIDAndAnAuthoritativeRepresentative() throws {
        for (index, question) in HappeningPersonalizationQuestion.allCases.enumerated() {
            var profile = HappeningPersonalizationProfile()
            profile.hasStarted = true
            profile.questionIndex = index
            XCTAssertEqual(profile.fieldChoices.count, question.choices.count)
            XCTAssertTrue(profile.fieldChoices.allSatisfy { $0.id.hasPrefix("survey:") && !$0.isBuiltIn && $0.useCount == 0 })
            for choice in question.choices {
                let representative = try XCTUnwrap(choice.visualHappeningID, choice.id)
                XCTAssertTrue(HappeningDefaults.builtInIds.contains(representative), choice.id)
            }
        }
        XCTAssertEqual(HappeningPersonalizationQuestion.unwind.choices.count, 8)
        XCTAssertEqual(HappeningPersonalizationQuestion.people.choices.count, 6)
        XCTAssertEqual(HappeningPersonalizationQuestion.aspirations.choices.count, 6)
    }

    func testAlcoholPreferencesAndLegacyBeerAnswersKeepDistinctMeaning() throws {
        var profile = HappeningPersonalizationProfile()
        profile.answers["habits"] = ["beer"]
        let decoded = try JSONDecoder().decode(HappeningPersonalizationProfile.self,
            from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.answers["habits"], ["beer"])
        XCTAssertEqual(decoded.scores(dayKey: "today")["event_beer"], 3)
        XCTAssertNil(decoded.scores(dayKey: "today")["event_drink"])
        XCTAssertNil(decoded.scores(dayKey: "today")["event_wasted"])
        profile.answers["habits"] = ["alcohol", "drunk"]
        let scores = profile.scores(dayKey: "today")
        XCTAssertEqual(scores["event_drink"], 3)
        XCTAssertEqual(scores["event_beer"], 3)
        XCTAssertEqual(scores["event_wasted"], 3)
        XCTAssertEqual(HappeningDefaults.canonicalID("event_beer"), "event_beer")
        XCTAssertEqual(HappeningDefaults.canonicalID("event_wasted"), "event_wasted")
        XCTAssertEqual(HappeningDefaults.canonicalID("happening_drinks"), "happening_drinks")
    }

    func testEmotionsExpireWithoutRemovingDurablePreferences() {
        var profile = HappeningPersonalizationProfile()
        profile.answers = ["feelings": ["tired"], "routine": ["walk"]]
        profile.emotionDayKey = "yesterday"
        let scores = profile.scores(dayKey: "today")
        XCTAssertNil(scores["event_tired"])
        XCTAssertEqual(scores["event_walk"], 3)
        XCTAssertEqual(profile.answers["feelings"], ["tired"])
    }

    func testCatalogTopUpKeepsBeerAndIntoxicationCountersIndependent() throws {
        let suite = "HappeningAlcoholTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored = [
            Happening(id: "event_beer", title: "Had a beer", isBuiltIn: true, useCount: 4),
            Happening(id: "event_wasted", title: "Got wasted", isBuiltIn: true, useCount: 2)
        ]
        defaults.set(try JSONEncoder().encode(stored), forKey: SharedKeys.happeningCatalog)
        let store = HappeningStore(defaults: defaults)
        store.load()
        XCTAssertEqual(store.selectable.first { $0.id == "event_beer" }?.useCount, 4)
        XCTAssertEqual(store.selectable.first { $0.id == "event_wasted" }?.useCount, 2)
        XCTAssertEqual(store.selectable.first { $0.id == "event_drink" }?.useCount, 0)
        XCTAssertEqual(store.selectable.first { $0.id == "event_wasted" }?.title, "Got drunk")
        XCTAssertEqual(store.all.first { $0.id == "event_wasted" }?.title, "Got wasted")
        for id in ["beer", "drink", "wasted"] {
            XCTAssertTrue(HappeningEventTree.tags(for: id).contains("alcohol"))
            XCTAssertEqual(HappeningEventTree.personalSphereIndex(for: id), 3)
        }
    }
}

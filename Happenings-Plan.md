# Canvas Happenings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the body/mind/heart category model from Nowhere and replace the radial hold menu + category sheet with a single one-tap palette of ten "happenings".

**Architecture:** `EnergyCategory`, `CustomEnergyOption` and `EphemeralMoment` are deleted; `EnergyOption` becomes `Happening` with stored `useCount`/`lastUsedAt`. The per-category *selection* model (three capped `[String]` arrays, toggled on/off) becomes a single append-only *additions* log (`[OptionEntry]`), which is what the new economy counts. Category-derived shape choice becomes a user-configured multi-select set. The only place `EnergyCategory` survives is a private decode-only `LegacyCategory` in `CanvasElement`'s migration path.

**Tech Stack:** SwiftUI, Swift 5.9+, XCTest, Supabase (postgres + swift client), App Group `group.personal-project.StepsTrader`, widget + 3 app extensions.

## Global Constraints

- Build command: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- Test command: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'`
- Daily point ceiling stays **100**. New formula: `steps(20) + sleep(20) + happenings(60)`, `happenings = min(additions × 10, 60)`.
- Copy lives in `StepsTrader/Localizable.xcstrings` under `option.title.<id>`. Never hardcode user-facing strings outside that convention.
- Logging uses `AppLogger.<category>`, never `print`.
- UserDefaults keys are declared in `StepsTrader/Utilities/SharedKeys.swift` with a `_v1` suffix convention.
- `CanvasShapeType.organicBlob` is Pro-gated at spawn time only — never removed from the settings UI.
- Do NOT change tab structure, navigation, design tokens, or onboarding copy. Those are separate specs.
- Do NOT drop any Supabase column in this change. Old clients stay in the field.

---

## Findings that change the brief

These were verified against the code on 2026-08-08 and contradict or extend `Happenings-Brief.md`. Read them before starting; they are the difference between a 2-day job and a 2-week one.

### F1 — The model is selection-based, not addition-based (biggest item)

The brief describes the economy switching from "categories" to "additions" as if only the arithmetic changes. It does not. Today:

- `AppModel.dailyBodySelections` / `dailyRestSelections` / `dailyHeartSelections` are `[String]` of option ids (`AppModel.swift:179` and neighbours), **toggled on and off**, capped at `EnergyDefaults.maxSelectionsPerCategory = 4`.
- `AppModel+DailyEnergy.toggleDailySelection(optionId:category:)` (line 679) adds *or removes*.
- `GalleryView.spawnElement` (line 1022) **deduplicates** by `optionId + category` — a second tap on the same option recolors the existing element instead of adding one.
- `GalleryView` reconcile (line 928) does `dayCanvas.elements.removeAll { !activeIds.contains($0.optionId) }` — the canvas is *derived from* the selection arrays. Any element whose optionId is not in a selection array is deleted on next reconcile.

Repeat additions therefore cannot work until the selection arrays are replaced by an append-only additions log. This is Task 4 and it is the load-bearing task; the palette (Task 8) is comparatively easy. ~103 call sites reference the three arrays.

### F2 — `PastDaySnapshot` has no `bodyPoints`/`mindPoints`/`heartPoints`

Brief §9 says "PastDaySnapshot keeps decoding `bodyPoints`/`mindPoints`/`heartPoints`". It does not have those fields. `PastDaySnapshot` (`Models/PastDaySnapshot.swift:3-131`) has `bodyIds`/`mindIds`/`heartIds: [String]` plus a legacy decode path for `activityIds`/`creativityIds`/`recoveryIds`/`restIds`/`joysIds`. The type that has `bodyPoints`/`mindPoints`/`heartPoints` is `WidgetSnapshot` (written at `AppModel+DailyEnergy.swift:1042-1054`). Both need handling; the plan treats them separately (Tasks 5 and 6).

### F3 — `EnergyCategory` has a legacy-alias decoder that must be preserved

`EnergyCategory.init(from:)` (`Models/EnergyCategory.swift:10-24`) maps five legacy raw values: `activity→body`, `creativity|recovery|rest→mind`, `joys→heart`. Saved canvases on beta devices contain these strings. `LegacyCategory` must reproduce **all** of them or old canvases fail to decode entirely — a louder failure than the shape drift the brief warns about, but the same fixture guards both.

### F4 — The legacy shape fallback is `defaultShape(for:)`, not the user preference

Brief §9 names the replacement `CanvasShapeType.legacyDefault(for:)`. The behaviour it must reproduce is `CanvasShapeType.defaultShape(for:)` (`Models/ShapeStyles.swift:43-49`): `body→.circle`, `mind→.snowflake`, `heart→.rays`. Note that `init(from:)` at `CanvasElement.swift:283-284` falls back to `defaultShape(for:)` (the static default), while the `resolvedShapeType` computed property at line 82 falls back to `resolved(for:)` (the user's live preference). Only the decode-path fallback is the migration concern.

### F5 — `CanvasElement.category` is a non-optional encoded field

`category` is `let` (line 16), decoded with `try c.decode` (line 260, non-optional) and written on encode (line 299). Removing it changes the on-disk format. New writes must omit it; reads must tolerate both. Also `CanvasElement.spawn` and `reroll` both call `CanvasShapeType.resolved(for: category)`.

### F6 — Two Supabase tables hold categories, not one

Beyond the three tables the brief lists, `user_daily_selections` (baseline schema line 95) is itself category-shaped: `activity_ids text[]`, `recovery_ids text[]`, `joys_ids text[]`. It is written by `SupabaseSyncService+Selections`. The plan keeps writing it during rollout (Task 11) and adds `happening_ids text[]` alongside, mirroring the column-relaxation strategy.

### F7 — The shape generators are static `Path` factories on `ProceduralShapeGenerator`

Not standalone types. Exact signatures:

```swift
extension ProceduralShapeGenerator {
    struct BlobSource { let center: CGPoint; let radius: CGFloat }

    static func metaballPath(
        blobs: [BlobSource], in rect: CGRect,
        gridResolution: Int = 50, threshold: CGFloat = 1.0
    ) -> Path

    static func organicBlobPath(
        seed: UInt64, complexity: Double = 0.5, symmetry: Int = 1,
        time: Double = 0, in rect: CGRect
    ) -> Path
}
```

Files: `StepsTrader/Shapes/MetaballGenerator.swift`, `StepsTrader/Shapes/OrganicBlobShapeGenerator.swift`.

---

## File Structure

**New files**

| Path | Responsibility |
|---|---|
| `StepsTrader/Models/Happening.swift` | The `Happening` struct, `OptionEntry` (decategorised), `EnergyRoutine` with flat `happeningIds` |
| `StepsTrader/Models/HappeningDefaults.swift` | The ten built-in happenings + description/example lookups |
| `StepsTrader/Stores/HappeningStore.swift` | Persistence of the happening catalog: load, create, orphan reconstitution, `recordUse` |
| `StepsTrader/Models/HappeningPaletteOrder.swift` | Pure ordering function + day-frozen cache. No UI, no AppModel — testable in isolation |
| `StepsTrader/Views/Palette/HappeningPaletteView.swift` | The sheet: metaball cluster, scroll, close button |
| `StepsTrader/Views/Palette/HappeningBlobLayout.swift` | Pure layout maths: blob centers/radii for N happenings. Testable without a view |
| `StepsTrader/Views/Palette/HappeningFreeTextField.swift` | The `+` node's inline free-text entry |
| `StepsTrader/Models/LegacyCategory.swift` | Decode-only enum, migration path only |
| `Steps4Tests/Fixtures/canvas_legacy_categorised.json` | Real captured old-format canvas (Task 1) |
| `Steps4Tests/HappeningMigrationTests.swift` | The migration guard |
| `Steps4Tests/HappeningPaletteOrderTests.swift` | Ordering + day-freeze |
| `Steps4Tests/HappeningEconomyTests.swift` | The 60-cap and the 100 formula |
| `supabase/migrations/20260808_happenings_relax_categories.sql` | Column relaxation + `allowed_canvas_shapes` + entries surrogate PK |

**Deleted files**

`Models/EnergyCategory.swift`, `Models/EnergyOption.swift`, `Models/EphemeralMoment.swift`, `Extensions/EnergyCategory+Helpers.swift`, `Models/CanvasImageCatalog.swift`, `Views/RadialHoldMenu.swift`, `Views/CategoryDetailView.swift`, `Views/MomentEntrySheet.swift`.

`CanvasImageCatalog` is already a no-op stub (its own doc comment says "safe to remove entirely") and its only API takes an `EnergyCategory`, so it goes with the enum.

**Heavily modified**

`AppModel.swift`, `AppModel+DailyEnergy.swift`, `Models/CanvasElement.swift`, `Models/ShapeStyles.swift`, `Models/PastDaySnapshot.swift`, `Views/GalleryView.swift`, `Stores/PreferencesStore.swift`, `Services/SupabaseSyncService{,+Entries,+Selections,+Preferences}.swift`, `Services/SupabaseSyncDTOs.swift`, `Views/Settings/SettingsAppearancePage.swift`, `Views/MeView.swift`, `Views/MainTabView.swift`, `Views/OnboardingStoriesView.swift`.

---

## Task 1: Capture the migration fixture and guard it

The brief's §12 working agreement: write this test first, from a real fixture, before deleting anything. At this point the code still compiles unchanged, so the test characterises **current** behaviour and will keep failing loudly if any later task drifts it.

**Files:**
- Create: `Steps4Tests/Fixtures/canvas_legacy_categorised.json`
- Create: `Steps4Tests/HappeningMigrationTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj` (add the fixture as a test-bundle resource)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `Steps4Tests/Fixtures/canvas_legacy_categorised.json`, a real old-format `DayCanvas` with elements that have `category` and no `frozenShapeType`. Task 7 depends on this file existing.

- [ ] **Step 1: Capture a real old-format canvas from the simulator**

Canvases live at `CanvasStorageService.storageDirectory` as `canvas_<dayKey>.json` (`Services/CanvasStorageService.swift:198`). Find the app container and list them:

```bash
find ~/Library/Developer/CoreSimulator/Devices -name "canvas_*.json" -not -path "*/Trash/*" 2>/dev/null
```

If that returns nothing, the simulator has no saved canvas yet. Produce one: run the app, add one option from each of Body, Mind and Heart via the existing radial menu, background the app, then re-run the `find`.

The captured file will already have `frozenShapeType` (it is written by current `spawn`). Strip it to recreate the pre-`frozenShapeType` format — that is the case under test:

```bash
mkdir -p Steps4Tests/Fixtures
python3 - <<'PY'
import json, glob, sys
src = sorted(glob.glob('/tmp/captured_canvas.json'))  # copy the found file here first
if not src: sys.exit("copy the captured canvas to /tmp/captured_canvas.json first")
d = json.load(open(src[0]))
for el in d.get('elements', []):
    el.pop('frozenShapeType', None)
assert d.get('elements'), "fixture must contain at least one element"
cats = {el.get('category') for el in d['elements']}
assert cats <= {'body','mind','heart'}, f"unexpected categories: {cats}"
json.dump(d, open('Steps4Tests/Fixtures/canvas_legacy_categorised.json','w'), indent=2)
print("categories in fixture:", cats)
PY
```

Verify the printed set covers all three categories. If it does not, add the missing ones in the app and recapture — the test asserts on all three mappings.

If capture is genuinely impossible (no device, no simulator data), **stop and report it** rather than synthesizing the file. The brief calls this out explicitly, and a synthesized fixture proves nothing about the real on-disk format.

- [ ] **Step 2: Add the fixture to the test bundle in Xcode**

The fixture must be a resource of the `Steps4Tests` target or `Bundle(for:)` will not find it. Open `Steps4.xcodeproj`, select `Steps4Tests` → Build Phases → Copy Bundle Resources → `+` → add `Steps4Tests/Fixtures/canvas_legacy_categorised.json`.

- [ ] **Step 3: Write the failing test**

Create `Steps4Tests/HappeningMigrationTests.swift`:

```swift
import XCTest
@testable import Steps4

/// Guards the one failure mode that is invisible in review: elements saved
/// before `frozenShapeType` existed resolve their shape *through* the category.
/// Dropping the category outright silently redraws historical canvases.
/// Fixture is a real captured canvas with `frozenShapeType` stripped.
final class HappeningMigrationTests: XCTestCase {

    private func loadFixture() throws -> Data {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(
            bundle.url(forResource: "canvas_legacy_categorised", withExtension: "json"),
            "Fixture missing from the Steps4Tests bundle — check Copy Bundle Resources"
        )
        return try Data(contentsOf: url)
    }

    /// The mapping the legacy decode path must reproduce, from
    /// CanvasShapeType.defaultShape(for:) as it stood before the refactor.
    private let expectedByCategory: [String: CanvasShapeType] = [
        "body": .circle,
        "mind": .snowflake,
        "heart": .rays
    ]

    func testLegacyCanvasDecodesToUnchangedFrozenShapeTypes() throws {
        let data = try loadFixture()

        // Read the raw categories straight out of the JSON so the expectation
        // does not depend on any type we are about to change.
        let raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let rawElements = try XCTUnwrap(raw["elements"] as? [[String: Any]])
        XCTAssertFalse(rawElements.isEmpty, "Fixture must contain elements")

        let canvas = try JSONDecoder().decode(DayCanvas.self, from: data)
        XCTAssertEqual(canvas.elements.count, rawElements.count)

        for (rawElement, decoded) in zip(rawElements, canvas.elements) {
            let rawCategory = try XCTUnwrap(rawElement["category"] as? String)
            XCTAssertNil(
                rawElement["frozenShapeType"],
                "Fixture element must predate frozenShapeType"
            )
            let expected = try XCTUnwrap(
                expectedByCategory[rawCategory],
                "Unmapped legacy category in fixture: \(rawCategory)"
            )
            XCTAssertEqual(
                decoded.frozenShapeType, expected,
                "Element \(decoded.optionId) drifted: category \(rawCategory) "
                + "must still resolve to \(expected)"
            )
        }
    }

    /// EnergyCategory's decoder maps five legacy raw values. Saved canvases on
    /// beta devices contain them, so LegacyCategory must accept all five or the
    /// whole canvas fails to decode.
    func testLegacyCategoryAliasesStillDecode() throws {
        let aliases: [String: CanvasShapeType] = [
            "activity": .circle,
            "creativity": .snowflake,
            "recovery": .snowflake,
            "rest": .snowflake,
            "joys": .rays
        ]
        let template = try loadFixture()
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: template) as? [String: Any]
        )
        let elements = try XCTUnwrap(json["elements"] as? [[String: Any]])
        let first = try XCTUnwrap(elements.first)

        for (alias, expected) in aliases {
            var element = first
            element["category"] = alias
            element["frozenShapeType"] = nil
            json["elements"] = [element]
            let patched = try JSONSerialization.data(withJSONObject: json)
            let canvas = try JSONDecoder().decode(DayCanvas.self, from: patched)
            XCTAssertEqual(
                canvas.elements.first?.frozenShapeType, expected,
                "Legacy alias \(alias) must resolve to \(expected)"
            )
        }
    }
}
```

- [ ] **Step 4: Run the test — it must PASS against unmodified code**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningMigrationTests 2>&1 | tail -20
```

Expected: **PASS**. This is the one test in the plan that starts green — it characterises behaviour we must not break. If it fails now, the fixture is wrong (probably `frozenShapeType` was not stripped, or the categories in it do not match `defaultShape(for:)`); fix the fixture, not the test.

- [ ] **Step 5: Commit**

```bash
git add Steps4Tests/Fixtures/canvas_legacy_categorised.json Steps4Tests/HappeningMigrationTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "test: guard legacy canvas shape resolution before decategorising"
```

---

## Task 2: The `Happening` model and its built-in set

**Files:**
- Create: `StepsTrader/Models/Happening.swift`
- Create: `StepsTrader/Models/HappeningDefaults.swift`
- Create: `Steps4Tests/HappeningModelTests.swift`
- Modify: `StepsTrader/Localizable.xcstrings`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `struct Happening: Identifiable, Codable, Equatable` with `let id: String`, `var title: String`, `let isBuiltIn: Bool`, `var useCount: Int`, `var lastUsedAt: Date?`, plus `func localizedTitle() -> String`
  - `enum HappeningDefaults` with `static let builtIns: [Happening]` (10 entries) and `static let builtInIds: Set<String>`
  - `struct OptionEntry` — same shape as today minus `category`
  - `struct EnergyRoutine` with `var happeningIds: [String]` replacing the three arrays

Do not delete `EnergyOption.swift` in this task — the project must keep compiling. Both types coexist until Task 4 cuts over.

- [ ] **Step 1: Write the failing test**

Create `Steps4Tests/HappeningModelTests.swift`:

```swift
import XCTest
@testable import Steps4

final class HappeningModelTests: XCTestCase {

    func testBuiltInSetIsExactlyTen() {
        XCTAssertEqual(HappeningDefaults.builtIns.count, 10)
    }

    func testBuiltInIdsAreUnique() {
        let ids = HappeningDefaults.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate built-in happening id")
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

    func testRoundTripsThroughCodable() throws {
        let original = Happening(
            id: "custom-1", title: "Rooftop coffee",
            isBuiltIn: false, useCount: 3, lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Happening.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testOptionEntryHasNoCategory() throws {
        let entry = OptionEntry(
            id: "e1", dayKey: "2026-08-08", optionId: "happening_walk",
            colorHex: "#AABBCC", timestamp: Date(timeIntervalSince1970: 0), assetVariant: nil
        )
        let data = try JSONEncoder().encode(entry)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["category"], "OptionEntry must no longer carry a category")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningModelTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'Happening' in scope`.

- [ ] **Step 3: Write `Happening.swift`**

```swift
import Foundation

/// A single loggable thing. Replaces EnergyOption, CustomEnergyOption and
/// EphemeralMoment — the three near-identical types the category model needed.
///
/// `useCount` and `lastUsedAt` are stored rather than derived because the
/// palette reads them on every open and must not scan history to do it.
struct Happening: Identifiable, Codable, Equatable {
    let id: String
    /// Fallback English title. For built-ins the authoritative copy lives in
    /// Localizable.xcstrings under `option.title.<id>`; user happenings use this directly.
    var title: String
    let isBuiltIn: Bool
    var useCount: Int
    var lastUsedAt: Date?

    init(id: String, title: String, isBuiltIn: Bool, useCount: Int = 0, lastUsedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.isBuiltIn = isBuiltIn
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    /// Built-ins resolve through the string catalog; user happenings return
    /// their own title, which is already in whatever language they typed.
    func localizedTitle() -> String {
        guard isBuiltIn else { return title }
        return Bundle.main.localizedString(
            forKey: "option.title.\(id)", value: title, table: nil
        )
    }

    /// Records one addition. Called by HappeningStore, never directly by views.
    mutating func recordUse(at date: Date = .now) {
        useCount += 1
        lastUsedAt = date
    }
}

/// One addition of one happening on one day. Repeat additions of the same
/// happening produce separate entries — that is what the economy counts.
struct OptionEntry: Identifiable, Codable, Equatable {
    let id: String
    let dayKey: String
    let optionId: String
    var colorHex: String
    var timestamp: Date
    var assetVariant: Int?
}

/// A saved preset. The three category arrays collapse to one flat list.
struct EnergyRoutine: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var happeningIds: [String]
    var lastUsed: Date?

    init(id: String = UUID().uuidString, name: String, happeningIds: [String], lastUsed: Date? = nil) {
        self.id = id
        self.name = name
        self.happeningIds = happeningIds
        self.lastUsed = lastUsed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, happeningIds, lastUsed
        case bodyIds, mindIds, heartIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
        if let flat = try c.decodeIfPresent([String].self, forKey: .happeningIds) {
            happeningIds = flat
        } else {
            // Legacy routines saved with three category arrays. Order is
            // body → mind → heart, matching how they were displayed.
            let body = try c.decodeIfPresent([String].self, forKey: .bodyIds) ?? []
            let mind = try c.decodeIfPresent([String].self, forKey: .mindIds) ?? []
            let heart = try c.decodeIfPresent([String].self, forKey: .heartIds) ?? []
            happeningIds = body + mind + heart
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(happeningIds, forKey: .happeningIds)
        try c.encodeIfPresent(lastUsed, forKey: .lastUsed)
    }
}
```

Note: `EnergyRoutine` already exists in `EnergyOption.swift:61-77`. Delete it from there in this step so there is exactly one declaration — it is the only type in that file with no category dependency, so moving it now costs nothing and avoids a duplicate-symbol build error.

- [ ] **Step 4: Write `HappeningDefaults.swift`**

Ten built-ins, ids prefixed `happening_` so they can never collide with the old `body_`/`mind_`/`heart_` ids still present in user history:

```swift
import Foundation

enum HappeningDefaults {
    static let sleepTargetHours: Double = 8
    static let sleepMaxPoints: Int = 20
    static let stepsTarget: Double = 10_000
    static let stepsMaxPoints: Int = 20

    /// Points per addition, and the ceiling additions can contribute.
    /// day = steps(20) + sleep(20) + happenings(60) = 100
    static let pointsPerAddition: Int = 10
    static let happeningsMaxPoints: Int = 60

    static let builtIns: [Happening] = [
        Happening(id: "happening_walk",           title: "Walk",                    isBuiltIn: true),
        Happening(id: "happening_workout",        title: "Workout",                 isBuiltIn: true),
        Happening(id: "happening_slept_well",     title: "Slept well",              isBuiltIn: true),
        Happening(id: "happening_called_someone", title: "Called someone I love",   isBuiltIn: true),
        Happening(id: "happening_drinks",         title: "Drinks with friends",     isBuiltIn: true),
        Happening(id: "happening_read",           title: "Read",                    isBuiltIn: true),
        Happening(id: "happening_laughed",        title: "Laughed",                 isBuiltIn: true),
        Happening(id: "happening_made_something", title: "Made something",          isBuiltIn: true),
        Happening(id: "happening_outside",        title: "Time outside",            isBuiltIn: true),
        Happening(id: "happening_did_nothing",    title: "Did nothing on purpose",  isBuiltIn: true)
    ]

    static let builtInIds: Set<String> = Set(builtIns.map(\.id))
}
```

`EnergyDefaults` keeps `maxBaseEnergy`, `sleepTargetHours`, `stepsTarget`, `sleepMaxPoints`, `stepsMaxPoints` for now — Task 5 removes the selection constants from it. The duplicated constants above exist so `HappeningDefaults` is self-contained; Task 5 collapses them.

- [ ] **Step 5: Add the ten strings to `Localizable.xcstrings`**

Add one entry per id under key `option.title.<id>` with the English source string matching the `title` field above. Follow the existing entries' shape exactly — open the file and copy the structure of an existing `option.title.body_walking` entry.

```bash
grep -c "option.title." StepsTrader/Localizable.xcstrings
```

Note the count before and after; it must increase by exactly 10.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningModelTests 2>&1 | tail -20
```

Expected: PASS, 6 tests.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Models/Happening.swift StepsTrader/Models/HappeningDefaults.swift StepsTrader/Models/EnergyOption.swift StepsTrader/Localizable.xcstrings Steps4Tests/HappeningModelTests.swift
git commit -m "feat: add Happening model and ten built-in happenings"
```

---

## Task 3: `HappeningStore` — catalog persistence and orphan reconstitution

**Files:**
- Create: `StepsTrader/Stores/HappeningStore.swift`
- Create: `Steps4Tests/HappeningStoreTests.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift`

**Interfaces:**
- Consumes: `Happening`, `HappeningDefaults` (Task 2)
- Produces:
  - `SharedKeys.happeningCatalog = "happeningCatalog_v1"`
  - `final class HappeningStore` with `init(defaults: UserDefaults)`, `var all: [Happening] { get }`, `func happening(id: String) -> Happening?`, `@discardableResult func create(title: String, at: Date) -> Happening`, `func recordUse(id: String, at: Date)`, `func reconstituteOrphans(fromHistoryIds: Set<String>, titleResolver: (String) -> String)`, `func load()`

- [ ] **Step 1: Add the storage key**

In `StepsTrader/Utilities/SharedKeys.swift`, next to the existing canvas-shape keys around line 104:

```swift
    static let happeningCatalog = "happeningCatalog_v1"
```

- [ ] **Step 2: Write the failing test**

Create `Steps4Tests/HappeningStoreTests.swift`:

```swift
import XCTest
@testable import Steps4

final class HappeningStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HappeningStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSeedsBuiltInsOnFirstLoad() {
        let store = HappeningStore(defaults: defaults)
        store.load()
        XCTAssertEqual(store.all.count, 10)
        XCTAssertEqual(Set(store.all.map(\.id)), HappeningDefaults.builtInIds)
    }

    func testRecordUseIncrementsAndStamps() {
        let store = HappeningStore(defaults: defaults)
        store.load()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordUse(id: "happening_walk", at: when)

        let walk = store.happening(id: "happening_walk")
        XCTAssertEqual(walk?.useCount, 1)
        XCTAssertEqual(walk?.lastUsedAt, when)
    }

    func testRecordUsePersistsAcrossInstances() {
        let first = HappeningStore(defaults: defaults)
        first.load()
        first.recordUse(id: "happening_read", at: Date(timeIntervalSince1970: 100))

        let second = HappeningStore(defaults: defaults)
        second.load()
        XCTAssertEqual(second.happening(id: "happening_read")?.useCount, 1)
    }

    func testCreateMakesUsedUserHappening() {
        let store = HappeningStore(defaults: defaults)
        store.load()
        let when = Date(timeIntervalSince1970: 500)
        let made = store.create(title: "Rooftop coffee", at: when)

        XCTAssertFalse(made.isBuiltIn)
        XCTAssertEqual(made.useCount, 1, "Creating a happening is itself an addition")
        XCTAssertEqual(made.lastUsedAt, when)
        XCTAssertEqual(store.all.count, 11)
        XCTAssertEqual(store.happening(id: made.id)?.title, "Rooftop coffee")
    }

    func testCreateTrimsWhitespace() {
        let store = HappeningStore(defaults: defaults)
        store.load()
        let made = store.create(title: "  Sauna \n", at: .now)
        XCTAssertEqual(made.title, "Sauna")
    }

    /// Cutting 31 built-ins to 10 must not orphan a user's history: any id that
    /// appears in their past days but is no longer built-in comes back as a
    /// user happening so old canvases keep their labels.
    func testReconstitutesOrphanedHistoryIds() {
        let store = HappeningStore(defaults: defaults)
        store.load()

        store.reconstituteOrphans(
            fromHistoryIds: ["body_walking", "heart_joy", "happening_walk"],
            titleResolver: { id in id == "body_walking" ? "Walking" : "Joy" }
        )

        XCTAssertEqual(store.all.count, 12, "Two orphans added, happening_walk already present")
        let walking = store.happening(id: "body_walking")
        XCTAssertEqual(walking?.title, "Walking")
        XCTAssertEqual(walking?.isBuiltIn, false)
        XCTAssertEqual(walking?.useCount, 0, "Reconstituted orphans do not fake usage")
    }

    func testReconstituteIsIdempotent() {
        let store = HappeningStore(defaults: defaults)
        store.load()
        store.reconstituteOrphans(fromHistoryIds: ["body_walking"], titleResolver: { _ in "Walking" })
        store.recordUse(id: "body_walking", at: .now)
        store.reconstituteOrphans(fromHistoryIds: ["body_walking"], titleResolver: { _ in "Walking" })

        XCTAssertEqual(store.all.count, 11)
        XCTAssertEqual(store.happening(id: "body_walking")?.useCount, 1, "Must not reset a reconstituted happening")
    }

    func testLoadAddsNewBuiltInsToAnExistingCatalog() {
        let store = HappeningStore(defaults: defaults)
        store.load()
        store.recordUse(id: "happening_walk", at: .now)

        // Simulate a catalog saved by an older build that lacked one built-in.
        var trimmed = store.all.filter { $0.id != "happening_laughed" }
        trimmed[0].useCount = 7
        defaults.set(try! JSONEncoder().encode(trimmed), forKey: SharedKeys.happeningCatalog)

        let reloaded = HappeningStore(defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.all.count, 10)
        XCTAssertNotNil(reloaded.happening(id: "happening_laughed"))
        XCTAssertEqual(reloaded.all.first(where: { $0.id == trimmed[0].id })?.useCount, 7,
                       "Existing counts survive a built-in top-up")
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningStoreTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'HappeningStore' in scope`.

- [ ] **Step 4: Write `HappeningStore.swift`**

```swift
import Foundation

/// Owns the happening catalog: the ten built-ins plus everything the user has
/// created or carried over from the old 31-option set.
///
/// Persisted as one JSON blob in the App Group so the widget and extensions
/// can resolve labels. Not an ObservableObject — AppModel republishes it.
final class HappeningStore {

    private let defaults: UserDefaults
    private(set) var all: [Happening] = []

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
    }

    /// Loads the catalog, seeding built-ins on first run and topping up any
    /// built-in a previous build did not know about. Existing counts survive.
    func load() {
        let stored: [Happening]
        if let data = defaults.data(forKey: SharedKeys.happeningCatalog),
           let decoded = try? JSONDecoder().decode([Happening].self, from: data) {
            stored = decoded
        } else {
            stored = []
        }

        var byId = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for builtIn in HappeningDefaults.builtIns where byId[builtIn.id] == nil {
            byId[builtIn.id] = builtIn
        }
        all = Array(byId.values)
        persist()
    }

    func happening(id: String) -> Happening? {
        all.first { $0.id == id }
    }

    /// Creating a happening is itself an addition — the palette's `+` node
    /// spawns its canvas element in the same action, so it starts used.
    @discardableResult
    func create(title: String, at date: Date = .now) -> Happening {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let made = Happening(
            id: "user_\(UUID().uuidString)",
            title: trimmed,
            isBuiltIn: false,
            useCount: 1,
            lastUsedAt: date
        )
        all.append(made)
        persist()
        return made
    }

    func recordUse(id: String, at date: Date = .now) {
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            AppLogger.energy.error("recordUse for unknown happening: \(id, privacy: .public)")
            return
        }
        all[index].recordUse(at: date)
        persist()
    }

    /// Cutting 31 built-ins to 10 would otherwise orphan ids sitting in a
    /// user's saved days. Bring each one back as a user happening so past
    /// canvases keep their labels. Idempotent: never touches an id we already
    /// hold, so counts accumulated after the first pass survive.
    func reconstituteOrphans(
        fromHistoryIds historyIds: Set<String>,
        titleResolver: (String) -> String
    ) {
        let known = Set(all.map(\.id))
        let orphans = historyIds.subtracting(known)
        guard !orphans.isEmpty else { return }

        for id in orphans.sorted() {
            all.append(Happening(
                id: id,
                title: titleResolver(id),
                isBuiltIn: false,
                useCount: 0,
                lastUsedAt: nil
            ))
        }
        AppLogger.energy.info("Reconstituted \(orphans.count) orphaned happening ids")
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(all), forKey: SharedKeys.happeningCatalog)
        } catch {
            AppLogger.energy.error("Failed to persist happening catalog: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningStoreTests 2>&1 | tail -20
```

Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Stores/HappeningStore.swift StepsTrader/Utilities/SharedKeys.swift Steps4Tests/HappeningStoreTests.swift
git commit -m "feat: add HappeningStore with orphan reconstitution"
```

---

## Task 4: Palette ordering, frozen per day

**Files:**
- Create: `StepsTrader/Models/HappeningPaletteOrder.swift`
- Create: `Steps4Tests/HappeningPaletteOrderTests.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift`

**Interfaces:**
- Consumes: `Happening` (Task 2)
- Produces:
  - `SharedKeys.paletteOrderDayKey = "paletteOrderDayKey_v1"`, `SharedKeys.paletteOrderIds = "paletteOrderIds_v1"`
  - `enum HappeningPaletteOrder` with `static let visibleCount = 10`, `static func rank(_ happenings: [Happening]) -> [String]`
  - `final class HappeningPaletteOrderCache` with `init(defaults:)`, `func order(for dayKey: String, happenings: [Happening]) -> [String]`, `func append(id: String, dayKey: String)`

The cache is deliberately a plain class over `UserDefaults`, mirroring how `AppModel+DailyRandomTheme` stamps `SharedKeys.dailyRandomThemeLastRolledKey` with `AppModel.dayKey(for:)` and only re-rolls when it differs (`AppModel+DailyRandomTheme.swift:100-103`). Reuse that pattern; do not invent a second day-boundary mechanism.

- [ ] **Step 1: Add the two keys**

In `SharedKeys.swift`, next to `happeningCatalog`:

```swift
    static let paletteOrderDayKey = "paletteOrderDayKey_v1"
    static let paletteOrderIds = "paletteOrderIds_v1"
```

- [ ] **Step 2: Write the failing test**

Create `Steps4Tests/HappeningPaletteOrderTests.swift`:

```swift
import XCTest
@testable import Steps4

final class HappeningPaletteOrderTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PaletteOrderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func make(_ id: String, count: Int, lastUsed: TimeInterval?) -> Happening {
        Happening(
            id: id, title: id, isBuiltIn: true, useCount: count,
            lastUsedAt: lastUsed.map { Date(timeIntervalSince1970: $0) }
        )
    }

    // MARK: - Ranking

    func testRanksByUseCountDescending() {
        let ranked = HappeningPaletteOrder.rank([
            make("a", count: 1, lastUsed: nil),
            make("b", count: 9, lastUsed: nil),
            make("c", count: 5, lastUsed: nil)
        ])
        XCTAssertEqual(ranked, ["b", "c", "a"])
    }

    func testBreaksTiesByMoreRecentUse() {
        let ranked = HappeningPaletteOrder.rank([
            make("older", count: 3, lastUsed: 100),
            make("newer", count: 3, lastUsed: 900)
        ])
        XCTAssertEqual(ranked, ["newer", "older"])
    }

    func testNeverUsedSortsBelowUsedAtSameCount() {
        let ranked = HappeningPaletteOrder.rank([
            make("never", count: 0, lastUsed: nil),
            make("used", count: 0, lastUsed: 50)
        ])
        XCTAssertEqual(ranked, ["used", "never"])
    }

    func testRankIsTotalAndStableForFullTies() {
        let all = [make("b", count: 0, lastUsed: nil), make("a", count: 0, lastUsed: nil)]
        XCTAssertEqual(HappeningPaletteOrder.rank(all), HappeningPaletteOrder.rank(all))
        XCTAssertEqual(HappeningPaletteOrder.rank(all), ["a", "b"], "Ties fall back to id for determinism")
    }

    // MARK: - Day freeze

    private func catalog(_ n: Int) -> [Happening] {
        (0..<n).map { make("h\($0)", count: n - $0, lastUsed: TimeInterval($0)) }
    }

    func testTakesTopTen() {
        let cache = HappeningPaletteOrderCache(defaults: defaults)
        let order = cache.order(for: "2026-08-08", happenings: catalog(15))
        XCTAssertEqual(order.count, 10)
        XCTAssertEqual(order.first, "h0")
        XCTAssertFalse(order.contains("h10"))
    }

    func testOrderIsStableAcrossOpensWithinOneDay() {
        let cache = HappeningPaletteOrderCache(defaults: defaults)
        var happenings = catalog(12)
        let first = cache.order(for: "2026-08-08", happenings: happenings)

        // A tap happened: the bottom entry is now the most-used by a mile.
        happenings[9].useCount = 999
        happenings[9].lastUsedAt = Date()
        let second = cache.order(for: "2026-08-08", happenings: happenings)

        XCTAssertEqual(second, first, "Buttons must not move under the user's thumb mid-day")
    }

    func testOrderReRanksAfterDayKeyRollsOver() {
        let cache = HappeningPaletteOrderCache(defaults: defaults)
        var happenings = catalog(12)
        let first = cache.order(for: "2026-08-08", happenings: happenings)
        XCTAssertNotEqual(first.first, "h11")

        happenings[11].useCount = 999
        happenings[11].lastUsedAt = Date()
        let next = cache.order(for: "2026-08-09", happenings: happenings)

        XCTAssertEqual(next.first, "h11", "A new day re-ranks")
        XCTAssertEqual(next.count, 10)
    }

    func testFrozenOrderSurvivesANewCacheInstance() {
        let first = HappeningPaletteOrderCache(defaults: defaults)
            .order(for: "2026-08-08", happenings: catalog(12))
        let second = HappeningPaletteOrderCache(defaults: defaults)
            .order(for: "2026-08-08", happenings: catalog(12))
        XCTAssertEqual(second, first)
    }

    // MARK: - Mid-day creation

    func testMidDayCreationAppendsWithoutReordering() {
        let cache = HappeningPaletteOrderCache(defaults: defaults)
        var happenings = catalog(12)
        let before = cache.order(for: "2026-08-08", happenings: happenings)

        let made = Happening(id: "user_new", title: "Sauna", isBuiltIn: false, useCount: 1, lastUsedAt: Date())
        happenings.append(made)
        cache.append(id: made.id, dayKey: "2026-08-08")
        let after = cache.order(for: "2026-08-08", happenings: happenings)

        XCTAssertEqual(after.count, 11, "The palette holds eleven on the day of creation")
        XCTAssertEqual(Array(after.prefix(10)), before, "Nothing already on screen moves")
        XCTAssertEqual(after.last, "user_new")
    }

    func testCreatedHappeningTakesItsRankedPositionNextDay() {
        let cache = HappeningPaletteOrderCache(defaults: defaults)
        var happenings = catalog(12)
        _ = cache.order(for: "2026-08-08", happenings: happenings)

        let made = Happening(id: "user_new", title: "Sauna", isBuiltIn: false, useCount: 99, lastUsedAt: Date())
        happenings.append(made)
        cache.append(id: made.id, dayKey: "2026-08-08")

        let nextDay = cache.order(for: "2026-08-09", happenings: happenings)
        XCTAssertEqual(nextDay.count, 10, "Back to ten the next day")
        XCTAssertEqual(nextDay.first, "user_new", "And it takes its ranked position")
    }

    func testDeletedHappeningDropsOutOfAFrozenOrder() {
        let cache = HappeningPaletteOrderCache(defaults: defaults)
        let happenings = catalog(12)
        _ = cache.order(for: "2026-08-08", happenings: happenings)

        let survivors = happenings.filter { $0.id != "h3" }
        let order = cache.order(for: "2026-08-08", happenings: survivors)
        XCTAssertFalse(order.contains("h3"), "A frozen id that no longer exists must not be returned")
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningPaletteOrderTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'HappeningPaletteOrder' in scope`.

- [ ] **Step 4: Write `HappeningPaletteOrder.swift`**

```swift
import Foundation

/// Ranking rule for the palette. Pure — no storage, no clock, no UI.
enum HappeningPaletteOrder {

    /// How many happenings the palette shows on a settled day.
    static let visibleCount = 10

    /// Score is `useCount`, ties broken by more recent `lastUsedAt`, then by id
    /// so the order is total and two calls on identical input always agree.
    /// Built-in and user happenings rank together with no distinction.
    static func rank(_ happenings: [Happening]) -> [String] {
        happenings.sorted { lhs, rhs in
            if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
            let l = lhs.lastUsedAt?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
            let r = rhs.lastUsedAt?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
            if l != r { return l > r }
            return lhs.id < rhs.id
        }.map(\.id)
    }
}

/// Freezes the palette order for the duration of one custom day.
///
/// Re-sorting after every tap moves buttons under the user's thumb and stops
/// muscle memory from forming, so the order is computed once per `dayKey` and
/// cached. Same shape as the daily-random-theme guard in
/// `AppModel+DailyRandomTheme` — stamp the day key, recompute only when it
/// changes. Callers pass a `dayKey` from `AppModel.dayKey(for:)`, which
/// respects the user's configured `dayEndHour`/`dayEndMinute`.
final class HappeningPaletteOrderCache {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
    }

    /// The frozen order for `dayKey`, recomputing only on rollover.
    /// Ids that no longer exist in `happenings` are dropped — a deleted
    /// happening must not linger in a frozen order.
    func order(for dayKey: String, happenings: [Happening]) -> [String] {
        let live = Set(happenings.map(\.id))

        if defaults.string(forKey: SharedKeys.paletteOrderDayKey) == dayKey,
           let cached = defaults.stringArray(forKey: SharedKeys.paletteOrderIds) {
            return cached.filter(live.contains)
        }

        let fresh = Array(HappeningPaletteOrder.rank(happenings)
            .prefix(HappeningPaletteOrder.visibleCount))
        defaults.set(dayKey, forKey: SharedKeys.paletteOrderDayKey)
        defaults.set(fresh, forKey: SharedKeys.paletteOrderIds)
        return fresh
    }

    /// Appends a happening created mid-day to the end of the frozen order, so
    /// it shows in addition to the ten and nothing already on screen moves.
    /// It takes its ranked position on the next rollover.
    func append(id: String, dayKey: String) {
        guard defaults.string(forKey: SharedKeys.paletteOrderDayKey) == dayKey else { return }
        var current = defaults.stringArray(forKey: SharedKeys.paletteOrderIds) ?? []
        guard !current.contains(id) else { return }
        current.append(id)
        defaults.set(current, forKey: SharedKeys.paletteOrderIds)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningPaletteOrderTests 2>&1 | tail -20
```

Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Models/HappeningPaletteOrder.swift StepsTrader/Utilities/SharedKeys.swift Steps4Tests/HappeningPaletteOrderTests.swift
git commit -m "feat: rank palette by use and freeze the order per day"
```

---

## Task 5: Replace selections with an append-only additions log

This is the load-bearing task — see **F1**. Everything downstream assumes it. Expect it to touch ~100 call sites and to be the one that takes longest.

**Files:**
- Modify: `StepsTrader/AppModel.swift:179` and the two neighbouring `@Published` selection arrays
- Modify: `StepsTrader/AppModel+DailyEnergy.swift` (the bulk of the file)
- Modify: `StepsTrader/Models/EnergyDefaults.swift`
- Create: `Steps4Tests/HappeningEconomyTests.swift`
- Modify: `Steps4Tests/DailyEnergyLogicTests.swift`, `Steps4Tests/EnergyRecalcTests.swift`

**Interfaces:**
- Consumes: `Happening`, `HappeningDefaults`, `OptionEntry` (Task 2); `HappeningStore` (Task 3); `HappeningPaletteOrderCache` (Task 4)
- Produces on `AppModel`:
  - `@Published var todayAdditions: [OptionEntry]` — append-only, replaces `dailyBodySelections` / `dailyRestSelections` / `dailyHeartSelections`
  - `var happeningPointsToday: Int` — replaces `bodyPointsToday` / `mindPointsToday` / `heartPointsToday`
  - `@discardableResult func addHappening(id: String, colorHex: String, at: Date) -> OptionEntry`
  - `func removeAddition(entryId: String)`
  - `var happeningStore: HappeningStore`
  - `func paletteOrder() -> [String]`

- [ ] **Step 1: Write the failing economy test**

Create `Steps4Tests/HappeningEconomyTests.swift`. This is a pure-formula test in the shape `DailyEnergyLogicTests` already uses (it mirrors the private `AppModel` logic rather than instantiating the model):

```swift
import XCTest
@testable import Steps4

/// The new scoring model (3 entities, still 100 max):
///   steps      = 20 × min(made_steps, target_steps) / target_steps
///   sleep      = 20 × min(today_sleep, target_sleep) / target_sleep
///   happenings = min(additions × 10, 60)
final class HappeningEconomyTests: XCTestCase {

    private func pointsFromAdditions(_ count: Int) -> Int {
        min(count * HappeningDefaults.pointsPerAddition, HappeningDefaults.happeningsMaxPoints)
    }

    func testConstants() {
        XCTAssertEqual(HappeningDefaults.pointsPerAddition, 10)
        XCTAssertEqual(HappeningDefaults.happeningsMaxPoints, 60)
        XCTAssertEqual(EnergyDefaults.maxBaseEnergy, 100)
    }

    func testThreePartFormulaStillTotalsOneHundred() {
        XCTAssertEqual(
            EnergyDefaults.stepsMaxPoints
            + EnergyDefaults.sleepMaxPoints
            + HappeningDefaults.happeningsMaxPoints,
            EnergyDefaults.maxBaseEnergy
        )
    }

    func testHappeningPointsScaleTenPerAddition() {
        XCTAssertEqual(pointsFromAdditions(0), 0)
        XCTAssertEqual(pointsFromAdditions(1), 10)
        XCTAssertEqual(pointsFromAdditions(3), 30)
        XCTAssertEqual(pointsFromAdditions(6), 60)
    }

    func testHappeningPointsCapAtSixty() {
        XCTAssertEqual(pointsFromAdditions(7), 60)
        XCTAssertEqual(pointsFromAdditions(20), 60, "Additions past the sixth stop earning")
        XCTAssertEqual(pointsFromAdditions(1000), 60)
    }

    /// Acceptance criterion: 2 happenings + full steps + full sleep = 60, not 100.
    func testTwoHappeningsWithFullStepsAndSleepTotalsSixty() {
        let total = EnergyDefaults.stepsMaxPoints
            + EnergyDefaults.sleepMaxPoints
            + pointsFromAdditions(2)
        XCTAssertEqual(total, 60)
    }

    func testSixHappeningsWithFullStepsAndSleepTotalsOneHundred() {
        let total = EnergyDefaults.stepsMaxPoints
            + EnergyDefaults.sleepMaxPoints
            + pointsFromAdditions(6)
        XCTAssertEqual(total, 100)
    }

    /// Repeat additions of the same happening count separately — the economy
    /// counts additions, not distinct happenings.
    func testRepeatAdditionsOfOneHappeningStillCount() {
        let sameHappeningTwice = 2
        XCTAssertEqual(pointsFromAdditions(sameHappeningTwice), 20)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningEconomyTests 2>&1 | tail -20
```

Expected: compile failure — `HappeningDefaults` has no member `pointsPerAddition` if Task 2 was skipped; otherwise it fails on `testThreePartFormulaStillTotalsOneHundred` only once `EnergyDefaults` is trimmed. If all seven pass immediately, Task 2 already added the constants — that is fine, proceed.

- [ ] **Step 3: Trim `EnergyDefaults`**

In `StepsTrader/Models/EnergyDefaults.swift`, delete `maxSelectionsPerCategory` (line 5), `selectionPoints` (line 13), `coreOptionIdsOrdered` (15-19), `coreOptionIds` (21), `coreOptions` (23-26), the whole `options` array (28-62), `description(for:)`, `examples(for:)`, `optionDescriptions` (64-110), and the entire `CustomActivityIcons` enum (137-168, its only API takes an `EnergyCategory`).

Keep `maxBaseEnergy`, `sleepTargetHours`, `sleepMaxPoints`, `assumedSleepPoints`, `stepsTarget`, `stepsMaxPoints`, and the whole `DayEndOptions` enum (113-135) untouched.

Then delete the now-duplicated four constants from `HappeningDefaults` (`sleepTargetHours`, `sleepMaxPoints`, `stepsTarget`, `stepsMaxPoints`) so each lives in exactly one place — `HappeningDefaults` keeps only `pointsPerAddition`, `happeningsMaxPoints`, `builtIns`, `builtInIds`.

`EnergyDefaults` keeps its name: it is referenced from the widget and extensions, and renaming it is churn this spec does not need.

- [ ] **Step 4: Replace the three published arrays on `AppModel`**

In `StepsTrader/AppModel.swift`, replace the three `@Published var daily*Selections: [String] = []` declarations (around line 179) with:

```swift
    /// Every happening added today, in the order they were added. Append-only:
    /// the same happening added twice produces two entries, because the economy
    /// counts additions. Replaces the three capped per-category selection arrays.
    @Published var todayAdditions: [OptionEntry] = []

    /// The happening catalog. Loaded once at launch by `loadDailyEnergyState`.
    let happeningStore = HappeningStore()

    /// Freezes the palette order for the duration of one custom day.
    let paletteOrderCache = HappeningPaletteOrderCache()
```

- [ ] **Step 5: Rewrite the energy surface in `AppModel+DailyEnergy.swift`**

Replace `bodyPointsToday` / `mindPointsToday` / `heartPointsToday` (lines 859-869) and `pointsFromSelections` (928-930) with:

```swift
    /// happenings = min(additions × 10, 60). Additions past the sixth still
    /// land on the canvas and still increment useCount — they just stop earning.
    var happeningPointsToday: Int {
        min(
            todayAdditions.count * HappeningDefaults.pointsPerAddition,
            HappeningDefaults.happeningsMaxPoints
        )
    }
```

In `recalculateDailyEnergy` (932-997) update the total and the two log lines:

```swift
        // Total = steps(20) + sleep(20) + happenings(60) = 100 max
        let total = stepsPts + sleepPts + happeningPointsToday
```

```swift
        AppLogger.energy.debug("⚡️ recalculateDailyEnergy: steps=\(stepsPts) + sleep=\(sleepPts)\(self.isSleepAssumed ? " (assumed)" : "") + happenings=\(self.happeningPointsToday) (\(self.todayAdditions.count) additions) = \(total)")
```

Replace `toggleDailySelection(optionId:category:)` (679-708) and `applySelections(body:mind:heart:)` (1065-1072) with append/remove:

```swift
    /// Adds one happening to today. Always appends — repeat additions of the
    /// same happening are the point, so there is no dedupe and no cap.
    @discardableResult
    func addHappening(id: String, colorHex: String, at date: Date = .now) -> OptionEntry {
        let entry = OptionEntry(
            id: UUID().uuidString,
            dayKey: Self.dayKey(for: date),
            optionId: id,
            colorHex: colorHex,
            timestamp: date,
            assetVariant: nil
        )
        todayAdditions.append(entry)
        happeningStore.recordUse(id: id, at: date)
        recalculateDailyEnergy()
        persistDailyEnergyState()
        Task { await SupabaseSyncService.shared.syncOptionEntry(entry) }
        return entry
    }

    /// Removes one addition by its entry id. Undo of a single tap — the
    /// happening's `useCount` is history and is deliberately not decremented.
    func removeAddition(entryId: String) {
        guard let index = todayAdditions.firstIndex(where: { $0.id == entryId }) else { return }
        todayAdditions.remove(at: index)
        recalculateDailyEnergy()
        persistDailyEnergyState()
    }

    /// The frozen palette order for today, resolved to happenings.
    func paletteOrder() -> [Happening] {
        let ids = paletteOrderCache.order(
            for: Self.dayKey(for: .now),
            happenings: happeningStore.all
        )
        return ids.compactMap { happeningStore.happening(id: $0) }
    }
```

Then work outward from the compiler. Delete every per-category helper in this file: `dailySelectionsKey(for:)`, `preferredOptionsKey(for:)`, `loadCustomEnergyOptions`, `saveCustomEnergyOptions`, `addCustomOption(category:titleEn:icon:)`, `customOptions(for:)`, `loadPreferredOptions(for:)`, `optionsOrderKey(for:)`, `hiddenOptionsKey(for:)`, `preferredOptionsIds(for:)`, `allOptions(for:)`, `hiddenOptionIds(for:)`, `hiddenOptions(for:)`, `orderedOptions(for:)`, `updateOptionsOrder(_:category:)`, `appendOptionToOrder(id:category:)`, `removeOptionFromOrder(id:category:)`, `preferredOptions(for:)`, `updatePreferredOptions(_:category:)`, `togglePreferredOption(optionId:category:)`, `isPreferredOptionSelected(_:category:)`, `isDailySelected(_:category:)`, `loadSavedMoments(from:)`, `addMoment(label:icon:category:)`, `dailySelectionsCount(for:)`, `isDailyLimitReached(for:)`, `dailySelections(for:)`, `setDailySelections(_:category:)`, `optionExists(_:category:)`, and `setDailyCanvasSlot(at:category:optionId:)`.

Persistence: `persistDailyEnergyState` and `loadDailyEnergyState` currently read and write three keyed arrays. Replace with a single `SharedKeys.todayAdditions = "todayAdditions_v1"` holding JSON-encoded `[OptionEntry]`. Add the key to `SharedKeys.swift`. On load, drop entries whose `dayKey` is not today — the day-rollover reset already exists in `resetDailyEnergyState` (441-446) and should now just clear `todayAdditions`.

Call `happeningStore.load()` at the top of `loadDailyEnergyState`, then reconstitute orphans from saved history:

```swift
        happeningStore.load()
        let historyIds = Set(CanvasStorageService.shared.allSavedOptionIds())
        happeningStore.reconstituteOrphans(fromHistoryIds: historyIds) { id in
            // Old built-ins keep their catalog copy; anything else falls back to the id.
            Bundle.main.localizedString(forKey: "option.title.\(id)", value: id, table: nil)
        }
```

Add `func allSavedOptionIds() -> [String]` to `CanvasStorageService` — it enumerates `canvas_*.json` in `storageDirectory` and collects `elements[].optionId`. Run it once per launch, off the main actor.

`saveCurrentAsRoutine(name:)` (1101-1111) and `applyRoutine(_:)` (1114-1124) collapse to the flat list:

```swift
    func saveCurrentAsRoutine(name: String) {
        let routine = EnergyRoutine(
            name: name,
            happeningIds: todayAdditions.map(\.optionId),
            lastUsed: Date.now
        )
        savedRoutines.append(routine)
        persistSavedRoutines()
    }

    func applyRoutine(_ routine: EnergyRoutine) {
        let known = Set(happeningStore.all.map(\.id))
        for id in routine.happeningIds where known.contains(id) {
            addHappening(
                id: id,
                colorHex: CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex
            )
        }
        if let idx = savedRoutines.firstIndex(where: { $0.id == routine.id }) {
            savedRoutines[idx].lastUsed = Date.now
            persistSavedRoutines()
        }
    }
```

`writeWidgetSnapshot` (1042-1054) — see **F2**. `WidgetSnapshot` has `bodyPoints`/`mindPoints`/`heartPoints`. Add `happeningPoints: Int` to `Models/WidgetSnapshot.swift`, keep the three old fields decoding (an already-installed widget binary reads them), and write `happeningPoints: happeningPointsToday` with the three old fields set to `0`. The widget UI is out of scope; only make it compile and show the new number where it showed the three.

- [ ] **Step 6: Rewrite the two existing energy test files**

`Steps4Tests/DailyEnergyLogicTests.swift`: the header comment (lines 5-12) and `testEnergyDefaultsSelectionPoints` and `testPointsFromSelectionsFormula` all assert the five-part model. Delete the two selection tests and the local `pointsFromSelections` helper, and rewrite the header comment to the three-part model. Keep the sleep and steps formula tests exactly as they are — that arithmetic is unchanged.

`Steps4Tests/EnergyRecalcTests.swift`: same treatment. Read it and replace every `body`/`mind`/`heart` points assertion with the `happeningPointsToday` equivalent.

- [ ] **Step 7: Build and run the full suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -40
```

Expected: the app target will still fail to compile — `GalleryView`, `CategoryDetailView`, `MeView` and friends have not been touched yet. That is expected at this step. What must hold: no error originates in `AppModel.swift`, `AppModel+DailyEnergy.swift`, `EnergyDefaults.swift`, or any `Happening*` file. Work until that is true, then move on; Tasks 6-12 clear the rest.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: replace per-category selections with an append-only additions log"
```

---

## Task 6: Decategorise `CanvasElement` and land the migration

**Files:**
- Create: `StepsTrader/Models/LegacyCategory.swift`
- Modify: `StepsTrader/Models/CanvasElement.swift`
- Modify: `StepsTrader/Models/ShapeStyles.swift`
- Modify: `StepsTrader/Models/PastDaySnapshot.swift`

**Interfaces:**
- Consumes: `CanvasShapeType.allowedByUser` (Task 7 — declare it there first if you are running tasks out of order)
- Produces:
  - `enum LegacyCategory: String, Decodable` — `body`, `mind`, `heart`, decode-only, with the five legacy aliases
  - `CanvasShapeType.legacyDefault(for: LegacyCategory) -> CanvasShapeType`
  - `CanvasElement.spawn(optionId:color:color2:label:existingElements:forcedVariant:dayKey:activityCount:)` — no `category` parameter
  - `CanvasElement` with no `category` property

**The regression test from Task 1 must stay green through this task.** It is the whole point.

- [ ] **Step 1: Write `LegacyCategory.swift`**

```swift
import Foundation

/// Decode-only. Exists solely so `CanvasElement.init(from:)` can resolve the
/// shape of elements saved before `frozenShapeType` existed — those resolved
/// their shape *through* the category, so dropping it outright would silently
/// redraw historical canvases.
///
/// It is not part of the domain model, is never stored on a struct, and is
/// never written back on encode. Do not import it anywhere else.
enum LegacyCategory: String, Decodable {
    case body, mind, heart

    /// Mirrors the alias map the deleted `EnergyCategory.init(from:)` carried.
    /// Beta devices have canvases containing all five of these raw values, so
    /// omitting any one of them fails the whole decode, not just the shape.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "body", "activity":
            self = .body
        case "mind", "creativity", "recovery", "rest":
            self = .mind
        case "heart", "joys":
            self = .heart
        default:
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown LegacyCategory: \(raw)"
            )
        }
    }
}
```

- [ ] **Step 2: Move the legacy shape mapping into `ShapeStyles.swift`**

Replace `defaultShape(for:)` (43-49) and `resolved(for:)` (53-65) with:

```swift
    /// The shape each category resolved to before shapes became user-configured.
    /// Migration path only — reproduces the exact mapping `defaultShape(for:)`
    /// had, so legacy canvases keep rendering as they did.
    static func legacyDefault(for category: LegacyCategory) -> CanvasShapeType {
        switch category {
        case .body:  .circle
        case .mind:  .snowflake
        case .heart: .rays
        }
    }
```

`allowedByUser` arrives in Task 7. If you are doing Task 6 first, add a temporary `static var allowedByUser: [CanvasShapeType] { selectableCases }` so the project compiles, and let Task 7 replace it.

- [ ] **Step 3: Decategorise `CanvasElement`**

In `Models/CanvasElement.swift`:

Delete the `let category: EnergyCategory` property (line 16) and its `init` parameter and assignment (86, 89).

`resolvedShapeType` (81-84) loses its category fallback. An element with no frozen shape and no category is either brand new (always frozen at spawn) or corrupt, so `.circle` is the right floor:

```swift
    var resolvedShapeType: CanvasShapeType {
        let shape = frozenShapeType ?? .circle
        return shape == .blob ? .circle : shape
    }
```

`reroll` (151-181) line 156 becomes:

```swift
        let resolvedShape = CanvasShapeType.allowedByUser.randomElement() ?? .circle
```

`spawn` (183-246) loses the `category` parameter, and line 194 becomes:

```swift
        let shapeType = CanvasShapeType.allowedByUser.randomElement() ?? .circle
```

Nothing else in `spawn` changes — `kind`, `size`, `isGrounded`, `pulseFreq` and `opacity` already derive from `shapeType` (196-218). Delete `category: category` from the returned initializer (line 227).

Remove `category` from `CodingKeys` (line 249) — **no**: keep the case, because `init(from:)` still needs it to read old files. Instead leave `case category` in the enum and simply stop encoding it. Add a comment saying so, or a future reader will delete it.

`init(from:)` line 260 and 283-284 become:

```swift
        // Decode-only. Used solely for the frozenShapeType fallback below and
        // then discarded — it is not stored on the struct, and `encode` never
        // writes it back. See LegacyCategory.
        let legacyCategory = try c.decodeIfPresent(LegacyCategory.self, forKey: .category)
```

```swift
        frozenShapeType = try c.decodeIfPresent(CanvasShapeType.self, forKey: .frozenShapeType)
            ?? legacyCategory.map(CanvasShapeType.legacyDefault(for:))
            ?? .circle
```

`encode(to:)` line 299 — delete `try c.encode(category, forKey: .category)`.

- [ ] **Step 4: Decategorise `PastDaySnapshot`** (see **F2**)

`bodyIds` / `mindIds` / `heartIds` collapse to `happeningIds: [String]`, and `moments` goes with `EphemeralMoment`. The legacy decode path (80-110) must keep working — old snapshots concatenate into the flat list in body → mind → heart order:

```swift
struct PastDaySnapshot: Codable, Equatable {
    var inkEarned: Int
    var inkSpent: Int
    var happeningIds: [String]
    var steps: Int
    var sleepHours: Double
    var stepsTarget: Double
    var sleepTargetHours: Double

    enum CodingKeys: String, CodingKey {
        case inkEarned, inkSpent, experienceEarned, experienceSpent
        case happeningIds
        case bodyIds, mindIds, heartIds
        case steps, sleepHours, stepsTarget, sleepTargetHours
        case controlGained, controlSpent
        case activityIds, creativityIds, recoveryIds, restIds, joysIds
        case moments
    }
    …
}
```

In `init(from:)`, replace the three `if let v = try container.decodeIfPresent…` blocks (80-110) with one that prefers the flat key and falls back through both legacy generations:

```swift
        if let flat = try container.decodeIfPresent([String].self, forKey: .happeningIds) {
            happeningIds = flat
        } else {
            let body = (try container.decodeIfPresent([String].self, forKey: .bodyIds))
                ?? (try container.decodeIfPresent([String].self, forKey: .activityIds)) ?? []
            var mind = (try container.decodeIfPresent([String].self, forKey: .mindIds)) ?? []
            if mind.isEmpty {
                mind = ((try container.decodeIfPresent([String].self, forKey: .creativityIds)) ?? [])
                    + ((try container.decodeIfPresent([String].self, forKey: .recoveryIds)) ?? [])
                    + ((try container.decodeIfPresent([String].self, forKey: .restIds)) ?? [])
            }
            let heart = (try container.decodeIfPresent([String].self, forKey: .heartIds))
                ?? (try container.decodeIfPresent([String].self, forKey: .joysIds)) ?? []
            happeningIds = body + mind + heart
        }
```

`encode(to:)` (118-130) writes only `happeningIds` — the legacy keys are read-only from here on. Drop the `moments` encode.

Delete `DayCanvasSlot` (133-136) entirely; it is `{ category, optionId }` and the slot mechanism dies with the selections (Task 5 deleted `setDailyCanvasSlot`).

- [ ] **Step 5: Run the migration guard**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningMigrationTests 2>&1 | tail -20
```

Expected: **PASS**, both tests, unchanged from Task 1. If `testLegacyCanvasDecodesToUnchangedFrozenShapeTypes` fails here, the `legacyDefault` mapping is wrong. If `testLegacyCategoryAliasesStillDecode` fails, an alias is missing from `LegacyCategory`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: decategorise CanvasElement behind a decode-only LegacyCategory"
```

---

## Task 7: User-configured shape set

**Files:**
- Modify: `StepsTrader/Models/ShapeStyles.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift:9-11`
- Modify: `StepsTrader/Stores/PreferencesStore.swift:43-45,87-89`
- Create: `Steps4Tests/AllowedCanvasShapesTests.swift`
- Modify: `Steps4Tests/PreferencesStoreTests.swift:55-57,88-90,106`

**Interfaces:**
- Consumes: `CanvasShapeType` (existing)
- Produces:
  - `SharedKeys.allowedCanvasShapes = "allowedCanvasShapes_v1"` (a `[String]` in `UserDefaults.standard`, matching where the three old keys lived)
  - `CanvasShapeType.allowedByUser: [CanvasShapeType]` — reads the key, seeds from the three legacy keys on first read, filters `organicBlob` when not Pro, never returns empty
  - `CanvasShapeType.setAllowed(_ shapes: Set<CanvasShapeType>) -> Bool` — returns `false` and writes nothing when asked to empty the set

- [ ] **Step 1: Write the failing test**

Create `Steps4Tests/AllowedCanvasShapesTests.swift`:

```swift
import XCTest
@testable import Steps4

final class AllowedCanvasShapesTests: XCTestCase {

    private let keys = [
        SharedKeys.allowedCanvasShapes,
        SharedKeys.bodyCanvasShape,
        SharedKeys.mindCanvasShape,
        SharedKeys.heartCanvasShape
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        CanvasShapeType.isProProvider = { true }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        CanvasShapeType.isProProvider = { false }
        super.tearDown()
    }

    func testSeedsFromTheUnionOfTheThreeLegacyKeys() {
        UserDefaults.standard.set(CanvasShapeType.circle.rawValue, forKey: SharedKeys.bodyCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.snowflake.rawValue, forKey: SharedKeys.mindCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.snowflake.rawValue, forKey: SharedKeys.heartCanvasShape)

        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.circle, .snowflake],
                       "Union of the three, deduplicated")
    }

    func testSeedMigratesLegacyBlobToCircle() {
        UserDefaults.standard.set(CanvasShapeType.blob.rawValue, forKey: SharedKeys.bodyCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.spirograph.rawValue, forKey: SharedKeys.mindCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.rays.rawValue, forKey: SharedKeys.heartCanvasShape)

        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.circle, .rays])
    }

    func testFallsBackToAllSelectableWhenNothingIsSaved() {
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), Set(CanvasShapeType.selectableCases))
    }

    func testSetAllowedRoundTrips() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.rays, .circle]))
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.rays, .circle])
    }

    func testCannotEmptyTheSet() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.rays]))
        XCTAssertFalse(CanvasShapeType.setAllowed([]), "Emptying must be rejected")
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.rays], "And must not have written")
    }

    func testNeverReturnsEmptyEvenIfStorageIsCorrupt() {
        UserDefaults.standard.set(["not-a-shape"], forKey: SharedKeys.allowedCanvasShapes)
        XCTAssertFalse(CanvasShapeType.allowedByUser.isEmpty)
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), Set(CanvasShapeType.selectableCases))
    }

    // MARK: - Pro gating

    func testNonProNeverSpawnsOrganicButKeepsThePreference() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.organicBlob, .circle]))
        CanvasShapeType.isProProvider = { false }

        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.circle],
                       "Organic is filtered at spawn time")
        XCTAssertEqual(
            Set(UserDefaults.standard.stringArray(forKey: SharedKeys.allowedCanvasShapes) ?? []),
            [CanvasShapeType.organicBlob.rawValue, CanvasShapeType.circle.rawValue],
            "But the saved preference survives"
        )

        CanvasShapeType.isProProvider = { true }
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.organicBlob, .circle],
                       "And reactivates on resubscribe")
    }

    func testNonProWithOnlyOrganicSavedStillGetsAShape() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.organicBlob]))
        CanvasShapeType.isProProvider = { false }
        XCTAssertFalse(CanvasShapeType.allowedByUser.isEmpty)
        XCTAssertFalse(CanvasShapeType.allowedByUser.contains(.organicBlob))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/AllowedCanvasShapesTests 2>&1 | tail -20
```

Expected: compile failure — `type 'CanvasShapeType' has no member 'allowedByUser'`.

- [ ] **Step 3: Add the key**

In `SharedKeys.swift`, replacing lines 104-106 — keep the three old keys, they are the migration source and are still read by `PreferencesStore` during rollout:

```swift
    static let bodyCanvasShape = "bodyCanvasShape_v1"   // legacy — read only, migration source
    static let mindCanvasShape = "mindCanvasShape_v1"   // legacy — read only, migration source
    static let heartCanvasShape = "heartCanvasShape_v1" // legacy — read only, migration source
    static let allowedCanvasShapes = "allowedCanvasShapes_v1"
```

- [ ] **Step 4: Implement in `ShapeStyles.swift`**

```swift
    /// Injected so tests can drive the gate without a StoreKit session.
    /// Production wires this to the subscription store at launch.
    nonisolated(unsafe) static var isProProvider: () -> Bool = { false }

    /// The shapes a new element may take. Seeds itself from the three legacy
    /// per-category keys on first read so current preferences carry over.
    ///
    /// Organic stays Pro. It is filtered here, at spawn time, rather than being
    /// removed from storage — so a lapsed subscriber's saved preference survives
    /// and reactivates on resubscribe. Never returns empty.
    static var allowedByUser: [CanvasShapeType] {
        let defaults = UserDefaults.standard
        let stored: [CanvasShapeType]
        if let raw = defaults.stringArray(forKey: allowedCanvasShapesKey) {
            stored = raw.compactMap(CanvasShapeType.init(rawValue:)).map(migrateLegacy)
        } else {
            stored = seedFromLegacyKeys()
        }

        var usable = Array(Set(stored)).filter { selectableCases.contains($0) }
        if !isProProvider() { usable.removeAll { $0 == .organicBlob } }
        return usable.isEmpty ? selectableCases : usable.sorted {
            (selectableCases.firstIndex(of: $0) ?? 0) < (selectableCases.firstIndex(of: $1) ?? 0)
        }
    }

    /// Writes the user's selection. Rejects an empty set — the UI blocks
    /// deselecting the last shape, and this is the backstop for that rule.
    @discardableResult
    static func setAllowed(_ shapes: Set<CanvasShapeType>) -> Bool {
        let valid = shapes.filter { selectableCases.contains($0) }
        guard !valid.isEmpty else { return false }
        UserDefaults.standard.set(valid.map(\.rawValue), forKey: allowedCanvasShapesKey)
        return true
    }

    private static var allowedCanvasShapesKey: String { SharedKeys.allowedCanvasShapes }

    /// Union of the three legacy keys, so a user's current shapes carry over.
    private static func seedFromLegacyKeys() -> [CanvasShapeType] {
        let defaults = UserDefaults.standard
        let legacy = [SharedKeys.bodyCanvasShape, SharedKeys.mindCanvasShape, SharedKeys.heartCanvasShape]
            .compactMap { defaults.string(forKey: $0) }
            .compactMap(CanvasShapeType.init(rawValue:))
            .map(migrateLegacy)
        guard !legacy.isEmpty else { return selectableCases }
        let seeded = Array(Set(legacy))
        defaults.set(seeded.map(\.rawValue), forKey: allowedCanvasShapesKey)
        return seeded
    }

    /// Hidden legacy shapes collapse to circle, as `resolved(for:)` used to.
    private static func migrateLegacy(_ shape: CanvasShapeType) -> CanvasShapeType {
        (shape == .blob || shape == .spirograph) ? .circle : shape
    }
```

Wire `isProProvider` where the subscription store is constructed (search for `isPro` on `AppModel`) so production reflects the real entitlement:

```swift
        CanvasShapeType.isProProvider = { [weak self] in self?.isPro ?? false }
```

- [ ] **Step 5: Rewrite the settings UI**

`Views/Settings/SettingsAppearancePage.swift` lines 9-11 currently hold three `@AppStorage` strings and render three single-select pickers. Replace with one multi-select over `CanvasShapeType.selectableCases`. The rule the test encodes must also hold in the UI: **the last selected shape is not deselectable.** Disable its control rather than letting the tap fail silently:

```swift
    @AppStorage(SharedKeys.allowedCanvasShapes) private var allowedRaw: [String] = []

    private var allowed: Set<CanvasShapeType> {
        Set(allowedRaw.compactMap(CanvasShapeType.init(rawValue:)))
    }

    private func toggle(_ shape: CanvasShapeType) {
        var next = allowed
        if next.contains(shape) { next.remove(shape) } else { next.insert(shape) }
        guard CanvasShapeType.setAllowed(next) else { return }
        allowedRaw = next.map(\.rawValue)
    }

    private func isLastSelected(_ shape: CanvasShapeType) -> Bool {
        allowed == [shape]
    }
```

Render each of `CanvasShapeType.selectableCases` as a toggleable chip using the existing `CanvasShapePreview` component (`Views/Components/CanvasShapePreview.swift`), with `.disabled(isLastSelected(shape))`. Organic stays in the list for non-Pro users — do not hide it — and keeps whatever Pro badge the current picker shows.

- [ ] **Step 6: Update `PreferencesStore`**

`Stores/PreferencesStore.swift:43-45` has three `var *CanvasShape: String` fields and 87-89 write them. Add `var allowedCanvasShapes: [String]` and write it to `SharedKeys.allowedCanvasShapes`. Keep the three legacy fields writing to their legacy keys during rollout — an older build on the same App Group still reads them, and the Supabase columns are still `NOT NULL` until the migration in Task 11 lands.

Update `Steps4Tests/PreferencesStoreTests.swift` lines 55-57, 88-90 and 106 to cover the new field alongside the three legacy ones.

- [ ] **Step 7: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/AllowedCanvasShapesTests -only-testing:Steps4Tests/PreferencesStoreTests 2>&1 | tail -30
```

Expected: PASS, 8 + existing tests.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: replace three per-category shape keys with one allowed set"
```

---

## Task 8: The palette

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningBlobLayout.swift`
- Create: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Create: `StepsTrader/Views/Palette/HappeningFreeTextField.swift`
- Create: `Steps4Tests/HappeningBlobLayoutTests.swift`

**Interfaces:**
- Consumes: `Happening` (Task 2), `HappeningStore` (Task 3), `AppModel.paletteOrder()` and `addHappening(id:colorHex:at:)` (Task 5), `ProceduralShapeGenerator.metaballPath`/`organicBlobPath` (**F7**), `CanvasColorPalette.paletteHex`
- Produces:
  - `struct HappeningBlobLayout` with `static func blobs(count: Int, in size: CGSize) -> [Blob]` where `Blob` has `center: CGPoint`, `radius: CGFloat`, `index: Int`
  - `struct HappeningPaletteView: View` with `init(model: AppModel, onPick: @escaping (Happening) -> Void, onCreate: @escaping (String) -> Void)`

Style it well enough to ship. It gets restyled onto the token system in spec A; do not build a token system here.

- [ ] **Step 1: Write the failing layout test**

Layout is the only part of a view worth unit-testing, and it is where the 7–8-visible requirement lives. Create `Steps4Tests/HappeningBlobLayoutTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Steps4

final class HappeningBlobLayoutTests: XCTestCase {

    private let canvas = CGSize(width: 390, height: 700)

    func testProducesOneBlobPerHappening() {
        XCTAssertEqual(HappeningBlobLayout.blobs(count: 10, in: canvas).count, 10)
        XCTAssertEqual(HappeningBlobLayout.blobs(count: 11, in: canvas).count, 11)
        XCTAssertEqual(HappeningBlobLayout.blobs(count: 1, in: canvas).count, 1)
    }

    func testHandlesEmptyInput() {
        XCTAssertTrue(HappeningBlobLayout.blobs(count: 0, in: canvas).isEmpty)
    }

    func testBlobsStayWithinTheHorizontalBounds() {
        for blob in HappeningBlobLayout.blobs(count: 11, in: canvas) {
            XCTAssertGreaterThanOrEqual(blob.center.x - blob.radius, 0)
            XCTAssertLessThanOrEqual(blob.center.x + blob.radius, canvas.width)
        }
    }

    /// The spec asks for 7–8 blobs visible without scrolling; the rest scroll.
    func testAtLeastSevenBlobsFitInTheFirstViewport() {
        let blobs = HappeningBlobLayout.blobs(count: 11, in: canvas)
        let visible = blobs.filter { $0.center.y + $0.radius <= canvas.height }
        XCTAssertGreaterThanOrEqual(visible.count, 7)
        XCTAssertLessThanOrEqual(visible.count, 8)
    }

    func testBlobsOverlapEnoughToMergeAsMetaballs() {
        let blobs = HappeningBlobLayout.blobs(count: 8, in: canvas)
        for (index, blob) in blobs.enumerated().dropFirst() {
            let nearest = blobs[..<index]
                .map { hypot($0.center.x - blob.center.x, $0.center.y - blob.center.y) - ($0.radius + blob.radius) }
                .min() ?? .greatestFiniteMagnitude
            XCTAssertLessThan(nearest, 0, "Blob \(index) must overlap a neighbour to merge")
        }
    }

    func testLayoutIsDeterministic() {
        XCTAssertEqual(
            HappeningBlobLayout.blobs(count: 9, in: canvas).map(\.center.x),
            HappeningBlobLayout.blobs(count: 9, in: canvas).map(\.center.x),
            "The cluster must not reshuffle between renders"
        )
    }

    func testContentHeightGrowsWithCount() {
        let eight = HappeningBlobLayout.contentHeight(count: 8, in: canvas)
        let sixteen = HappeningBlobLayout.contentHeight(count: 16, in: canvas)
        XCTAssertGreaterThan(sixteen, eight)
        XCTAssertGreaterThanOrEqual(eight, canvas.height * 0.5)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningBlobLayoutTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'HappeningBlobLayout' in scope`.

- [ ] **Step 3: Write `HappeningBlobLayout.swift`**

Deterministic staggered two-column cluster. Radii vary by a hash of the index so the cluster reads as organic without being random between renders:

```swift
import SwiftUI

/// Pure layout maths for the palette's metaball cluster. No view, no state —
/// so the "7–8 visible without scrolling" rule is unit-testable.
enum HappeningBlobLayout {

    struct Blob: Equatable {
        let index: Int
        let center: CGPoint
        let radius: CGFloat
    }

    /// Rows are staggered left/right and spaced closer than a diameter so
    /// neighbours merge under `metaballPath`.
    private static let rowsPerViewport: CGFloat = 4
    private static let radiusRatio: CGFloat = 0.19
    private static let radiusJitter: CGFloat = 0.22

    static func blobs(count: Int, in size: CGSize) -> [Blob] {
        guard count > 0, size.width > 0, size.height > 0 else { return [] }

        let baseRadius = size.width * radiusRatio
        let rowHeight = size.height / rowsPerViewport
        let topInset = rowHeight * 0.55

        return (0..<count).map { index in
            let row = CGFloat(index / 2)
            let isRight = index % 2 == 1
            // Deterministic per-index variation — the cluster must look organic
            // but must not reshuffle between renders.
            let wobble = CGFloat((index &* 2_654_435_761) % 1_000) / 1_000
            let radius = baseRadius * (1 - radiusJitter / 2 + radiusJitter * wobble)

            let x = isRight ? size.width * 0.63 : size.width * 0.37
            let nudge = (wobble - 0.5) * size.width * 0.06
            let clampedX = min(max(x + nudge, radius), size.width - radius)
            let y = topInset + row * rowHeight + (isRight ? rowHeight * 0.5 : 0)

            return Blob(index: index, center: CGPoint(x: clampedX, y: y), radius: radius)
        }
    }

    /// Scrollable content height for `count` blobs.
    static func contentHeight(count: Int, in size: CGSize) -> CGFloat {
        guard count > 0 else { return size.height }
        let blobs = blobs(count: count, in: size)
        let lowest = blobs.map { $0.center.y + $0.radius }.max() ?? size.height
        return max(size.height, lowest + size.height * 0.12)
    }
}
```

If `testAtLeastSevenBlobsFitInTheFirstViewport` fails, tune `rowsPerViewport` and `radiusRatio` until it passes — those two constants are exactly what that test pins.

- [ ] **Step 4: Run the layout tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningBlobLayoutTests 2>&1 | tail -20
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Write `HappeningPaletteView.swift`**

Merged contour behind, per-blob gradient and label in front, labels in dark text directly on the shapes, close button below — the metaball-cluster reference from brief §3.

```swift
import SwiftUI

/// The palette. Tap a blob and the happening lands on the canvas immediately;
/// tap the `+` node to type a new one, which also lands in the same action.
/// No categories anywhere in this flow.
struct HappeningPaletteView: View {

    @ObservedObject var model: AppModel
    let onPick: (Happening) -> Void
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isTypingNew = false
    @State private var draftTitle = ""

    private var happenings: [Happening] { model.paletteOrder() }

    /// One palette color per blob, keyed by index so a blob keeps its color
    /// for as long as the frozen order holds.
    private func color(at index: Int) -> Color {
        let hexes = CanvasColorPalette.paletteHex
        return Color(hex: hexes[index % hexes.count]) ?? .gray
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let blobs = HappeningBlobLayout.blobs(count: happenings.count, in: size)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Merged contour behind everything, so neighbours read as
                    // one organic cluster rather than separate circles.
                    ProceduralShapeGenerator.metaballPath(
                        blobs: blobs.map {
                            ProceduralShapeGenerator.BlobSource(center: $0.center, radius: $0.radius)
                        },
                        in: CGRect(origin: .zero, size: CGSize(
                            width: size.width,
                            height: HappeningBlobLayout.contentHeight(count: happenings.count, in: size)
                        ))
                    )
                    .fill(.white.opacity(0.06))

                    ForEach(Array(zip(blobs, happenings)), id: \.1.id) { blob, happening in
                        blobNode(blob: blob, happening: happening)
                    }

                    if let plus = HappeningBlobLayout.blobs(
                        count: happenings.count + 1, in: size
                    ).last {
                        plusNode(blob: plus)
                    }
                }
                .frame(
                    width: size.width,
                    height: HappeningBlobLayout.contentHeight(count: happenings.count + 1, in: size)
                )
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Close", comment: "Palette close button"))
            .padding(.bottom, 12)
        }
        .presentationDetents([.large])
    }

    private func blobNode(blob: HappeningBlobLayout.Blob, happening: Happening) -> some View {
        let tint = color(at: blob.index)
        return ZStack {
            ProceduralShapeGenerator.organicBlobPath(
                seed: CanvasElement.makeSeed(
                    optionId: happening.id, dayKey: AppModel.dayKey(for: .now), index: blob.index
                ),
                complexity: 0.45,
                in: CGRect(
                    x: 0, y: 0,
                    width: blob.radius * 2, height: blob.radius * 2
                )
            )
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.55)],
                    center: .center, startRadius: 0, endRadius: blob.radius
                )
            )

            Text(happening.localizedTitle())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black.opacity(0.8))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .frame(width: blob.radius * 1.5)
        }
        .frame(width: blob.radius * 2, height: blob.radius * 2)
        .position(blob.center)
        .contentShape(Circle())
        .onTapGesture {
            onPick(happening)
            dismiss()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(happening.localizedTitle())
    }

    private func plusNode(blob: HappeningBlobLayout.Blob) -> some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            if isTypingNew {
                HappeningFreeTextField(text: $draftTitle) { title in
                    onCreate(title)
                    draftTitle = ""
                    isTypingNew = false
                    dismiss()
                }
                .frame(width: blob.radius * 1.6)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: blob.radius * 2, height: blob.radius * 2)
        .position(blob.center)
        .contentShape(Circle())
        .onTapGesture { isTypingNew = true }
        .accessibilityLabel(Text("Add a happening", comment: "Palette free-text node"))
    }
}
```

- [ ] **Step 6: Write `HappeningFreeTextField.swift`**

No confirm step, no category, no icon picker — submitting the field creates and spawns in one action (brief §6).

```swift
import SwiftUI

/// Free-text entry inside the palette's `+` node. Submitting creates the
/// happening and spawns its canvas element in the same action.
struct HappeningFreeTextField: View {

    @Binding var text: String
    let onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        TextField(
            String(localized: "What happened?", comment: "Palette free-text placeholder"),
            text: $text
        )
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.black.opacity(0.8))
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.done)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onSubmit {
            guard !trimmed.isEmpty else { return }
            onSubmit(trimmed)
        }
    }
}
```

- [ ] **Step 7: Build**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | grep -E "error:" | head -20
```

Expected: errors only from files Tasks 9-12 have not touched yet (`GalleryView`, `CategoryDetailView`, `MeView`, `OnboardingStoriesView`, the Supabase services). No error may originate in the three new `Views/Palette/` files.

- [ ] **Step 8: Commit**

```bash
git add StepsTrader/Views/Palette Steps4Tests/HappeningBlobLayoutTests.swift
git commit -m "feat: add the happening palette as a metaball cluster"
```

---

## Task 9: Wire the palette into the canvas

**Files:**
- Modify: `StepsTrader/Views/GalleryView.swift` (lines 15-17, 44, 48, 394-443, 555-579, 920-961, 1022-1077)
- Modify: `StepsTrader/Views/Gallery/CanvasStateManagers.swift`
- Modify: `StepsTrader/Views/Gallery/GalleryNotifications.swift`
- Modify: `StepsTrader/Views/Gallery/GalleryMetricOverlayView.swift`
- Delete: `StepsTrader/Views/RadialHoldMenu.swift`, `StepsTrader/Views/CategoryDetailView.swift`, `StepsTrader/Views/MomentEntrySheet.swift`, `StepsTrader/Models/EphemeralMoment.swift`

**Interfaces:**
- Consumes: `HappeningPaletteView` (Task 8), `AppModel.addHappening(id:colorHex:at:)` (Task 5), `CanvasElement.spawn` without `category` (Task 6)
- Produces: nothing downstream

`GalleryView.swift` is 1588 lines and owns the canvas state. Splitting it is welcome but **not required** — do not let this expand into a refactor (brief §10).

- [ ] **Step 1: Replace the trigger**

Lines 555-579 currently mount `RadialHoldMenu` with `onCategorySelected` and `onMomentSelected`. Replace with a plain `+` button that presents the palette — a tap, not a long-press:

```swift
            Button {
                showPalette = true
                CoachMarkManager.postAction(for: .tapPlusButton)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(buttonColor)
                    .frame(width: 56, height: 56)
            }
            .coachMarkAnchor(.tapPlusButton)
```

Add `@State private var showPalette = false` near line 44 and delete `showMomentEntry`, `showMomentPaywall`, and `isFanOpen` (line 48 — its only job was hiding the share button while the radial fan was open; the palette is a sheet, so the share button is covered anyway).

`CoachMarkManager.postAction(for: .tapMind)` (line 563) has no meaning without categories. Grep for `.tapMind` and remove the case from the coach-mark enum along with its step; check `Steps4Tests/CoachMarkTourTests.swift` for an assertion on it.

- [ ] **Step 2: Replace the sheets**

Delete the `.sheet(item: $toolbar.pickerCategory)` block (417-432), the `.sheet(isPresented: $showMomentEntry)` block (438-440) and the `.fullScreenCover(isPresented: $showMomentPaywall)` block (441-443). Add:

```swift
        .sheet(isPresented: $showPalette) {
            HappeningPaletteView(
                model: model,
                onPick: { happening in
                    addHappening(happening.id)
                },
                onCreate: { title in
                    let made = model.happeningStore.create(title: title)
                    model.paletteOrderCache.append(id: made.id, dayKey: AppModel.dayKey(for: .now))
                    addHappening(made.id)
                }
            )
        }
```

Remove `pickerCategory` from the toolbar state object in `Views/Gallery/CanvasStateManagers.swift`.

- [ ] **Step 3: Rewrite the spawn path for repeat additions**

`spawnElement(optionId:category:color:assetVariant:)` (1022-1049) currently **deduplicates** by `optionId + category` — see **F1**. Repeat additions are now the point, so it must always append:

```swift
    /// Adds one happening: a canvas element plus the model-side addition that
    /// earns points. Always appends — the same happening added twice in one day
    /// is two elements and two additions, by design.
    private func addHappening(_ optionId: String) {
        let color = CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex
        let color2 = CanvasColorPalette.randomSecondColor(excluding: color)
        let label = model.happeningStore.happening(id: optionId)?.localizedTitle() ?? optionId

        var element = CanvasElement.spawn(
            optionId: optionId,
            color: color,
            color2: color2,
            label: label,
            existingElements: dayCanvas.elements,
            dayKey: dayCanvas.dayKey
        )
        element.lastEditedAt = Date.now
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            dayCanvas.elements.append(element)
        }
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()

        model.addHappening(id: optionId, colorHex: color)
    }
```

`removeElement(optionId:category:)` (1051-1060) and `rerollElement(optionId:category:)` (1062-1077) key on `optionId + category`, which no longer identifies one element now that duplicates exist. Rekey both on `CanvasElement.id`:

```swift
    private func removeElement(id: UUID) {
        guard let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }
        var updated = dayCanvas
        let removed = updated.elements.remove(at: index)
        pendingDeletedIds.insert(removed.id)
        updated.lastModified = Date.now
        dayCanvas = updated
        localMutationCounter &+= 1
        saveCanvasLocally()
    }

    private func rerollElement(id: UUID) {
        guard let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }
        let currentColor = dayCanvas.elements[index].hexColor
        let palette = CanvasColorPalette.paletteHex.filter { $0 != currentColor }
        let newColor = palette.randomElement() ?? currentColor
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dayCanvas.elements[index].reroll()
            dayCanvas.elements[index].hexColor = newColor
            dayCanvas.elements[index].hexColor2 = CanvasColorPalette.randomSecondColor(excluding: newColor)
            dayCanvas.elements[index].lastEditedAt = Date.now
        }
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()
    }
```

- [ ] **Step 4: Delete the reconcile-from-selections logic**

Lines 920-961 rebuild the canvas *from* the three selection arrays: `removeAll { !activeIds.contains($0.optionId) }` then spawn-for-missing. With an append-only additions log the canvas is authoritative for what is on screen — that whole block goes.

Delete the `activeIds` removal (the block ending at line 932) and the spawn-for-missing loop (934-961). Keep everything from line 963 (`// 2. Update canvas metrics from model`) onward untouched.

This changes one real behaviour, and it is a fix: a Supabase restore no longer resurrects elements the user deleted locally.

- [ ] **Step 5: Rewrite the cross-tab notifications**

Lines 394-416 decode `category` out of `userInfo` for three notifications. Drop the field from all three and update every poster. Find them:

```bash
grep -rn "canvasElementSpawnRequested\|canvasElementRemoveRequested\|canvasElementRerollRequested" --include="*.swift" .
```

`MainTabView.swift` is the main poster. Remove/reroll now carry `elementId: UUID` rather than `optionId`; spawn carries `optionId` and `color`.

In `Views/Gallery/GalleryNotifications.swift`, delete `case category(EnergyCategory)` from the sheet route enum and every `switch` arm that handles it.

- [ ] **Step 6: Delete the four files**

```bash
git rm StepsTrader/Views/RadialHoldMenu.swift \
       StepsTrader/Views/CategoryDetailView.swift \
       StepsTrader/Views/MomentEntrySheet.swift \
       StepsTrader/Models/EphemeralMoment.swift
```

Then remove them from the Xcode target in `project.pbxproj` (open the project, delete the now-red references).

`SubscriptionGate.canAddMoment(isPro:)` loses its only caller. Delete it, and delete the corresponding case from `Steps4Tests/SubscriptionGateTests.swift`. This is the deliberate Pro giveaway from brief §6 — free-text entry is not gated.

- [ ] **Step 7: Build**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | grep -E "error:" | head -30
```

Expected: errors only from `MeView`, `OnboardingStoriesView`, `ActivitySuggestion` and the Supabase services. Nothing from `GalleryView` or `Views/Gallery/`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: replace the radial hold menu and category sheet with the palette"
```

---

## Task 10: Supabase schema and sync

**Files:**
- Create: `supabase/migrations/20260808_happenings_relax_categories.sql`
- Modify: `StepsTrader/Services/SupabaseSyncService+Entries.swift:35,98,114,122`
- Modify: `StepsTrader/Services/SupabaseSyncService+Selections.swift:111,260,264`
- Modify: `StepsTrader/Services/SupabaseSyncService+Preferences.swift:36-38,68-70,198-200,241-243,309-311`
- Modify: `StepsTrader/Services/SupabaseSyncDTOs.swift:354-356,387-389,422-424`
- Modify: `StepsTrader/Services/SupabaseSyncService.swift:127-129,477-479,562-564`

**Interfaces:**
- Consumes: `OptionEntry` without `category` (Task 2), `CanvasShapeType.allowedByUser` (Task 7)
- Produces: `SupabaseSyncService.syncOptionEntry(_ entry: OptionEntry) async` — called from `AppModel.addHappening` (Task 5)

Nothing is dropped in this change. Old app versions stay in the field and keep writing the old columns.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260808_happenings_relax_categories.sql`:

```sql
-- Canvas happenings: the client stops writing categories, but old app versions
-- are still in the field and keep writing them. Relax, don't drop. A separate
-- later migration drops these columns once telemetry shows no old clients.

-- 1. Relax the five NOT NULL category columns ------------------------------
ALTER TABLE public.user_custom_activities ALTER COLUMN category DROP NOT NULL;
ALTER TABLE public.user_option_entries    ALTER COLUMN category DROP NOT NULL;
ALTER TABLE public.user_preferences ALTER COLUMN body_canvas_shape  DROP NOT NULL;
ALTER TABLE public.user_preferences ALTER COLUMN mind_canvas_shape  DROP NOT NULL;
ALTER TABLE public.user_preferences ALTER COLUMN heart_canvas_shape DROP NOT NULL;

-- 2. The new multi-select shape preference, backfilled from the union -------
ALTER TABLE public.user_preferences
    ADD COLUMN IF NOT EXISTS allowed_canvas_shapes text[];

UPDATE public.user_preferences
SET allowed_canvas_shapes = (
    SELECT array_agg(DISTINCT shape)
    FROM unnest(ARRAY[
        body_canvas_shape, mind_canvas_shape, heart_canvas_shape
    ]) AS shape
    WHERE shape IS NOT NULL
      -- Hidden legacy shapes collapse to circle, matching CanvasShapeType.migrateLegacy.
      AND shape NOT IN ('blob', 'spirograph')
)
WHERE allowed_canvas_shapes IS NULL;

-- Rows whose only shapes were legacy end up empty; give them the default set.
UPDATE public.user_preferences
SET allowed_canvas_shapes = ARRAY['circle', 'snowflake', 'rays', 'organicBlob']
WHERE allowed_canvas_shapes IS NULL OR cardinality(allowed_canvas_shapes) = 0;

-- 3. Flat happening ids alongside the three category arrays ----------------
ALTER TABLE public.user_daily_selections
    ADD COLUMN IF NOT EXISTS happening_ids text[];

UPDATE public.user_daily_selections
SET happening_ids = COALESCE(activity_ids, '{}')
                  || COALESCE(recovery_ids, '{}')
                  || COALESCE(joys_ids, '{}')
WHERE happening_ids IS NULL;

-- 4. Repeat additions: surrogate PK on user_option_entries -----------------
-- Was PRIMARY KEY (user_id, day_key, option_id) — one row per option per day.
-- The economy now counts additions and everyday things repeat, so the same
-- happening logged twice must produce two rows rather than an upsert collision.
ALTER TABLE public.user_option_entries DROP CONSTRAINT IF EXISTS user_option_entries_pkey;

ALTER TABLE public.user_option_entries
    ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE public.user_option_entries ADD PRIMARY KEY (id);

-- Demoted to a plain index — still the read path for "today's entries".
CREATE INDEX IF NOT EXISTS user_option_entries_user_day_option_idx
    ON public.user_option_entries (user_id, day_key, option_id);
```

- [ ] **Step 2: Verify the migration against a branch, not production**

```bash
supabase --version
```

Apply it to a Supabase **branch** and confirm each statement. Never run it against production from here — that is the user's call, and the PR is the place to ask.

If the CLI is not configured in this environment, say so in the PR body and leave the SQL for the user to apply. Do not use the Supabase MCP `apply_migration` tool against the live project without asking.

- [ ] **Step 3: Drop `category` from the entries row struct**

`SupabaseSyncService+Entries.swift`: delete `"category": entry.category.rawValue` (line 35), delete `let category: String` from the row struct (114) and its `CodingKeys` case (122), and delete `category: EnergyCategory(rawValue: row.category) ?? .body` from the decode (98).

The upsert also needs the surrogate id. Find the `.upsert(` call in this file and add `"id": entry.id` to the payload, and change any `onConflict:` argument from the composite key to `"id"`.

Add the single-entry sync `AppModel.addHappening` calls:

```swift
    /// Syncs one addition. Repeat additions of the same happening in one day
    /// are separate rows, keyed by the client-generated entry id.
    func syncOptionEntry(_ entry: OptionEntry) async {
        // Follow the existing syncOptionEntries batching/retry conventions in
        // this file — same table, same auth guard, same retry-queue enqueue.
    }
```

- [ ] **Step 4: Write the nullable-category decode test**

Add to `Steps4Tests/HappeningMigrationTests.swift`:

```swift
    /// A sync round-trip against the relaxed schema must not resurrect a
    /// category — there is no longer a `.body` to fall back to.
    func testEntryRowDecodesWithNullCategory() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "day_key": "2026-08-08",
          "option_id": "happening_walk",
          "category": null,
          "color_hex": "#AABBCC",
          "asset_variant": null,
          "created_at": "2026-08-08T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(OptionEntryRow.self, from: json)
        XCTAssertEqual(row.optionId, "happening_walk")
    }
```

Match `OptionEntryRow` to whatever the row struct in `SupabaseSyncService+Entries.swift` is actually called, and raise its access level to `internal` if it is `private` — `@testable import` reaches `internal`, not `private`.

- [ ] **Step 5: Update selections, preferences and DTOs**

`SupabaseSyncService+Selections.swift`: line 111 writes `category: activity.category.rawValue` for custom activities — drop the field. Lines 260-264 decode a category and bail when it is unknown (`guard let category = … else { return nil }`); that guard now **drops valid rows**, so remove it entirely. Write `happening_ids` alongside the three legacy arrays.

`SupabaseSyncService+Preferences.swift`, `SupabaseSyncDTOs.swift`, `SupabaseSyncService.swift`: add `allowedCanvasShapes: [String]` / `allowed_canvas_shapes` through the parameter list, the payload dict, the row struct, its `CodingKeys` and its `decodeIfPresent` fallback — following exactly the shape the three existing shape fields have at the line numbers listed above. Keep the three legacy fields being written during rollout.

- [ ] **Step 6: Build and run the migration tests**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningMigrationTests 2>&1 | tail -20
```

Expected: PASS, 3 tests.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: relax category columns and allow repeat option entries"
```

---

## Task 11: Fallout — the remaining category references

**Files:**
- Modify: `StepsTrader/Models/ActivitySuggestion.swift`
- Modify: `StepsTrader/AppModel+WorkoutSuggestions.swift`
- Modify: `StepsTrader/Views/MeView.swift` (~line 548), `StepsTrader/Views/MeViewSupport.swift`, `StepsTrader/Views/MeAxisDetailView.swift`
- Modify: `StepsTrader/Models/Note.swift` (the `NoteCatalog` entry)
- Modify: `StepsTrader/Views/MainTabView.swift`
- Delete: `StepsTrader/Models/EnergyCategory.swift`, `StepsTrader/Extensions/EnergyCategory+Helpers.swift`, `StepsTrader/Models/EnergyOption.swift`, `StepsTrader/Models/CanvasImageCatalog.swift`
- Modify: analytics call site for `piece_selected`

**Interfaces:**
- Consumes: everything from Tasks 2-10
- Produces: nothing downstream

- [ ] **Step 1: `ActivitySuggestion`**

Drop `category` from the struct and remove `suggestedCategory` from the workout mapping in `AppModel+WorkoutSuggestions.swift`. `acceptActivitySuggestion` (called from `GalleryView:496`) now routes through `model.addHappening(id:colorHex:)`.

An accepted workout suggestion needs a happening id. Map `HKWorkoutActivityType` to `happening_workout` for everything except walking, which maps to `happening_walk`. Keep it that simple — a richer mapping is not in this spec.

- [ ] **Step 2: `MeView` breakdown**

Around line 548, `summary.topBody` / `topMind` / `topHeart` render a three-dimension breakdown. Replace with the three entities that mirror the new formula: **sleep / steps / happenings**. Same visual treatment, three rows, values `model.sleepPointsToday`, `model.stepsPointsToday`, `model.happeningPointsToday`, each out of its own max (20 / 20 / 60).

Do not rework the screen. Its full rework is `Me-Spec.md`, which depends on this landing. Grep `MeViewSupport.swift` and `MeAxisDetailView.swift` for the summary type's category fields and collapse them the same way.

- [ ] **Step 3: `NoteCatalog`**

Remove the "Body, Mind, and Heart" note:

```bash
grep -rn "Body, Mind" --include="*.swift" .
```

Delete the entry and its `Localizable.xcstrings` keys. Check whether any test asserts the catalog's count.

- [ ] **Step 4: Analytics**

Drop the `category` field from `piece_selected`:

```bash
grep -rn "piece_selected" --include="*.swift" .
```

Leave the event name alone — renaming it breaks the existing dashboard, and that is not this spec's call.

- [ ] **Step 5: Delete the four model files**

```bash
git rm StepsTrader/Models/EnergyCategory.swift \
       StepsTrader/Extensions/EnergyCategory+Helpers.swift \
       StepsTrader/Models/EnergyOption.swift \
       StepsTrader/Models/CanvasImageCatalog.swift
```

Remove them from `project.pbxproj`. `EnergyOption.swift`'s remaining contents (`EnergyOption`, `OptionEntry`, `CustomEnergyOption`) are all superseded by `Happening.swift`; `EnergyRoutine` already moved there in Task 2.

`EnergyCategory+Helpers.defaultColorHex` (line 15) is used at spawn sites. Its body is `CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex` — already category-independent. Inline it at the call sites rather than keeping a one-line extension alive.

- [ ] **Step 6: Verify the enum is gone**

```bash
grep -rn "EnergyCategory" --include="*.swift" . 
```

Expected: **no output**. The only surviving legacy type is `LegacyCategory`, in the migration path. If anything remains, it belongs in this task.

```bash
grep -rn "LegacyCategory" --include="*.swift" .
```

Expected: exactly two files — `Models/LegacyCategory.swift` and `Models/CanvasElement.swift`. If `LegacyCategory` has leaked into a view or a service, it has become a domain type and the migration boundary is broken; push it back.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: remove EnergyCategory from the domain model"
```

---

## Task 12: Onboarding compile fix

**Files:**
- Modify: `StepsTrader/Views/OnboardingStoriesView.swift` (lines 1189, 1284, 1777, 1861, 1919, 1968)

**Interfaces:**
- Consumes: `CanvasElement.spawn` without `category` (Task 6)
- Produces: nothing

**Mechanical only.** Do not touch copy, slide order, or narrative. After this ships the onboarding describes a three-category model the app no longer has — that is known, accepted, and scheduled for spec C (brief §4, §9).

- [ ] **Step 1: Read the six sites**

```bash
grep -n "categoryTokens\|spec.cat" StepsTrader/Views/OnboardingStoriesView.swift
```

Line numbers drift as earlier tasks land; trust the grep, not the numbers in the brief.

- [ ] **Step 2: Collapse `categoryTokens` to a flat token list**

`categoryTokens` is keyed by category. Replace the dictionary with a single `[String]` holding the same tokens in body → mind → heart order, and replace each `categoryTokens[cat]` lookup with a slice or the whole list, whichever preserves what is drawn. The slides must render **identically** — this is a compile fix, not a redesign. Screenshot before and after if the layout is at all ambiguous.

- [ ] **Step 3: Hardcode the demo spawn's shape**

At the `spec.cat` site (~1777), the demo canvas element takes its shape from a category. `spawn` no longer accepts one, and the demo must not depend on the user's `allowedCanvasShapes` — an onboarding user has not configured it and a random shape would make the slide inconsistent between runs. Set the element's `frozenShapeType` to `.circle` explicitly after spawning.

- [ ] **Step 4: Build and check the onboarding tests**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/OnboardingFlowTests 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 5: Run the app and step through onboarding**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -5
```

Launch it, reset onboarding, and walk every slide. You are checking that nothing renders blank or crashes — not that the copy makes sense. It does not, and that is expected.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/OnboardingStoriesView.swift
git commit -m "fix: compile onboarding without EnergyCategory"
```

---

## Task 13: Full verification against the acceptance criteria

**Files:**
- Modify: whatever the failures point at
- Modify: `Steps4Tests/CustomActivityTests.swift`, `Steps4Tests/CanvasPersistenceRegressionTests.swift`, `Steps4Tests/WidgetTests.swift`

**Interfaces:**
- Consumes: everything
- Produces: a green build and suite

- [ ] **Step 1: Fix the remaining test files**

`Steps4Tests/CustomActivityTests.swift` tests `CustomEnergyOption`, which is deleted. Rewrite it against `HappeningStore.create` or delete it if `HappeningStoreTests` already covers the behaviour — do not keep both.

`Steps4Tests/CanvasPersistenceRegressionTests.swift:39-55` builds `DayCanvasSlot(category:optionId:)`, which is deleted. `testLoadDailyEnergyState_SlotsDoNotOverridePersistedSelections` tests a mechanism that no longer exists; delete that test. Keep `testLoadDailyEnergyState_MissingAnchor_DoesNotResetSelectionsOrBaseEnergy` and port it to `todayAdditions`.

`Steps4Tests/WidgetTests.swift` — port any `bodyPoints`/`mindPoints`/`heartPoints` assertion to `happeningPoints`.

- [ ] **Step 2: Full build**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | grep -E "error:|warning: .*deprecated" | head -30
```

Expected: no `error:` lines.

- [ ] **Step 3: Full test suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -40
```

Expected: `** TEST SUCCEEDED **`. Paste the real summary line into the PR; do not claim green without it.

- [ ] **Step 4: Walk the acceptance criteria by hand**

Build to the simulator and check each one. The automated suite covers 6, 7, 8, 9, 10, 11 and 13; the rest need eyes:

- [ ] Adding a happening takes one tap from the canvas
- [ ] A mid-day creation appears without reordering anything on screen
- [ ] `allowedCanvasShapes` cannot be emptied through the UI (tap the last selected chip — it must be disabled, not silently fail)
- [ ] A non-Pro user with Organic saved never spawns an Organic element, and the preference survives a Pro round-trip
- [ ] Palette order is stable across repeated opens within one `dayKey` (open, tap, reopen — nothing moves)
- [ ] Palette order re-ranks after `dayKey` rolls over (set the day end to a few minutes out in settings, wait, reopen)

- [ ] **Step 5: Confirm no `EnergyCategory` outside the migration path**

```bash
grep -rn "EnergyCategory" --include="*.swift" . ; echo "exit: $?"
```

Expected: no output, `exit: 1`.

- [ ] **Step 6: Commit and push**

```bash
git add -A
git commit -m "test: port the remaining suites off categories"
git push -u origin feat/happenings
```

---

## Self-review notes

**Spec coverage.** Every row of brief §10's fallout checklist maps to a task: `RadialHoldMenu`/`CategoryDetailView`/`MomentEntrySheet`/`EphemeralMoment` → Task 9; `MeView`/`ActivitySuggestion`/`NoteCatalog`/analytics/`EnergyCategory+Helpers`/`CanvasImageCatalog`/`EnergyDefaults` → Task 11; `EnergyRoutine` → Task 2; `GalleryNotifications` → Task 9; `PreferencesStore` → Task 7. All thirteen §11 acceptance criteria are checked in Task 13 Step 4 or by a named test.

**Known gaps, deliberately left.**

- The palette's visual polish is minimal by design (spec §"Out of scope": it gets restyled onto the token system in spec A).
- The widget still renders the happenings number in the slot where three category numbers were. Reworking widget layout is not in this spec.
- Onboarding narrative stays wrong until spec C. Task 12 only makes it compile.

**The risk that is not fully retired by tests.** Task 5 rewrites ~100 call sites of a published property that half the app reads. The tests pin the *formula* and the *store*, not every call site. Task 13 Step 4's manual walk is the real guard there, and it is not optional.

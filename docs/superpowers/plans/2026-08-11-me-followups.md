# Me — follow-ups and fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the verification debt left by `2026-08-11-me-screen-three-tabs.md`, isolate the one test that reads real app data, bring Me the rest of the way to `Me-Spec.md`, and settle the screen visually now that it is three sections instead of a radar.

**Architecture:** No new subsystems. One test file gains its own storage, one renderer gets a characterisation test, `MeView` loses a leftover section, and `MeCalendarStrip` gains month separators and a lighter tile. The two "first launch after update" risks — the `@SceneStorage` clamp and the grandfathering crash — are verified together, because both need a build of `main` installed before a build of this branch.

**Tech Stack:** Swift 6, SwiftUI, XCTest (`@testable import Steps4`), iOS Simulator `iPhone 17`.

## Global Constraints

- Build: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- Test: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'`
- **The `Steps4` target is NOT a file-system-synchronized group.** Every new `.swift` file needs four `Steps4.xcodeproj/project.pbxproj` edits: `PBXBuildFile`, `PBXFileReference`, a child entry in the owning `PBXGroup`, and an entry in the target's `Sources` phase. **Object IDs must be unique** — a duplicate ID silently resolves to the other file and yours never compiles (it cost a full debugging cycle last time). Check with `grep -c <id> project.pbxproj` before writing.
- `SubscriptionGate.allFeaturesUnlocked` stays `true` in every commit.
- User-facing strings use `String(localized:comment:)`.
- The simulator carries whatever data the last run left behind. Before judging any test result, know which state the simulator is in — see Task 1.

## Known simulator state

The device used for the previous plan (`00349825-3076-4659-80E4-50B9CFF9090F`) holds seeded history: 14 past-day snapshots and per-app spend, written directly into
`<app container>/Library/Application Support/personal-project.StepsTrader/`. That data is what makes Task 1's test fail. Keep it — several tasks below need a populated Me — and let Task 1 make the test independent of it instead.

---

## File Structure

**Tests**
- Modify `Steps4Tests/HappeningAdditionsTests.swift`: give the model under test its own defaults suite and snapshot file.
- Create `Steps4Tests/RayShapeRendererTests.swift`: characterisation test for the CPU spotlight renderer left behind by the radar deletion.

**Me**
- Modify `StepsTrader/Views/MeView.swift`: drop the earned/spent row, scope the subtitle.
- Modify `StepsTrader/Views/Me/MeCalendarStrip.swift`: month separators, lighter tile, empty state.

**Docs**
- Modify `docs/superpowers/plans/2026-08-11-me-screen-three-tabs.md`: record the two verifications once they are real.

---

## Task 1: Isolate `HappeningAdditionsTests` from app state — DONE (`29366dd`)

**Files:**
- Modify: `Steps4Tests/HappeningAdditionsTests.swift`
- Read first: `StepsTrader/Utilities/UserDefaults+StepsTrader.swift:11`, `StepsTrader/AppModel+DailyEnergy.swift:179`, `StepsTrader/Services/PersistenceManager.swift:12`

**Interfaces:**
- Produces: a `makeModel()` whose `AppModel` reads and writes only test-owned storage. Later tasks rely on the full suite being green, so this lands first.

- [ ] **Step 1: Reproduce the failure deliberately**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningAdditionsTests/testSavingPaletteSelectionUsesTheFullCatalogAndRefreshesAvailability 2>&1 | grep -E "XCTAssert|Executed"
```

Expected on the seeded simulator: `XCTAssertEqual failed: ("18") is not equal to ("11")`.

The 7 extra entries are custom happenings reconstituted from the app's saved history by `happeningStore.reconstituteOrphans(fromHistoryIds:)` (`AppModel+DailyEnergy.swift:179`), which reads `PersistenceManager.pastDaySnapshotsFileURL`. The catalog itself lives in `UserDefaults.stepsTrader()` — the real App Group suite, shared with the running app.

- [ ] **Step 2: Point the test's model at its own storage**

`makeModel()` in that file must supply a per-test `UserDefaults(suiteName:)` and a snapshot source that does not touch the app container. Whichever seam `AppModel`/`HappeningStore` already offers (initialiser parameter, DI container) is the one to use — do not add a new production seam if one exists.

`tearDown` must call `removePersistentDomain(forName:)` on the suite, or the next run inherits it.

- [ ] **Step 3: Prove it is independent, in both directions**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningAdditionsTests 2>&1 | grep -E "Executed"
```

Run it twice: once as-is (simulator holds seeded history), then again after
`xcrun simctl uninstall 00349825-3076-4659-80E4-50B9CFF9090F personal-project.StepsTrader`. Both runs must pass. **Do not weaken the assertion to 18 or to a range** — the point is that the number stops depending on the device.

- [ ] **Step 4: Check the file's other tests for the same dependency**

Any test in `HappeningAdditionsTests.swift` that asserts a catalog count, palette contents or availability has the same exposure. Fix them the same way; report which ones were affected.

- [ ] **Step 5: Run the whole suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "Executed .* tests|TEST (SUCCEEDED|FAILED)" | tail -4
```

Expected: 377 unit tests, 0 failures; 9 UI tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Steps4Tests/HappeningAdditionsTests.swift
git commit -m "test: isolate happening additions tests from app storage"
```

---

## Task 2: Characterise the spotlight renderer the radar left behind — DONE (`f67d3dd`)

**Files:**
- Create: `Steps4Tests/RayShapeRendererTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Read first: `StepsTrader/Shapes/RayShapeRenderer.swift:199` (`renderSpotlightBitmap`)

**Interfaces:**
- Consumes: `RayShapeRenderer.renderSpotlightBitmap(size:time:near:mid:far:)` and `RayShapeRenderer.rgbComponents(_:)`, both `nonisolated static`, both left in place when the radar cache was deleted.
- Produces: nothing other than coverage.

**Why this exists:** deleting the radar removed the only caller of the radar spotlight cache, but `renderSpotlightBitmap` stayed because the Gallery canvas ray path calls it per frame (`RayShapeRenderer.swift:149`). That path was never re-verified visually after the deletion — this test covers it deterministically instead of hunting for a ray element on screen.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import Steps4

/// The CPU spotlight renderer survived the radar deletion because the Gallery
/// canvas ray path calls it per frame. Nothing else covers it.
final class RayShapeRendererTests: XCTestCase {

    func testRendersABitmapOfTheRequestedSize() throws {
        let image = try XCTUnwrap(
            RayShapeRenderer.renderSpotlightBitmap(
                size: 64,
                time: 0,
                near: (1.0, 0.8, 0.4),
                mid: (0.8, 0.5, 0.2),
                far: (0.2, 0.1, 0.05)
            )
        )
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
    }

    func testTheBitmapIsNotBlank() throws {
        let image = try XCTUnwrap(
            RayShapeRenderer.renderSpotlightBitmap(
                size: 32, time: 0,
                near: (1, 1, 1), mid: (1, 1, 1), far: (1, 1, 1)
            )
        )
        // A blank render would be uniformly transparent; the beam must put
        // some non-zero alpha on the canvas.
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertTrue(data.contains { $0 != 0 }, "Spotlight bitmap is entirely empty")
    }

    func testRgbComponentsRoundTripAKnownColour() {
        let (r, g, b) = RayShapeRenderer.rgbComponents(Color(red: 1, green: 0.5, blue: 0))
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.5, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }
}
```

Register the file in `project.pbxproj` (four entries, unique IDs).

- [ ] **Step 2: Run it**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/RayShapeRendererTests 2>&1 | grep -E "error:|Executed"
```

Expected: PASS, 3 tests. The renderer is already correct — this is a characterisation test, so a red-then-green cycle is not expected. If it fails, the radar deletion took something it should not have: say so and investigate rather than adjusting the test.

- [ ] **Step 3: Confirm a ray element still renders on screen**

Open the canvas and add happenings until a ray-family element appears (`ElementKind.ray`, `CanvasElement.swift:35`). If injected taps do not reach the palette, use Settings → Developer → **Restore Colors to Max** first — the palette was unresponsive on a fresh account with zero colors, which is the likeliest cause.

Screenshot the canvas with a ray element visible and attach it to the task report. If a ray still cannot be produced by hand, say so plainly and let the test stand as the evidence — do not claim a visual check that did not happen.

- [ ] **Step 4: Commit**

```bash
git add Steps4Tests/RayShapeRendererTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "test: cover the CPU spotlight renderer kept for the canvas"
```

---

## Task 3: Verify both first-launch-after-update risks for real — DONE

Both upgrades open the canvas (Settings→4 and History→3), and the grandfathering
path ran without trapping. Recorded in `2026-08-11-me-screen-three-tabs.md`.

**Files:**
- Modify: `docs/superpowers/plans/2026-08-11-me-screen-three-tabs.md` (record the outcome)
- No production code, unless a check fails.

**Interfaces:**
- Consumes: `MainTabView.Tab.resolve(storedRawValue:)` and `SubscriptionStore.configure(apiKey:appUserID:)` as they stand on this branch.

**Why both together:** each needs a build of `main` installed and used first, then this branch installed over it without deleting the app. Doing them in one pass costs one extra build instead of two.

- [ ] **Step 1: Install and use the five-tab build**

```bash
git stash --include-untracked && git checkout main
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

Install it, launch, switch to the **Settings** tab (raw value 4), then send the app to the background (`Device ▸ Home`) so UIKit writes the scene-restoration archive. `@SceneStorage` lives in that archive, not in `UserDefaults` — `defaults write` cannot set it, which is why this has to be a real upgrade.

- [ ] **Step 2: Install this branch over the top**

```bash
git checkout feat/happenings && git stash pop
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

`xcrun simctl install` over the existing app — **no uninstall, no erase**. Launch.

Expected: the canvas opens. A blank screen or a crash is the failure this whole check exists for.

- [ ] **Step 3: Repeat for the History tab**

Same loop, leaving the `main` build on the **History** tab (raw value 3). Expected: the canvas opens.

- [ ] **Step 4: Verify the grandfathering crash is really gone on an upgrade**

The same setup covers it: the `main` build leaves app-group data behind, so `detectExistingUser` is true. Before launching this branch's build, clear the evaluation flag so the grandfathering path actually runs:

```bash
xcrun simctl spawn 00349825-3076-4659-80E4-50B9CFF9090F log stream --predicate 'process == "Nowhere"' --style compact
```

Watch the launch. Expected: `🎁 Grandfathered existing user into Pro` and **no** `Fatal error: Purchases has not been configured`. If the flag was already set by a previous run and the message does not appear, the path did not execute — say so rather than reporting a pass.

- [ ] **Step 5: Record the outcome**

Replace the "Verify the stored-tab clamp" and Pro-gate notes in `docs/superpowers/plans/2026-08-11-me-screen-three-tabs.md` with what actually happened, including which checks ran and which did not.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-08-11-me-screen-three-tabs.md
git commit -m "docs: record the real upgrade verification for Me"
```

---

## Task 4: Bring Me the rest of the way to the spec

**Files:**
- Modify: `StepsTrader/Views/MeView.swift`
- Modify: `StepsTrader/Views/Me/MeCalendarStrip.swift`

**Interfaces:**
- Consumes: `MeWeekStats.Summary`, `cachedSnaps`, `cachedTopApps` as they stand.
- Produces: `MeView.contentSection` with exactly three sections; `MeCalendarStrip` with an empty state.

**What the spec says** (`Me-Spec.md`, "The screen"): a settings button, no energy bar, then **1.** this week in three numbers, **2.** connected apps, **3.** the calendar. Nothing else.

- [ ] **Step 1: Delete the earned/spent row**

`compactColorsRow(earned:spent:)` and `statPair(value:label:accent:)` in `MeView.swift` are the last survivors of the old dashboard — a fourth reading the spec does not list, sitting between two headed sections with no header of its own. Delete both, and the `weekEarned` / `weekSpent` computation feeding them in `contentSection`.

The colors a day earned are still visible: the canvas shows today's, and each past day's poster shows its own.

- [ ] **Step 2: Scope the subtitle honestly**

The subtitle reads `Statistics for the last 7 days`, but the calendar below it now shows every day ever recorded. Move the seven-day claim onto the section it describes:

- Subtitle: delete it. The `THIS WEEK` header already says which window the three numbers cover.
- Leave `CONNECTED APPS` as is — `MeWeekStats.appSpend` is called with `cachedDayKeys`, which is the same seven days, and the header sits directly under `THIS WEEK`.

If deleting the subtitle leaves the greeting looking bare, say so in the report and propose a replacement rather than inventing copy here.

- [ ] **Step 3: Give the calendar an empty state**

`MeCalendarStrip` always renders at least today's tile, so it never looks broken — but on a first run there is nothing to scroll and no explanation. When `pastDays` is empty:

```swift
            if pastDays.isEmpty {
                Text(String(localized: "Your days will collect here.",
                            comment: "Me calendar – empty state"))
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            } else {
                ScrollView(.horizontal) { … }
            }
```

Keep the header row visible in both branches.

- [ ] **Step 4: Build and look at all three states**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -3
```

Check: a populated Me (seed data as in the previous plan), a Me with no history at all (fresh install), and a Me with history but no connected-app spend. None may show an orphaned header or an empty bordered block.

- [ ] **Step 5: Run the suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests 2>&1 | grep -E "Executed .* tests" | tail -1
```

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/MeView.swift StepsTrader/Views/Me/MeCalendarStrip.swift
git commit -m "feat: reduce Me to the three sections the spec names"
```

---

## Task 5: Settle the calendar visually

**Files:**
- Modify: `StepsTrader/Views/Me/MeCalendarStrip.swift`

**Interfaces:**
- Consumes: `DayHistoryTile` as moved in the previous plan.
- Produces: the same view with month separators and a quieter tile.

**These are my aesthetic calls, not the spec's** — the spec says only "past days, scrolling horizontally back into the past". Each is cheap to reverse, and the report should say how each one landed.

- [ ] **Step 1: Quieten the tile**

`DayHistoryTile` came from a Photos-style grid on a light settings background. On Me it sits on the dark energy gradient, where `Color(white: 0.88)` placeholders read as hard white blocks and the day numeral (28pt black serif, yellow) shouts over the three numbers above it.

- Placeholder fill: use `theme.textPrimary.opacity(0.06)` for a day with no canvas and `theme.textPrimary.opacity(0.10)` for a day with no data, instead of the two fixed greys.
- Day numeral: 20pt semibold serif, `theme.textPrimary.opacity(0.75)`. Keep the serif — it is the app's voice — and keep the yellow only on today's.
- Border: `theme.stroke.opacity(theme.strokeOpacity * 0.5)` instead of `Color(white: 0.82)`.

Thumbnails, blur, lock overlay and Pro badge stay exactly as they are.

- [ ] **Step 2: Separate months**

Fourteen identical tiles give no sense of how far back you are. When the month changes between adjacent tiles, insert a slim vertical label before the older one:

```swift
    private func monthLabel(for dayKey: String) -> String? {
        guard let date = CachedFormatters.dayKey.date(from: dayKey) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("LLL")
        return formatter.string(from: date)
    }
```

Render it as `.font(.caption2)` rotated -90°, in `theme.textSecondary.opacity(0.5)`, in a 16pt-wide column. Show it before the first tile too, so the newest month is named rather than implied.

- [ ] **Step 3: Check the accessibility text sizes**

Me's layout branches on `useTightMeLayout` (`dynamicTypeSize < .accessibility1`). The three-number rows now carry the longest strings on the screen — a happenings list like "called someone I love, made something, time outside" at `.accessibility3` will wrap hard.

Set the simulator to `.accessibility3` and confirm: no clipped text, no row overlapping the next, the calendar still scrollable, and the tab bar not covering the last row. Fix what breaks; report what you changed.

- [ ] **Step 4: Screenshot before and after**

Attach both to the task report — populated Me at default type size, and at `.accessibility3`.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/Me/MeCalendarStrip.swift
git commit -m "feat: quieten the calendar tile and name its months"
```

---

## Self-review notes

- Task 1 must land before any task whose verification reads "run the suite" — until it does, one failure is expected and would mask a real one.
- Task 3 is the only task that checks out `main`. Do not interleave it with edits in the working tree; it stashes.
- Tasks 4 and 5 both touch `MeCalendarStrip.swift`. Task 4 adds the empty state, Task 5 restyles the tile — they do not overlap, but run them in order.
- If Task 3 turns up a failure, stop and report before starting Task 4: a broken upgrade path outranks visual polish.

# Implementation brief — canvas pieces

Self-contained brief for reworking Nowhere's activity-logging mechanic. Written
to be handed to an implementer cold, with no access to the conversation that
produced it. The design rationale lives in `CanvasPieces-Spec.md`; this document
is the execution surface.

---

## 1. Context

Nowhere is a SwiftUI iOS app (target `Steps4`, display name **Nowhere**). Real
activity — steps, sleep, and daily choices — produces **colors**, which are spent
to unlock blocked apps ("feeds") through a PayGate. The **canvas** is a
generative animated picture of the day, and it is the product's centrepiece.

The app is feature-complete for beta and has real users with real saved data.
Nothing here is greenfield. Three app extensions and a widget share state through
App Group `group.personal-project.StepsTrader`.

Build:

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build
```

FamilyControls and DeviceActivity need a physical device; canvas and palette work
is fine in the simulator.

---

## 2. The problem

Adding an activity currently costs four interactions:

1. Long-press the `+` on the canvas
2. A radial fan of three category nodes appears — Body, Mind, Heart
3. Pick a category
4. A sheet lists that category's activities; pick one

The classification step is dead weight. Nobody deciding to log "called mom"
first wants to decide whether that is Mind or Heart. The three-category model
exists in the code, the economy, the stats tab, the onboarding and the editorial
notes — but it does not exist in anyone's head.

---

## 3. Target behaviour

Tap the `+`. A palette opens showing ten things as overlapping organic blobs with
labels set on them. Tap one — it lands on the canvas immediately as a generative
shape. A separate `+` node in the palette takes free text and creates a new piece
on the spot, which also lands on the canvas in the same action.

No categories anywhere in the flow.

**Visual reference:** a metaball cluster — soft overlapping gradient blobs,
labels in dark text directly on the shapes, close button below. Build it on the
existing `MetaballGenerator` and `OrganicBlobShapeGenerator`, not from scratch.

---

## 4. Scope boundary

**In scope:** the model, the palette, shape selection, the daily economy, the Now
tab's breakdown, the Supabase schema, and the migration of existing saved data.

**Out of scope:** design tokens, component library, tab structure, navigation.
Those are a separate spec. Style the palette well enough to ship; it gets
restyled later. Do not start renumbering tabs.

**Deferred:** the onboarding narrative. It will keep describing three categories
after this lands — accepted, scheduled separately. But see §9, it still needs a
compile fix.

---

## 5. Model changes

Collapse three near-identical types into one.

Delete `EnergyCategory`, `CustomEnergyOption`, `EphemeralMoment`.
Reshape `EnergyOption` into `Piece`. Remove `category` from `OptionEntry`.

```swift
struct Piece: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    let isBuiltIn: Bool
    var useCount: Int
    var lastUsedAt: Date?
}
```

`useCount` and `lastUsedAt` are stored, not derived — palette ordering reads them
on every open and they must not require a scan of history.

### Built-in set

31 built-ins today (body 11, mind 10, heart 10) become 10. Proposed, confirm
before writing strings:

Walk · Workout · Slept well · Called someone I love · Drinks with friends ·
Read · Laughed · Made something · Time outside · Did nothing on purpose

Copy goes in `Localizable.xcstrings` under `option.title.<id>`, matching the
existing convention. Any option id that exists in a user's history but is no
longer built-in is reconstituted as a `Piece` with `isBuiltIn: false` on first
launch, so nobody's past days lose their labels.

---

## 6. The palette

### Ordering

Rank by `useCount`, ties broken by more recent `lastUsedAt`, take the top ten.
Built-in and user pieces rank together with no visual distinction.

**The order is computed once per day and frozen.** Do not re-sort after each tap
— buttons that move under the thumb destroy muscle memory. Cache the computed
order against `dayKey` and recompute only when `dayKey` changes.

`dayKey` respects the user's configured `dayEndHour` / `dayEndMinute`, not
calendar midnight. `AppModel+DailyRandomTheme` already does exactly this; reuse
that pattern rather than writing a second one.

A piece created mid-day is appended to the end of the frozen order and shown in
addition to the ten, so the palette can hold eleven on the day of creation. It
takes its ranked position, and the list returns to ten, the next day. Nothing
already on screen moves.

### Layout

Metaball cluster. 7–8 blobs visible without scrolling, the rest reachable by
scroll. Colors from `CanvasColorPalette.paletteHex` — 29 entries, already
category-independent, no changes needed. A distinct `+` node opens free text.

### Free text

Submitting text creates a `Piece` with `isBuiltIn: false`, `useCount: 1`,
`lastUsedAt: now` and spawns its canvas element in the same action. No confirm
step, no category, no icon picker.

This replaces the ✦ Moment feature entirely. Delete `MomentEntrySheet` and
`EphemeralMoment`. Moment was Pro-gated and free text is not — that giveaway is
intentional and already decided.

---

## 7. Shapes

```swift
// before, in CanvasElement.spawn
let shapeType = CanvasShapeType.resolved(for: category)

// after
let shapeType = CanvasShapeType.allowedByUser.randomElement()!
```

Everything downstream in `spawn` — `kind`, `size`, `isGrounded`,
`pulseFrequency`, `opacity` — already derives from `shapeType`, not from
category. No other line in that function changes. This is the single most
important thing to notice before starting: the change is far smaller than the
23-file grep suggests.

### Settings

Three single-value keys become one multi-select over
`CanvasShapeType.selectableCases` (Circle, Snowflake, Rays, Organic):

- `SharedKeys.bodyCanvasShape` / `mindCanvasShape` / `heartCanvasShape` →
  `SharedKeys.allowedCanvasShapes`
- Seed the new key from the union of the three old ones so current preferences
  carry over
- The set may never be empty — the UI blocks deselecting the last shape
- Organic stays Pro. Keep it visible in settings for non-Pro users but filter it
  at spawn time, so a lapsed subscriber's preference survives and reactivates

---

## 8. Economy

Categories supplied 60 of the 100 daily points, 20 each. Replacement:

```
pieces = min(additions × 10, 60)
day    = steps(20) + sleep(20) + pieces(60) = 100
```

The 100 ceiling is deliberately unchanged — onboarding has a slide built on it.

In `AppModel+DailyEnergy`: delete `bodyPointsToday`, `mindPointsToday`,
`heartPointsToday`; add `piecePointsToday`.

Additions past the sixth still land on the canvas and still increment
`useCount`. They stop earning. Do not block them.

---

## 9. Migration — the part that breaks silently

### Saved canvases

`CanvasElement.init(from:)` contains:

```swift
frozenShapeType = try c.decodeIfPresent(CanvasShapeType.self, forKey: .frozenShapeType)
    ?? CanvasShapeType.defaultShape(for: category)
```

Elements saved before `frozenShapeType` existed resolve their shape **through the
category**. Deleting the field outright redraws historical canvases with
different shapes, and nothing fails loudly when it happens.

Decode the legacy category into a local constant, use it only for that fallback,
discard it. It is not stored on the struct and not written on encode.

```swift
let legacyCategory = try c.decodeIfPresent(LegacyCategory.self, forKey: .category)
frozenShapeType = try c.decodeIfPresent(CanvasShapeType.self, forKey: .frozenShapeType)
    ?? legacyCategory.map(CanvasShapeType.legacyDefault(for:))
    ?? .circle
```

`LegacyCategory` is a private, decode-only enum living in the migration path. It
is not part of the domain model and must not leak into it.

`PastDaySnapshot` keeps decoding `bodyPoints` / `mindPoints` / `heartPoints` for
historical rows and stops writing them. New rows write `piecePoints`.

### Supabase

Three tables hold categories, all `NOT NULL`, so the client cannot just stop
writing them. Old app versions stay in the field during rollout, so nothing gets
dropped in this change.

| Table | Column |
|-------|--------|
| `user_custom_activities` | `category` |
| `user_option_entries` | `category` |
| `user_preferences` | `body_canvas_shape`, `mind_canvas_shape`, `heart_canvas_shape` |

Sequence:

1. Migration relaxes all five columns to nullable
2. Add `user_preferences.allowed_canvas_shapes text[]`, backfilled from the union
   of the three shape columns
3. New clients stop writing the old columns; old clients keep working
4. A separate later change drops them, once no old clients are writing

Remove `category` from the row structs in `SupabaseSyncService+Entries` and
`SupabaseSyncService+Selections`.

### Repeat additions

`user_option_entries` is keyed `PRIMARY KEY (user_id, day_key, option_id)` — one
row per option per day. Correct for one-shot category selections, wrong now: the
economy counts additions and everyday things repeat.

Make the primary key a surrogate `id uuid` and demote
`(user_id, day_key, option_id)` to a plain index. The local `OptionEntry`
already carries its own `id`, so client code is unaffected.

### Onboarding compile fix

`OnboardingStoriesView` references categories in roughly six places —
`categoryTokens` at 1189, 1284, 1861, 1919, 1968 and `spec.cat` at 1777 — so it
will not compile once the enum is gone. Collapse `categoryTokens` to a flat
token list and hardcode the demo spawn's shape. **Mechanical only.** Do not touch
copy, slide order, or narrative; that is a separate spec, and the onboarding will
temporarily describe a model the app no longer has. That is known and accepted.

---

## 10. Fallout checklist

| Area | Action |
|------|--------|
| `RadialHoldMenu` | Delete — replaced by the palette |
| `CategoryDetailView` | Delete — replaced by the palette |
| `EnergyCategory+Helpers` | Delete |
| `MomentEntrySheet`, `EphemeralMoment` | Delete |
| `MeView` breakdown (`summary.topHeart` etc., ~line 548) | Replace with three color sources: steps / sleep / additions |
| `EnergyRoutine` | `bodyIds` / `mindIds` / `heartIds` → flat `pieceIds` |
| `ActivitySuggestion` | Drop `category`; remove `suggestedCategory` from workouts |
| `GalleryNotifications` | Remove `case category(EnergyCategory)` from the route enum |
| `PreferencesStore` | Three shape fields → one set |
| `CanvasImageCatalog`, `EnergyDefaults` | Decategorise |
| Analytics `piece_selected` | Drop the `category` field |
| `NoteCatalog` "Body, Mind, and Heart" | Remove from the catalog |

Full list of files touching `EnergyCategory` (23):

```
Steps4Tests/DailyEnergyLogicTests.swift
StepsTrader/AppModel+DailyEnergy.swift
StepsTrader/Extensions/EnergyCategory+Helpers.swift
StepsTrader/Models/ActivitySuggestion.swift
StepsTrader/Models/CanvasElement.swift
StepsTrader/Models/CanvasImageCatalog.swift
StepsTrader/Models/EnergyCategory.swift
StepsTrader/Models/EnergyDefaults.swift
StepsTrader/Models/EnergyOption.swift
StepsTrader/Models/EphemeralMoment.swift
StepsTrader/Models/PastDaySnapshot.swift
StepsTrader/Models/ShapeStyles.swift
StepsTrader/Services/SupabaseSyncService+Entries.swift
StepsTrader/Services/SupabaseSyncService+Selections.swift
StepsTrader/Views/CategoryDetailView.swift
StepsTrader/Views/Gallery/CanvasStateManagers.swift
StepsTrader/Views/Gallery/GalleryMetricOverlayView.swift
StepsTrader/Views/Gallery/GalleryNotifications.swift
StepsTrader/Views/GalleryView.swift
StepsTrader/Views/MainTabView.swift
StepsTrader/Views/MomentEntrySheet.swift
StepsTrader/Views/OnboardingStoriesView.swift
StepsTrader/Views/RadialHoldMenu.swift
```

`GalleryView.swift` is 1588 lines and owns the canvas state the palette has to
talk to. It is the hardest file here. Splitting it is welcome but is not required
by this brief — do not let it expand into a refactor.

---

## 11. Acceptance criteria

Rewrite `DailyEnergyLogicTests` and `EnergyRecalcTests` — both assert the old
five-part 100-point formula.

- [ ] Adding a piece takes one tap from the canvas
- [ ] `piecePointsToday` caps at 60 regardless of addition count
- [ ] A day of 2 pieces + full steps + full sleep totals 60, not 100
- [ ] Palette order is stable across repeated opens within one `dayKey`
- [ ] Palette order re-ranks after `dayKey` rolls over, at the user's configured day end
- [ ] A mid-day creation appears without reordering anything on screen
- [ ] `allowedCanvasShapes` cannot be emptied through the UI
- [ ] A non-Pro user with Organic saved never spawns an Organic element, and the preference survives a Pro round-trip
- [ ] **A `DayCanvas` fixture captured in the old format — with `category`, without `frozenShapeType` — decodes to the same `frozenShapeType` as before the change.** Use a real captured fixture, not a synthesized one. This is the guard on the only failure mode that is invisible in review.
- [ ] The same piece added twice in one day produces two `user_option_entries` rows
- [ ] A sync round-trip against nullable `category` decodes without falling back to `.body`
- [ ] Project builds with zero references to `EnergyCategory` outside the migration path

---

## 12. Working agreement

- The migration in §9 is the highest-risk item. Write its test first, from a real
  fixture, before deleting anything.
- Prefer following existing patterns over introducing new ones. `dayKey`
  handling, `Localizable.xcstrings` keys, `AppLogger` over `print`, and the
  `SharedKeys` convention all have established shapes in this codebase.
- Report honestly. If the `GalleryView` integration turns out to need a larger
  change than this brief assumes, say so rather than expanding scope quietly.

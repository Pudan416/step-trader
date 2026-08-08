# Canvas pieces — replacing body/mind/heart

**Date:** 2026-08-08
**Status:** Draft, awaiting review
**Scope:** Spec 0 of the redesign stack

---

## Why this exists

The redesign started as a view-layer rebuild driven by two complaints: the app
looks unpolished, and its five-tab structure buries the actions people use most.
Answering the second complaint surfaced a deeper one — the body / mind / heart
split is itself the thing making adding a piece slow. You cannot pick an
activity without first picking which of three dimensions it belongs to, and that
classification means nothing to the person doing it.

So this spec comes before the visual work. It removes categories from the
product and replaces the radial hold menu with a single palette.

### Relationship to the rest of the redesign

The redesign is a stack of three specs. This one was inserted ahead of them:

| Spec | Covers | Status |
|------|--------|--------|
| **0. Canvas pieces** | This document — kill categories, add the palette | Draft |
| A. Foundation + shell | Design tokens, component set, navigation and IA | Not started |
| B. Core loop surfaces | Canvas home, Feeds and PayGate | Not started |
| C. Everything else | Now, Notes, Settings, widget, shield, onboarding narrative | Not started |

Spec A cannot start until this one lands, because the palette is the single
biggest new surface and it sets the visual direction the token system has to
support.

---

## What changes for the user

Today: long-press the `+`, a fan of three category nodes appears, pick a
category, a sheet opens listing that category's activities, pick one, it lands
on the canvas.

After: tap the `+`, a palette opens showing ten things as organic blob shapes,
tap one, it lands on the canvas immediately. A separate `+` node in the palette
takes free text and creates a new piece on the spot.

The reference for the palette's look is a metaball cluster — overlapping
gradient blobs with labels set directly on them. `MetaballGenerator` and
`OrganicBlobShapeGenerator` already exist and are what this should be built on.

---

## Model

Three near-identical types collapse into one.

Removed: `EnergyCategory`, `CustomEnergyOption`, `EphemeralMoment`.
Reshaped: `EnergyOption` becomes `Piece`; `OptionEntry` loses `category`.

```swift
struct Piece: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    let isBuiltIn: Bool
    var useCount: Int
    var lastUsedAt: Date?
}
```

`useCount` and `lastUsedAt` are what drive palette ordering, so they are part of
the model rather than derived at read time.

### Built-in pieces

There are 31 built-in options today (body 11, mind 10, heart 10). The palette
shows ten, so the built-in set is cut to ten — chosen for everyday specificity
over category coverage.

Proposed set, to be confirmed during implementation:

| # | Piece |
|---|-------|
| 1 | Walk |
| 2 | Workout |
| 3 | Slept well |
| 4 | Called someone I love |
| 5 | Drinks with friends |
| 6 | Read |
| 7 | Laughed |
| 8 | Made something |
| 9 | Time outside |
| 10 | Did nothing on purpose |

Copy is authored in `Localizable.xcstrings` under `option.title.<id>`, the same
convention built-ins already use.

Cutting built-ins does not orphan user data: existing `OptionEntry` rows
reference option ids, and any id no longer in the built-in set is reconstituted
as a `Piece` with `isBuiltIn: false` on first migration pass.

---

## The palette

### Ordering

Ordering is by use frequency, as decided. The naive version re-sorts after every
tap, which moves buttons under the user's thumb and prevents muscle memory from
forming.

**Rule:** the order is computed once per day and frozen for that day.

- Score is `useCount`, ties broken by more recent `lastUsedAt`.
- Top ten are shown.
- Built-in and user pieces are ranked together, with no visual distinction.
- The computed order is cached against `dayKey` and only recomputed when
  `dayKey` changes.

`dayKey` respects the user's configured `dayEndHour` / `dayEndMinute`, not
calendar midnight. This is the same mechanism `AppModel+DailyRandomTheme`
already uses, and it should reuse that pattern rather than invent a second one.

A piece created mid-day is appended to the end of the frozen order and shown in
addition to the ten, so the palette may hold up to eleven entries on the day a
piece is created. It takes its ranked position — and the list returns to ten —
the next day. Nothing already on screen moves.

### Layout

Metaball cluster, 7–8 blobs visible without scrolling, remainder reachable by
scroll. Labels sit on the blobs. A distinct `+` node opens free text entry.

Colors come from `CanvasColorPalette.paletteHex` (29 colors), which is already
category-independent.

### Free text entry

Entering text creates a `Piece` with `isBuiltIn: false`, `useCount: 1`,
`lastUsedAt: now`, and spawns its canvas element in the same action. There is no
separate confirm step and no category to assign.

This subsumes the ✦ Moment feature, which is removed. `MomentEntrySheet` and
`EphemeralMoment` are deleted. Moment was Pro-gated; free text entry is not, so
this is a small giveaway of paid surface area — accepted deliberately, because
maintaining two ways to write down one-off events is not worth the revenue.

---

## Shapes

Shape selection moves from category-derived to user-configured.

```swift
// before
let shapeType = CanvasShapeType.resolved(for: category)

// after
let shapeType = CanvasShapeType.allowedByUser.randomElement()!
```

Everything downstream in `CanvasElement.spawn` — `kind`, `size`, `isGrounded`,
`pulseFrequency`, `opacity` — already derives from `shapeType` rather than from
category, so no other line in `spawn` changes.

### Settings

Three single-value keys (`bodyCanvasShape`, `mindCanvasShape`,
`heartCanvasShape`) become one multi-select, `allowedCanvasShapes`, over
`CanvasShapeType.selectableCases`: Circle, Snowflake, Rays, Organic.

- The set may never be empty. The UI prevents deselecting the last shape.
- Organic remains Pro. It stays visible in settings for non-Pro users but is
  filtered out at spawn time, so a lapsed subscriber's saved preference survives
  and reactivates on resubscribe.
- Migration: seed `allowedCanvasShapes` from the union of the three existing
  keys, so a user's current shapes carry over.

---

## Economy

Categories supplied 60 of the 100 daily points — 20 each. The replacement:

```
pieces = min(additions × 10, 60)
day    = steps(20) + sleep(20) + pieces(60) = 100
```

The 100 ceiling is unchanged, which matters because onboarding has a slide
built on it.

Removed from `AppModel+DailyEnergy`: `bodyPointsToday`, `mindPointsToday`,
`heartPointsToday`. Added: `piecePointsToday`.

Additions past the sixth still appear on the canvas and still count toward
`useCount`. They just stop earning.

---

## Data migration

Beta testers have saved `DayCanvas` JSON on disk. Old days must keep rendering
exactly as they did.

The subtle part is in `CanvasElement.init(from:)`:

```swift
frozenShapeType = try c.decodeIfPresent(CanvasShapeType.self, forKey: .frozenShapeType)
    ?? CanvasShapeType.defaultShape(for: category)
```

Elements saved before `frozenShapeType` existed resolve their shape *through*
the category. Dropping the field outright would silently redraw historical
canvases with different shapes.

**Rule:** decode the legacy `category` key into a local constant, use it solely
for that `frozenShapeType` fallback, and discard it. It is not stored on the
struct and not written back on encode.

```swift
let legacyCategory = try c.decodeIfPresent(LegacyCategory.self, forKey: .category)
frozenShapeType = try c.decodeIfPresent(CanvasShapeType.self, forKey: .frozenShapeType)
    ?? legacyCategory.map(CanvasShapeType.legacyDefault(for:))
    ?? .circle
```

`LegacyCategory` is a private decode-only enum kept in the migration path. It is
not part of the domain model.

`PastDaySnapshot` keeps decoding `bodyPoints` / `mindPoints` / `heartPoints` for
historical rows but stops writing them. New rows write `piecePoints`.

---

## Fallout

| Area | Resolution |
|------|-----------|
| `MeView` dimension breakdown | Replaced by three color sources: steps / sleep / additions. Mirrors the new 100-point formula honestly instead of pretending to be analytics |
| `EnergyRoutine` | `bodyIds`/`mindIds`/`heartIds` collapse to a flat `pieceIds` |
| `ActivitySuggestion` | Drops `category`; `suggestedCategory` on workouts is removed |
| `RadialHoldMenu` | Deleted. Replaced by the palette |
| `CategoryDetailView` | Deleted. Replaced by the palette |
| `EnergyCategory+Helpers` | Deleted |
| `GalleryNotifications` | `case category(EnergyCategory)` removed from the sheet route enum |
| Analytics `piece_selected` | `category` field dropped |
| `NoteCatalog` "Body, Mind, and Heart" | Removed from the catalog |
| Onboarding narrative | **Deferred to spec C** |

### Known temporary inconsistency

Onboarding's narrative stays as-is, so after this spec ships the onboarding
teaches a three-category model the app no longer has. This is accepted and
scheduled for spec C.

It is not free, though. `OnboardingStoriesView` references categories in roughly
six places (`categoryTokens` at 1189, 1284, 1861, 1919, 1968; `spec.cat` at
1777), so it will not compile once the enum is deleted. This spec includes a
mechanical compile fix there — collapsing `categoryTokens` to a flat token list
and hardcoding the demo spawn's shape — with no narrative or copy changes.

---

## Testing

- `DailyEnergyLogicTests` and `EnergyRecalcTests` both assert the five-part
  100-point formula and must be rewritten for the three-part one.
- New: `piecePointsToday` caps at 60 regardless of addition count.
- New: palette ordering is stable within a `dayKey` and re-ranks across one.
- New: a mid-day addition appears in the palette without reordering it.
- New (regression): a `DayCanvas` fixture saved in the old format, with a
  `category` and no `frozenShapeType`, decodes to the same `frozenShapeType`
  it resolved to before the change. This is the migration's guard and should be
  written from a real captured fixture, not a synthesized one.
- `allowedCanvasShapes` cannot be emptied.
- Non-Pro user with Organic in `allowedCanvasShapes` never spawns an Organic
  element, and the preference survives.

---

## Out of scope

Visual tokens, component library, tab structure, and navigation — all spec A.
The palette gets whatever styling it needs to ship, and is restyled onto the
token system in spec A rather than blocking on it.

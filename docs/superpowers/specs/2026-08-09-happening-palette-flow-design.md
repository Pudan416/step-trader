# Happening Palette Flow

## Goal

Replace the scrolling cluster of separate happening blobs with one fixed,
single-screen palette. At the start of each day the palette exposes ten
activities, while the full catalog and custom-activity creation remain one tap
away.

## Interaction

### Closed

The canvas shows one circular `+` control above the tab bar. Tapping it expands
the happening palette in place. It is not presented as a separate system sheet.

### Open palette

One continuous, softly blended multicolor blob contains the day's remaining
happenings as stable tap zones. Each zone displays one happening title. The
field is a transparent, irregular `Living island` contour rendered directly
over the live canvas; it has no rectangular background, sheet, or image asset.
Canvas content remains visible and tappable outside the contour.

Tapping a zone adds that happening to the current day once. The zone then sinks
through the field, disappears for the rest of the day, and the remaining zones
flow into the vacated space. The palette stays open so the user can add another
happening. It closes only when the user taps `×` or free canvas space outside
the contour and its controls.

The original `+` becomes the larger central `×`. Two smaller controls appear
beside it:

- Left: catalog/settings icon. Opens the happening chooser.
- Center: `×`. Closes the palette without adding anything.
- Right: `+`. Opens custom happening creation.

The controls form one compact horizontal group visually attached to the bottom
of the blob. The center control remains the strongest visual anchor.

### Liquid removal motion

The selected zone compresses for 100–150 ms, then its text and color contract
toward a sink point while the corresponding canvas element emerges below. Over
the next 300–450 ms the field recomputes its metaball sources and neighboring
colors interpolate into the empty space with a spring that does not overshoot
the contour. A light haptic marks the moment the zone breaks through.

Input is locked only for the selected zone during this transition. The field
does not flash, fade to a rectangle, or cross-dissolve between static images.
`Reduce Motion` replaces sinking and fluid interpolation with a short opacity
transition and immediate stable reflow.

### Choose happenings

The left control opens a floating panel over the dimmed palette. It lists the
entire catalog: built-ins, user-created happenings, and reconstituted legacy
items. Each row is a multi-select checkbox.

Exactly ten items may be selected. Selecting an eleventh item does not silently
remove another one; the user must first deselect an existing item. The header
shows `N of 10 selected`, and `Done` is enabled only when exactly ten are
selected. Cancelling discards edits. Saving updates the palette immediately and
persists the chosen ids in their displayed order.

The first launch starts with the ten built-ins selected.

### Add a happening

The right control opens a compact input panel over the dimmed palette. A valid,
trimmed title enables `Add to palette`.

Submitting creates the happening in the full catalog and selects it for the
palette. Because the palette is already full, the least-used currently visible
happening is removed from the visible set. Ties are resolved by the oldest
`lastUsedAt`, then by stable palette order. The removed happening remains in the
catalog and can be restored from the chooser.

Creation itself does not log the happening to the day. After creation, the
input panel closes, the palette remains open, and the new happening occupies
the replaced zone with a short highlight. The user taps it separately to log
it. This prevents an editing action from being mistaken for a journal action.

Blank titles are rejected. Duplicate titles are allowed because catalog
identity is id-based.

## Palette stability

The ten selected ids are a user preference, not a daily ranking. Their order
and tap-zone positions remain stable until the user changes the selection or
adds a new happening. Usage counters remain catalog metadata used only to pick
the automatic replacement after creation.

The visible set for a day is the configured ten minus ids already present in
that day's additions. A happening can be added at most once per custom day.
Reopening the palette on the same day keeps logged ids hidden. At the next
`dayKey`, all configured happenings become available again. Remaining items
keep their relative order while the layout recomputes positions for the smaller
count.

New custom happenings take the replaced item's position. Changes made in the
chooser retain the order of surviving items; newly selected items fill empty
positions in selection order.

## State and persistence

Persist a palette configuration containing exactly ten happening ids. On load:

1. Remove ids no longer present in the catalog.
2. Fill missing slots from built-ins in their default order.
3. If necessary, fill remaining slots from the catalog's stable insertion
   order.

The catalog remains independent from palette membership. No happening is
deleted when it is removed from the visible ten.

## Components

- `HappeningPaletteView`: expanded blob, ten hit zones, and three-control dock.
- `HappeningLiquidField`: SwiftUI `Canvas`/`Shape` rendering, mesh color field,
  hit regions, and animated source interpolation; no raster palette artwork.
- `HappeningChooserView`: searchable catalog checklist and ten-item validation.
- `HappeningCreatorView`: title input and creation action.
- `HappeningPaletteSelectionStore`: validates, repairs, orders, and persists the
  ten visible ids.
- Existing `HappeningStore`: continues to own the complete catalog and usage
  metadata.

The old daily ranking cache is retired; it conflicts with stable user-selected
positions.

The implementation uses native SwiftUI and existing procedural shape utilities.
It must not add a third-party rendering dependency or ship the concept mockup
as a bitmap.

## Accessibility and errors

Every blob zone is an accessibility button with the happening title. The three
controls have explicit labels: `Choose happenings`, `Close`, and
`Add a happening`. Panels support Dynamic Type and scrolling. The blob's visual
shape is not used as the hit-test boundary; each title receives a generous,
non-overlapping tap region.

Persistence failure leaves the previous valid ten selected and reports the
error through existing logging. Startup repair always restores ten configured
ids; the live palette may show fewer because today's logged ids are hidden.

## Verification

- Opening and closing preserves the same ten ids and positions.
- Every visible zone triggers its own happening, including overlapping visual
  areas.
- A happening can produce at most one addition per `dayKey`; duplicate taps and
  restored duplicate entries do not return it to the live field.
- After a pick, the selected zone disappears, remaining zones reflow, and the
  palette stays open until `×` or an outside tap.
- The chooser cannot save fewer or more than ten selections.
- Adding a custom happening adds it to the catalog, replaces the deterministic
  least-used visible item, and does not create a day entry.
- The replaced item remains available in the chooser.
- A palette with missing or unknown ids repairs deterministically on load.
- VoiceOver exposes all ten happenings and all three controls in a predictable
  order.
- The complete flow fits on an iPhone 17 without scrolling the palette itself.
- Simulator review covers iPhone 17 in light/dark accessibility settings,
  Dynamic Type, Reduce Motion, opening/closing, 10→9→8 reflow, chooser, creator,
  and outside-tap dismissal. Screenshots are compared against the approved
  `Living island` direction before the change is considered complete.

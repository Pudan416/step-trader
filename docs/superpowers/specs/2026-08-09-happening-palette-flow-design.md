# Happening Palette Flow

## Goal

Replace the scrolling cluster of separate happening blobs with one fixed,
single-screen palette. The palette always exposes ten activities, while the
full catalog and custom-activity creation remain one tap away.

## Interaction

### Closed

The canvas shows one circular `+` control above the tab bar. Tapping it expands
the happening palette in place. It is not presented as a separate system sheet.

### Open palette

One continuous, softly blended multicolor blob contains ten stable tap zones.
Each zone displays one happening title. Tapping a zone immediately adds that
happening to the current day and closes the palette.

The original `+` becomes the larger central `×`. Two smaller controls appear
beside it:

- Left: catalog/settings icon. Opens the happening chooser.
- Center: `×`. Closes the palette without adding anything.
- Right: `+`. Opens custom happening creation.

The controls form one compact horizontal group visually attached to the bottom
of the blob. The center control remains the strongest visual anchor.

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
- `HappeningChooserView`: searchable catalog checklist and ten-item validation.
- `HappeningCreatorView`: title input and creation action.
- `HappeningPaletteSelectionStore`: validates, repairs, orders, and persists the
  ten visible ids.
- Existing `HappeningStore`: continues to own the complete catalog and usage
  metadata.

The old daily ranking cache is retired; it conflicts with stable user-selected
positions.

## Accessibility and errors

Every blob zone is an accessibility button with the happening title. The three
controls have explicit labels: `Choose happenings`, `Close`, and
`Add a happening`. Panels support Dynamic Type and scrolling. The blob's visual
shape is not used as the hit-test boundary; each title receives a generous,
non-overlapping tap region.

Persistence failure leaves the previous valid ten selected and reports the
error through existing logging. The UI never renders fewer than ten zones after
startup repair.

## Verification

- Opening and closing preserves the same ten ids and positions.
- Every visible zone triggers its own happening, including overlapping visual
  areas.
- The chooser cannot save fewer or more than ten selections.
- Adding a custom happening adds it to the catalog, replaces the deterministic
  least-used visible item, and does not create a day entry.
- The replaced item remains available in the chooser.
- A palette with missing or unknown ids repairs deterministically on load.
- VoiceOver exposes all ten happenings and all three controls in a predictable
  order.
- The complete flow fits on an iPhone 17 without scrolling the palette itself.

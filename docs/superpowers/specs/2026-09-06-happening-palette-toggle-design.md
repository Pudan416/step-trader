# Happening Palette Toggle Design

Date: 2026-09-06  
Status: approved
Target: Canvas happening palette in the `Current Integrations` branch

## 1. Job and outcome

The palette is a persistent editor for the ten configured happenings, not a queue of unused items. A person opens it from Canvas to understand what each happening will look like, add it, see which happenings are already on today's Canvas, and remove an accidental addition without entering edit mode.

Success means:

- all ten configured happenings always remain in fixed slots;
- the first activation previews the exact future Canvas object;
- the second activation adds that object;
- an added item is unmistakably marked inside the palette;
- the same two-activation pattern safely removes an added item;
- palette rendering and transitions remain smooth on a physical iPhone.

The surface is an iOS **Operate** experience. Clarity of state and reversibility outrank decoration.

## 2. Selected interaction direction

The palette uses four mutually exclusive visual states per slot. Only one slot may be armed for addition or removal at a time.

### Available

- The slot is a neutral, translucent yellow sphere with a softer, more transparent centre and warmer yellow edges.
- All available slots use the same neutral material so they read as equal categories rather than ten preselected artworks.
- The happening name remains visible in the established fixed typography, with at most two lines.
- The final shape, colour, and material are already resolved and cached but are not revealed yet.

### Addition preview

- The first activation morphs the sphere into the exact production shape, colour, material, and grain that will be committed to Canvas.
- The preview rises slightly in depth and receives a restrained highlight. It does not fly toward Canvas.
- A stable liquid-glass instruction surface appears above the bottom controls. It contains the selected happening name and `Tap again to add to Canvas`.
- Activating a different slot cancels the old preview and previews the new slot.
- Closing the palette cancels an uncommitted preview.

### Added

- The second activation commits the exact previewed object.
- The slot stays in its original position and retains the committed silhouette.
- Its production material becomes strongly desaturated and slightly recessed, while remaining legible.
- A small liquid-glass check badge provides a non-colour status cue.
- The instruction surface briefly confirms `On Canvas`, then may settle away. The persistent desaturated silhouette and check remain.
- The palette stays open. The committed Canvas object becomes normally visible when the palette closes; no flight animation is shown while the palette is open.

### Removal preview

- The first activation of an added slot arms removal instead of adding a duplicate.
- The desaturated silhouette rises slightly, the check becomes a minus, and a restrained warm destructive edge appears.
- The instruction surface contains the happening name and `Tap again to remove from Canvas`.
- The second activation removes the Canvas object and its daily addition record, then returns the slot to the neutral available sphere.
- Activating another slot or closing the palette cancels removal preview without changing Canvas.

No modal confirmation is used. The first activation is the confirmation step, and the second performs the reversible intent.

## 3. Palette-level layout and chrome

- The palette always contains exactly the configured ten happenings in the established `3–2–3–2` arrangement.
- Adding or removing does not remove a slot and does not trigger grid reflow.
- The energy bar remains visible.
- The main tab bar is hidden while the palette is open.
- The list control remains in the bottom-left position and the rotated plus/close control remains in the bottom-right position.
- The contextual instruction surface occupies the stable space above those controls and never follows a selected shape through the dense cluster.
- The softened Canvas background and all palette artwork are rendered as one visual scene. A separate full-screen blur layer is not stacked over a second active renderer.

The list editor continues to configure which ten happenings occupy the slots. An added happening cannot be replaced in that editor until it is removed from today's Canvas; the editor explains this constraint instead of silently orphaning an object.

## 4. State and data model

The presentation model derives a slot's durable state from today's loaded `DayCanvas` using the happening `optionId`. `todayAdditions` remains synchronized bookkeeping for energy and cloud sync, but it is not an independent visual source of truth.

Each configured happening has one deterministic assignment for the current day:

- stable Canvas element UUID;
- exact production shape and silhouette seed;
- material and colour variant;
- eventual Canvas placement inputs.

The assignment is resolved once when the palette opens and is cached by day key, Canvas event identity, configured happening IDs, and colour nonce. It is recomputed only when one of those inputs changes.

Add and remove are symmetric transactions:

1. derive the proposed Canvas and daily-addition state;
2. persist the Canvas mutation;
3. commit the daily addition or removal and cloud-sync work;
4. publish the new palette state.

If persistence fails, neither side is committed. Add remains in addition preview; remove returns to the added state. Re-adding a removed happening on the same day clears its deletion tombstone before synchronization.

A happening is binary for a given day: absent or present. Usage ranking increments at most once per happening per day, so remove/re-add corrections cannot inflate frequency data.

Colour reroll affects only available assignments. An already-added Canvas object and its desaturated palette representation retain the persisted committed assignment.

## 5. Rendering and performance architecture

The palette is a mode of the existing `DayObjects` Metal renderer, not ten SwiftUI material stacks and not a second `MTKView`.

- The renderer receives a palette frame containing ten instanced actors and their fixed `3–2–3–2` positions.
- Available actors use the shared neutral sphere material.
- Addition preview swaps one actor to its resolved production silhouette and appearance.
- Added actors use the same silhouette with a renderer-level desaturation parameter; the SwiftUI layer owns text, badges, accessibility, and hit regions only.
- Shape morph, desaturation, removal arming, and slot-state transitions update actor data without rebuilding the scene, render pipelines, or textures.
- The background is rendered or cached once for the palette session and reused during interaction frames.
- Grain is applied once in the production display pass across the palette artwork, matching Canvas rather than using per-circle grain images.
- Interactive morphs run at a measured 60 fps target. The view returns to 30 fps or a static frame after settling.
- The underlying Canvas is not rendered as a second continuously active scene while the palette is open.

Performance is evaluated in both Debug and Release builds. Debug may remain slower, but it must still respond without multi-second loading or visibly stalled animation.

## 6. Motion and feedback

- Opening the palette transforms the bottom-right plus into close and reveals the palette scene without staggered per-item construction.
- Sphere-to-shape preview uses one cohesive morph and material bloom.
- Committing addition desaturates and gently settles the same slot; it never falls or travels to Canvas.
- Arming removal uses a subtle inward pulse and warm edge, not shaking or aggressive red flashing.
- Successful add and remove use distinct restrained haptics.
- With Reduce Motion, every morph becomes a short crossfade and no depth lift or pulse is used.

## 7. Accessibility and copy

Colour is never the only status signal:

- available: sphere and accessibility value `Available`;
- preview: exact silhouette, highlight, and `Preview — activate again to add`;
- added: desaturation, check badge, and `On Canvas`;
- removal preview: minus badge, warm edge, and `Activate again to remove`.

VoiceOver activation follows the same two-stage state machine and announces every state change. The second action must never be described as a system “double tap,” because that phrase conflicts with the VoiceOver activation gesture; spoken hints use “activate again.” Visible copy may use concise localized equivalents of `Tap again`.

Labels preserve the existing 15-character naming limit, consistent type size, and two-line maximum. All new strings are localized in Russian and English.

## 8. Failure and edge states

- A failed addition stays in preview and shows a localized non-blocking failure message.
- A failed removal restores the check-marked added state and shows a localized non-blocking failure message.
- Duplicate addition is impossible because an added slot enters removal preview.
- If Canvas and daily additions are inconsistent on load, Canvas wins and bookkeeping is reconciled before interaction.
- Day rollover closes the palette, cancels armed intent, and rebuilds all ten assignments for the new day.
- Leaving the Canvas tab closes the palette and cancels armed intent.
- The configured list may contain fewer than ten valid catalog records during recovery; missing slots use the existing catalog-repair path rather than blank interactive circles.

## 9. Verification

### State tests

- available → addition preview → added;
- added → removal preview → available;
- switching selection cancels the previous armed state;
- closing, tab departure, and day rollover cancel armed state;
- repeated rapid activation cannot produce duplicate commits.

### Persistence tests

- add and remove keep `DayCanvas`, `todayAdditions`, energy totals, local storage, and sync tombstones consistent;
- persistence failure leaves both stores unchanged;
- remove then re-add uses the stable identity without a stale deletion winning;
- usage ranking records at most one use per happening per day.

### Rendering tests

- addition preview GPU shape, material, colour variant, and silhouette seed equal the committed Canvas actor;
- an added palette actor retains shape while applying only the approved desaturation treatment;
- one global grain pass is present and per-circle SwiftUI grain is absent;
- neutral, preview, added, and removal states remain legible across representative light and dark materials.

### End-to-end and performance tests

- all ten slots remain visible after multiple add/remove cycles;
- the complete two-activation add and remove flows work with touch and VoiceOver;
- physical-device profiling covers palette open, morph, add, removal arming, and remove;
- interaction targets 60 fps without actor backlog drops, repeated render-target allocation, or a second active Metal renderer;
- final visual review uses the shipped iPhone classes and one Release installation, not simulator screenshots alone.

## 10. Explicit non-goals

- adding multiple copies of the same happening on one day;
- drag-and-drop from palette to Canvas;
- modal add or removal confirmation;
- removing or reflowing slots after a commit;
- per-item SwiftUI recreation of the production material;
- a second palette-specific Metal view;
- flight animations between palette and Canvas;
- changing the broader Canvas art direction, energy bar, or list-editor information architecture.

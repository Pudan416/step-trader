# Day Object Slot Collision And Sparse Admission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent arbitrary event IDs from collapsing onto identical Day Object routes and make 1–3 object scenes compositionally balanced without changing retained actors.

**Architecture:** Keep the ten preset-owned stable geometry slots, but separate a slot's topology phase from an actor-local identity offset. The identity offset follows an arbitrary event ID through every production route, while preset-specific admission order chooses balanced geometry for sparse scenes and never redistributes an existing actor.

**Tech Stack:** Swift, SwiftUI scene model, XCTest, Xcode iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-08-29-day-object-choreography-presets-design.md`

## Global Constraints

- A day owns one deterministic choreography preset and one stable set of ten geometry slots.
- Adding, removing, or reordering events must not change any retained actor's slot, route, material, colors, size role, or depth role.
- Arbitrary production-style event IDs that hash to the same geometry slot must not occupy an identical pose for the complete loop.
- Collision separation must preserve the selected shared formation; it may shift an actor along its existing route but may not create an unrelated local orbit.
- Sparse scenes must fill balanced positions first for double orbit, wave ribbon, and spiral procession.
- Motion remains smooth, closed, bounded, deterministic, and limited to ten actors.
- Preserve the unrelated working-tree edit in `StepsTrader/Localizable.xcstrings` exactly and never stage or commit it.

---

### Task 1: Separate actor identity phase and balance sparse admission

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify if required by the stored value: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`
- Test if render identity needs coverage: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `DayObjectChoreographyConfiguration.slot(eventID:rootSeed:)`, `DayObjectChoreographySlot`, `DayObjectMotionPlan.make(configuration:rootSeed:eventIDs:)`, and production `DayObjectPose` evaluation.
- Produces: a separately named stable actor-local identity/collision phase, plus preset-specific sparse admission order that leaves the ten canonical geometry slots intact.

- [ ] **Step 1: Add failing production-pose collision tests**

  Add helpers that find two arbitrary non-`event-N` IDs mapping to the same canonical ordinal. For multiple representative seeds of every preset, build real `DayObjectMotionPlan`/scene poses and prove the colliding actors do not have equal routes and do not occupy equal positions at several loop times. Include the known `rootSeed == 77`, `radialBloom`, `uuid-like-0-x` / `uuid-like-2-x` counterexample as a literal regression.

  ```swift
  func testArbitraryIDsSharingCanonicalSlotKeepDistinctProductionPoses() throws {
      let configuration = DayObjectChoreographyConfiguration.make(seed: 77)
      XCTAssertEqual(configuration.preset, .radialBloom)
      let ids = ["uuid-like-0-x", "uuid-like-2-x"]
      XCTAssertEqual(
          configuration.slot(eventID: ids[0], rootSeed: 77).ordinal,
          configuration.slot(eventID: ids[1], rootSeed: 77).ordinal
      )

      let plan = DayObjectMotionPlan.make(
          configuration: configuration,
          rootSeed: 77,
          eventIDs: ids
      )
      XCTAssertNotEqual(plan.routes[ids[0]], plan.routes[ids[1]])
  }
  ```

  The tests must exercise real routes/poses, not merely compare stored phase fields. Before implementation, name the mutation caught: setting the actor-local identity phase to zero in any route branch must make at least one test fail.

- [ ] **Step 2: Run the collision tests and verify RED**

  Run the new named tests with `xcodebuild test` against `Steps4Tests/DayObjectChoreographyTests`. Confirm they fail because the two routes/poses are identical, not because of fixture or simulator setup.

- [ ] **Step 3: Add failing sparse-admission tests**

  Across multiple representative seeds, build actual production scenes for `.doubleOrbit`, `.waveRibbon`, and `.spiralProcession` at counts `1`, `2`, `3`, and `5` using retained IDs. Assert observable composition:

  - double orbit's first two actors occupy different rings and substantially separated angles rather than one ray;
  - a one-ribbon wave fills center/opposed longitudinal positions before adjacent points, while two ribbons do not begin at the same endpoint;
  - spiral procession samples inner/middle/outer spatial roles early rather than admitting consecutive core points;
  - rebuilding after add/remove/reorder keeps each retained actor's full slot and route unchanged.

  Use hand-derived geometric thresholds and actual poses. Do not compute expected positions through production slot builders.

- [ ] **Step 4: Run sparse tests and verify RED**

  Run the new named sparse tests and confirm the current consecutive admission order produces the expected failures.

- [ ] **Step 5: Implement the minimal separation and admission fix**

  Introduce a dedicated stable actor-local identity offset on `DayObjectChoreographySlot` (or an equivalent explicitly separated value). Canonical `event-N` slots retain zero identity offset. Arbitrary IDs derive a deterministic bounded offset from their full stable hash. Every preset route must consume the offset as progress along that preset's existing shared path, including circular choir, double orbit, radial bloom, spiral procession, and constellation; do not distort the shared topology or use an unrelated local loop.

  Define explicit admission-to-geometry mappings for double orbit, one/two wave ribbons, and spiral procession. Geometry membership, direction, group speed, size, and depth stay attached to the chosen canonical geometry slot. Reordering the admission list must not depend on current event count.

- [ ] **Step 6: Verify GREEN and compatibility**

  Run the new collision and sparse tests, then all `DayObjectChoreographyTests`, `DayObjectSceneTests`, `DayObjectPaletteTests`, and `DayObjectRenderFrameTests`. Run the full `Steps4Tests` target and an iOS Simulator build. Confirm finite/bounded poses, loop position/tangent continuity, exact ten-actor capacity, and unchanged retained routes.

- [ ] **Step 7: Commit and report**

  Commit only the in-scope implementation and tests. Record the RED commands/results, GREEN commands/results, full-suite result, build result, files, commit hash, and any concern in the task report. Leave `StepsTrader/Localizable.xcstrings` unstaged.

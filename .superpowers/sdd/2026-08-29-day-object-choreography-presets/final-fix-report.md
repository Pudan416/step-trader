# Day Object Choreography Presets — Final Fix Report

## Status

Complete. Every Critical and Important item in `final-review-findings.md` is
implemented and verified. The focused choreography suites, full `Steps4Tests`
target, and iOS Simulator build all pass.

## Commits

- `79177b41d088c320d5afc20b2f6b1a3e3223b14d` —
  `fix(day-objects): unify choreography presets`
- The report itself is committed separately after this implementation commit.

## Files changed

Production:

- `StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectPaletteSet.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`

Tests:

- `Steps4Tests/DayObjectChoreographyTests.swift`
- `Steps4Tests/DayObjectPaletteTests.swift`
- `Steps4Tests/DayObjectSceneTests.swift`
- `Steps4Tests/DayObjectRenderFrameTests.swift`

Report:

- `.superpowers/sdd/2026-08-29-day-object-choreography-presets/final-fix-report.md`

`StepsTrader/Localizable.xcstrings` was not edited or committed. Its preserved
working-tree SHA-256 at handoff is
`8b8c88563178e06981fdcd39165ad1f8522024371eb77afc75e73a978e1c242d`.

## Findings addressed

### Critical 1 — coherent shared formations

- Replaced generic anchors, five pair groups, and 3×3 sector projection with
  preset-owned topology and stable slots.
- Added daily topology/configuration for shared center/orientation, ring,
  stream, ribbon, grid, cluster, direction, bounded speed ratio, size role,
  and depth role.
- Implemented production routes for all ten named formations: circular choir,
  double orbit, radial bloom, breathing grid, wave ribbon, spiral procession,
  eclipse stack, cross currents, constellation, and depth field.
- Production poses now consume the preset routes directly. Reserved-region
  handling uses one shared affine transform for the whole formation rather
  than per-actor sector remapping.

### Critical 2 — legacy motion mixing removed

- Removed `DayObjectChoreographyFamily` selection and pose behavior.
- Removed production encounter centers and `.softEncounters` influence.
- `DayObjectChoreographyScore` and `DayObjectMotionPlan` now share the exact
  scene `DayObjectChoreographyConfiguration`.
- Removed unused actor-local legacy speed ratios; preset group speed ratios now
  control ring/stream periods coherently.
- Eclipse overlap and depth exchange are owned by the eclipse preset.

### Important 1 — list-independent retained appearance

- Palette choice and one-to-three-color subset are derived actor-locally from
  root seed plus event ID.
- Adding, removing, or reordering arbitrary IDs no longer rebalances a retained
  actor between primary and secondary palettes.
- Added adversarial add/remove/reorder coverage over multiple seeds, including
  preferred-primary insertion counterexamples at allocator, scene, and render
  levels.

### Important 2 — exact material compatibility

- Implemented the authoritative preferred-preset matrix with weight `3` for a
  preferred pairing and `1` otherwise.
- Added a direct exhaustive test over every material/preset pair.
- All actors in one day still inherit one material family.

### Important 3 — preset-specific size and depth

- Uniform presets use one narrow medium band and flat focus.
- Double orbit uses two closely related medium sizes.
- Cross-current size/depth groups follow stream membership.
- Spiral, eclipse, and constellation use bounded preset-owned groups.
- Eclipse foreground actors grow and soften with depth while exchanging
  front/back order.
- Only depth field uses independent migrating depth and the routine extreme
  full-canvas spatial range, clamped to the approved `0.12...0.74` diameter.
- Non-full-canvas scenes retain their existing small render cap and all
  formations retain footprint/exclusion safety.

### Important 4 — production-pose tests and cleanup

- Replaced masking sector/count assertions with multi-seed tests against actual
  production poses for every named formation.
- Tests prove ring centers/directions, two cross-current streams, travelling
  ribbon order, real grid rows, shared bloom opening, spiral ordering, eclipse
  cluster/depth exchange, constellation cluster retention and six-plus actor
  vertical coverage, and depth-field size/depth/focus behavior.
- Preserved deterministic event identity, actor-local route/slot stability,
  bounded motion, loop position continuity, and loop tangent continuity.
- Removed the test-only two-argument `DayObjectVisualLanguage.make` overload
  and migrated every caller to explicit choreography.
- Updated render acceptance checks and perceptual signatures for the coherent
  formations; removal comparisons now ignore only the frame-local GPU buffer
  index while still comparing complete semantic actor state.
- Migrated one stale production-shape ABI assertion to the established daily
  sphere grammar; separate tests continue to cover every circle-derived enum
  value and numeric shader ABI.

## Verification

### Focused scene, choreography, and palette suites

```sh
set -o pipefail
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  | tee /tmp/day-object-scene-choreo-palette-final.log
```

Result: **PASS** — 79 tests, 0 failures, 89.141 seconds (89.165 seconds
including suite overhead).

### Focused render-frame suite

```sh
set -o pipefail
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  | tee /tmp/day-object-render-full.log
```

Result: **PASS** — 79 tests, 0 failures, 256.656 seconds (256.683 seconds
including suite overhead).

### Full `Steps4Tests`

```sh
set -o pipefail
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 \
  | tee /tmp/steps4tests-final-green.log \
  | rg --line-buffered \
    "(Test Suite '.*(started|passed|failed)|error: -\\[|Executed [0-9]+ tests|\\*\\* TEST)"
```

Result: **PASS** — 964 tests, 1 intentionally skipped, 0 failures,
363.605 seconds (363.942 seconds including suite overhead). The existing skip
is `AppGroupRMWConcurrencyTests.testConcurrentReadModifyWrite_losesUpdates`,
whose source explicitly defers that unrelated §5.2 fix.

### iOS Simulator build

```sh
set -o pipefail
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 \
  | tee /tmp/steps4-simulator-build-final.log \
  | rg --line-buffered "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"
```

Result: **PASS** — `** BUILD SUCCEEDED **`.

### Static audit

- `git diff --check`: pass, no whitespace errors.
- Production search for `DayObjectChoreographyFamily`, `softEncounters`,
  encounter state, and legacy motion-family selection: no matches.
- Search for the two-argument `DayObjectVisualLanguage.make`: no matches.
- `StepsTrader/Localizable.xcstrings`: remains the sole unrelated dirty file
  after the implementation commit and is not staged.

## Remaining concerns

No known in-scope correctness or verification concerns remain. The only full
suite skip and the pre-existing localization working-tree change are unrelated
to this choreography wave and were deliberately left untouched.

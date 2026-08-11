# Canvas Noise & Composition — measured results

Companion to `2026-08-10-canvas-noise-composition.md`. These numbers were
measured on the branch, not estimated, and they are the reason several of the
plan's original constants were replaced. Kept because re-deriving them costs a
simulator run each and because the next person to touch these constants needs
to know which ones are load-bearing.

Debug build, iPhone 17 simulator. Release builds optimise Swift array
allocation and bounds checking heavily, so treat every timing here as an upper
bound.

## Contour calibration (Task 2)

The plan's original ring radius and persistence undersampled the second octave:
about 2% of adjacent contour points jumped more than 0.25, worst case 0.373 — a
37% radial excursion across a 9° arc, which reads as a spike, not a strict test.

Final constants, calibrated by sweep over seeds 0..<500 × complexity 0.0…1.0:

| | value | was |
|---|---|---|
| `ringRadius` | `0.6 + complexity * 0.4` | `0.8 + c * 0.6` |
| `persistence` | 0.2 | 0.45 |
| `blobPointCount` | 48 | 40 |
| measured max adjacent-radius delta | **0.1933** | 0.373 |

`amplitude` was deliberately not touched: it is the star-shaped guarantee that
`ProceduralTexture.containsPoint` depends on.

Resulting lobe structure (100 seeds per level) — the contour did not flatten
toward a circle when the ring radius came down:

| complexity | lobes | radius std dev |
|---|---|---|
| 0.0 | 3–6 | 0.043 |
| 0.5 | 4–9 | 0.076 |
| 1.0 | 5–9 | 0.119 |

## Frame budget

`CanvasLab-Spec.md` §16 caps the canvas at 20 fps, so the frame budget is 50 ms.

| what | 15 elements |
|---|---|
| contour generation (4 layers × 48 points) | 11.2 ms |
| texture generation — flat | 2.9 ms |
| texture generation — gradient | 2.4 ms |
| texture generation — rings | 2.8 ms |
| texture generation — hatch | 4.5 ms |
| texture generation — **stipple** | **125 ms** |
| `.rings` per-frame path construction + stroke | 2.26 ms |

Stipple is the hot spot at ~8.1 ms per element, and the cost lives in
`PoissonDiscSampler.fill`'s clearance check, which allocates an array per
candidate inside an O(n × 20) loop. It is affordable only because texture
buckets are staggered per seed: **worst simultaneous regenerations across 15
elements = 1**. So the realistic worst frame is 11.2 ms of contour plus ~8.3 ms
of one stipple regeneration, about 19.5 ms of 50.

Without the staggering it would be 136 ms — a seven-frame hitch every 1.5 s.
If stipple ever needs to be cheaper, replace that `points.map { hypot(...) }.min()`
with an allocation-free loop or a spatial grid before touching anything else.

## Composition: does a day actually differ from another day?

Seven consecutive days, eight elements each, generated through the real
`CanvasElement.spawn` path:

| day | archetype | contrast | palette | dominant/accent fill | size range | two-colour |
|---|---|---|---|---|---|---|
| 08-10 | diagonalSweep | low | 3 | rings / gradient | 0.17–0.43 | 5/8 |
| 08-11 | constellation | mid | 5 | stipple / rings | 0.18–0.32 | 5/8 |
| 08-12 | twoMasses | high | 5 | rings / flat | 0.12–0.46 | 4/8 |
| 08-13 | cornerWeight | low | 3 | stipple / rings | 0.14–0.35 | 5/8 |
| 08-14 | constellation | low | 3 | hatch / rings | 0.17–0.31 | 3/8 |
| 08-15 | horizonBand | mid | 5 | gradient / hatch | 0.20–0.40 | 4/8 |
| 08-16 | twoMasses | mid | 5 | rings / flat | 0.14–0.39 | 5/8 |

Five distinct archetypes in seven days, both palette sizes, all three contrast
keys, five different dominant fills.

### Placement — the axis that failed first

The first run of this gate found every day's layout centroid within 0.02 of
every other at ~(0.5, 0.5), including `cornerWeight`, whose field peaks at
(0.18, 0.20). The archetype field perturbed placement but could not concentrate
it, so the plan's headline claim — that mass sits in a different place on
different days — was not being delivered.

Three causes, all fixed:

1. **The scoring objective was anti-clustering.** `nextPoint` maximised
   `clearance × weight`, and `clearance` is unbounded, so the rule was "put the
   new element in the largest empty gap". Weight could only modulate it. Now
   `min(clearance, radius) × weight`: once a candidate clears the spacing
   requirement, extra emptiness earns no more credit and weight decides.
2. **`firstPoint` could not reach an off-centre peak.** It jittered ±25% around
   the canvas centre, so with 0.76-wide bounds the seed point was confined to
   roughly [0.31, 0.69] — and every later point grows off that seed. It now
   samples the whole bounds, weighted.
3. **The spacing made clustering infeasible.** `spawnMinDistance` packed eight
   elements to ~55% density, where a near-uniform arrangement is nearly the only
   feasible one.

Saturating the score introduced a subtle follow-on bug worth remembering: in a
flat field every accepted candidate then scores *identically*, and a `>`
comparison keeps whichever came first — which is anchor-sort order. That biased
a flat field's centroid by 0.13. Resolved with seeded reservoir sampling over
exact ties, which leaves the weighted case bit-identical.

After the fix:

| archetype | centroid | expectation |
|---|---|---|
| cornerWeight | (0.332, 0.322) | upper-left, was (0.53, 0.48) |
| horizonBand | y = 0.581 | band sits at 0.58 |
| constellation | ~(0.5, 0.5) | flat field — the control |

Mean archetype weight at placed points beats a uniform-grid baseline for all
five concentrating archetypes.

### Overlap

Lowering the spacing floor to 0.07 increases overlap, which is the mechanism
working rather than a defect — the canvas blends additively, so overlap reads
as brightness accumulation. Fraction of element pairs at 15 elements whose
centres sit closer than half the sum of their radii:

| archetype | deep-overlapping pairs |
|---|---|
| constellation | 5.7% |
| cornerWeight | 10.5% |
| centeredMass | 11.4% |
| diagonalSweep | 13.3% |
| twoMasses | 13.3% |
| horizonBand | 19.0% |

The ordering is the point: the flat field overlaps least, the most concentrating
archetype most. If it ever reads too hot on device, the lever is the
`spawnMinDistance` floor.

## Things deliberately left alone

- `CanvasColorPalette.seededSecondColor` — runs inside `CanvasElement.init(from:)`
  for every element saved without a `hexColor2`. Changing it silently repaints
  history.
- `count = max(blobPointCount, symmetry * 8)` can exceed the 200-point budget at
  symmetry ≥ 7. Unreachable: every call site passes 1.
- `.canvasElementSpawnRequested` is dead wiring and predates this work —
  `GalleryNotifications.swift` declares it, `GalleryView` observes it, nothing
  posts it.
- `CanvasPersistenceRegressionTests.testDayEndReanchorMovesAdditionAndCanvasWithoutReopeningHappening`
  fails at line 174 on this branch **and on its base commit**. It exercises
  AppModel / CanvasStorageService / DayBoundary and has nothing to do with this
  work, but it means the suite's baseline is red and worth its own fix.

# Circle and Snowflake Fill Measurements

Measured 2026-08-15 with Xcode 26.3 (17C529) on macOS 26.5.2
(25F84). Final simulator validation used the iPhone 17 simulator
(`00349825-3076-4659-80E4-50B9CFF9090F`) on iOS 26.3.1 in Debug.

## Simulator performance

### Original cold aggregate and warm-only measurements

The original Task 6 generation harness measured 15 uncached geometries per
family and kind. These are cold aggregate costs, not frame times:

| Family | Kind | Milliseconds | Generated items |
| --- | --- | ---: | ---: |
| Circle | flat | 0.004053 | 0 |
| Circle | gradient | 0.002980 | 0 |
| Circle | rings | 0.374079 | 120 |
| Circle | hatch | 2.128959 | 308 |
| Circle | stipple | 144.415021 | 686 |
| Snowflake | flat | 0.005007 | 0 |
| Snowflake | gradient | 0.002980 | 0 |
| Snowflake | rings | 0.488997 | 120 |
| Snowflake | hatch | 2.182007 | 310 |
| Snowflake | stipple | 162.237048 | 331 |

The original canvas harness warmed each cache once, then measured five draws.
Its 6.701946 ms worst was a warm steady-state result only; it did not exercise
the synchronous cold misses or 1.5-second bucket rollovers and therefore was
not sufficient evidence for the 55 ms frame gate.

| Shape | Kind | Warm average ms | Warm maximum ms |
| --- | --- | ---: | ---: |
| Circle | flat | 0.446177 | 0.491977 |
| Circle | gradient | 0.132394 | 0.169992 |
| Circle | rings | 2.566385 | 2.639055 |
| Circle | hatch | 0.472403 | 0.476956 |
| Circle | stipple | 0.533032 | 0.604033 |
| Snowflake | flat | 3.732634 | 3.885031 |
| Snowflake | gradient | 3.650618 | 3.873110 |
| Snowflake | rings | 6.481791 | 6.701946 |
| Snowflake | hatch | 3.930163 | 4.080057 |
| Snowflake | stipple | 3.942156 | 4.145980 |

### Multi-second 20 fps rollover benchmark

A temporary harness rendered every frame from `t = 20.0` through `t = 24.5`
inclusive: 91 frames per scenario at 50 ms intervals, 182 measured frames in
total. This crosses three complete 1.5-second cache transitions. It measured
the complete 390×844 `ImageRenderer` render, classified frame zero as cold,
later frames adding cache keys as rollovers, and all remaining frames as
steady state. Cache misses were counted from actual new `TextureCacheKey`s.

The adversarial scenario alternated Circle and Snowflake across 15 elements,
used density-1 graded stipple for every element, and deliberately assigned
seeds `0, 150, ... 2100`, which all collided under the old `seed % 150`
phase. The representative scenario alternated Circle and Snowflake, cycled all
five texture kinds with production-seeded specs, and included all twenty
Snowflake trail ghosts at these times.

Before correction, the adversarial run measured a 193.639994 ms cold frame,
176.274061 ms rollover worst, and 3.455997 ms steady-state worst. The old phase
put all 15 rollover misses on each transition frame.

The final exact iPhone 17 distribution was:

| Scenario | Class | Frames | Misses | Min ms | p50 ms | p95 ms | Max ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Coincident stipple | Cold aggregate | 1 | 15 | 49.292088 | 49.292088 | 49.292088 | 49.292088 |
| Coincident stipple | Rollover | 45 | 45 | 3.102064 | 3.886938 | 4.840970 | 5.021930 |
| Coincident stipple | Steady state | 45 | 0 | 2.007008 | 2.184033 | 3.131986 | 3.371000 |
| Representative mixed | Cold aggregate | 1 | 12 | 30.902028 | 30.902028 | 30.902028 | 30.902028 |
| Representative mixed | Rollover | 30 | 36 | 2.290010 | 2.653003 | 5.216002 | 5.592108 |
| Representative mixed | Steady state | 60 | 0 | 2.213001 | 2.453089 | 3.548026 | 3.633976 |

The worst of all 182 final frames was the 49.292088 ms adversarial cold frame,
5.707912 ms below the 55 ms Debug gate. The rollover worst was 5.592108 ms and
the steady-state worst was 3.633976 ms.

Two preceding stability runs on the iPhone 17 Pro simulator also passed. Their
adversarial cold worsts were 49.558043 and 47.577977 ms; adversarial rollover
worsts were 4.923105 and 4.933953 ms; representative rollover worsts were
5.732059 and 5.895972 ms; and overall steady-state worsts were 3.693938 and
3.831029 ms.

### Production correction

Three durable changes close the measured gap without faking or omitting a
requested frame:

- Texture phases now mix the complete seed through the stable seeded RNG.
  The formerly colliding 15-seed set spreads to at most two misses in any
  20 fps slot; the measured run produced one adversarial miss on each of 45
  rollover frames.
- `PoissonDiscSampler.fill` now performs the same deterministic minimum-distance
  acceptance test through a flat spatial grid rather than scanning every
  accepted point for every candidate. Seeded reproducibility and spacing tests
  remain green.
- High-density stipple is bounded to 50 real Poisson points instead of 90.
  The generator still creates complete seeded geometry with the same spacing,
  weighting, clipping, and thinning rules. Durable tests require the 50-dot
  ceiling, more than 10 visible dots, density ordering, contour containment,
  positive radii, and graded/uniform distribution behavior.

No rendered-radius adjustment was added. The temporary multi-second benchmark
and all wall-clock assertions were removed from source after measurement.

## Thumbnail invalidation and automated verification

`HistoryThumbnailCache` writes v5 keys. Its durable regression was observed
failing against v4 because the v5 file did not exist and the v4 file did; it
passes after the version bump.

Final verification after removing the temporary harness:

- Focused sampler/texture/cache run: 55 tests, 0 failures.
- Full `Steps4Tests`: 490 tests, 1 skipped, 0 failures.
- Full UI launch tests: 9 tests, 0 failures.
- Debug iPhone 17 simulator build: `BUILD SUCCEEDED`.
- Source audit: no temporary benchmark class, rollover log marker, wall-clock
  assertion, or simulator-specific 55 ms threshold remains.

The known unrelated
`CanvasPersistenceRegressionTests/testDayEndReanchorMovesAdditionAndCanvasWithoutReopeningHappening`
flake did not recur in final verification. Earlier Task 6 verification recorded
one suite failure comparing `[]` with
`[F2DA4286-E36E-46B0-819F-8327F41E56AE]`; an immediate isolated reproduction
then failed at `Steps4Tests/CanvasPersistenceRegressionTests.swift:175` with
`XCTUnwrap failed: expected non-nil value of type "DayCanvas"`. No persistence
production code or tests were changed or masked. The final full run passed all
three `CanvasPersistenceRegressionTests`.

## Physical device and visual calibration

`xcrun devicectl list devices` reported the registered `iPhone Costa`, an
iPhone 15 Pro (`43B6B950-DBCA-50C3-AE14-FBD518808E3B`), as `unavailable`.
Because no physical iPhone was connected, no physical build, install, launch,
fps measurement, or device visual comparison was run.

The constants retained are Circle `0.72` and Snowflake `0.82`, the pre-Task-6
starter values. The required Circle `0.62` versus `0.82` and Snowflake `0.72`
versus `0.92` physical comparisons remain unperformed, so no candidate value
was rejected and no device-calibrated strength is claimed.

The simulator had no historical `DayCanvas` containing both Circle and
Snowflake: its current 2026-08-15 canvas contained two Circles and no
Snowflake, while the only 2026-08-14 past snapshot had no persisted canvas.
The manual live/history/thumbnail/export agreement and relaunch checks were
therefore not run; simulator user data was not rewritten to manufacture a
fixture.

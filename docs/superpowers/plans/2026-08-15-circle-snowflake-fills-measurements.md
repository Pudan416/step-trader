# Circle and Snowflake Fill Measurements

Measured 2026-08-15 with Xcode 26.3 (17C529) on macOS 26.5.2
(25F84). The simulator destination was the booted iPhone 17 simulator
(`00349825-3076-4659-80E4-50B9CFF9090F`) running iOS 26.3.1. The app and
tests used the Debug configuration.

## Simulator performance

The temporary Task 6 harness rendered at 390×844 points with 15 elements per
case. Snowflakes were rendered at `t = 20`, including all twenty existing
trail-ghost slots. Each draw result is five measured `ImageRenderer` renders
after one warm-up render.

### Geometry generation for 15 elements

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

The 55 ms cold-generation assertion applies to every kind except stipple; all
asserted cases passed. Stipple's cold 15-element batch is intentionally
ungated. Its warmed, phased-cache draw result is included below.

### Canvas draw time

| Shape | Kind | Average ms | Maximum ms |
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

The worst measured frame was Snowflake rings at 6.701946 ms, 48.298054 ms
below the 55 ms Debug simulator gate. No radius-based density or ring-count
adjustment was made. The complete temporary performance class was removed
after measurement.

## Thumbnail invalidation and automated verification

`HistoryThumbnailCache` now writes v5 keys. The durable regression test was
observed failing against v4 because the v5 file did not exist and the v4 file
did; after the bump, the focused test passed with 1 test and 0 failures.

Fresh verification after removing the harness:

- Debug iPhone 17 simulator build: `BUILD SUCCEEDED`.
- Full `Steps4Tests`: 487 tests executed, 1 skipped, 0 failures,
  `TEST SUCCEEDED`.

The known unrelated
`CanvasPersistenceRegressionTests/testDayEndReanchorMovesAdditionAndCanvasWithoutReopeningHappening`
failure reproduced before Task 6 changes. The initial full run executed 486
tests with 1 skipped and 1 failure; its assertion compared `[]` with
`[F2DA4286-E36E-46B0-819F-8327F41E56AE]`. An immediate isolated reproduction
failed at `Steps4Tests/CanvasPersistenceRegressionTests.swift:175` with
`XCTUnwrap failed: expected non-nil value of type "DayCanvas"`. No persistence
code or test was changed. The same suite passed in the fresh final run above.

## Physical device and visual calibration

`xcrun devicectl list devices` reported the registered `iPhone Costa`, an
iPhone 15 Pro (`43B6B950-DBCA-50C3-AE14-FBD518808E3B`), as `unavailable` at
both device checks. Because no physical iPhone was connected, no physical
build, install, launch, fps measurement, or device visual comparison was run.

The constants retained in this build are Circle `0.72` and Snowflake `0.82`,
the pre-Task-6 starter values. The required Circle `0.62` versus `0.82` and
Snowflake `0.72` versus `0.92` physical comparisons were not run, so no
candidate value was rejected and no device-calibrated strength is claimed.

The simulator had no historical `DayCanvas` containing both Circle and
Snowflake: its current 2026-08-15 canvas contained two Circles and no
Snowflake, while the only 2026-08-14 past snapshot had no persisted canvas.
Therefore the manual live/history/thumbnail/export agreement and relaunch
checks were not run; simulator user data was not rewritten to manufacture a
fixture.

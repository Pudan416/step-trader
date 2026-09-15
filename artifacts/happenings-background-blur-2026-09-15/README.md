# Soft canvas backdrop while choosing happenings

A native UIVisualEffectView with systemUltraThinMaterial, blended at 50%, appears between the canvas and happening picker. Its visibility fades over 0.2 seconds when opening or closing the picker. The effect softens the canvas and its objects while labels, picker artwork and controls remain sharp. Both Frequent and All share the same backdrop.

Native backdrop sampling is necessary because SwiftUI raster blur omits the CAMetalLayer canvas. A fractional property animator was also evaluated, but keeping it paused blocked UI-test quiescence, and finishing at the current position removed its effect. Neither approach remains in the implementation. The shipped version uses a standard, fully configured material with no retained animator.

Validation: two existing UI scenarios passed for Health/canvas selection across modes and stationary canvas pixels while panning. Simulator captures were visually inspected: canvas visible and softened, picker and chrome sharp. Matching pixel patches against the unblurred baseline show reduced canvas texture contrast; the chrome patch is identical. Result: /tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_19-57-13-+0200.xcresult.

Screenshots are from the simulator. Physical-device installation and launch are recorded separately; no physical-device visual verification is implied. Feature branch codex/happenings-field; no integration publication.

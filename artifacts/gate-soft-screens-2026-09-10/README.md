# Nowhere gate screens — soft colors

Captured from the implementation at commit 146d7411 using an iPhone 17 simulator.

- `03-paygate.png`–`06-paygate-alternative.png`: real screenshots of production PayGateView with temporary fixture data (32 colors, 2 colors, and a day boundary 23 minutes ahead).
- `01-shield.png`, `02-shield-notification.png`: SwiftUI reconstructions of the system-owned Screen Time layout, with the real bundled artwork. These are not screenshots of an actual iOS shield.
- `01-flow.png`, `02-paygate-states.png`: contact sheets of the unedited screenshots.

All artwork uses the approved soft side-light material and varied colors. Seed 1 (pink clover) for both shield states and the corresponding PayGate; seed 2 (lime windflower), 3 (lavender snowflake), 4 (peach soft square) for the other PayGate examples. In normal use the artwork is random and independent of the balance.

The screenshot fixture was applied only for the local simulator build and restored afterward. It does not change production behavior. Fixture source is in `artifacts/gate-native-review-2026-09-10/ScreenshotFixture.swift`.

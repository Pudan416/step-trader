# Readable Canvas hints — 13 September 2026

Morning/evening nudges and the add-step coach mark now point to the measured + button. The row publishes its actual bounds; the bubble derives its horizontal placement from that anchor and measures text height, so larger type grows upward without moving the pointer. Hidden controls do not leave a hint behind.

The bubble uses an opaque daily chrome surface with contrasting text and a continuous outlined tail. All coach-mark cards use the same opaque palette and stronger, non-italic text. Existing wording, timing and tour navigation are preserved.

Validation: 22 focused tests passed (geometry, every catalog palette's contrast, Canvas overlay routing and coach-tour behavior). The geometry regression failed against the old centered layout before the fix. Five simulator-hosted native component captures were inspected at 320pt, 393pt, 852pt, and accessibility3 text size; these are component fixtures, not screenshots of the physical phone. A second batched capture confirmed the continuous tail and dark-background outline.

The temporary screenshot harness is retained as `ScreenshotFixture.swift.txt` for reproduction; it is not part of the XCTest suite. Full logs and xcresults: `/tmp/nowhere-hint-validation`.

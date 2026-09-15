# Subtle square shape and daily tint

Happening targets use a superellipse with exponent 2.2: a small step from a circle (2) toward a soft squircle (4). Width, height, spacing and name typography are unchanged. Contours stay aligned with the field, regardless of the randomly assigned figure rotation. SwiftUI hit areas follow the same contour.

The light translucent fill mixes in 10% of the interface accent resolved from the saved scene background colors. The tone stays stable during scrolling; the day background remains visible through the fill. Native and fallback Metal renderers share the contour and fill helper. Selected figures retain their existing material and morph behavior.

## Verification

- Steps4 app and embedded extensions built for the simulator.
- 126 rendering/state tests and both UI tests passed in the initial run. One existing GPU test had two stale opacity bounds (the previous implementation already used 0.72 center alpha); its expectations were corrected and the test passed on rerun. No failing checks remain.
- UI checks cover diagonal scrolling, selection persistence and the largest Dynamic Type size. Initial, scrolled and large-type screenshots were visually inspected.
- Initial result: `/private/tmp/nowhere-happenings-field-dd/Logs/Test/Test-Steps4-2026.09.14_23-00-43-+0200.xcresult`.
- Corrected test rerun: `/private/tmp/nowhere-happenings-field-dd/Logs/Test/Test-Steps4-2026.09.14_23-06-53-+0200.xcresult`.
- Nowhere Catalog QA simulator, iOS 26.3, 402 × 874 points. No physical-device installation or remote publication.

## Screenshots

- [Initial field](happenings-field-start.png)
- [After diagonal scrolling](happenings-field-diagonal.png)
- [Added happening](happenings-field-added.png)
- [Largest text size](happenings-field-large-type.png)

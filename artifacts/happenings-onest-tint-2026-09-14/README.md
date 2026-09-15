# Onest titles and visible daily tint

Happening titles use Onest Semibold again. The shared native/fallback fill now mixes 38% of the already-lightened daily interface accent in linear light, up from 10%. This produces a visible pastel tint after display transfer and grain, while preserving opacity, the near-circular superellipse, and black text.

The GPU contrast/morph test passed after the tint adjustment. Both UI tests passed on the final build: diagonal scrolling and selection persistence, plus largest Dynamic Type. Screenshots were inspected at normal and large text sizes.

Simulator: Nowhere Catalog QA, iOS 26.3, 402 × 874 points. No physical-device installation or remote publication.

- Tint/GPU result: `/private/tmp/nowhere-happenings-field-dd/Logs/Test/Test-Steps4-2026.09.14_23-44-57-+0200.xcresult`.
- Final UI result: `/private/tmp/nowhere-happenings-field-dd/Logs/Test/Test-Steps4-2026.09.14_23-46-44-+0200.xcresult`.

[Initial field](happenings-field-start.png) · [Scrolled](happenings-field-diagonal.png) · [Added](happenings-field-added.png) · [Large text](happenings-field-large-type.png)

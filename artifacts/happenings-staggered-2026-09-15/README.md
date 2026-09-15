# Centered staggered happening field

The field now has seven alternating rows, 4–5–4–5–4–5–4. `Listened` is the 31st built-in so the requested layout is symmetric. The original identifiers and saved usage remain intact. Partial rows and extra custom choices keep non-overlapping targets.

Opening or reopening starts at the centre of the full arrangement. Row and column offsets are symmetric, and native scrolling uses a centre anchor.

The lag came from two independently updated surfaces: labels scrolled natively, while a viewport-sized Metal view outside the scroll container waited for a SwiftUI offset update and another rendered frame. The complete field artwork and labels now share one scroll-content transform. Scroll positions are no longer relayed through GalleryView state. Existing rendered pixels move immediately with labels, even when Metal is paused. The field's background travels with this common surface.

## Verification

- A new geometry regression failed on the previous grid (row pattern and centre), then passed after the change.
- 127 unit/integration checks passed, covering layout, synchronous scroll movement, catalogue migration, history, selection and rendering presentation.
- Four UI scenarios passed: centred staggered field, diagonal scroll/select/reopen, largest Dynamic Type, seven accessible rows, and preview/add/removal states. The main scroll test also cleans up its domain addition so hosted unit tests can run afterward without shared-state contamination.
- A UIKit-hosted regression checks that the artwork is inside the scroll view and moves by the exact offset immediately, without a SwiftUI update or Metal frame.
- Normal and large-text screenshots inspected. Native video frames during the swipe were inspected; labels remained centred on their targets.
- Unit result: `/private/tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_01-13-15-+0200.xcresult`.
- Final scroll/reopen/cleanup UI result: `/private/tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_01-10-54-+0200.xcresult`.
- Other passing UI captures: `/private/tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_01-04-32-+0200.xcresult`.
- Simulator: Nowhere Catalog QA, iOS 26.3, 402 × 874 points. These captures are not physical-device visual verification.
- Xcode blocked on NSFileCoordinator while opening the project under Documents; builds/tests used an identical source mirror at `/private/tmp/nowhere-happenings-validation-src`.

## Captures

[Centred opening](happenings-field-start.png) · [Scrolled](happenings-field-diagonal.png) · [Added](happenings-field-added.png) · [Large type](happenings-field-large-type.png) · [Swipe recording](scrolling.mov)

## Device installation

Built and installed revision `4c7146b4f3532f47ea80a0150a350028a184ce29` on iPhone Costa over Wi-Fi on 2026-09-15 at approximately 01:19 Europe/Belgrade. devicectl confirmed installation. The subsequent launch was denied because the phone was locked (FBSOpenApplicationErrorDomain 7). App and all four embedded extensions passed strict signing and resource validation. No remote publication or current-integration change. Physical-device visual/gesture inspection was not performed.

### Installation retry

Reinstalled revision `4c7146b4f3532f47ea80a0150a350028a184ce29` on iPhone Costa over Wi-Fi at 2026-09-15T09:23:13.694284+02:00. Installation and launch both succeeded according to devicectl. Physical-device visual verification was not performed.

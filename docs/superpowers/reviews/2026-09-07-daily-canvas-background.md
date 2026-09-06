# Today's Canvas across the app

The app-owned surfaces now use one shared, static image of today's artwork instead of independently drawing the old energy gradient. Objects and Legacy use the existing export renderers and today's persisted elements, current style/palette/texture and current energy metrics.

Covered surfaces: Feeds, Me, Settings and all its detail pages, calendar and day viewer surroundings, feed creation/settings, profile editing, in-app sign-in, notes/choice sheets, feature tips and day statistics. Historical artwork inside a day poster remains historical. The onboarding illustration and system-owned Apple/photo/Screen Time dialogs retain their own presentation.

A single owner at MainTabView refreshes on artwork storage changes, applied preferences, metric changes, foreground entry and the logical day boundary (including a changed day-start preference). Background views only display a shared image: no extra live Canvas, Smudge, sound bus or display link. The render size is bounded to 585 × 1266 pixels; one serial worker coalesces updates for 180 ms and discards stale output. Identical refreshes avoid both disk reads and rendering. New-day changes clear yesterday's image immediately. Legacy snapshots are frozen after the newest shape's spawn animation.

The image is blurred slightly and dimmed behind text, more strongly on detail pages and with Reduce Transparency. Removed the duplicate texture overlays on Me and Feeds.

Validation:
- Initial targeted suite: 11 tests passed, including background cache/stale-result tests, Appearance draft tests and artwork routing tests (`/tmp/daily-canvas-tests.xcresult`).
- Updated code: background tests and the cross-screen UI scenario passed (`/tmp/daily-canvas-final.xcresult`).
- Final iPhone build succeeded (`/tmp/daily-canvas-device-final.log`).
- Populated Canvas cross-screen UI pass succeeded (`/tmp/daily-canvas-populated.xcresult`); 8 screenshots retained in `artifacts/daily-canvas-background/`. Objects/Legacy backgrounds, text and navigation inspected.
- An additional real-image export test verifies that Legacy figures change the rendered image (`/tmp/daily-canvas-legacy-image.xcresult`, passed). Total: 12 unique targeted unit tests plus the UI scenario for empty and populated Canvas.

No physical-device performance measurement or installation in this pass. No commit or push.

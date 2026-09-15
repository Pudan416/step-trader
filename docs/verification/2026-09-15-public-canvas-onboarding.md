# Public Canvas onboarding — verification

## Change

The real Canvas tour replaces the old first-run stories and coach marks in Debug and Release. Legacy completion flags migrate into `onboarding_state_v1`; completed installs keep their completion. Automatic first launch starts at Welcome after local bootstrap, before network authentication and data refresh, without requesting permissions. Confirmed exit and Finish persist completion. An interrupted first run starts at Welcome on the next process launch.

Progress is stored separately at `canvas.onboarding.session.v2`; historical DEBUG progress is not adopted. DEBUG replay and diagnostic controls remain available. UI tests and fixture replays suppress experimental analytics; ordinary first-run product mutations keep their existing analytics. The removed legacy coach funnel is not replayed as part of the new tour.

The first-run preparation gate keeps MainTab mounted at its normal size and prevents competing sheets during startup. Health query outcomes and export completion callbacks are available in both configurations; cached Health values and the existing economy remain unchanged.

## Testing on an existing installation

In a Debug build: **Me → Settings → Developer → Canvas onboarding (Debug) → Test first launch**. Close the app completely and reopen it. This resets onboarding completion flags only. It preserves days, happenings, groups, colors, accounts and permissions; it does not emulate an empty installation. Start from welcome remains an explicit replay action.

## Source areas

- Root lifecycle: `StepsTraderApp.swift`, new `CanvasOnboardingState.swift`.
- Shared tour: `Views/Onboarding/CanvasTour.swift`, `CanvasTourUI.swift`, `CanvasTourSetup.swift`; DEBUG `CanvasTourDeveloperPage.swift`.
- Product hooks: MainTab, Gallery, happening palette, drawer, Apps/Feeds, Me/share and Settings permission screens.
- Permission/export result semantics: HealthStore, HealthKitService, GallerySubviews.
- Xcode project references and coordinator, lifecycle, Health and UI tests.
- Deleted: old story/demo screens, onboarding-only models/floaters/Apple helper, old coach manager/overlay/anchor producers and obsolete tests.

## Evidence

QA simulator: iPhone SE, simulator ID `0B85D254-A7BB-4813-9D5C-04FB33F895B7`. Signing disabled for simulator tests and the generic iOS Release compile.

- Initial selected run: 30 lifecycle/coordinator unit tests and 5 UI tests passed. Result: `/tmp/nowhere-public-onboarding-tests.xcresult`.
- After startup/Health fixes: 47 lifecycle/coordinator/Health unit tests and 2 automatic first-run UI tests passed. Result: `/tmp/nowhere-public-onboarding-final-tests.xcresult`.
- Export/body refactor: 23 coordinator tests and drawer/share cancellation UI route passed. Result: `/tmp/nowhere-public-onboarding-developer-tests.xcresult`. The first Developer-path attempt failed in the generic reveal helper by opening Permissions while dragging; the existing clipped-row navigation helper fixed the test interaction.
- Developer action → app restart → automatic Welcome → confirmed exit passed. Result: `/tmp/nowhere-public-onboarding-developer-verified.xcresult`.
- Final generic iOS Release build passed (`CODE_SIGNING_ALLOWED=NO`). Log: `/tmp/nowhere-public-onboarding-release-verified.log`. Two earlier compile failures identified the oversized Me expression and DEBUG-only share callback; both were corrected.
- Across selected runs: 47 unique unit tests and 6 unique UI tests passed. Debug UI tests include the final promoted share callback. Scoped source review found no remaining important issues in the startup/Health/share fixes.

Covered UI routes: Developer first-launch reset and restart, automatic Welcome, confirmed exit surviving relaunch, interrupted Add returning to Welcome, unchanged Canvas render viewport during/after the tour, drawer drag, share cancellation, setup page exit/return context. Unit tests cover completion migration, reset retaining unrelated defaults, duplicate/late events, operation identity, missing targets/groups and optional branches.

## Scope and limitations

These checks use product views on a dedicated QA simulator with existing day data; the happening route uses “Use this day”. They do not establish behavior of real Health reads, FamilyActivityPicker authorization/blocking, Sign in with Apple, or Share delivery on a physical phone. A new full device pass remains necessary before shipping.

No new happenings/groups or unlock spends were made by these selected UI checks. First-launch markers and QA launch counts changed. The settings fixture sets QA appearance, step/sleep targets and day boundary; it does not touch the user's physical device. Temporary poster export images may be rendered for the share cancellation test.

No installation, integration publishing or physical-device verification was performed for this replacement. The previously installed device build predates these changes.

## Follow-up: offline first-launch startup

Local loads, day-boundary reconciliation, cached energy and the day timer now finish before awaiting account initialization. Clearing `isBootstrapping` enables Canvas persistence and starts automatic Welcome through the same once-per-process claim. `didCompleteBootstrap` still gates the existing full-startup consumers. The initial-restore guard remains after authentication and reads current local state.

Regression evidence on the dedicated **Nowhere Offline Onboarding QA** simulator (`C88045BB-7C9D-4CF9-8391-EEDF769D3F8F`):

- Before the fix, the held-authentication regression failed because `isBootstrapping` was still true (`/tmp/nowhere-offline-onboarding-red-retry.xcresult`).
- After the fix, 48 unit tests and 2 UI tests passed (`/tmp/nowhere-offline-onboarding-green.xcresult`). This includes local editing while authentication is suspended, preservation of the new entry when startup resumes, automatic Welcome/Skip persistence and interrupted-tour restart.
- Debug app, test targets and embedded extensions compiled together in `/tmp/nowhere-offline-onboarding-derived`.

The regression uses a suspended authentication dependency and real AppModel startup. It does not exercise a real server restore or establish physical-device permission behavior. No physical-device install or integration/main merge was performed.

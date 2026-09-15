# Canvas onboarding DEBUG — implementation and verification

> Последующие изменения выхода, размещения карточек и анимаций: [UX/UI-ревью](2026-09-15-canvas-onboarding-ux-review.md). Описание и результаты ниже относятся к первой реализации.

## Delivery

- Branch: `codex/canvas-onboarding-debug`.
- Base: fetched `origin/codex/current-integration`, `16a17ddce6aed17a9c93e3a08f832458d3468e21`.
- Worktree: `.worktrees/canvas-onboarding-debug`. The original dirty checkout was preserved.
- Entry: **Settings → Developer → Canvas onboarding (Debug) → Start from welcome**.
- The `…` button in the coach opens tour controls and diagnostics without ending the session. Quiet controls can change live.
- Ordinary Start/Restart begins at Welcome. Resume is explicit after an interrupted session. Debug jumps validate prerequisites; a group can be selected by ID. Steps that teach opening a palette/drawer/duration require that preceding real action.
- No physical-device installation or remote publication was performed.

## Implementation

The DEBUG coordinator stores progress in one separate UserDefaults key. It never creates entries, grants colors, selects apps, logs in, or purchases access. Views report real saved results; palette/picker/share dismissal is a separate guarded event. Stop/Restart invalidate session and operation identities. A result may still complete its authorized product operation after Stop; it cannot advance the retired tour.

Actual product controls register semantic anchors. Anchor preferences resolve within the root overlay host; sheets use their own product interfaces. Per-control opacity, hit testing and accessibility are restored when the tour stops. Coach colors come from the current `CanvasChromePalette`; Onest and Dynamic Type use the product font API. The card measures its height and reserves space above the actual happening field. Text scrolls when needed; Skip stays outside that scroll area. Reduce Motion removes pulse; solid coach surfaces also work with Reduce Transparency.

Account checks use `hasAppleAccount`. Your setup reuses real Settings pages and LoginView, preserves return context and reminder toggles, and remains optional. Me exposes today's real poster during the tour and guards both sides of async export against stale day/session. Real UIActivity completion and cancellation are different results.

Legacy coach progress remains intact while its actions/overlay are suppressed. Delayed feature tips do not consume their seen flag during the tour. Existing analytics enqueueing is suppressed for the active DEBUG experiment; the tour log is local and exported only by Copy local log.

## Changed areas

| Area | Files |
| --- | --- |
| Coordinator, controls, overlay and diagnostics | `Views/CoachMark/DebugCanvasTour.swift`, `DebugCanvasTourUI.swift`, `DebugCanvasTourDeveloperPage.swift`, `DebugCanvasTourSetup.swift` |
| Root, launch and legacy tips | `Views/MainTabView.swift`, `StepsTraderApp.swift`, `Views/CoachMark/CoachMarkManager.swift`, `Services/SupabaseSyncService+Analytics.swift` |
| Developer entry | `Views/Settings/SettingsDeveloperPage.swift` |
| Canvas, palette, drawer | `Views/GalleryView.swift`, `Views/Gallery/CanvasBottomActionRow.swift`, `CanvasDataPanel.swift`, `Views/Palette/HappeningPaletteView.swift`, `HappeningShapeField.swift` |
| Feeds, actual picker and purchase | `Views/AppsPageSimplified.swift`, `Views/Feeds/FeedTileView.swift`, `Views/TicketTemplatePickerView.swift` |
| Me, real export and setup | `Views/MeView.swift`, `MeViewSupport.swift`, `Views/Gallery/GallerySubviews.swift`, `Views/Settings/SettingsPermissionsPage.swift` |
| Honest Health query diagnostics | `Stores/HealthStore.swift`, `Services/HealthKitService.swift` |
| Tests and registration | `Steps4.xcodeproj/project.pbxproj`, `Steps4Tests/DebugCanvasTourTests.swift`, `Steps4Tests/HealthKitTests.swift`, `Steps4UITests/CanvasSimplificationUITests.swift` |

Paths in this table are under `StepsTrader/` unless they start with `Steps4`.

## Test configuration and data

- `debug-canvas-tour-welcome`: DEBUG-only direct Welcome launch; normal first-run flags remain unchanged.
- `debug-canvas-tour-fixtures`: isolates **coordinator persistence only** in memory. This is not a Simulation mode and does not claim to isolate AppModel or its singletons.
- Reducer/state tests instantiate the actual coordinator with no persistence or a temporary test defaults suite. Service errors use injected Health mocks. DEBUG query outcomes distinguish loading, empty, received data and failure, including errors masked by a cached positive service result. These diagnostics do not change energy calculations or imply read permission.
- UI tests use dedicated fresh simulators and real product views/model. They do not seed fake colors, permissions or FamilyControls tokens.
- UI runs add test happenings to the QA simulator's local day. They do not alter the physical device's day, groups, login, notifications or balance. Trial unlock was skipped; share was cancelled, without a saved image or outgoing share. Health unit tests also wrote mock query caches inside the dedicated QA simulator. These are real local test data effects; the fixture flag does not sandbox product storage.

## Verification status

### Builds and automated checks

All commands used the `Steps4` scheme, which builds the app and its embedded extensions together, and dedicated DerivedData directories. Signing was disabled for these compile/simulator checks.

| Check | Result | Evidence |
| --- | --- | --- |
| DEBUG build and tests, iPhone 17 / iOS 26.3 | Passed | `/tmp/nowhere-canvas-tour-verified.xcresult` |
| Coordinator (14), palette interaction (11), drawer presentation (31) | 56 passed, 0 failures | Same result bundle |
| HealthStore, including cached-data error and retry cases | 17 passed, 0 failures | `/tmp/nowhere-canvas-tour-small-tests.xcresult` |
| Four UI routes on iPhone 17 | 4 passed, 0 failures | `/tmp/nowhere-canvas-tour-verified.xcresult` |
| Final DEBUG rebuild and same four UI routes on iPhone SE 3 / iOS 26.3 | 4 passed, 0 failures | `/tmp/nowhere-canvas-tour-small-verified.xcresult` |
| Release compile, generic iOS destination | Build succeeded | `/tmp/nowhere-canvas-tour-release-final.log` |
| Whitespace/error-marker check | `git diff --check` passed | Local checkout |

There are **73 distinct passing unit tests** across these suites. Repeated executions are not counted again. The final small-device run includes the last coach scroll-reset adjustment.

UI routes exercised:

1. Welcome → actual + → first tap preview / second tap saves one moment → actual drawer tap → Health Later → user Feeds → skip apps → user Me → current poster → Later → Your setup → Continue → skip export → Finish.
2. Existing day → actual drawer drag → optional branches → real share sheet → cancel → Finish.
3. Stop restores normal controls; Restart returns to Welcome.
4. Maximum accessibility text size: the coach scrolls, Skip remains available and the real happening target remains reachable. After skipping, the normal product palette can be closed normally.

Reproduction uses `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,id=<QA simulator UUID>' -derivedDataPath /tmp/nowhere-canvas-tour-derived CODE_SIGNING_ALLOWED=NO test`, narrowed with `-only-testing:` to the named suites above. Release uses `-configuration Release -destination generic/platform=iOS -derivedDataPath /tmp/nowhere-canvas-tour-release-derived CODE_SIGNING_ALLOWED=NO build`.

### Simulator screenshots

[Welcome](canvas-onboarding-debug/welcome.jpg) · [Actual happening field](canvas-onboarding-debug/happenings.jpg) · [Your setup](canvas-onboarding-debug/setup.jpg) · [Real share sheet](canvas-onboarding-debug/share.jpg) · [iPhone SE, maximum text size](canvas-onboarding-debug/accessibility-se.jpg)

At maximum text size on iPhone SE, the coach content requires scrolling while Skip stays pinned. Existing long labels inside the product's circular happening controls retain their line limit and can truncate. Full visual/accessibility acceptance remains open; a passing reachability test is not a claim that every label fits.


## Differences and remaining device checks

- The integration's visible category is **Steps**, using `EnergyDefaults.stepsMaxPoints`; the prototype's older Activity naming is not imposed.
- The actual configured palette currently displays ten slots. No Figma-only thirty-item catalog or demo balance is substituted.
- The product's group picker includes its existing naming step for multi-target groups.
- The real drawer had drag/accessibility actions but no ordinary touch tap. A 44-point tappable handle is enabled only while the DEBUG tour runs, preserving Release behavior.
- There is no manual Simulation mode, no second app, and no fake system UI.
- Physical-device Health authorization/read outcomes, FamilyActivityPicker selections and Screen Time enforcement, Apple login success/cancellation/network failure, real paid unlock and background timer recovery, notification authorization variants and share success require device verification. Unsigned simulator builds cannot establish these entitlements or behaviors.
- Picker Done/cancel/double-commit and unlock failure/retry are covered at the coordinator/operation boundary and in the real handler code, but **not** by service-backed picker/unlock UI fixtures. These remain part of the device acceptance matrix.
- VoiceOver activation policies are enforced in code. Full spoken VoiceOver navigation, multiple real day palettes and physical Reduce Motion/Transparency checks remain manual acceptance items.

The code is a DEBUG implementation with the checks stated here. This report does not assert completion of the physical-device acceptance matrix.

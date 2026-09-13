# App group creation without bundled brand icons

## Behavior

- The Feeds add button opens FamilyActivityPicker directly.
- One app uses an empty persisted custom name and a native title-only FamilyControls Label. Multiple apps or categories require a name.
- Cancel and swipe dismissal discard the draft. Groups are created with their final selection in one persistence operation.
- Editing replaces the selection instead of unioning it with old apps. Empty/app-less selections cannot create invisible groups.
- Settings support Rename and Use app name. Existing named and preset groups retain their names.
- Feed rows, settings, PayGate and widget cards share AppGroupTitle.
- Removed the 11 bundled social-app image sets and registry image references. Onboarding retains text choices, with a system app symbol for its spending example.

## Boundaries

- The app cannot extract a string title from an opaque Screen Time token. AppIntent configuration menus use numbered App group labels for unnamed groups; persisted transaction history uses a generic textual fallback. The widget card itself uses the native app title.
- New token-only groups have no known URL scheme, so the existing non-launchable group behavior applies after unlocking. Old presets retain their launch mapping until their app selection changes.
- Actual app names and icons require a device with Screen Time authorization and real selected apps. Synthetic Codable tokens in model tests verify identity routing and persistence, not native name rendering.

## Validation

- Base: fetched origin/codex/current-integration at 80f47c6a. Local integration was fast-forwarded before creating codex/app-group-picker.
- Steps4 scheme compiled with embedded extensions, dedicated DerivedData at /tmp/nowhere-app-group-picker-dd, signing disabled for simulator testing.
- The Documents checkout hit an NSFileCoordinator wait and a Git-object mmap stall. Build ran from a local copy in /tmp/nowhere-app-group-picker-build; all 546 copied Swift/project/entitlement/config files were byte-compared with the working source, with no differences.
- 52 unit tests passed: FeedRowModelTests (18), WidgetTests (34).
- Two UI tests passed on iPhone 17 / iOS 26.3 Simulator: direct selection and cancel without mutation; category selection, name validation, and return to the preserved draft.
- Examined native selection and naming screenshots. The naming run requested large text. Both screenshots show the app's dark appearance (the saved app theme overrides the system Light launch argument).
- No physical-device installation or real-token UI verification. No remote publication.

Screenshots: artifacts/app-group-picker-2026-09-13/native-selection-dark.png and name-step-large.png.

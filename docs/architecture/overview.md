# Code map

Use this map to choose a narrow search area. The app source, project, Swift module
and primary scheme are named Nowhere. Energy and steps remain domain concepts.

| Change | Entry points | Useful regression tests |
| --- | --- | --- |
| Startup, dependency wiring, app lifecycle | `Nowhere/NowhereApp.swift`, `DIContainer.swift`, `AppModel.swift` | `AuthSessionRestoreTests`, `AuthSignInLoadingStateTests` |
| Tabs and navigation | `Views/MainTabView.swift`, `Views/GalleryView.swift`, `Views/MeView.swift`, `Views/AppsPageSimplified.swift` | `MainTabSelectionTests`, `CanvasPresentationStateTests` |
| Onboarding and tours | `Views/Onboarding/` (including `HappeningPersonalization.swift` and `HappeningOnboardingView.swift`), `Views/CoachMark/` | `CanvasOnboardingStateTests` |
| Happenings, Personal recommendations, daily colors and Health inputs | `AppModel+DailyEnergy.swift`, `AppModel+WorkoutSuggestions.swift`, `Models/ActivitySuggestion.swift`, `Models/HappeningDefaults.swift`, `Models/HappeningEventTree.swift`, `Models/EnergyDefaults.swift`, `Models/Happening.swift`, `Stores/HealthStore.swift`, `Stores/HappeningStore.swift` | `PersonalHappeningRecommendationsTests`, `DailyEnergyLogicTests`, `EnergyRecalcTests`, `HappeningAdditionsTests`, `HealthKitTests` |
| Palette selection and adding/removing objects | `Views/Palette/`, `Models/CanvasElement.swift`, `Models/DayCanvas.swift` | `HappeningPaletteSelectionTests`, `CanvasPersistenceRegressionTests` |
| Canvas rendering, gestures, saved artwork | `Views/GalleryView.swift`, `Views/Gallery/`, `Experiments/DayObjects/`, `Experiments/ShapeGenome/`, `Metal/` | `DayCanvasArtworkRoutingTests`, `MetalShapeCompatibilityTests`, `CanvasRemixTests` |
| Music | `Experiments/DayObjects/Sound/` — Director, Domain, Engine, Playback, Lab, Diagnostics | `DeterministicMusicDirectorTests`, `DayObjectsMusicPlaybackEngineTests`, `DayObjectsAudioResourceTests` |
| Feed groups and purchases | `Views/Feeds/`, `Views/PayGateView.swift`, `AppModel+TicketManagement.swift`, `Stores/BlockingStore.swift`, `Stores/UserEconomyStore.swift` | `PaymentTests`, `BudgetEngineTests`, `TicketGroupCostTests` |
| Actual Screen Time usage and shielding | `Shared/ShieldRebuildHelper.swift`, `DeviceActivityMonitor/`, `ShieldAction/`, `ShieldConfiguration/`; locate budget operations with `rg 'UsageBudget' Nowhere Shared` | `UsageBudgetScheduleTests`, `AppGroupRMWConcurrencyTests`, `UnspentUsageBudgetTests` |
| Widgets and wallpaper | [App opening](widget-app-opening.md), `TargetResolver.swift`, `Models/TicketGroup.swift`, `UnlockWidget/`, `Intents/ExportCanvasWallpaperIntent.swift`, `Services/CanvasStorageService.swift` | `WidgetTests`, `GateArtworkTests` |
| Authentication, local persistence and cloud sync | `Services/AuthenticationService.swift`, `Services/CanvasStorageService.swift`, `Services/SupabaseSyncService*.swift`, `Stores/PreferencesStore.swift` | `RetryQueueClassificationTests`, `PreferencesStoreTests`, `CanvasPersistenceRegressionTests` |
| Analytics event schema and runtime context | `Services/SupabaseSyncService+Analytics.swift`, `supabase/migrations/` | [Analytics event contract](analytics-events.md) |
| Appearance, typography and copy | `Views/Settings/`, `Theme/`, `Utilities/Font+Custom.swift`, `Fonts/`, `Localizable.xcstrings` | `AppTypographyTests`, `SettingsAppearanceDraftTests`, `DailyInterfaceColorTests` |

Paths in the table without a repository prefix are relative to `Nowhere/`.
Test names live in `NowhereTests/` unless stated otherwise.

## Ownership and compatibility

- `AccountHistoryVault` is an additive, local-only archive primitive. It is not
  wired into authentication yet. Before calling `activate`, an account-transition
  coordinator must suspend app and extension writers, invalidate stale asynchronous
  callbacks, and provide explicit history defaults/file locations. Legacy history
  is archived as `legacy-unattributed`; it must have a recoverable local access path
  before runtime activation is enabled. Archives preserve file/UUID bytes and use a
  recovery journal; files are copied individually instead of loading PNG history into
  memory. Credentials, diagnostics and lock files must never enter the working set.
- `UserEconomyStore.suspendPersistence()` pauses scalar/JSON writers, cancels
  and awaits their pending tasks, and flushes the latest outgoing state before
  storage rotation. It throws if that state cannot be preserved. Its caller must
  separately finish local loaders/migrations, suspend other app/extension writers,
  and reload the incoming account before `resumePersistence()`. These transition
  hooks are not wired into authentication yet.
- `AppModel` coordinates the existing stores; `DIContainer.applicationModel` is shared by
  foreground UI and app intents. Avoid creating a second independent purchase model.
- `HappeningDefaults.builtIns` derives the fixed 106 choices from `HappeningEventTree.all`.
  `HappeningStore.selectable` attaches usage metadata to authoritative English copy;
  `all` also contains historical/imported records and must not feed new-choice UI.
  Canonical selection aliases never rewrite saved entry IDs or Canvas labels.
  Removal resolves the current-day entry by UUID, then exact option ID, then
  canonical alias, and deletes using the entry's original durable ID.
- `HappeningPersonalizationStore` keeps account-scoped committed survey preferences
  separate from resumable drafts. `GalleryView` gates only the explicit Add action,
  then reveals the existing All atlas without changing its cells. Survey seeds never
  enter `HappeningStore`; temporary emotion scores expire by logical day. The Debug
  coordinator prepares a fresh survey draft for a Debug replay and starts the
  existing CanvasTour at welcome. The same HappeningPaletteView stays mounted
  across six questions and the All reveal. Synthetic IDs own only survey answers;
  explicit representative catalog IDs reuse the full authoritative Editorial
  assignment snapshot, including frozen current-day actors. Survey taps reuse
  HappeningPaletteInteractionState's removal preview and confirmation, without
  invoking Canvas mutation paths. Headings and the persistent first-All choice
  prompt contribute to the same CanvasTourHost coach surface. The coach publishes
  its destination geometry rather than every animation frame; content changes
  atomically. HappeningFieldReveal samples an immutable schedule in the leaf
  TimelineView, preserving the full All world and Today hub. Palette presentation
  copies reuse the prepared DayObjects scene rather than deriving it per frame. A real
  addition or explicit tap on an already recorded happening, followed by palette
  dismissal, advances to Health, Feeds and Me. Recorded event taps acknowledge
  the durable entry without a mutation, including at the ten-addition limit.
- `HappeningShapeField` keeps the nominal picker and caption target, then adds
  revealed Native Atlas actors' frozen contours using the renderer's rotation and
  feedback scale. Confirmation targets include the peak breathing extent and the
  full Add/Delete capsule. The current confirmation action outranks returning
  previews, which outrank ordinary neighbors. Returning previews retain their
  figure envelope for the renderer's
  transition duration, with independent expiry tokens; the departed action capsule
  immediately stops receiving taps. Available neighbors retain the nominal picker
  contour. `MetalShapeContour`
  samples saved uniforms through a bounded cache rather than regenerating presets.
- `HappeningEventTree.startingEvents` owns six fixed canonical starter events
  for work, rest, home, movement, food/drink and people. Personal uses
  `HappeningEventTreeState.nodes` to reveal the same complete `atlasNodes` used by
  All. `PersonalHappeningRecommendations.rankedEventIDs` ranks the full catalog
  once on opening from usage, canonical restored history and survey scores.
  Nonstarter occupants rank within their domain's immutable cells; parent IDs
  follow the cell graph. Successful additions commit the actual canonical event
  and expand at most three neighbors; there are no synthetic navigation IDs or
  category screens. Today/Health paths reveal without another mutation. Final
  removal calls `resetVisibleEvents`, retaining the opening atlas and frozen
  actors. Reopening replays stored expansion IDs using fresh opening ranking;
  day and account changes invalidate expansion state.
  Stationary inline expansion keeps existing targets interactive while neighbors
  grow; transitions that move or shrink targets retain their interaction gate.
- Live Happenings artwork uses a fixed world-sized `HappeningPaletteTileSurfaceView`
  with 256-point world-aligned Metal tiles. Labels, capsules and hit targets retain
  the same world coordinates; scrolling never moves a surviving tile or changes
  its source projection. Native offset/bounds observation changes residency only.
  The event-tree field does not sample scroll offsets through SwiftUI or animate
  a Timeline while static artwork is being panned.
  The native host samples one transition timeline. One serial GPU worker shares
  the prepared scene, Native Atlas pipelines, command queue and three scratch
  textures. Drawable acquisition and encoding run outside the main thread. At most
  one batch is in flight until GPU completion; it acquires every required drawable
  before presenting any, with atomic cancellation against submission. A batch
  encodes dirty tiles with one sampled time and one command buffer. Tile-local
  projection preserves controls and assignments; finish grain uses world pixels.
  Static pan renders new tiles only. Morphs, reduced-motion fades and confirmation
  breaths render their exact terminal frame before the display link stops.
  Residency covers the viewport plus 64 points. Pan-independent scale limits
  resident outputs to 12 Mi pixels, with two drawables per tile and one shared
  scratch set (three RGBA16Float textures); one older residency can be retained
  by the sole in-flight batch during pan/resize. No world-sized Metal texture is allocated.
  Scene/tab inactivity stops rendering; detachment/dismissal releases tile residency.
  Canvas retains its existing renderer. The legacy viewport presentation path still
  gates pending size/camera draws and is separate from the live fixed-tile picker.
  Personal domain ranking freezes on opening (and rebuilds on day change), while
  additions reveal current paths without reading or ranking history again.
- `GalleryView.refreshEventTreePalette` retains Editorial assignments while their
  complete request is unchanged; expansion and duplicate mutation/sync callbacks
  must not rebuild all catalog candidates. Native available choices retain their
  opening assignments; committed UUID/color/frozen-actor changes refresh only
  affected choices. Removed choices retain their returning preview contour until
  the next commit or opening. Actor-generation context changes (day, identity,
  recipe/style/material, metrics, palette or nonce) invalidate the complete map.
  Legacy scene recipes retain full resolution. `DayObjectPaletteSet.make` shares a bounded
  16-entry palette cache keyed by root seed, normalized categories, day and identity.
  Its lock protects lookup/publication, while palette derivation runs outside the lock.
- `MePosterEventLedger.unlocks` retains four immutable full-ledger requests so live
  Canvas updates do not repeatedly classify every historical unlock by its logical
  day. Record edits/removals, day/boundary/calendar changes and formatting/locale
  context invalidate the cache; the underlying classification stays unchanged.
- `DetectedWorkout.suggestedOptionId` and `ActivitySuggestion.isSatisfied` own
  Health-to-catalog identity and equivalence. Views log the resolved catalog ID;
  a generic workout must not satisfy a specific run or swim.
- The app and extensions are separate processes. Preserve App Group identifiers, persisted
  keys, atomic read/modify/write operations and the existing lock ordering. An actor in one
  process does not synchronize another process.
  All shield assignments route through `ShieldRebuildHelper.rebuild`; the usage-budget
  state lock spans the persisted snapshot and ManagedSettings write. DeviceActivity
  registration always happens after that lock is released.
  `withAccountHistoryTransitionLock` acquires the registration lock before the
  state lock, excluding both an in-flight daemon registration and extension
  callbacks during synchronous account-history replacement. Its body must not
  await, call DeviceActivity or rebuild shields. Keep both lock files outside
  archived paths; stop obsolete monitors and rebuild only after releasing them.
  This additive transition hook is not wired into authentication yet.
- `DayCanvas` and versioned recipes are durable data. Older render paths and textures are
  still required by saved artwork and export. Preserve decoder defaults, stable IDs, random
  consumption order and Metal uniform layouts. See [Canvas components](canvas-components.md).
- `DayObjectsMusicLabController` also drives production music; its name does not make it
  debug-only. Audio recipes select assets dynamically through their catalogs.
- Swift protocol callbacks, AppIntents and extension entry points may have no textual caller.
  Confirm target membership and framework use before treating a declaration as dead code.

## Working on a feature

1. Start at the table row, then read its entry point and related test.
2. Follow explicit calls to the owning store/service. Avoid reading all historical docs.
3. Verify every affected target, including extensions when shared code or resources change.
4. Update the relevant maintained document when behavior or ownership changes.

## Installed-app identity

Developer-facing names use Nowhere. These historical values intentionally remain
stable so updates keep existing installations, data and extension communication:

- App bundle ID: `personal-project.StepsTrader`; extension bundle IDs retain that prefix.
- Test bundle IDs: `personal-project.Steps4Tests` and `personal-project.Steps4UITests`;
  test targets and products are `NowhereTests` and `NowhereUITests`.
- Shared container: `group.personal-project.StepsTrader` (`SharedKeys.appGroupId`).
- Keychain service/account: `com.stepstrader.supabase-session` / `session_v1`
  (`Services/AuthSupportTypes.swift`).
- Registered URL schemes: `stepstrader://` and `steps-trader://`; widgets still use them.
- `SharedKeys.lastAppOpenedFromNowhere(_:)` retains the persisted prefix
  `lastAppOpenedFromStepsTrader_`. Swift method names are not persisted key names.
- Persistence services retain their `StepsTrader` fallback directory name.
- Existing diagnostic subsystem strings retain their historical names for log continuity.

Do not replace these strings during naming cleanup. Keep current persisted keys,
Codable keys, widget kinds and enum raw values unless a separate migration is tested.

The account coordinator uses the vault's two-phase activation: `prepareActivation` retains the outgoing recovery journal while the incoming model is loaded, then `commitActivation` completes it after validating the incoming authentication generation, immediately before publishing authentication without an intervening await. A receipt can undo only its own still-pending switch through `rollbackActivation`; this includes the original unattributed working set without exposing normal activation/import of legacy history. Restart before commit also restores the outgoing archive. Existing `activate` remains the immediate prepare/commit convenience.
Usage budget account transitions use `UsageBudgetAccountBoundary` inside the registration/state lock boundary. Its device-level `accountHistoryBudgetEpoch_v1` and `accountHistoryBudgetSuspended_v1` keys are excluded from account storage. Suspend invalidates measurement identities without changing paid minutes and returns monitor names for stopping outside locks. Apply suspend to incoming restored sessions before resume; normal recovery then registers a fresh identity. Callback continuations retain their original epoch, so a delayed outgoing callback cannot recover the incoming account's budget. The hooks remain dormant until the account coordinator adopts them.

### Cloud work during account transitions

`SupabaseSyncService` exposes `captureSyncEpoch()` and the `historySyncEpoch`
TaskLocal. Producers capture the epoch before creating their asynchronous Task,
then retain it with `$historySyncEpoch.withValue`. Canceling and awaiting producer
tasks is still required: this token prevents a suspended old payload from first
entering the service after the incoming account resumes.

The transition contract starts with synchronous `beginAccountSwitch()` before
canceling and awaiting any producer Task. Then `pauseForAccountSwitch()` (invalidate, cancel tracked
jobs, await active leases, then reset transient caches), `resumeAfterAccountSwitch()`
(reads only), and `allowUploadsAfterRestore(for:)` (uploads for the restored current
owner). An HTTP request already submitted under the outgoing bearer cannot be
undone; its lease must finish before files or owner rotate, and stale completion
must not apply or acknowledge local state. Durable retry/entry queues are preserved.
All history entrypoints and HTTP continuations acquire/check operation leases;
restore checks again inside each MainActor commit. Canvas recovery jobs are tracked,
and analytics persistence is awaited. After draining, pause commits the final outgoing
analytics snapshot before files rotate, preserving events whose normal persistence was
invalidated. Resuming re-reads the incoming queue; owner readiness schedules its flush. Device-token
registration and captured-bearer APNs teardown are outside the history barrier.

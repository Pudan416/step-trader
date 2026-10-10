# Code map

Use this map to choose a narrow search area. The app source, project, Swift module
and primary scheme are named Nowhere. Energy and steps remain domain concepts.

| Change | Entry points | Useful regression tests |
| --- | --- | --- |
| Startup, dependency wiring, app lifecycle | `Nowhere/NowhereApp.swift`, `DIContainer.swift`, `AppModel.swift` | `AuthSessionRestoreTests`, `AuthSignInLoadingStateTests` |
| Tabs and navigation | `Views/MainTabView.swift`, `Views/GalleryView.swift`, `Views/MeView.swift`, `Views/AppsPageSimplified.swift` | `MainTabSelectionTests`, `CanvasPresentationStateTests` |
| Onboarding and tours | `Views/Onboarding/`, `Views/CoachMark/` | `CanvasOnboardingStateTests` |
| Happenings, Personal recommendations, daily colors and Health inputs | `AppModel+DailyEnergy.swift`, `AppModel+WorkoutSuggestions.swift`, `Models/ActivitySuggestion.swift`, `Models/HappeningDefaults.swift`, `Models/HappeningCatalog.swift`, `Models/AdaptiveHappeningRecommendations.swift`, `Models/PersonalHappeningProfile.swift`, `Stores/PersonalHappeningProfileStore.swift`, `Models/HappeningEventTree.swift`, `Models/EnergyDefaults.swift`, `Models/Happening.swift`, `Stores/HealthStore.swift`, `Stores/HappeningStore.swift` | `PersonalHappeningRecommendationsTests`, `DailyEnergyLogicTests`, `EnergyRecalcTests`, `HappeningAdditionsTests`, `HealthKitTests` |
| Palette selection and adding/removing objects | `Views/Palette/` (including `HappeningCatalogBrowser.swift`), `Models/CanvasElement.swift`, `Models/DayCanvas.swift` | `HappeningPaletteSelectionTests`, `CanvasPersistenceRegressionTests` |
| Canvas rendering, gestures, saved artwork | `Views/GalleryView.swift`, `Views/Gallery/`, `Experiments/DayObjects/`, `Experiments/ShapeGenome/`, `Metal/` | `DayCanvasArtworkRoutingTests`, `MetalShapeCompatibilityTests`, `CanvasRemixTests` |
| Music | `Experiments/DayObjects/Sound/` — Director, Domain, Engine, Playback, Lab, Diagnostics | `DeterministicMusicDirectorTests`, `DayObjectsMusicPlaybackEngineTests`, `DayObjectsAudioResourceTests` |
| Feed groups and purchases | `Views/Feeds/`, `Views/PayGateView.swift`, `AppModel+TicketManagement.swift`, `Stores/BlockingStore.swift`, `Stores/UserEconomyStore.swift` | `PaymentTests`, `BudgetEngineTests`, `TicketGroupCostTests` |
| Actual Screen Time usage and shielding | `Shared/ShieldRebuildHelper.swift`, `DeviceActivityMonitor/`, `ShieldAction/`, `ShieldConfiguration/`; locate budget operations with `rg 'UsageBudget' Nowhere Shared` | `UsageBudgetScheduleTests`, `AppGroupRMWConcurrencyTests`, `UnspentUsageBudgetTests` |
| Widgets and wallpaper | `UnlockWidget/`, `Intents/ExportCanvasWallpaperIntent.swift`, `Services/CanvasStorageService.swift` | `WidgetTests`, `GateArtworkTests` |
| Authentication, local persistence and cloud sync | `Services/AuthenticationService.swift`, `Services/CanvasStorageService.swift`, `Services/SupabaseSyncService*.swift`, `Stores/PreferencesStore.swift` | `RetryQueueClassificationTests`, `PreferencesStoreTests`, `CanvasPersistenceRegressionTests` |
| Analytics event schema and runtime context | `Services/SupabaseSyncService+Analytics.swift`, `supabase/migrations/` | [Analytics event contract](analytics-events.md) |
| Appearance, typography and copy | `Views/Settings/`, `Theme/`, `Utilities/Font+Custom.swift`, `Fonts/`, `Localizable.xcstrings` | `AppTypographyTests`, `SettingsAppearanceDraftTests`, `DailyInterfaceColorTests` |

Paths in the table without a repository prefix are relative to `Nowhere/`.
Test names live in `NowhereTests/` unless stated otherwise.

## Ownership and compatibility

- `AppModel` coordinates the existing stores; `DIContainer.applicationModel` is shared by
  foreground UI and app intents. Avoid creating a second independent purchase model.
- `HappeningCatalog.definitions` owns 278 stable editorial definitions independently
  of geometry. Every definition maps to an ordinary loggable Canvas record;
  `HappeningStore.selectable` attaches usage metadata to authoritative copy. `all`
  also contains historical/imported records and must not feed new-choice UI.
  Canonical aliases never rewrite saved entry IDs or Canvas labels. Removal resolves
  the current-day entry by UUID, then exact option ID, then canonical alias, and
  deletes using the original durable ID. The original 100 definitions preserve their
  IDs, labels and tags; the full field no longer depends on the event tree's old atlas.
- `AdaptiveHappeningRecommendations` ranks explicit choices, distinct recorded days,
  a bounded legacy fallback, interests and discovery. It returns stable reason codes
  and does not mutate the catalog or award Colors. Hidden and unavailable choices
  are filtered before ranking; pins and intentions cannot bypass availability.
  `PersonalHappeningProfileStore` keeps preferences in
  app-private standard defaults, outside shared storage and sync models. Reset saves
  a custom-day cutoff and disables pre-reset counter fallback without editing history.
- `GalleryView` snapshots recommendations on field/browser opening. The Personal
  field and browser keep separate snapshots, so opening the browser cannot change
  the active constellation. The constellation places six roots and the current
  recommendations near its center;
  All lays out every catalog definition in a deterministic, day-specific two-dimensional
  spiral. Positions remain fixed while open; hidden Personal choices have no hit area,
  unavailable choices are visible but locked, and already-added events remain removable.
  Metal receives only visible positions through viewport culling. `HappeningCatalogBrowser`
  remains available for text search, disables unavailable choices with an explanation,
  and calls the existing `addAndSpawnHappening` transaction, preserving the ten-event
  limit and Colors. Its settings never write to `Happening` or Canvas metadata.
  Care events and habit events use the ordinary Canvas history and sync path.
  Sexual events are not offered as new choices; historical records retain their
  existing resolution/removal paths.
  The existing slot chooser also searches and filters the complete selectable catalog.
- `HappeningEventTreeState.atlasNodes` retains its historical 100-position map for
  compatibility, but it does not cap the full field. `HappeningFieldLayout.catalogLayout`
  creates centered staggered positions for the complete editorial catalog without
  changing its circle scale or day-count hub; renderer slots are culled to the visible
  world rect. Personal records an append-only reveal sequence with semantic parent
  IDs for the open field. It allocates every reveal to a free cell near its parent
  and retains earlier allocations when later activities are added or removed;
  selection and placement share the same recorded IDs. Reopening rebuilds the
  sequence from the current day. Successful removal of the final Canvas element resets
  expansion IDs; a local cleared-day marker suppresses Personal prereveals while empty.
- `GalleryView.refreshEventTreePalette` retains Editorial assignments while their
  complete request is unchanged; expansion and duplicate mutation/sync callbacks
  must not rebuild all 100 candidates. `DayObjectPaletteSet.make` shares a bounded
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

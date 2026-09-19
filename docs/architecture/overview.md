# Code map

Use this map to choose a narrow search area. Names such as Steps4, StepsTrader,
energy and steps remain in internal identifiers for compatibility; the product is Nowhere.

| Change | Entry points | Useful regression tests |
| --- | --- | --- |
| Startup, dependency wiring, app lifecycle | `StepsTrader/NowhereApp.swift`, `DIContainer.swift`, `AppModel.swift` | `AuthSessionRestoreTests`, `AuthSignInLoadingStateTests` |
| Tabs and navigation | `Views/MainTabView.swift`, `Views/GalleryView.swift`, `Views/MeView.swift`, `Views/AppsPageSimplified.swift` | `MainTabSelectionTests`, `CanvasPresentationStateTests` |
| Onboarding and tours | `Views/Onboarding/`, `Views/CoachMark/` | `CanvasOnboardingStateTests` |
| Happenings, daily colors and Health inputs | `AppModel+DailyEnergy.swift`, `AppModel+WorkoutSuggestions.swift`, `Models/EnergyDefaults.swift`, `Models/Happening.swift`, `Stores/HealthStore.swift`, `Stores/HappeningStore.swift` | `DailyEnergyLogicTests`, `EnergyRecalcTests`, `HappeningAdditionsTests`, `HealthKitTests` |
| Palette selection and adding/removing objects | `Views/Palette/`, `Models/CanvasElement.swift`, `Models/DayCanvas.swift` | `HappeningPaletteSelectionTests`, `CanvasPersistenceRegressionTests` |
| Canvas rendering, gestures, saved artwork | `Views/GalleryView.swift`, `Views/Gallery/`, `Experiments/DayObjects/`, `Experiments/ShapeGenome/`, `Metal/` | `DayCanvasArtworkRoutingTests`, `MetalShapeCompatibilityTests`, `CanvasRemixTests` |
| Music | `Experiments/DayObjects/Sound/` — Director, Domain, Engine, Playback, Lab, Diagnostics | `DeterministicMusicDirectorTests`, `DayObjectsMusicPlaybackEngineTests`, `DayObjectsAudioResourceTests` |
| Feed groups and purchases | `Views/Feeds/`, `Views/PayGateView.swift`, `AppModel+TicketManagement.swift`, `Stores/BlockingStore.swift`, `Stores/UserEconomyStore.swift` | `PaymentTests`, `BudgetEngineTests`, `TicketGroupCostTests` |
| Actual Screen Time usage and shielding | `Shared/ShieldRebuildHelper.swift`, `DeviceActivityMonitor/`, `ShieldAction/`, `ShieldConfiguration/`; locate budget operations with `rg 'UsageBudget' StepsTrader Shared` | `UsageBudgetScheduleTests`, `AppGroupRMWConcurrencyTests`, `UnspentUsageBudgetTests` |
| Widgets and wallpaper | `UnlockWidget/`, `Intents/ExportCanvasWallpaperIntent.swift`, `Services/CanvasStorageService.swift` | `WidgetTests`, `GateArtworkTests` |
| Authentication, local persistence and cloud sync | `Services/AuthenticationService.swift`, `Services/CanvasStorageService.swift`, `Services/SupabaseSyncService*.swift`, `Stores/PreferencesStore.swift` | `RetryQueueClassificationTests`, `PreferencesStoreTests`, `CanvasPersistenceRegressionTests` |
| Appearance, typography and copy | `Views/Settings/`, `Theme/`, `Utilities/Font+Custom.swift`, `Fonts/`, `Localizable.xcstrings` | `AppTypographyTests`, `SettingsAppearanceDraftTests`, `DailyInterfaceColorTests` |

Paths in the table without a repository prefix are relative to `StepsTrader/`.
Test names live in `Steps4Tests/` unless stated otherwise.

## Ownership and compatibility

- `AppModel` coordinates the existing stores; `DIContainer.applicationModel` is shared by
  foreground UI and app intents. Avoid creating a second independent purchase model.
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

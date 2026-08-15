# Remove RevenueCat and ship the app free

Date: 2026-08-13
Status: approved, pending implementation plan

## Why

The app already ships free. `SubscriptionGate.allFeaturesUnlocked` is `true`, and
`isPro` reads as `allFeaturesUnlocked || state.isPro`, so every one of the 44
subscription call sites already resolves to "unlocked". RevenueCat still
initialises on launch, phones home, and requires an API key in four config
files — for an entitlement nobody reads.

There are no paying users. The decision is to make that permanent and delete the
machinery.

Supporting facts established before this design:

- `import RevenueCat` appears in exactly one file, `SubscriptionStore.swift`.
- Supabase has no subscription or purchase table (all 16 tables checked), so
  there is no server-side entitlement state to migrate.
- No widget or app extension reads the cached Pro flag from the app group.
- `SubscriptionIDs` is referenced only by the three files being deleted or
  reduced.
- The App Store, not RevenueCat, is the system of record for purchases. Nothing
  here destroys a purchase; StoreKit 2 could reconstruct entitlements later.

## Decisions

Three forks, all settled with the user:

1. **Depth** — remove RevenueCat and the paywall, keep the gate scaffolding
   (`SubscriptionStore`, `SubscriptionGate`, the DI wiring) rather than deleting
   the concept of Pro from the codebase. Consumers keep calling the same API.
   This is about the type surface; the UI cleanup in decision 3 still edits
   seven view files.
2. **Free/Pro matrix** — collapse to unconditional yes. The limits and the
   `allFeaturesUnlocked` flag go; the gate query functions stay and return
   `true`.
3. **Dead UI** — full cleanup. Lock badges, history blur and limit affordances
   go along with the paywall, not just the parts that block compilation.

## Scope

### Deleted outright

| Path | Lines |
|---|---|
| `StepsTrader/Views/PaywallView.swift` | 692 |
| `StepsTrader/Views/Settings/SettingsSubscriptionPage.swift` | 437 |
| `StepsTrader/Models/SubscriptionEntitlement.swift` | 59 |
| `Steps4/Configuration.storekit` | — |
| `Steps4Tests/SubscriptionStateTests.swift` | 96 |

Plus the `purchases-ios` SPM package reference in `Steps4.xcodeproj`.

### Reduced

**`StepsTrader/Stores/SubscriptionStore.swift`** — 629 lines down to roughly 20.
It becomes an `ObservableObject` exposing `isPro: Bool { true }` and nothing
else. Gone: `configure`, `logIn`, `logOut`, `refresh`, `restore`, `purchase`,
`presentRedeemCodeSheet`, `presentManageSubscriptions`, the `customerInfo`
stream, grandfathering evaluation, `SubscriptionState`, `SubscriptionPurchaseResult`
and `PurchasePackage`.

The DI wiring stays: `DIContainer.makeSubscriptionStore()`,
`AppModel.subscriptionStore`, `AppModel.isPro`. That is what keeps the consumer
files from needing edits.

**`StepsTrader/Stores/SubscriptionGate.swift`** — keeps the query functions
(`canAddBlockingGroup`, `canCreateCustomActivity`, `canAddMoment`,
`canUseDailyRandomTheme`, `canCustomizeShapes`, the three `is*Available`),
all returning `true` unconditionally. Signatures keep their `isPro:` parameter
so call sites are untouched. Gone: `allFeaturesUnlocked`, `freeMaxBlockingGroups`,
`freeHistoryDayCount`, `freeCanCreateCustomActivity`, `freeCanUseDailyRandomTheme`,
`freeCanCustomizeShapes`, `shouldShowPostOnboardingPaywall`,
`markPostOnboardingPaywallShown`, `postOnboardingPaywallShownKey`.

### UI cleanup

| File | What goes |
|---|---|
| `StepsTrader/StepsTraderApp.swift` | `SubscriptionStore.configure` call; post-onboarding paywall trigger and its sheet |
| `StepsTrader/Views/MeViewSupport.swift` | `showPaywall` binding and its `fullScreenCover` |
| `StepsTrader/Views/Me/MeCalendarStrip.swift` | Day locking, blur, and the tap-to-paywall path |
| `StepsTrader/Views/AppsPageSimplified.swift` | Blocking-group limit check and its paywall presentation |
| `StepsTrader/Views/Settings/SettingsAppearancePage.swift` | Three `isUnlocked` checks and the lock affordances they drive |
| `StepsTrader/Views/SettingsSheet.swift` | Membership row and the `state` switches feeding it |
| `StepsTrader/Services/AuthenticationService.swift` | `SubscriptionStore.shared.logIn` / `logOut` calls |

Two more files carry only stale comments about the dormant gate and need no
behavioural change: `StepsTrader/Views/Me/MeWeekStats.swift` and
`StepsTrader/AppModel+DailyEnergy.swift`. Update the wording so the comments do
not describe a flag that no longer exists.

Removing the `AuthenticationService` calls also disarms a live hazard found
during investigation: `Purchases.shared` traps when read before `configure`, and
`SubscriptionStore` has no configured-check, so an empty API key would crash the
app on the next sign-in.

### Config and CI

`REVENUECAT_API_KEY` appears in five tracked files: `Steps4/Info.plist` (×2),
`Config/Secrets.xcconfig.template`, `ci_scripts/ci_post_clone.sh` (×3),
`StepsTrader/StepsTraderApp.swift` (×2) and a comment in
`.github/workflows/ci.yml`. It is *not* in `Config/Secrets-Dev.xcconfig.template`.
Remove it from all of them, plus the untracked local `Config/Secrets.xcconfig`
and its five worktree copies. `Scripts/check-secrets-config.sh` needs no
edit — it derives its key list from the template, and its "every template key
must still be referenced" check will fail if the key is dropped from one place
but not the other. That is the intended behaviour.

### Tests

- `SubscriptionStateTests.swift` is deleted with the state machine it covers.
- `SubscriptionGateTests.swift` is rewritten to assert every gate returns `true`
  regardless of input.
- `EnergyRecalcTests`, `PaymentTests`, `HappeningAdditionsTests` and
  `HappeningLiquidLayoutTests` set `SharedKeys.isGrandfathered = true` as a
  fixture to obtain Pro behaviour. Those lines become meaningless and are
  removed; the assertions themselves stay.
- `SharedKeys` entries `isGrandfathered`, `cachedHasProEntitlement` and
  `rcAppUserID` lose their last readers and are removed. The stored values are
  left on device — harmless orphans in UserDefaults, and cheaper than a
  migration.

## Out of scope

`Tariff.swift`, `TariffDecodingTests` and `PaymentTests` concern the in-app
steps-to-minutes economy, not in-app purchases. Untouched apart from the
fixture cleanup noted above.

Removing the subscription products from App Store Connect is a console task for
the user, not part of this change.

## Verification

1. `xcodebuild build` for the Steps4 scheme succeeds with no reference to
   RevenueCat remaining: `grep -rn "RevenueCat\|Purchases\." StepsTrader/`
   returns nothing.
2. `Steps4Tests` passes in full.
3. `Scripts/check-secrets-config.sh` passes, proving the key was removed from
   every config layer consistently rather than half of them.
4. The app runs on the simulator: onboarding completes without a paywall, the Me
   calendar shows every day unblurred, Settings has no Membership row, and a
   third blocking group can be created.

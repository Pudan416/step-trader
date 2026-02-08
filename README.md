# DOOM CTRL (iOS, SwiftUI)

An iOS app that turns daily activity into “control” points and spends them to unlock access to selected apps or app groups.

## Core mechanics
- **Daily Control (0–100)** is built from:
  - steps (HealthKit)
  - sleep hours
  - daily choices across Activity / Recovery / Joys
- **Bonus control** can be granted by the backend and is capped by the daily max.
- **Spending control** happens when you unlock access windows for selected apps/groups (PayGate) or buy a day pass.
- **Minute mode** optionally tracks real app usage via DeviceActivity and consumes a minute budget derived from steps and the selected tariff.

## Targets
- **`Steps4`** — main iOS app (display name: **DOOM CTRL**)
- **`DeviceActivityMonitor`** — extension (`com.apple.deviceactivity.monitor`) that receives DeviceActivity events for usage tracking

## Capabilities / Permissions
- **HealthKit (Read)** — read step count and sleep hours
- **Family Controls + Device Activity** — app selection + usage tracking
 - **App Group** — `group.personal-project.StepsTrader` (shared storage between app and extension)

Important: **ManagedSettings “shield blocking” was removed**. The app does not block apps via Screen Time shielding.

## Deep links
Schemes registered in `Steps4/Info.plist`:
- `stepstrader://...`
- `steps-trader://...`

Examples (see `StepsTrader/AppModel.swift`):
- `steps-trader://pay?target=<bundleId|alias>`
- `steps-trader://guard?target=<bundleId|alias>` (guard no longer enables shielding; it’s kept only as a UX/deeplink trigger)

## Supabase
Keys used in `Steps4/Info.plist`:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Recommendation: **don’t commit keys in `Info.plist`**. Move them to `.xcconfig` (Debug/Release) or use CI secrets + a local gitignored config.

## Choice cards (polaroid images)
Cards on the Choices tab use a polaroid style: image on top, caption on white below. When a choice is completed, a yellow cross is overlaid on the image.

**To add images for testing:**
1. In **Assets.xcassets** create an image set named `choice_<optionId>`.
2. **Option IDs** are in `StepsTrader/Models/DailyEnergy.swift` (e.g. `activity_stairs`, `activity_10k_steps`, `recovery_sleeping_well`, `joys_coffee_tea`).
3. Example: for “Taking the stairs instead of the elevator” the ID is `activity_stairs`, so the asset name is **`choice_activity_stairs`**. An imageset `choice_activity_stairs` already exists — add your photo as `stairs.jpg` (or update `Contents.json` to your filename).
4. Format: JPG or PNG; recommended height ~200–300 pt for sharp @2x. If an image is missing, the card shows a gray placeholder with the option’s SF Symbol icon.

## Run / Build
- For real **FamilyControls/DeviceActivity**, test on a **physical device** (entitlements + system limitations).
- Quick build check:

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build
```

## Notes
- This repo **does not include** any web admin panels: `admin-panel/` and `doomctrl-tg-admin/` were removed as unused by the iOS app.

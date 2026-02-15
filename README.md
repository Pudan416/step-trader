# Proof (iOS, SwiftUI)

An iOS app that turns daily real-world activity into experience and spends that experience to open access windows for selected apps or app groups ("tickets").

## Core mechanics
- **Daily experience** is built from:
  - steps (HealthKit)
  - sleep hours
  - daily selections across body / mind / heart rooms
- **Bonus experience** can be granted and is added to the same spendable balance.
- **Spending experience** happens in PayGate when opening a ticket for a selected interval.
- **Minute mode** can track app usage via DeviceActivity and charge per-minute based on ticket settings.

## Targets
- **`Steps4`** — main iOS app (display name: **Proof**)
- **`DeviceActivityMonitor`** — extension (`com.apple.deviceactivity.monitor`) for interval/events and shield rebuilds
- **`ShieldConfiguration`** — extension that renders custom shield UI
- **`ShieldAction`** — extension handling shield actions and unlock flow

## Capabilities / Permissions
- **HealthKit (Read)** — step count and sleep hours
- **Family Controls + Device Activity + ManagedSettings** — app selection, monitoring, and shielding
- **App Group** — `group.personal-project.StepsTrader` (shared state between app + extensions)

Important: **ManagedSettings shielding is active**. Blocking and unblocking flow is implemented through ticket settings, DeviceActivity, and custom shield extensions.

## Deep links
Schemes registered in `Steps4/Info.plist`:
- `stepstrader://...`
- `steps-trader://...`

Examples (see `StepsTrader/AppModel.swift`):
- `steps-trader://pay?target=<bundleId|alias>`
- `steps-trader://guard?target=<bundleId|alias>`

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
- The repo includes an `admin-panel/` workspace used for operational tooling.

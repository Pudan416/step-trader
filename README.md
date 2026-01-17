# DOOM CTRL (iOS, SwiftUI)

An iOS app that converts steps (HealthKit) into “energy” and uses **DeviceActivity** for **usage-based minute mode** (charging steps per minute of actual usage of selected apps).

## Targets
- **`Steps4`**: main iOS app (display name: **DOOM CTRL**)
- **`DeviceActivityMonitor`**: extension (`com.apple.deviceactivity.monitor`) — receives DeviceActivity events and charges steps per minute

## Capabilities / Permissions
- **HealthKit (Read)**: step count reading
- **Family Controls + Device Activity**: app selection + usage-based tracking
- **App Group**: `group.personal-project.StepsTrader` (shared storage between the app and the extension)

Important: **ManagedSettings “shield blocking” has been removed**. The app does not attempt to block apps via iOS Screen Time shielding.

## Deep links
Schemes registered in `Steps4/Info.plist`:
- `stepstrader://...`
- `steps-trader://...`

Examples (see `StepsTrader/AppModel.swift`):
- `steps-trader://pay?target=<bundleId|alias>`
- `steps-trader://guard?target=<bundleId|alias>` *(guard no longer enables shielding; it’s kept only as a deeplink/UX trigger)*

## Configuration (Supabase)
Keys used in `Steps4/Info.plist`:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Recommendation: **don’t commit keys in `Info.plist`**. Move them to `.xcconfig` (Debug/Release) or use CI secrets + a gitignored local config.

## Run / Build
- For real **FamilyControls/DeviceActivity**, test on a **physical device** (entitlements + system limitations).
- Quick build check:

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build
```

## Project notes
- This repo **does not include** any web admin panels: previously present `admin-panel/` and `doomctrl-tg-admin/` were removed as unused by the iOS app.

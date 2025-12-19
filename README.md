# 👟⚡ Steps Trader (iOS 17+, SwiftUI)

## Capabilities
- HealthKit (Read)
- Family Controls
- Device Activity

Add to Info.plist:
- NSHealthShareUsageDescription = "Steps Trader needs access to your step count to manage app time."

## Notes
- Run on a real device. Family Controls/Device Activity require device and Apple entitlements.
- First launch requests HealthKit and Family Controls.
- "Choose from system list" opens the picker; the toggle starts monitoring.

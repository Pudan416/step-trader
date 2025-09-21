# 👟⚡ Steps Trader (iOS 17+, SwiftUI)

## Capabilities
- HealthKit (Read)
- Family Controls
- Device Activity

Add to Info.plist:
- NSHealthShareUsageDescription = "Steps Trader нужен доступ к шагам для управления временем приложений"

## Notes
- Run on a real device. Family Controls/Device Activity require device and Apple entitlements.
- First launch requests HealthKit and Family Controls.
- "Выбрать приложения" opens the picker; toggle starts monitoring.

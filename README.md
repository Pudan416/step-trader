# StepTimeLimiter (iOS 17+, SwiftUI)

## Capabilities
- HealthKit (Read)
- Family Controls
- Device Activity

Add to Info.plist:
- NSHealthShareUsageDescription = "Нужен доступ к шагам для лимита времени приложений"

## Notes
- Run on a real device. Family Controls/Device Activity require device and Apple entitlements.
- First launch requests HealthKit and Family Controls.
- "Выбрать приложения" opens the picker; toggle starts monitoring.

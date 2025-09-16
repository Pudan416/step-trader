import DeviceActivity
import FamilyControls

// Note: In production you'd place this in a DeviceActivityMonitor extension target.
public class DailyEventHandler: DeviceActivityEventHandler {
    public override func eventsDidReachThreshold(_ events: [DeviceActivityEvent.Name: DeviceActivityEvent]) {
        // We cannot access shared selection instance here directly in real extension; this is a stub for demo build.
        ShieldController.shared.enableShield(for: FamilyActivitySelection())
    }
}

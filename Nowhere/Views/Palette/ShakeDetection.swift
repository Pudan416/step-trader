import SwiftUI
import UIKit

/// SwiftUI has no shake gesture. UIKit delivers the motion event to the
/// responder chain and nothing forwards it, so the window republishes it as a
/// notification any view can observe.
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
    }
}

extension View {
    /// Runs `action` when the device is shaken.
    ///
    /// The palette is the only caller, and it guards on having no panel open —
    /// a shake behind the chooser or the creator should do nothing.
    func onShake(perform action: @escaping () -> Void) -> some View {
        onReceive(
            NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)
        ) { _ in
            action()
        }
    }
}

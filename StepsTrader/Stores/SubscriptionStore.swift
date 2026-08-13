import Foundation
import SwiftUI

/// Subscription state, retired.
///
/// The app is free for everyone and there is no purchase path, so this exists
/// only to keep `AppModel.isPro` and the `SubscriptionGate` call sites wired to
/// something. `DIContainer` still vends the shared instance; `AppModel`
/// subscribes to `objectWillChange` and that subscription simply never fires.
@MainActor
final class SubscriptionStore: ObservableObject {
    /// Always true. See `SubscriptionGate` for the gates this feeds.
    var isPro: Bool { true }
}

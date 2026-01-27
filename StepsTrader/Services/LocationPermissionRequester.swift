import Foundation
import CoreLocation
import SwiftUI

final class LocationPermissionRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    @MainActor
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }
}

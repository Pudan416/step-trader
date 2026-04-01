import Foundation
import CoreLocation
import Combine

@MainActor
class ProfileLocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var completion: ((String?) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func requestCountryCode(completion: @escaping (String?) -> Void) {
        self.completion = completion
        self.errorMessage = nil
        self.isLoading = true
        
        let status = manager.authorizationStatus
        
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location access denied. Enable in Settings."
            completion(nil)
        @unknown default:
            isLoading = false
            completion(nil)
        }
    }
    
    fileprivate func handleAuthorizationChange(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied {
            isLoading = false
            errorMessage = "Location access denied"
            completion?(nil)
        }
    }
    
    fileprivate func handleLocations(_ locations: [CLLocation]) {
        guard let location = locations.first else {
            isLoading = false
            completion?(nil)
            return
        }
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor in
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.completion?(nil)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    self?.completion?(nil)
                    return
                }
                
                self?.completion?(placemark.isoCountryCode)
                self?.completion = nil
            }
        }
    }
    
    fileprivate func handleError(_ error: Error) {
        isLoading = false
        
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain {
            switch CLError.Code(rawValue: nsError.code) {
            case .locationUnknown:
                errorMessage = "Could not determine location. Try again or select manually."
            case .denied:
                errorMessage = "Location access denied. Enable in Settings."
            case .network:
                errorMessage = "Network error. Check your connection."
            default:
                errorMessage = "Location error. Please select country manually."
            }
        } else {
            errorMessage = error.localizedDescription
        }
        
        completion?(nil)
        completion = nil
    }
}

extension ProfileLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.handleAuthorizationChange(manager) }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.handleLocations(locations) }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.handleError(error) }
    }
}

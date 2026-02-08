import Foundation
import CoreLocation
import Combine

class ProfileLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
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
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied {
            isLoading = false
            errorMessage = "Location access denied"
            completion?(nil)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            isLoading = false
            completion?(nil)
            return
        }
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
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
                
                let countryCode = placemark.isoCountryCode
                
                self?.completion?(countryCode)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            
            // Provide user-friendly error messages
            let nsError = error as NSError
            if nsError.domain == kCLErrorDomain {
                switch CLError.Code(rawValue: nsError.code) {
                case .locationUnknown:
                    self.errorMessage = "Could not determine location. Try again or select manually."
                case .denied:
                    self.errorMessage = "Location access denied. Enable in Settings."
                case .network:
                    self.errorMessage = "Network error. Check my connection."
                default:
                    self.errorMessage = "Location error. Please select country manually."
                }
            } else {
                self.errorMessage = error.localizedDescription
            }
            
            self.completion?(nil)
        }
    }
}

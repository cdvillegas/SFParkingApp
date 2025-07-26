import CoreLocation

class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    private let completion: (Bool) -> Void
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            AnalyticsManager.shared.logPermissionGranted(permissionType: "location")
            completion(true)
        case .denied, .restricted:
            AnalyticsManager.shared.logPermissionDenied(permissionType: "location")
            completion(false)
        case .notDetermined:
            // Still waiting for user decision
            break
        @unknown default:
            completion(false)
        }
    }
}
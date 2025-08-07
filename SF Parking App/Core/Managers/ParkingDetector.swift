import Foundation
import CoreLocation
import CoreMotion
import AVFoundation
import UIKit
import UserNotifications

// Simple rules for parking detection:
// 1. Car Connected + Driving Speed (>10mph) = Start tracking
// 2. Car Disconnected after driving = Save location and notify immediately

// MARK: - Supporting Types

enum ParkingDetectionState {
    case idle
    case connected
    case driving
    case parked
}

enum ParkingDetectionMethod {
    case carPlay
    case carAudio
    case bluetooth
}

struct DetectedParkingLocation {
    let coordinate: CLLocationCoordinate2D
    let address: String
    let timestamp: Date
    let confidence: Float
    let detectionMethod: ParkingDetectionMethod
}

class ParkingDetector: NSObject, ObservableObject {
    static let shared = ParkingDetector()
    
    // MARK: - Published Properties
    @Published var isMonitoring = false
    @Published var currentState: ParkingDetectionState = .idle
    @Published var currentParkingLocation: DetectedParkingLocation?
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var vehicleManager: VehicleManager?
    
    // Tracking data
    private var maxSpeedWhileConnected: Double = 0
    
    // Constants
    private let drivingSpeedThreshold: Double = 10.0 // mph
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
        setupNotifications()
        
        // Auto-start if previously enabled
        if UserDefaults.standard.bool(forKey: "parkingDetectionEnabled") {
            startMonitoring()
        }
    }
    
    // MARK: - Public API
    
    func configure(vehicleManager: VehicleManager) {
        self.vehicleManager = vehicleManager
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Check motion permission first
        guard hasMotionPermission() else {
            print("🚗 ❌ Smart Parking requires motion permission - requesting now")
            requestMotionPermissionAndStart()
            return
        }
        
        print("🚗 Starting Smart Parking")
        isMonitoring = true
        
        // Request location permission
        requestLocationPermission()
        
        // Check current car connection
        checkCarConnection()
        
        // Save state
        UserDefaults.standard.set(true, forKey: "parkingDetectionEnabled")
    }
    
    private func requestMotionPermissionAndStart() {
        // Check if motion is available
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("🚗 ❌ Motion tracking is not available on this device")
            return
        }
        
        let motionManager = CMMotionActivityManager()
        
        // Request motion permission by starting activity updates
        motionManager.startActivityUpdates(to: .main) { activity in
            // Stop immediately after permission is granted
            motionManager.stopActivityUpdates()
            
            DispatchQueue.main.async {
                print("🚗 ✅ Motion permission granted - starting Smart Parking")
                self.actuallyStartMonitoring()
            }
        }
        
        // Handle permission denial with a timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if CMMotionActivityManager.authorizationStatus() != .authorized {
                motionManager.stopActivityUpdates()
                print("🚗 ❌ Motion permission denied - cannot start Smart Parking")
                self.showMotionPermissionDeniedAlert()
            }
        }
    }
    
    private func actuallyStartMonitoring() {
        guard !isMonitoring else { return }
        
        print("🚗 Starting Smart Parking")
        isMonitoring = true
        
        // Request location permission
        requestLocationPermission()
        
        // Check current car connection
        checkCarConnection()
        
        // Save state
        UserDefaults.standard.set(true, forKey: "parkingDetectionEnabled")
    }
    
    private func showMotionPermissionDeniedAlert() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            
            let alert = UIAlertController(
                title: "Motion Permission Required",
                message: "Smart Parking needs access to motion data to detect when you've parked. This helps automatically update your parking location.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                // Open directly to Privacy & Security > Motion & Fitness settings
                if let url = URL(string: "App-Prefs:root=Privacy&path=MOTION") {
                    UIApplication.shared.open(url)
                }
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("🚗 Stopping Smart Parking")
        isMonitoring = false
        currentState = .idle
        
        // Clean up
        locationManager.stopUpdatingLocation()
        
        // Save state
        UserDefaults.standard.set(false, forKey: "parkingDetectionEnabled")
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        // Smart Park doesn't need background location updates
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        
        // For terminated app support
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    private func setupNotifications() {
        // Listen for audio route changes (car connection/disconnection)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    private func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            print("🚗 Location permission granted")
        default:
            print("🚗 ⚠️ Location permission denied")
        }
    }
    
    // MARK: - Car Connection Detection
    
    private func checkCarConnection() {
        if isCarConnected() {
            handleCarConnected()
        }
    }
    
    @objc private func audioRouteChanged() {
        guard isMonitoring else { return }
        
        if isCarConnected() {
            handleCarConnected()
        } else if currentState == .driving {
            handleCarDisconnected()
        }
    }
    
    private func isCarConnected() -> Bool {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        
        for output in currentRoute.outputs {
            // Check for car audio
            if output.portType == .carAudio {
                print("🚗 Car audio detected")
                return true
            }
            
            // Check for CarPlay
            if output.portType == .usbAudio && output.portName.lowercased().contains("carplay") {
                print("🚗 CarPlay detected")
                return true
            }
            
            // Check for Bluetooth with car keywords
            if output.portType == .bluetoothA2DP {
                let deviceName = output.portName.lowercased()
                let carKeywords = [
                    // Generic vehicle terms
                    "car", "vehicle", "auto", "automobile", "suv", "truck", "van", "sedan", "coupe",
                    "hatchback", "wagon", "minivan", "crossover", "pickup", "jeep",
                    
                    // Common Bluetooth terms
                    "handsfree", "hands-free", "hfp", "a2dp", "carplay", "android auto",
                    "uconnect", "sync", "mylink", "intellilink", "entune",
                    
                    // Car manufacturers
                    "toyota", "honda", "ford", "bmw", "mercedes", "benz", "audi", "volkswagen", "vw",
                    "tesla", "nissan", "mazda", "hyundai", "kia", "chevrolet", "chevy", "gmc",
                    "cadillac", "buick", "chrysler", "dodge", "ram", "jeep", "fiat", "alfa romeo",
                    "subaru", "mitsubishi", "lexus", "infiniti", "acura", "genesis", "lincoln",
                    "volvo", "porsche", "jaguar", "land rover", "range rover", "mini", "bentley",
                    "maserati", "ferrari", "lamborghini", "bugatti", "rolls royce", "aston martin",
                    "peugeot", "renault", "citroen", "skoda", "suzuki", "isuzu",
                    
                    // Common model names or abbreviations
                    "camry", "accord", "civic", "outback", "corolla", "prius", "rav4", "cr-v", "f-150",
                    "altima",
                    
                    // Years (recent model years)
                    "2018", "2019", "2020", "2021", "2022", "2023", "2024", "2025",
                ]
                
                if carKeywords.contains(where: deviceName.contains) {
                    print("🚗 Car Bluetooth detected: \(output.portName)")
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - State Management
    
    private func handleCarConnected() {
        print("🚗 Car connected")
        
        // Reset tracking
        maxSpeedWhileConnected = 0
        currentState = .connected
        
        // Start location updates
        locationManager.startUpdatingLocation()
        
        // Send test notification for car connection
        sendTestNotification(
            title: "🚗 Car Connected",
            body: "Smart Parking is now monitoring your drive"
        )
    }
    
    private func handleCarDisconnected() {
        print("🚗 Car disconnected")
        
        // Only save parking if we were driving
        guard currentState == .driving else {
            print("🚗 Wasn't driving - ignoring disconnection")
            currentState = .idle
            locationManager.stopUpdatingLocation()
            return
        }
        
        // Save parking location immediately
        if let location = locationManager.location {
            saveParkingLocation(location)
        }
        
        // Reset state
        currentState = .idle
        locationManager.stopUpdatingLocation()
    }
    
    
    // MARK: - Parking Location
    
    private func saveParkingLocation(_ location: CLLocation) {
        // Reverse geocode for address
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            let address = self.formatAddress(from: placemarks?.first) ?? "Parking Location"
            
            // Save to vehicle manager
            if let vehicleManager = self.vehicleManager,
               let currentVehicle = vehicleManager.currentVehicle {
                
                let parkingLocation = ParkingLocation(
                    coordinate: location.coordinate,
                    address: address,
                    timestamp: Date(),
                    source: .carDisconnect,
                    selectedSchedule: nil
                )
                
                vehicleManager.setParkingLocation(for: currentVehicle, location: parkingLocation)
                print("🚗 Parking saved: \(address)")
                
                // Send notification immediately
                self.sendParkingNotification(location: location, address: address)
                
                // Post notification for UI updates
                NotificationCenter.default.post(
                    name: .smartParkLocationSaved,
                    object: nil,
                    userInfo: [
                        "coordinate": location.coordinate,
                        "address": address
                    ]
                )
            }
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark?) -> String? {
        guard let placemark = placemark else { return nil }
        
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            return "\(streetNumber) \(streetName)"
        } else if let streetName = placemark.thoroughfare {
            return streetName
        } else if let name = placemark.name {
            return name
        }
        
        return nil
    }
    
    private func sendParkingNotification(location: CLLocation, address: String) {
        let content = UNMutableNotificationContent()
        content.title = "🅿️ Parking Location Saved"
        content.body = "Your car is parked at \(address)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "parking_saved_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🚗 Failed to send notification: \(error)")
            } else {
                print("🚗 Notification sent successfully")
            }
        }
    }
    
    private func sendTestNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "smart_park_test_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🚗 Failed to send test notification: \(error)")
            } else {
                print("🚗 Test notification sent: \(title)")
            }
        }
    }
    
    // MARK: - Motion Permission Check
    
    private func hasMotionPermission() -> Bool {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("🚗 Motion activity not available")
            return false
        }
        
        let status = CMMotionActivityManager.authorizationStatus()
        return status == .authorized
    }
    
    func checkMotionPermission() -> Bool {
        return hasMotionPermission()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - CLLocationManagerDelegate

extension ParkingDetector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update speed tracking when connected
        if currentState == .connected || currentState == .driving {
            let speedMph = location.speed * 2.23694 // m/s to mph
            
            if speedMph > maxSpeedWhileConnected {
                maxSpeedWhileConnected = speedMph
            }
            
            // Transition to driving state if threshold met
            if speedMph >= drivingSpeedThreshold && currentState == .connected {
                print("🚗 Driving detected (\(Int(speedMph)) mph)")
                currentState = .driving
                
                // Send test notification for driving detected
                sendTestNotification(
                    title: "🏎️ Driving Detected",
                    body: "Speed: \(Int(speedMph)) mph - Parking location will be saved when you disconnect"
                )
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            checkCarConnection()
        }
    }
}

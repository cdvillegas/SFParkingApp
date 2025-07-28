import Foundation
import CoreLocation
import CoreMotion
import AVFoundation
import UIKit
import UserNotifications

enum ParkingDetectionState {
    case idle           // No car connection
    case connected      // Car audio connected, monitoring speed
    case driving        // Confirmed driving (speed > 25 mph detected)
    case parked         // Connection lost after driving, location saved
}

enum ParkingDetectionMethod {
    case carPlay
    case carAudio
    case bluetooth
}

enum CarConnectionConfidence {
    case high    // .carAudio, CarPlay
    case low     // Generic USB, name matching
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
    @Published var currentState: ParkingDetectionState = .idle
    @Published var isMonitoring = false
    @Published var currentParkingLocation: DetectedParkingLocation?
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    // Dependencies
    private weak var vehicleManager: VehicleManager?
    
    // Speed tracking
    private var speedReadings: [(speed: Double, timestamp: Date)] = []
    private var speedTimer: Timer?
    private var maxSpeedInWindow: Double = 0
    
    // Motion validation
    private var motionValidationTimer: Timer?
    private var walkingDetected = false
    
    // Car connection tracking
    private var carConnectedTimestamp: Date?
    private var lastDisconnectionTime: Date?
    private var currentDetectionMethod: ParkingDetectionMethod?
    private var currentConnectionConfidence: CarConnectionConfidence = .low
    private var pendingParkingLocation: DetectedParkingLocation?
    
    // Settings
    private var isEnabled = false
    private let speedThreshold: Double = 10.0 // mph - lowered from 15 for better parking lot detection
    private let speedWindowDuration: TimeInterval = 600 // 10 minutes
    private let motionValidationDuration: TimeInterval = 600 // 10 minutes - extended from 20 seconds
    private let reconnectionGracePeriod: TimeInterval = 30 // 30 seconds
    
    override init() {
        super.init()
        setupLocationManager()
        setupAudioSession()
        setupNotifications()
        loadSettings()
    }
    
    // MARK: - Public API
    
    func configure(vehicleManager: VehicleManager) {
        self.vehicleManager = vehicleManager
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("🚗 Starting parking detection monitoring")
        isEnabled = true
        isMonitoring = true
        
        // Check initial car connection state
        checkInitialCarConnectionState()
        
        saveSettings()
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("🚗 Stopping parking detection monitoring")
        isEnabled = false
        isMonitoring = false
        
        stopSpeedMonitoring()
        stopMotionValidation()
        updateState(.idle)
        
        saveSettings()
    }
    
    func getCurrentParkingLocation() -> DetectedParkingLocation? {
        return currentParkingLocation
    }
    
    // MARK: - Setup Methods
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            print("🚗 Audio session configured for parking detection")
        } catch {
            print("🚗 ❌ Failed to setup audio session: \(error)")
        }
    }
    
    private func setupNotifications() {
        // Audio route change notifications (works in background)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // App lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // UIScreen notifications for CarPlay (foreground only)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
    }
    
    // MARK: - Car Connection Detection
    
    private func checkInitialCarConnectionState() {
        let isConnected = isCarAudioConnected()
        
        if isConnected {
            print("🚗 Car audio detected on startup")
            handleCarConnected()
        } else {
            print("🚗 No car audio detected on startup")
            updateState(.idle)
        }
    }
    
    private func isCarAudioConnected() -> Bool {
        // Check audio routes for car audio
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        
        print("🚗 🔍 Checking audio routes - found \(currentRoute.outputs.count) outputs:")
        for (index, output) in currentRoute.outputs.enumerated() {
            print("🚗   Output \(index): \(output.portType.rawValue) - \(output.portName)")
        }
        
        for output in currentRoute.outputs {
            let portName = output.portName.lowercased()
            
            // High Confidence Detection
            if output.portType == .carAudio {
                currentDetectionMethod = .carAudio
                currentConnectionConfidence = .high
                print("🚗 High confidence: iOS detected car audio")
                return true
            }
            
            if output.portType == .usbAudio && portName.contains("carplay") {
                currentDetectionMethod = .carPlay
                currentConnectionConfidence = .high
                print("🚗 High confidence: CarPlay detected")
                return true
            }
            
            // Low Confidence Detection
            if output.portType == .usbAudio {
                currentDetectionMethod = .carPlay
                currentConnectionConfidence = .low
                print("🚗 Low confidence: Generic USB audio")
                return true
            }
            
            // Check for Bluetooth A2DP devices
            if output.portType == .bluetoothA2DP {
                // Check for car brand names in Bluetooth device name (High Confidence)
                let carBrands = ["toyota", "honda", "ford", "bmw", "mercedes", "audi", "lexus", "acura", "infiniti", "cadillac", "buick", "gmc", "chevrolet", "chevy", "dodge", "ram", "jeep", "chrysler", "nissan", "mazda", "subaru", "hyundai", "kia", "volvo", "volkswagen", "vw", "porsche", "tesla", "mini", "land rover", "jaguar", "fiat", "alfa romeo"]
                
                for brand in carBrands {
                    if portName.contains(brand) {
                        currentDetectionMethod = .bluetooth
                        currentConnectionConfidence = .high  // Car brand names are high confidence
                        print("🚗 High confidence: Bluetooth device with car brand '\(brand)' - \(output.portName)")
                        return true
                    }
                }
                
                // Generic Bluetooth audio without car brand - Low Confidence
                currentDetectionMethod = .bluetooth
                currentConnectionConfidence = .low
                print("🚗 Low confidence: Generic Bluetooth A2DP device - \(output.portName)")
                return true
            }
            
            if portName.contains("car") {
                currentDetectionMethod = .carAudio
                currentConnectionConfidence = .low
                print("🚗 Low confidence: Device name contains 'car'")
                return true
            }
        }
        
        // Check for CarPlay via UIScreen (when app is active) - High Confidence
        let carPlayScreens = UIScreen.screens.filter { $0.traitCollection.userInterfaceIdiom == .carPlay }
        if !carPlayScreens.isEmpty {
            currentDetectionMethod = .carPlay
            currentConnectionConfidence = .high
            print("🚗 High confidence: CarPlay screen detected")
            return true
        }
        
        return false
    }
    
    @objc private func audioRouteChanged(notification: Notification) {
        print("🚗 Audio route changed (background capable)")
        print("🚗 Current state: \(currentState), isEnabled: \(isEnabled), isMonitoring: \(isMonitoring)")
        
        let isConnected = isCarAudioConnected()
        let wasConnected = (currentState == .connected || currentState == .driving)
        
        print("🚗 isConnected: \(isConnected), wasConnected: \(wasConnected)")
        
        if isConnected && !wasConnected {
            print("🚗 🔄 Handling car connection...")
            handleCarConnected()
        } else if !isConnected && wasConnected {
            print("🚗 🔄 Handling car disconnection...")
            handleCarDisconnected()
        } else {
            print("🚗 ℹ️ No state change needed")
        }
    }
    
    @objc private func screenDidConnect(notification: Notification) {
        if let screen = notification.object as? UIScreen,
           screen.traitCollection.userInterfaceIdiom == .carPlay {
            print("🚗 CarPlay screen connected")
            currentDetectionMethod = .carPlay
            handleCarConnected()
        }
    }
    
    @objc private func screenDidDisconnect(notification: Notification) {
        if let screen = notification.object as? UIScreen,
           screen.traitCollection.userInterfaceIdiom == .carPlay {
            print("🚗 CarPlay screen disconnected")
            handleCarDisconnected()
        }
    }
    
    @objc private func appDidBecomeActive() {
        if isMonitoring {
            checkInitialCarConnectionState()
        }
    }
    
    @objc private func appDidEnterBackground() {
        print("🚗 App entered background - parking detection continues via audio notifications")
    }
    
    // MARK: - State Management
    
    private func updateState(_ newState: ParkingDetectionState) {
        let oldState = currentState
        currentState = newState
        
        print("🚗 State: \(oldState) → \(newState)")
        
        DispatchQueue.main.async {
            // Update UI if needed
        }
    }
    
    private func handleCarConnected() {
        guard isEnabled else { return }
        
        print("🚗 ✅ Car connected via \(currentDetectionMethod?.description ?? "unknown")")
        
        // Check for quick reconnection (cancel parking)
        if let lastDisconnection = lastDisconnectionTime,
           Date().timeIntervalSince(lastDisconnection) < reconnectionGracePeriod {
            print("🚗 Quick reconnection detected - canceling parking detection")
            stopMotionValidation()
            // Cancel any pending parking location
            pendingParkingLocation = nil
            updateState(.connected)
            return
        }
        
        carConnectedTimestamp = Date()
        updateState(.connected)
        startSpeedMonitoring()
        
        // Request location permission if needed
        requestLocationPermissionIfNeeded()
    }
    
    private func handleCarDisconnected() {
        guard isEnabled else { return }
        guard currentState == .connected || currentState == .driving else { return }
        
        print("🚗 ❌ Car disconnected (Confidence: \(currentConnectionConfidence))")
        lastDisconnectionTime = Date()
        
        stopSpeedMonitoring()
        
        // Confidence-based parking detection
        let shouldStartParkingValidation: Bool
        
        if currentConnectionConfidence == .high {
            // High confidence - trust the connection, no speed validation needed
            shouldStartParkingValidation = true
            print("🚗 High confidence source - proceeding to parking validation")
        } else {
            // Low confidence - require driving confirmation
            if maxSpeedInWindow >= speedThreshold {
                shouldStartParkingValidation = true
                print("🚗 Low confidence source + driving confirmed (\(maxSpeedInWindow) mph) - proceeding to parking validation")
            } else {
                shouldStartParkingValidation = false
                print("🚗 Low confidence source + no driving detected (\(maxSpeedInWindow) mph) - ignoring")
            }
        }
        
        if shouldStartParkingValidation {
            // Save location immediately at disconnection time
            saveParkingLocationAtDisconnection()
            startWalkingValidation()
        } else {
            updateState(.idle)
        }
        
        // Reset for next connection
        speedReadings.removeAll()
        maxSpeedInWindow = 0
    }
    
    // MARK: - Speed Monitoring
    
    private func startSpeedMonitoring() {
        print("🚗 Starting speed monitoring")
        
        speedTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.updateSpeedReading()
        }
        
        // Get initial reading
        updateSpeedReading()
    }
    
    private func stopSpeedMonitoring() {
        speedTimer?.invalidate()
        speedTimer = nil
        print("🚗 Stopped speed monitoring")
    }
    
    private func updateSpeedReading() {
        guard let location = locationManager.location,
              location.speed >= 0 else { return }
        
        let speedMph = location.speed * 2.23694 // m/s to mph
        let now = Date()
        
        speedReadings.append((speed: speedMph, timestamp: now))
        
        // Remove readings older than window
        let cutoffTime = now.addingTimeInterval(-speedWindowDuration)
        speedReadings.removeAll { $0.timestamp < cutoffTime }
        
        // Update max speed in window
        maxSpeedInWindow = speedReadings.map { $0.speed }.max() ?? 0
        
        print("🚗 Speed: \(String(format: "%.1f", speedMph)) mph, Max in window: \(String(format: "%.1f", maxSpeedInWindow)) mph")
        
        // Transition to driving state if threshold met
        if maxSpeedInWindow >= speedThreshold && currentState == .connected {
            updateState(.driving)
        }
    }
    
    // MARK: - Parking Validation
    
    private func startWalkingValidation() {
        print("🚗 Starting walking validation - waiting for walking motion")
        
        startBackgroundTask()
        startMotionValidation()
        
        // Timeout for validation
        DispatchQueue.main.asyncAfter(deadline: .now() + motionValidationDuration) {
            print("🚗 ⏰ Walking validation timeout reached after \(self.motionValidationDuration) seconds")
            self.completeWalkingValidation()
        }
    }
    
    private func startMotionValidation() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("🚗 Motion activity not available - skipping validation")
            completeWalkingValidation()
            return
        }
        
        walkingDetected = false
        
        motionManager.startActivityUpdates(to: .main) { activity in
            guard let activity = activity else { 
                print("🚗 ⚠️ No motion activity data received")
                return 
            }
            
            print("🚗 Motion update - walking: \(activity.walking), confidence: \(activity.confidence.rawValue), automotive: \(activity.automotive), stationary: \(activity.stationary)")
            
            if activity.walking && activity.confidence == .high {
                print("🚗 ✅ Walking detected - parking validated")
                self.walkingDetected = true
                self.completeWalkingValidation()
            }
        }
    }
    
    private func stopMotionValidation() {
        motionManager.stopActivityUpdates()
        motionValidationTimer?.invalidate()
        motionValidationTimer = nil
    }
    
    private func completeWalkingValidation() {
        stopMotionValidation()
        
        if walkingDetected {
            // Confirm the parking location and send notification
            confirmParkingLocation()
        } else {
            print("🚗 No walking detected - parking not confirmed, discarding location")
            pendingParkingLocation = nil
            updateState(.idle)
        }
        
        endBackgroundTask()
    }
    
    // MARK: - Parking Location
    
    private func saveParkingLocationAtDisconnection() {
        guard let location = locationManager.location else {
            print("🚗 ❌ No location available at disconnection")
            updateState(.idle)
            return
        }
        
        print("🚗 📍 Saving parking location at disconnection time")
        
        // Reverse geocode for address
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            let address = self.formatAddress(from: placemarks?.first) ?? "Parking Location"
            
            let parkingLocation = DetectedParkingLocation(
                coordinate: location.coordinate,
                address: address,
                timestamp: Date(),
                confidence: 0.9,
                detectionMethod: self.currentDetectionMethod ?? .carAudio
            )
            
            DispatchQueue.main.async {
                // Store as pending until walking is confirmed
                self.pendingParkingLocation = parkingLocation
                print("🚗 Parking location saved (pending walking validation): \(address)")
            }
        }
    }
    
    private func confirmParkingLocation() {
        guard let pendingLocation = pendingParkingLocation else {
            print("🚗 ❌ No pending parking location to confirm")
            updateState(.idle)
            return
        }
        
        print("🚗 ✅ Walking confirmed - finalizing parking location")
        
        // Convert DetectedParkingLocation to ParkingLocation and save to vehicle
        let source: ParkingSource = {
            switch pendingLocation.detectionMethod {
            case .carPlay: return .carplay
            case .carAudio: return .carDisconnect
            case .bluetooth: return .bluetooth
            }
        }()
        
        let parkingLocation = ParkingLocation(
            coordinate: pendingLocation.coordinate,
            address: pendingLocation.address,
            timestamp: pendingLocation.timestamp,
            source: source
        )
        
        // Save to vehicle manager
        if let vehicleManager = vehicleManager,
           let currentVehicle = vehicleManager.currentVehicle {
            vehicleManager.setParkingLocation(for: currentVehicle, location: parkingLocation)
            print("🚗 Parking location saved to vehicle: \(pendingLocation.address)")
        } else {
            print("🚗 ⚠️ VehicleManager not available - location not saved to vehicle")
        }
        
        // Set as the current parking location for our own state
        currentParkingLocation = pendingLocation
        updateState(.parked)
        sendParkingNotification(location: pendingLocation)
        
        // Clear pending location
        pendingParkingLocation = nil
    }
    
    private func saveParkingLocation() {
        guard let location = locationManager.location else {
            print("🚗 ❌ No location available for parking")
            updateState(.idle)
            return
        }
        
        print("🚗 ✅ Saving parking location")
        
        // Reverse geocode for address
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            let address = placemarks?.first?.thoroughfare ?? "Unknown Location"
            
            let parkingLocation = DetectedParkingLocation(
                coordinate: location.coordinate,
                address: address,
                timestamp: Date(),
                confidence: 0.9,
                detectionMethod: self.currentDetectionMethod ?? .carAudio
            )
            
            DispatchQueue.main.async {
                self.currentParkingLocation = parkingLocation
                self.updateState(.parked)
                self.sendParkingNotification(location: parkingLocation)
            }
        }
    }
    
    private func sendParkingNotification(location: DetectedParkingLocation) {
        let content = UNMutableNotificationContent()
        content.title = "🅿️ Parking Location Saved"
        content.body = "Your car is parked at \(location.address)"
        content.sound = .default
        content.categoryIdentifier = "PARKING_SAVED"
        
        content.userInfo = [
            "type": "parking_location_update",
            "action": "open_parking_confirmation",
            "coordinate": [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude
            ],
            "address": location.address,
            "timestamp": location.timestamp.timeIntervalSince1970,
            "source": location.detectionMethod.rawValue
        ]
        
        let request = UNNotificationRequest(
            identifier: "parking_detection_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🚗 ❌ Failed to send parking notification: \(error)")
            } else {
                print("🚗 ✅ Parking notification sent")
            }
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark?) -> String? {
        guard let placemark = placemark else { return nil }
        
        // Try different address components
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            return "\(streetNumber) \(streetName)"
        } else if let streetName = placemark.thoroughfare {
            return streetName
        } else if let locality = placemark.locality {
            return locality
        } else if let name = placemark.name {
            return name
        }
        
        return nil
    }
    
    // MARK: - Background Task
    
    private func startBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    // MARK: - Permissions
    
    private func requestLocationPermissionIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("🚗 ⚠️ Location permission denied")
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    // MARK: - Settings
    
    private func loadSettings() {
        isEnabled = UserDefaults.standard.bool(forKey: "parkingDetectionEnabled")
        isMonitoring = isEnabled
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "parkingDetectionEnabled")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopSpeedMonitoring()
        stopMotionValidation()
        endBackgroundTask()
    }
}

// MARK: - CLLocationManagerDelegate

extension ParkingDetector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Speed monitoring is handled in updateSpeedReading()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .authorizedWhenInUse:
            // Request always authorization for background detection
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("🚗 Location access denied - parking detection won't work")
        default:
            break
        }
    }
}

// MARK: - Extensions

extension ParkingDetectionMethod {
    var description: String {
        switch self {
        case .carPlay: return "CarPlay"
        case .carAudio: return "Car Audio"
        case .bluetooth: return "Bluetooth"
        }
    }
    
    var rawValue: String {
        return description.lowercased()
    }
}
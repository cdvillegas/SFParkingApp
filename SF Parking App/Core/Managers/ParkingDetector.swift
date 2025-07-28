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
    
    // Settings
    private var isEnabled = false
    private let speedThreshold: Double = 25.0 // mph
    private let speedWindowDuration: TimeInterval = 600 // 10 minutes
    private let motionValidationDuration: TimeInterval = 20 // 20 seconds
    private let reconnectionGracePeriod: TimeInterval = 30 // 30 seconds
    
    override init() {
        super.init()
        setupLocationManager()
        setupAudioSession()
        setupNotifications()
        loadSettings()
    }
    
    // MARK: - Public API
    
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
        
        for output in currentRoute.outputs {
            if output.portType == .carAudio {
                currentDetectionMethod = .carAudio
                return true
            }
            
            if output.portType == .usbAudio {
                currentDetectionMethod = .carPlay
                return true
            }
            
            // Check for CarPlay via name
            let portName = output.portName.lowercased()
            if portName.contains("carplay") || portName.contains("car") {
                currentDetectionMethod = .carPlay
                return true
            }
        }
        
        // Check for CarPlay via UIScreen (when app is active)
        let carPlayScreens = UIScreen.screens.filter { $0.traitCollection.userInterfaceIdiom == .carPlay }
        if !carPlayScreens.isEmpty {
            currentDetectionMethod = .carPlay
            return true
        }
        
        return false
    }
    
    @objc private func audioRouteChanged(notification: Notification) {
        print("🚗 Audio route changed (background capable)")
        
        let isConnected = isCarAudioConnected()
        let wasConnected = (currentState == .connected || currentState == .driving)
        
        if isConnected && !wasConnected {
            handleCarConnected()
        } else if !isConnected && wasConnected {
            handleCarDisconnected()
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
        
        print("🚗 ❌ Car disconnected")
        lastDisconnectionTime = Date()
        
        stopSpeedMonitoring()
        
        // Check if we were actually driving
        if maxSpeedInWindow >= speedThreshold {
            print("🚗 Driving detected (max speed: \(maxSpeedInWindow) mph) - starting parking validation")
            startParkingValidation()
        } else {
            print("🚗 No significant driving detected (max speed: \(maxSpeedInWindow) mph) - ignoring")
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
    
    private func startParkingValidation() {
        print("🚗 Starting parking validation - waiting for walking motion")
        
        startBackgroundTask()
        startMotionValidation()
        
        // Timeout for validation
        DispatchQueue.main.asyncAfter(deadline: .now() + motionValidationDuration) {
            self.completeParkingValidation()
        }
    }
    
    private func startMotionValidation() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("🚗 Motion activity not available - skipping validation")
            completeParkingValidation()
            return
        }
        
        walkingDetected = false
        
        motionManager.startActivityUpdates(to: .main) { activity in
            guard let activity = activity else { return }
            
            if activity.walking && activity.confidence == .high {
                print("🚗 ✅ Walking detected - parking validated")
                self.walkingDetected = true
                self.completeParkingValidation()
            }
        }
    }
    
    private func stopMotionValidation() {
        motionManager.stopActivityUpdates()
        motionValidationTimer?.invalidate()
        motionValidationTimer = nil
    }
    
    private func completeParkingValidation() {
        stopMotionValidation()
        
        if walkingDetected {
            saveParkingLocation()
        } else {
            print("🚗 No walking detected - parking not confirmed")
            updateState(.idle)
        }
        
        endBackgroundTask()
    }
    
    // MARK: - Parking Location
    
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
        
        content.userInfo = [
            "type": "parking_location_update",
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
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
    
    // Visit monitoring for terminated app support
    private var isVisitMonitoringEnabled = false
    
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
    private let speedThreshold: Double = 15.0 // mph (reduced from 25)
    private let speedWindowDuration: TimeInterval = 600 // 10 minutes
    private let motionValidationDuration: TimeInterval = 20 // 20 seconds
    private let reconnectionGracePeriod: TimeInterval = 30 // 30 seconds
    
    // State persistence for background/terminated app recovery
    private struct PersistentState: Codable {
        let wasConnected: Bool
        let maxSpeed: Double
        let connectionTimestamp: Date?
        let lastLocationLatitude: Double?
        let lastLocationLongitude: Double?
        let version: Int // For future migrations
        let savedAt: Date // Track when state was saved
        
        var wasDriving: Bool {
            return maxSpeed >= 15.0
        }
        
        var lastLocation: CLLocation? {
            guard let lat = lastLocationLatitude, let lng = lastLocationLongitude else { return nil }
            return CLLocation(latitude: lat, longitude: lng)
        }
        
        var isStale: Bool {
            // Consider state stale after 2 hours
            return Date().timeIntervalSince(savedAt) > 7200
        }
        
        init(wasConnected: Bool, maxSpeed: Double, connectionTimestamp: Date?, lastLocation: CLLocation?) {
            self.wasConnected = wasConnected
            self.maxSpeed = maxSpeed
            self.connectionTimestamp = connectionTimestamp
            self.lastLocationLatitude = lastLocation?.coordinate.latitude
            self.lastLocationLongitude = lastLocation?.coordinate.longitude
            self.version = 1
            self.savedAt = Date()
        }
    }
    
    override init() {
        super.init()
        setupLocationManager()
        setupAudioSession()
        setupNotifications()
        loadSettings()
        
        // Check for pending parking detection on startup
        checkPendingParkingOnStartup()
    }
    
    // MARK: - Public API
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("🚗 Starting parking detection monitoring")
        isEnabled = true
        isMonitoring = true
        
        // Send debug notification
        sendDebugNotification(
            title: "🚗 Smart Park Enabled",
            body: "Monitoring started - App state: \(UIApplication.shared.applicationState.rawValue == 0 ? "active" : "background/inactive")"
        )
        
        // Start visit monitoring for terminated app support
        startVisitMonitoring()
        
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
        stopVisitMonitoring()
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
        
        return false
    }
    
    @objc private func audioRouteChanged(notification: Notification) {
        print("🚗 Audio route changed (background capable)")
        
        let isConnected = isCarAudioConnected()
        let wasConnected = (currentState == .connected || currentState == .driving)
        
        // Debug notification for route change
        let routeChangeReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reasonString = getRouteChangeReasonString(reason: routeChangeReason)
        
        sendDebugNotification(
            title: "🎵 Audio Route Changed",
            body: "Reason: \(reasonString), Connected: \(isConnected), App: \(UIApplication.shared.applicationState.rawValue == 0 ? "active" : "background")"
        )
        
        if isConnected && !wasConnected {
            handleCarConnected()
        } else if !isConnected && wasConnected {
            handleCarDisconnected()
        }
    }
    
    private func getRouteChangeReasonString(reason: UInt) -> String {
        switch reason {
        case AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue:
            return "New device available"
        case AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue:
            return "Old device unavailable"
        case AVAudioSession.RouteChangeReason.categoryChange.rawValue:
            return "Category change"
        case AVAudioSession.RouteChangeReason.override.rawValue:
            return "Override"
        case AVAudioSession.RouteChangeReason.wakeFromSleep.rawValue:
            return "Wake from sleep"
        case AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue:
            return "No suitable route"
        case AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue:
            return "Route configuration change"
        default:
            return "Unknown (\(reason))"
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
        
        // Send debug notification for connection
        sendDebugNotification(
            title: "🚗 Car Connected",
            body: "Connected via \(currentDetectionMethod?.description ?? "unknown") - App state: \(UIApplication.shared.applicationState.rawValue == 0 ? "active" : "background/inactive")"
        )
        
        // Check for quick reconnection (cancel parking)
        if let lastDisconnection = lastDisconnectionTime,
           Date().timeIntervalSince(lastDisconnection) < reconnectionGracePeriod {
            print("🚗 Quick reconnection detected - canceling parking detection")
            stopMotionValidation()
            clearPersistentState() // Clear any pending parking state
            updateState(.connected)
            return
        }
        
        carConnectedTimestamp = Date()
        updateState(.connected)
        startSpeedMonitoring()
        
        // Save initial state for background recovery
        savePersistentState()
        
        // Request location permission if needed
        requestLocationPermissionIfNeeded()
    }
    
    private func handleCarDisconnected() {
        guard isEnabled else { return }
        guard currentState == .connected || currentState == .driving else { return }
        
        print("🚗 ❌ Car disconnected")
        lastDisconnectionTime = Date()
        
        // Send debug notification for disconnection
        sendDebugNotification(
            title: "🚗 Car Disconnected",
            body: "Max speed: \(String(format: "%.1f", maxSpeedInWindow)) mph - App state: \(UIApplication.shared.applicationState.rawValue == 0 ? "active" : "background/inactive")"
        )
        
        stopSpeedMonitoring()
        
        // Confidence-based validation logic
        let shouldValidateParking = shouldValidateParkingBasedOnConfidence()
        
        if shouldValidateParking {
            let confidenceReason = getConfidenceReason()
            print("🚗 \(confidenceReason) - starting parking validation")
            sendDebugNotification(
                title: "🚗 Parking Validation Started",
                body: confidenceReason
            )
            startParkingValidation()
        } else {
            print("🚗 Low confidence connection (max speed: \(maxSpeedInWindow) mph) - ignoring")
            sendDebugNotification(
                title: "🚗 Parking Ignored",
                body: "Low confidence - Max speed: \(String(format: "%.1f", maxSpeedInWindow)) mph"
            )
            updateState(.idle)
        }
        
        // Reset for next connection
        speedReadings.removeAll()
        maxSpeedInWindow = 0
    }
    
    private func shouldValidateParkingBasedOnConfidence() -> Bool {
        // High confidence: iOS explicitly identifies this as car audio
        if currentDetectionMethod == .carAudio || currentDetectionMethod == .carPlay {
            print("🚗 High confidence car detection - trusting iOS identification")
            return true
        }
        
        // Medium confidence: Generic connection but confirmed driving speed
        if maxSpeedInWindow >= speedThreshold {
            return true
        }
        
        // Low confidence: Generic connection with low speed
        return false
    }
    
    private func getConfidenceReason() -> String {
        if currentDetectionMethod == .carAudio {
            return "iOS-confirmed car audio (confidence: high)"
        } else if currentDetectionMethod == .carPlay {
            return "iOS-confirmed CarPlay (confidence: high)"
        } else if maxSpeedInWindow >= speedThreshold {
            return "Driving speed confirmed: \(String(format: "%.1f", maxSpeedInWindow)) mph (confidence: medium)"
        } else {
            return "Unknown confidence level"
        }
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
        
        // Save updated state for background recovery
        savePersistentState()
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
    
    private func sendDebugNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "parking_debug_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🚗 ❌ Failed to send debug notification: \(error)")
            } else {
                print("🚗 ✅ Debug notification sent: \(title)")
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
    
    // MARK: - Visit Monitoring (for terminated app support)
    
    private func startVisitMonitoring() {
        guard locationManager.authorizationStatus == .authorizedAlways else {
            print("🚗 ⚠️ Visit monitoring requires Always location permission")
            return
        }
        
        print("🚗 Starting visit monitoring for terminated app support")
        locationManager.startMonitoringVisits()
        isVisitMonitoringEnabled = true
    }
    
    private func stopVisitMonitoring() {
        guard isVisitMonitoringEnabled else { return }
        
        print("🚗 Stopping visit monitoring")
        locationManager.stopMonitoringVisits()
        isVisitMonitoringEnabled = false
    }
    
    private func handleVisitEvent(_ visit: CLVisit) {
        print("🚗 📍 Visit detected - Arrival: \(visit.arrivalDate), Departure: \(visit.departureDate)")
        
        // Only process visit if we have a recent driving session
        guard let persistentState = loadPersistentState(),
              !persistentState.isStale,
              persistentState.wasDriving,
              let connectionTime = persistentState.connectionTimestamp,
              Date().timeIntervalSince(connectionTime) < 3600 else { // Within 1 hour
            print("🚗 Visit ignored - no recent driving session or state is stale")
            // Clean up stale state
            if let state = loadPersistentState(), state.isStale {
                clearPersistentState()
            }
            return
        }
        
        // If this is a departure from where we were connected, likely parking
        if visit.departureDate != Date.distantFuture {
            print("🚗 🅿️ Visit departure detected - potential parking location")
            validateParkingFromVisit(visit)
        }
    }
    
    private func validateParkingFromVisit(_ visit: CLVisit) {
        startBackgroundTask()
        
        // Use visit location as parking location
        let visitLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        
        // Quick motion check - if we can detect walking, confirm parking
        if CMMotionActivityManager.isActivityAvailable() {
            motionManager.queryActivityStarting(from: Date().addingTimeInterval(-60), // Last minute
                                              to: Date(),
                                              to: .main) { activities, error in
                
                let hasWalking = activities?.contains { $0.walking && $0.confidence == .high } ?? false
                
                if hasWalking {
                    print("🚗 ✅ Visit + walking detected - saving parking location")
                    self.saveParkingLocationFromVisit(visitLocation)
                } else {
                    print("🚗 ❌ Visit detected but no walking - not confirming parking")
                    // Still clear persistent state even if we don't save parking
                    self.clearPersistentState()
                }
                
                self.endBackgroundTask()
            }
        } else {
            // No motion available, save parking based on visit alone
            print("🚗 💾 Motion unavailable - saving parking based on visit")
            saveParkingLocationFromVisit(visitLocation)
            endBackgroundTask()
        }
    }
    
    private func saveParkingLocationFromVisit(_ location: CLLocation) {
        // Clear persistent state since we've processed it
        clearPersistentState()
        
        // Reverse geocode for address
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            let address = placemarks?.first?.thoroughfare ?? "Unknown Location"
            
            let parkingLocation = DetectedParkingLocation(
                coordinate: location.coordinate,
                address: address,
                timestamp: Date(),
                confidence: 0.7, // Lower confidence for visit-based detection
                detectionMethod: .carAudio
            )
            
            DispatchQueue.main.async {
                self.currentParkingLocation = parkingLocation
                self.updateState(.parked)
                self.sendParkingNotification(location: parkingLocation)
            }
        }
    }
    
    // MARK: - State Persistence
    
    private func savePersistentState() {
        let state = PersistentState(
            wasConnected: (currentState == .connected || currentState == .driving),
            maxSpeed: maxSpeedInWindow,
            connectionTimestamp: carConnectedTimestamp,
            lastLocation: locationManager.location
        )
        
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(state) {
            UserDefaults.standard.set(data, forKey: "parkingDetectorState")
            print("🚗 💾 Persistent state saved - wasDriving: \(state.wasDriving), maxSpeed: \(state.maxSpeed)")
        }
    }
    
    private func loadPersistentState() -> PersistentState? {
        guard let data = UserDefaults.standard.data(forKey: "parkingDetectorState") else { return nil }
        
        let decoder = JSONDecoder()
        do {
            let state = try decoder.decode(PersistentState.self, from: data)
            print("🚗 📱 Loaded persistent state - wasDriving: \(state.wasDriving), maxSpeed: \(state.maxSpeed)")
            return state
        } catch {
            print("🚗 ❌ Failed to decode persistent state: \(error)")
            // Clear corrupted state
            clearPersistentState()
            return nil
        }
    }
    
    private func clearPersistentState() {
        UserDefaults.standard.removeObject(forKey: "parkingDetectorState")
        print("🚗 🧹 Persistent state cleared")
    }
    
    private func checkPendingParkingOnStartup() {
        // Check if we have persistent state indicating a potential parking event
        guard let persistentState = loadPersistentState(),
              !persistentState.isStale,
              persistentState.wasDriving else {
            return
        }
        
        print("🚗 🔄 App startup detected pending parking state - monitoring visits")
        
        // If we have pending driving state on startup, we might have missed a parking event
        // Start visit monitoring immediately if we have permission
        if locationManager.authorizationStatus == .authorizedAlways {
            startVisitMonitoring()
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
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        print("🚗 📍 CLLocationManager visit received")
        handleVisitEvent(visit)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
            // Start visit monitoring if we're already monitoring
            if isMonitoring && !isVisitMonitoringEnabled {
                startVisitMonitoring()
            }
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
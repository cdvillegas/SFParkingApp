import Foundation
import CoreLocation
import Combine
import SwiftUI

// MARK: - Smart Park Parking Location
struct SmartParkLocation: Codable, Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let timestamp: Date
    let triggerType: String // "carPlay" or "bluetooth"
    let bluetoothDeviceName: String?
    var confirmationStatus: ConfirmationStatus
    var detectedSchedule: PersistedSweepSchedule? // For confirmation mode
    
    enum ConfirmationStatus: String, Codable {
        case pending = "pending"
        case confirmed = "confirmed"
        case cancelled = "cancelled"
        case requiresUserConfirmation = "requiresUserConfirmation" // New status
    }
    
    // Custom encoding/decoding for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, coordinate, address, timestamp, triggerType, bluetoothDeviceName, confirmationStatus, detectedSchedule
    }
    
    enum CoordinateKeys: String, CodingKey {
        case latitude, longitude
    }
    
    init(id: String = UUID().uuidString,
         coordinate: CLLocationCoordinate2D,
         address: String?,
         timestamp: Date = Date(),
         triggerType: String,
         bluetoothDeviceName: String? = nil,
         confirmationStatus: ConfirmationStatus = .pending,
         detectedSchedule: PersistedSweepSchedule? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.address = address
        self.timestamp = timestamp
        self.triggerType = triggerType
        self.bluetoothDeviceName = bluetoothDeviceName
        self.confirmationStatus = confirmationStatus
        self.detectedSchedule = detectedSchedule
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coordinateContainer = try container.nestedContainer(keyedBy: CoordinateKeys.self, forKey: .coordinate)
        
        let latitude = try coordinateContainer.decode(Double.self, forKey: .latitude)
        let longitude = try coordinateContainer.decode(Double.self, forKey: .longitude)
        
        self.id = try container.decode(String.self, forKey: .id)
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.address = try container.decodeIfPresent(String.self, forKey: .address)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.triggerType = try container.decode(String.self, forKey: .triggerType)
        self.bluetoothDeviceName = try container.decodeIfPresent(String.self, forKey: .bluetoothDeviceName)
        self.confirmationStatus = try container.decode(ConfirmationStatus.self, forKey: .confirmationStatus)
        self.detectedSchedule = try container.decodeIfPresent(PersistedSweepSchedule.self, forKey: .detectedSchedule)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var coordinateContainer = container.nestedContainer(keyedBy: CoordinateKeys.self, forKey: .coordinate)
        
        try container.encode(id, forKey: .id)
        try coordinateContainer.encode(coordinate.latitude, forKey: .latitude)
        try coordinateContainer.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(triggerType, forKey: .triggerType)
        try container.encodeIfPresent(bluetoothDeviceName, forKey: .bluetoothDeviceName)
        try container.encode(confirmationStatus, forKey: .confirmationStatus)
        try container.encodeIfPresent(detectedSchedule, forKey: .detectedSchedule)
    }
    
    // Equatable conformance
    static func == (lhs: SmartParkLocation, rhs: SmartParkLocation) -> Bool {
        return lhs.id == rhs.id &&
               lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.address == rhs.address &&
               lhs.timestamp == rhs.timestamp &&
               lhs.triggerType == rhs.triggerType &&
               lhs.bluetoothDeviceName == rhs.bluetoothDeviceName &&
               lhs.confirmationStatus == rhs.confirmationStatus
    }
}

// MARK: - Parking Location Manager
@MainActor
class ParkingLocationManager: ObservableObject {
    static let shared = ParkingLocationManager()
    
    @Published var pendingSmartParkLocation: SmartParkLocation?
    
    private let locationManager = LocationManager()
    private let geocoder = CLGeocoder()
    private var confirmationTimer: Timer?
    
    // UserDefaults key - only for pending location during 2-minute wait
    private let pendingLocationKey = "smartPark2_pendingLocation"
    
    private init() {
        loadPersistedLocations()
    }
    
    // MARK: - Public Methods
    
    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        
        // Request location permission if needed
        if locationManager.authorizationStatus == .notDetermined {
            print("📍 [Smart Park] Location permission not determined, requesting...")
            locationManager.requestLocationPermission()
            // Wait a moment for permission dialog
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // If we have a recent location, use it
        if let currentLocation = locationManager.userLocation,
           currentLocation.timestamp.timeIntervalSinceNow > -30 { // Less than 30 seconds old
            print("📍 [Smart Park] Using cached location: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
            return currentLocation.coordinate
        }
        
        print("📍 [Smart Park] Requesting fresh location...")
        // Otherwise request a fresh location
        return await withCheckedContinuation { continuation in
            locationManager.requestLocation()
            
            // Use a class to safely share state between closures
            class LocationState {
                var isResumed = false
                let lock = NSLock()
                
                func safeResume(with result: CLLocationCoordinate2D?, continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>) -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    
                    if !isResumed {
                        isResumed = true
                        continuation.resume(returning: result)
                        return true
                    }
                    return false
                }
            }
            
            let state = LocationState()
            
            // Set up a one-time observer for location update
            var cancellable: AnyCancellable?
            cancellable = locationManager.$userLocation
                .compactMap { $0 }
                .first()
                .sink { location in
                    if state.safeResume(with: location.coordinate, continuation: continuation) {
                        print("📍 [Smart Park] Got fresh location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    }
                    cancellable?.cancel()
                }
            
            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                
                if state.safeResume(with: nil, continuation: continuation) {
                    print("⏰ [Smart Park] Location request timed out")
                }
                cancellable?.cancel()
            }
        }
    }
    
    func savePendingParkingLocation(
        at coordinate: CLLocationCoordinate2D,
        triggerType: ParkingTriggerType
    ) async throws -> SmartParkLocation {
        print("💾 [Smart Park] Saving pending parking location for confirmation - Type: \(triggerType.rawValue)")
        print("💾 [Smart Park] Coordinates: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Validate coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0,
              coordinate.longitude != 0 else {
            print("❌ [Smart Park] Invalid coordinates provided")
            throw IntentError.invalidCoordinates
        }
        
        // Get address for the coordinate
        let address = await reverseGeocode(coordinate: coordinate)
        if let address = address {
            print("🏠 [Smart Park] Geocoded address: \(address)")
        } else {
            print("🏠 [Smart Park] No address found for coordinates")
        }
        
        // Detect schedule for the location
        let detectedSchedule = await detectScheduleForLocation(coordinate)
        if let schedule = detectedSchedule {
            print("📅 [Smart Park] Detected schedule: \(schedule.streetName) - \(schedule.weekday) \(schedule.startTime)-\(schedule.endTime)")
        } else {
            print("📅 [Smart Park] No schedule detected for this location")
        }
        
        // Create pending parking location with detected schedule
        let parkingLocation = SmartParkLocation(
            coordinate: coordinate,
            address: address,
            triggerType: triggerType.rawValue,
            bluetoothDeviceName: nil,
            confirmationStatus: .requiresUserConfirmation,
            detectedSchedule: detectedSchedule
        )
        
        // Save as pending for user confirmation
        pendingSmartParkLocation = parkingLocation
        savePendingLocation(parkingLocation)
        
        // Send notification for confirmation
        await NotificationManager.shared.sendParkingConfirmationRequired(for: parkingLocation)
        
        return parkingLocation
    }
    
    func saveParkingLocation(
        at coordinate: CLLocationCoordinate2D,
        triggerType: ParkingTriggerType,
        delayConfirmation: Bool
    ) async throws -> SmartParkLocation {
        print("💾 [Smart Park] Saving parking location - Type: \(triggerType.rawValue), Delay: \(delayConfirmation)")
        print("💾 [Smart Park] Coordinates: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Validate coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0,
              coordinate.longitude != 0 else {
            print("❌ [Smart Park] Invalid coordinates provided")
            throw IntentError.invalidCoordinates
        }
        
        // Get address for the coordinate
        let address = await reverseGeocode(coordinate: coordinate)
        if let address = address {
            print("🏠 [Smart Park] Geocoded address: \(address)")
        } else {
            print("🏠 [Smart Park] No address found for coordinates")
        }
        
        // Create parking location
        let parkingLocation = SmartParkLocation(
            coordinate: coordinate,
            address: address,
            triggerType: triggerType.rawValue,
            bluetoothDeviceName: nil, // Will be set by the intent if needed
            confirmationStatus: delayConfirmation ? .pending : .confirmed
        )
        
        // Save to storage
        if delayConfirmation {
            print("⏳ [Smart Park] Saving as pending - will confirm in 2 minutes")
            pendingSmartParkLocation = parkingLocation
            savePendingLocation(parkingLocation)
            // No notification sent - wait for 2-minute confirmation
        } else {
            print("✅ [Smart Park] Immediate confirmation - saving to vehicle manager")
            // Immediately save to the main app's vehicle manager and send confirmation
            await saveToVehicleManager(parkingLocation)
            await NotificationManager.shared.sendParkingConfirmation(for: parkingLocation)
        }
        
        return parkingLocation
    }
    
    func saveSmartParkLocationAutomatic(
        at coordinate: CLLocationCoordinate2D,
        triggerType: ParkingTriggerType
    ) async throws -> SmartParkLocation {
        print("🤖 [Smart Park] Automatic mode - saving location with schedule detection")
        print("💾 [Smart Park] Coordinates: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Validate coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0,
              coordinate.longitude != 0 else {
            print("❌ [Smart Park] Invalid coordinates provided")
            throw IntentError.invalidCoordinates
        }
        
        // Get address for the coordinate
        let address = await reverseGeocode(coordinate: coordinate)
        if let address = address {
            print("🏠 [Smart Park] Geocoded address: \(address)")
        } else {
            print("🏠 [Smart Park] No address found for coordinates")
        }
        
        // Detect schedule for the location
        let detectedSchedule = await detectScheduleForLocation(coordinate)
        if let schedule = detectedSchedule {
            print("📅 [Smart Park] Automatically detected schedule: \(schedule.streetName) - \(schedule.weekday) \(schedule.startTime)-\(schedule.endTime)")
        } else {
            print("📅 [Smart Park] No schedule detected for this location")
        }
        
        // Create confirmed parking location with detected schedule
        let parkingLocation = SmartParkLocation(
            coordinate: coordinate,
            address: address,
            triggerType: triggerType.rawValue,
            bluetoothDeviceName: nil,
            confirmationStatus: .confirmed,
            detectedSchedule: detectedSchedule
        )
        
        // Save immediately to vehicle manager with schedule
        await saveToVehicleManager(parkingLocation)
        
        // Notify UI to recenter map on new parking location and include schedule data
        await MainActor.run {
            var userInfo: [String: Any] = [
                "coordinate": [
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude
                ],
                "address": address ?? ""
            ]
            
            // Include detected schedule in notification for immediate UI update
            if let schedule = detectedSchedule {
                userInfo["detectedSchedule"] = [
                    "streetName": schedule.streetName,
                    "weekday": schedule.weekday,
                    "startTime": schedule.startTime,
                    "endTime": schedule.endTime,
                    "blockSide": schedule.blockSide
                ]
                print("📅 [Smart Park] Including schedule in notification: \(schedule.streetName) - \(schedule.weekday) \(schedule.startTime)-\(schedule.endTime)")
            }
            
            NotificationCenter.default.post(
                name: .smartParkAutomaticUpdateCompleted,
                object: nil,
                userInfo: userInfo
            )
        }
        
        print("✅ [Smart Park] Location automatically saved with schedule")
        
        return parkingLocation
    }
    
    func confirmPendingLocation() async {
        print("✅ [Smart Park] Confirming pending location")
        
        guard let pendingLocation = pendingSmartParkLocation else {
            print("⚠️ [Smart Park] No pending location to confirm")
            return
        }
        
        // Update status to confirmed
        var confirmedLocation = pendingLocation
        confirmedLocation.confirmationStatus = .confirmed
        
        // Clear pending
        pendingSmartParkLocation = nil
        clearPendingLocation()
        
        // Save to main app with the detected schedule
        await saveToVehicleManager(confirmedLocation)
        
        print("✅ [Smart Park] Location confirmed and saved")
    }
    
    func cancelPendingLocation() {
        print("❌ [Smart Park] Cancelling pending location")
        
        pendingSmartParkLocation = nil
        clearPendingLocation()
        
        print("❌ [Smart Park] Pending location cancelled")
    }
    
    func updateParkingLocation(
        id: String,
        newLocation: CLLocationCoordinate2D
    ) async throws -> SmartParkLocation {
        // Find the pending location
        guard let parkingLocation = pendingSmartParkLocation,
              parkingLocation.id == id else {
            throw IntentError.parkingNotFound
        }
        
        // Validate new coordinate
        guard CLLocationCoordinate2DIsValid(newLocation),
              newLocation.latitude != 0,
              newLocation.longitude != 0 else {
            throw IntentError.invalidCoordinates
        }
        
        // Get new address
        let newAddress = await reverseGeocode(coordinate: newLocation)
        
        // Create updated location
        let updatedLocation = SmartParkLocation(
            id: parkingLocation.id,
            coordinate: newLocation,
            address: newAddress,
            timestamp: Date(), // Update timestamp
            triggerType: parkingLocation.triggerType,
            bluetoothDeviceName: parkingLocation.bluetoothDeviceName,
            confirmationStatus: .confirmed
        )
        
        // Clear pending
        pendingSmartParkLocation = nil
        clearPendingLocation()
        
        // Save to main app's vehicle manager
        await saveToVehicleManager(updatedLocation)
        
        return updatedLocation
    }
    
    func scheduleConfirmationCheck(for location: SmartParkLocation) async {
        await MainActor.run {
            scheduleConfirmationCheck(for: location, delay: 120)
        }
    }
    
    // MARK: - Private Methods
    
    private func performConfirmationCheck(for location: SmartParkLocation) async {
        print("⏰ [Smart Park] Performing 2-minute confirmation check for \(location.id)")
        
        // Check if still pending
        guard let pending = pendingSmartParkLocation,
              pending.id == location.id else {
            print("⚠️ [Smart Park] No matching pending location found - may have been cleared")
            return
        }
        
        // Check car connection
        let detector = CarConnectionDetector()
        let isConnected = await detector.isCarConnected(
            type: ParkingTriggerType(rawValue: location.triggerType) ?? .carPlay
        )
        
        print("🚗 [Smart Park] Car connection status after 2 minutes: \(isConnected ? "CONNECTED" : "DISCONNECTED")")
        
        if !isConnected {
            print("✅ [Smart Park] Car still disconnected - confirming parking location")
            // Car is still disconnected, confirm the location
            var confirmedLocation = location
            confirmedLocation.confirmationStatus = .confirmed
            
            // Clear pending
            pendingSmartParkLocation = nil
            clearPendingLocation()
            
            // Save to main app and send notification
            await saveToVehicleManager(confirmedLocation)
            await NotificationManager.shared.sendParkingConfirmation(for: confirmedLocation)
        } else {
            print("🚫 [Smart Park] Car reconnected - cancelling parking detection")
            // Car reconnected, cancel the parking
            pendingSmartParkLocation = nil
            clearPendingLocation()
        }
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String? {
        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                return formatAddress(from: placemark)
            }
        } catch {
            print("Geocoding error: \(error)")
        }
        
        return nil
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var addressParts: [String] = []
        
        // Combine street number and street name without comma
        var streetAddress = ""
        if let streetNumber = placemark.subThoroughfare {
            streetAddress += streetNumber
        }
        if let streetName = placemark.thoroughfare {
            if !streetAddress.isEmpty {
                streetAddress += " " + streetName
            } else {
                streetAddress = streetName
            }
        }
        
        if !streetAddress.isEmpty {
            addressParts.append(streetAddress)
        } else if let name = placemark.name {
            addressParts.append(name)
        }
        
        if let city = placemark.locality {
            addressParts.append(city)
        }
        
        return addressParts.joined(separator: ", ")
    }
    
    func saveToVehicleManager(_ smartParkLocation: SmartParkLocation) async {
        print("🚙 [Smart Park] Saving to VehicleManager - Address: \(smartParkLocation.address ?? "Unknown")")
        
        // Use already-detected schedule if available, otherwise detect it
        let selectedSchedule: PersistedSweepSchedule?
        if let detectedSchedule = smartParkLocation.detectedSchedule {
            print("📅 [Smart Park] Using already-detected schedule: \(detectedSchedule.streetName) - \(detectedSchedule.weekday) \(detectedSchedule.startTime)-\(detectedSchedule.endTime)")
            selectedSchedule = detectedSchedule
        } else {
            print("📅 [Smart Park] No pre-detected schedule, detecting schedule for the parking location")
            selectedSchedule = await detectScheduleForLocation(smartParkLocation.coordinate)
            if let schedule = selectedSchedule {
                print("📅 [Smart Park] Found schedule: \(schedule.streetName) - \(schedule.weekday) \(schedule.startTime)-\(schedule.endTime)")
            } else {
                print("📅 [Smart Park] No schedule found for this location")
            }
        }
        
        // Convert to regular ParkingLocation with schedule information
        let parkingLocation = ParkingLocation(
            coordinate: smartParkLocation.coordinate,
            address: smartParkLocation.address ?? "Unknown Location",
            timestamp: smartParkLocation.timestamp,
            source: smartParkLocation.triggerType == "carPlay" ? .carplay : .bluetooth,
            selectedSchedule: selectedSchedule
        )
        
        // Get the vehicle manager and update
        if let vehicle = VehicleManager.shared.currentVehicle {
            VehicleManager.shared.setParkingLocation(for: vehicle, location: parkingLocation)
            print("✅ [Smart Park] Successfully saved to VehicleManager with schedule")
            
            // CRITICAL FIX: Update StreetDataManager to process the schedule for immediate UI updates
            await updateStreetDataManager(with: selectedSchedule, at: smartParkLocation.coordinate)
        } else {
            print("⚠️ [Smart Park] No vehicle found in VehicleManager")
        }
    }
    
    private func detectScheduleForLocation(_ coordinate: CLLocationCoordinate2D) async -> PersistedSweepSchedule? {
        print("🔍 [Smart Park] ========== SCHEDULE DETECTION STARTING ==========")
        print("🔍 [Smart Park] Detecting schedule for coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        
        return await withCheckedContinuation { continuation in
            // Get the raw schedule data with centerline geometry for true geometric detection
            StreetDataService.shared.getClosestScheduleWithGeometry(for: coordinate) { result in
                switch result {
                case .success(let scheduleData):
                    if let (rawSchedules, closestSchedule) = scheduleData {
                        print("📅 [Smart Park] Using TRUE geometric side detection with street centerline")
                        
                        if let (determinedSide, matchedSchedule) = self.determineActualSideOfStreetWithSchedule(
                            userLocation: coordinate,
                            streetSchedules: rawSchedules,
                            closestSchedule: closestSchedule
                        ) {
                            print("📅 [Smart Park] Geometric detection result: \(closestSchedule.streetName ?? "Unknown") - \(determinedSide)")
                            
                            let persistedSchedule = PersistedSweepSchedule(
                                from: matchedSchedule,
                                side: determinedSide
                            )
                            continuation.resume(returning: persistedSchedule)
                        } else {
                            print("📅 [Smart Park] Geometric detection failed, using closest schedule")
                            let persistedSchedule = PersistedSweepSchedule(
                                from: closestSchedule,
                                side: "Both"
                            )
                            continuation.resume(returning: persistedSchedule)
                        }
                    } else {
                        print("📅 [Smart Park] No schedule data found")
                        continuation.resume(returning: nil)
                    }
                case .failure(let error):
                    print("❌ [Smart Park] Failed to get schedule geometry: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func selectBestScheduleForAutoDetection(_ schedulesWithSides: [SweepScheduleWithSide], userLocation: CLLocationCoordinate2D) -> SweepScheduleWithSide? {
        guard !schedulesWithSides.isEmpty else { return nil }
        
        print("🎯 [Smart Park] Selecting best schedule from \(schedulesWithSides.count) options using street geometry:")
        
        // Group schedules by street name to handle multiple sides of the same street
        let schedulesByStreet = Dictionary(grouping: schedulesWithSides) { schedule in
            schedule.schedule.streetName ?? "Unknown"
        }
        
        var bestSchedule: SweepScheduleWithSide?
        var bestScore = Double.infinity
        
        for (streetName, streetSchedules) in schedulesByStreet {
            print("   🛣️ Analyzing \(streetName) with \(streetSchedules.count) sides")
            
            if streetSchedules.count >= 2 {
                // Multiple sides available - use geometric side detection
                let selected = selectBestSideGeometrically(streetSchedules, userLocation: userLocation)
                
                let distance = selected.distance
                print("   ✅ \(streetName) \(selected.side): \(String(format: "%.2f", distance)) meters (geometric selection)")
                
                if distance < bestScore {
                    bestScore = distance
                    bestSchedule = selected
                }
            } else if let single = streetSchedules.first {
                // Only one side available - use it
                let distance = single.distance
                print("   ➡️ \(streetName) \(single.side): \(String(format: "%.2f", distance)) meters (only option)")
                
                if distance < bestScore {
                    bestScore = distance
                    bestSchedule = single
                }
            }
        }
        
        if let best = bestSchedule {
            print("🏆 [Smart Park] Selected: \(best.schedule.streetName ?? "Unknown") \(best.side)")
        }
        
        return bestSchedule
    }
    
    private func selectBestSideGeometrically(_ streetSchedules: [SweepScheduleWithSide], userLocation: CLLocationCoordinate2D) -> SweepScheduleWithSide {
        print("     🧭 Using TRUE GEOMETRIC side detection")
        
        // First, try to determine which side of the street the user is actually on using geometry
        if let geometricallyDeterminedSchedule = determineGeometricSide(streetSchedules, userLocation: userLocation) {
            return geometricallyDeterminedSchedule
        }
        
        // Fallback to preference logic if geometric detection fails
        print("     ⚠️ Geometric detection failed, falling back to preference logic")
        
        let bestSchedule = streetSchedules.min { schedule1, schedule2 in
            let side1Lower = schedule1.side.lowercased()
            let side2Lower = schedule2.side.lowercased()
            
            print("     🔍 Comparing \(schedule1.side) vs \(schedule2.side)")
            print("       - Base distances: \(String(format: "%.2f", schedule1.distance)) vs \(String(format: "%.2f", schedule2.distance)) meters")
            
            // Prefer more specific side designations
            let side1Specific = side1Lower.contains("north") || side1Lower.contains("south") || 
                               side1Lower.contains("east") || side1Lower.contains("west")
            let side2Specific = side2Lower.contains("north") || side2Lower.contains("south") || 
                               side2Lower.contains("east") || side2Lower.contains("west")
            
            if side1Specific && !side2Specific {
                print("       - Preferring \(schedule1.side) (more specific)")
                return true
            } else if side2Specific && !side1Specific {
                print("       - Preferring \(schedule2.side) (more specific)")
                return false
            }
            
            // Otherwise, use distance
            return schedule1.distance < schedule2.distance
        }
        
        return bestSchedule ?? streetSchedules.first!
    }
    
    private func determineGeometricSide(_ streetSchedules: [SweepScheduleWithSide], userLocation: CLLocationCoordinate2D) -> SweepScheduleWithSide? {
        // We need access to the street centerline geometry to do proper geometric side detection
        // For now, this is a placeholder - we'd need to modify the data structure to include
        // the actual line geometry from AggregatedSweepSchedule.lineCoordinates
        
        print("     📐 Geometric side detection: Need street line geometry data")
        print("     📍 User location: \(userLocation.latitude), \(userLocation.longitude)")
        
        // This requires the actual street line segments from AggregatedSweepSchedule.lineCoordinates
        // to calculate which side of the centerline the user is on using cross product math
        
        // For now, we'll use a distance-based heuristic with the offset coordinates
        var bestSchedule: SweepScheduleWithSide?
        var bestDistance = Double.infinity
        
        for schedule in streetSchedules {
            let distance = CLLocation(latitude: schedule.offsetCoordinate.latitude, longitude: schedule.offsetCoordinate.longitude)
                .distance(from: CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude))
            
            print("     📏 \(schedule.side): \(String(format: "%.6f", distance)) meters from offset coordinate")
            
            if distance < bestDistance {
                bestDistance = distance
                bestSchedule = schedule
            }
        }
        
        if let best = bestSchedule {
            print("     ✅ Geometric selection: \(best.side) (closest to user)")
        }
        
        return bestSchedule
    }
    
    private func determineActualSideOfStreetWithSchedule(
        userLocation: CLLocationCoordinate2D,
        streetSchedules: [AggregatedSweepSchedule],
        closestSchedule: SweepSchedule
    ) -> (String, SweepSchedule)? {
        print("📐 [Geometric Detection] Starting TRUE geometric side detection")
        print("📐 [Geometric Detection] User location: \(userLocation.latitude), \(userLocation.longitude)")
        print("📐 [Geometric Detection] Available schedules: \(streetSchedules.count)")
        
        for (index, schedule) in streetSchedules.enumerated() {
            let days = [
                ("Mon", schedule.mondayHours),
                ("Tue", schedule.tuesdayHours), 
                ("Wed", schedule.wednesdayHours),
                ("Thu", schedule.thursdayHours),
                ("Fri", schedule.fridayHours),
                ("Sat", schedule.saturdayHours),
                ("Sun", schedule.sundayHours)
            ]
            let activeDays = days.filter { !$0.1.isEmpty }.map { "\($0.0):\($0.1)" }
            print("📐 [DEBUG] Schedule \(index): \(schedule.blockSide) - Days: \(activeDays.joined(separator: ", "))")
        }
        
        // Find the schedule that matches our closest schedule
        guard let matchingSchedule = streetSchedules.first(where: { aggregated in
            aggregated.corridor == closestSchedule.corridor && 
            !aggregated.lineCoordinates.isEmpty
        }) else {
            print("📐 [Geometric Detection] No matching schedule with geometry found")
            return nil
        }
        
        print("📐 [Geometric Detection] Using schedule: \(matchingSchedule.corridor)")
        print("📐 [Geometric Detection] Line segments: \(matchingSchedule.lineCoordinates.count)")
        
        // Find the closest line segment to the user
        var closestSegmentIndex: Int?
        var closestDistance = Double.infinity
        var closestPoint: CLLocationCoordinate2D?
        
        for i in 0..<(matchingSchedule.lineCoordinates.count - 1) {
            let startCoord = matchingSchedule.lineCoordinates[i]
            let endCoord = matchingSchedule.lineCoordinates[i + 1]
            
            // Validate coordinates
            guard startCoord.count >= 2 && endCoord.count >= 2 else { continue }
            
            let segmentStart = CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0])
            let segmentEnd = CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0])
            
            // Calculate closest point on this segment
            let closestOnSegment = closestPointOnLineSegment(
                point: userLocation,
                lineStart: segmentStart,
                lineEnd: segmentEnd
            )
            
            let distance = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
                .distance(from: CLLocation(latitude: closestOnSegment.latitude, longitude: closestOnSegment.longitude))
            
            if distance < closestDistance {
                closestDistance = distance
                closestSegmentIndex = i
                closestPoint = closestOnSegment
            }
        }
        
        guard let segmentIndex = closestSegmentIndex,
              let _ = closestPoint else {
            print("📐 [Geometric Detection] No valid line segment found")
            return nil
        }
        
        print("📐 [Geometric Detection] Closest segment: \(segmentIndex), distance: \(String(format: "%.2f", closestDistance))m")
        
        // Get the closest segment coordinates
        let startCoord = matchingSchedule.lineCoordinates[segmentIndex]
        let endCoord = matchingSchedule.lineCoordinates[segmentIndex + 1]
        
        let segmentStart = CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0])
        let segmentEnd = CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0])
        
        // Use cross product to determine which side of the line the user is on
        let crossProduct = calculateCrossProduct(
            lineStart: segmentStart,
            lineEnd: segmentEnd,
            point: userLocation
        )
        
        print("📐 [Geometric Detection] Cross product: \(String(format: "%.6f", crossProduct))")
        
        // Determine the geometric side (positive = left side when traveling along segment direction, negative = right side)
        let isLeftSide = crossProduct > 0
        
        // Map geometric side to actual street sides and get the matching schedule
        let (determinedSide, matchedSchedule) = mapGeometricSideToStreetSideWithSchedule(
            isLeftSide: isLeftSide,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd,
            availableSchedules: streetSchedules
        )
        
        print("📐 [Geometric Detection] Geometric result: \(isLeftSide ? "LEFT" : "RIGHT") side")
        print("📐 [Geometric Detection] Mapped to street side: \(determinedSide ?? "UNKNOWN")")
        
        if let side = determinedSide, let schedule = matchedSchedule {
            return (side, schedule)
        } else {
            return nil
        }
    }
    
    private func closestPointOnLineSegment(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let A = point
        let B = lineStart
        let C = lineEnd
        
        // Vector from B to C (line direction)
        let BCx = C.longitude - B.longitude
        let BCy = C.latitude - B.latitude
        
        // Vector from B to A (point)
        let BAx = A.longitude - B.longitude
        let BAy = A.latitude - B.latitude
        
        // Project BA onto BC
        let dotProduct = BAx * BCx + BAy * BCy
        let lengthSquared = BCx * BCx + BCy * BCy
        
        if lengthSquared == 0 {
            // B and C are the same point
            return B
        }
        
        let t = max(0, min(1, dotProduct / lengthSquared))
        
        return CLLocationCoordinate2D(
            latitude: B.latitude + t * (C.latitude - B.latitude),
            longitude: B.longitude + t * (C.longitude - B.longitude)
        )
    }
    
    private func calculateCrossProduct(
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D,
        point: CLLocationCoordinate2D
    ) -> Double {
        // Calculate cross product: (lineEnd - lineStart) × (point - lineStart)
        let vectorLine = (
            x: lineEnd.longitude - lineStart.longitude,
            y: lineEnd.latitude - lineStart.latitude
        )
        let vectorPoint = (
            x: point.longitude - lineStart.longitude,
            y: point.latitude - lineStart.latitude
        )
        
        // Cross product in 2D: v1.x * v2.y - v1.y * v2.x
        return vectorLine.x * vectorPoint.y - vectorLine.y * vectorPoint.x
    }
    
    private func mapGeometricSideToStreetSideWithSchedule(
        isLeftSide: Bool,
        segmentStart: CLLocationCoordinate2D,
        segmentEnd: CLLocationCoordinate2D,
        availableSchedules: [AggregatedSweepSchedule]
    ) -> (String?, SweepSchedule?) {
        // Calculate the bearing/direction of the street segment
        let deltaLon = segmentEnd.longitude - segmentStart.longitude
        let deltaLat = segmentEnd.latitude - segmentStart.latitude
        
        // Calculate bearing (0° = North, 90° = East, 180° = South, 270° = West)
        var bearing = atan2(deltaLon, deltaLat) * 180 / Double.pi
        if bearing < 0 { bearing += 360 }
        
        print("📐 [Geometric Detection] Street bearing: \(String(format: "%.1f", bearing))°")
        
        // Determine street orientation
        var streetSide: String
        
        // For different street orientations, left/right sides correspond to different compass directions
        if bearing >= 315 || bearing < 45 {
            // North-bound street (0° ± 45°)
            streetSide = isLeftSide ? "West" : "East"
        } else if bearing >= 45 && bearing < 135 {
            // East-bound street (90° ± 45°)  
            streetSide = isLeftSide ? "North" : "South"
        } else if bearing >= 135 && bearing < 225 {
            // South-bound street (180° ± 45°)
            streetSide = isLeftSide ? "East" : "West"
        } else {
            // West-bound street (270° ± 45°)
            streetSide = isLeftSide ? "South" : "North"
        }
        
        print("📐 [Geometric Detection] Street orientation-based side: \(streetSide)")
        
        // Find a matching schedule with this side designation
        let matchingSchedule = availableSchedules.first { schedule in
            let blockSide = schedule.blockSide.lowercased()
            let targetSide = streetSide.lowercased()
            
            return blockSide.contains(targetSide)
        }
        
        if let match = matchingSchedule {
            print("📐 [Geometric Detection] Found matching schedule: \(match.blockSide)")
            
            // Convert the matched AggregatedSweepSchedule to SweepSchedule format
            if let convertedSchedule = convertAggregatedToSweepSchedule(match) {
                return (match.blockSide, convertedSchedule)
            }
        } else {
            // Fallback: try to find any schedule that makes sense
            print("📐 [Geometric Detection] No exact match found, using best available")
            
            // If we can't find an exact match, return the calculated side for the closest available schedule
            if let closestSchedule = availableSchedules.first,
               let convertedSchedule = convertAggregatedToSweepSchedule(closestSchedule) {
                print("📐 [Geometric Detection] Using fallback schedule: \(closestSchedule.blockSide)")
                return (closestSchedule.blockSide, convertedSchedule)
            }
        }
        
        return (nil, nil)
    }
    
    private func convertAggregatedToSweepSchedule(_ aggregated: AggregatedSweepSchedule) -> SweepSchedule? {
        // Create the schedule based on the specific aggregated schedule's active days
        let days = [
            ("Mon", aggregated.mondayHours),
            ("Tue", aggregated.tuesdayHours), 
            ("Wed", aggregated.wednesdayHours),
            ("Thu", aggregated.thursdayHours),
            ("Fri", aggregated.fridayHours),
            ("Sat", aggregated.saturdayHours),
            ("Sun", aggregated.sundayHours)
        ]
        
        // Find the first active day for this specific schedule
        for (dayName, hours) in days {
            if !hours.isEmpty {
                let fromHour = hours.min() ?? 0
                let toHour = (hours.max() ?? 0) + 1
                
                // Create a simple schedule struct for this specific day/side combination
                return SweepSchedule(
                    cnn: aggregated.cnn,
                    corridor: aggregated.corridor,
                    limits: aggregated.limits,
                    blockside: aggregated.blockSide,
                    fullname: aggregated.scheduleSummary,
                    weekday: String(dayName.prefix(3)), // Convert to abbreviated form
                    fromhour: String(fromHour),
                    tohour: String(toHour),
                    week1: String(aggregated.week1),
                    week2: String(aggregated.week2),
                    week3: String(aggregated.week3),
                    week4: String(aggregated.week4),
                    week5: String(aggregated.week5),
                    holidays: "0",
                    line: nil, // We don't need geometry here since we already have the aggregated data
                    avgSweeperTime: aggregated.avgCitationTime,
                    medianSweeperTime: aggregated.medianCitationTime
                )
            }
        }
        
        return nil
    }
    
    private func updateStreetDataManager(with selectedSchedule: PersistedSweepSchedule?, at coordinate: CLLocationCoordinate2D) async {
        await MainActor.run {
            if let schedule = selectedSchedule {
                print("📊 [Smart Park] Notifying UI to refresh schedule display for: \(schedule.streetName)")
                
                // Post notification to trigger UI refresh with new schedule data
                NotificationCenter.default.post(
                    name: .init("smartParkScheduleUpdated"),
                    object: nil,
                    userInfo: [
                        "coordinate": [
                            "latitude": coordinate.latitude,
                            "longitude": coordinate.longitude
                        ],
                        "selectedSchedule": [
                            "streetName": schedule.streetName,
                            "weekday": schedule.weekday,
                            "startTime": schedule.startTime,
                            "endTime": schedule.endTime,
                            "blockSide": schedule.blockSide
                        ]
                    ]
                )
                
                print("✅ [Smart Park] Schedule update notification sent to UI")
            } else {
                print("📊 [Smart Park] No schedule to update in UI")
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadPersistedLocations() {
        // Load pending location (only needed during app restart while waiting for 2-minute confirmation)
        if let data = UserDefaults.standard.data(forKey: pendingLocationKey),
           let location = try? JSONDecoder().decode(SmartParkLocation.self, from: data) {
            pendingSmartParkLocation = location
            
            // Check if the 2-minute window has passed
            let timeSinceSave = Date().timeIntervalSince(location.timestamp)
            if timeSinceSave >= 120 {
                // Time has passed, perform the check now
                Task { @MainActor in
                    await performConfirmationCheck(for: location)
                }
            } else {
                // Resume the timer for remaining time
                let remainingTime = 120 - timeSinceSave
                scheduleConfirmationCheck(for: location, delay: remainingTime)
            }
        }
    }
    
    private func scheduleConfirmationCheck(for location: SmartParkLocation, delay: TimeInterval) {
        confirmationTimer?.invalidate()
        
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                await self.performConfirmationCheck(for: location)
            }
        }
    }
    
    func savePendingLocation(_ location: SmartParkLocation) {
        pendingSmartParkLocation = location
        if let data = try? JSONEncoder().encode(location) {
            UserDefaults.standard.set(data, forKey: pendingLocationKey)
        }
    }
    
    
    private func clearPendingLocation() {
        UserDefaults.standard.removeObject(forKey: pendingLocationKey)
    }
}
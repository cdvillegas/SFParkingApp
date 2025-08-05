import Foundation
import CoreLocation
import Combine
import SwiftUI

// MARK: - Smart Park 2.0 Parking Location
struct SmartParkLocation: Codable, Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let timestamp: Date
    let triggerType: String // "carPlay" or "bluetooth"
    let bluetoothDeviceName: String?
    var confirmationStatus: ConfirmationStatus
    
    enum ConfirmationStatus: String, Codable {
        case pending = "pending"
        case confirmed = "confirmed"
        case cancelled = "cancelled"
    }
    
    // Custom encoding/decoding for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, coordinate, address, timestamp, triggerType, bluetoothDeviceName, confirmationStatus
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
         confirmationStatus: ConfirmationStatus = .pending) {
        self.id = id
        self.coordinate = coordinate
        self.address = address
        self.timestamp = timestamp
        self.triggerType = triggerType
        self.bluetoothDeviceName = bluetoothDeviceName
        self.confirmationStatus = confirmationStatus
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
        print("📍 [Smart Park 2.0] Getting current location...")
        
        // Request location permission if needed
        if locationManager.authorizationStatus == .notDetermined {
            print("📍 [Smart Park 2.0] Location permission not determined, requesting...")
            locationManager.requestLocationPermission()
            // Wait a moment for permission dialog
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // If we have a recent location, use it
        if let currentLocation = locationManager.userLocation,
           currentLocation.timestamp.timeIntervalSinceNow > -30 { // Less than 30 seconds old
            print("📍 [Smart Park 2.0] Using cached location: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
            return currentLocation.coordinate
        }
        
        print("📍 [Smart Park 2.0] Requesting fresh location...")
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
                        print("📍 [Smart Park 2.0] Got fresh location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    }
                    cancellable?.cancel()
                }
            
            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                
                if state.safeResume(with: nil, continuation: continuation) {
                    print("⏰ [Smart Park 2.0] Location request timed out")
                }
                cancellable?.cancel()
            }
        }
    }
    
    func saveParkingLocation(
        at coordinate: CLLocationCoordinate2D,
        triggerType: ParkingTriggerType,
        delayConfirmation: Bool
    ) async throws -> SmartParkLocation {
        print("💾 [Smart Park 2.0] Saving parking location - Type: \(triggerType.rawValue), Delay: \(delayConfirmation)")
        print("💾 [Smart Park 2.0] Coordinates: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Validate coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0,
              coordinate.longitude != 0 else {
            print("❌ [Smart Park 2.0] Invalid coordinates provided")
            throw IntentError.invalidCoordinates
        }
        
        // Get address for the coordinate
        let address = await reverseGeocode(coordinate: coordinate)
        if let address = address {
            print("🏠 [Smart Park 2.0] Geocoded address: \(address)")
        } else {
            print("🏠 [Smart Park 2.0] No address found for coordinates")
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
            print("⏳ [Smart Park 2.0] Saving as pending - will confirm in 2 minutes")
            pendingSmartParkLocation = parkingLocation
            savePendingLocation(parkingLocation)
            // No notification sent - wait for 2-minute confirmation
        } else {
            print("✅ [Smart Park 2.0] Immediate confirmation - saving to vehicle manager")
            // Immediately save to the main app's vehicle manager and send confirmation
            await saveToVehicleManager(parkingLocation)
            await NotificationManager.shared.sendParkingConfirmation(for: parkingLocation)
        }
        
        return parkingLocation
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
        print("⏰ [Smart Park 2.0] Performing 2-minute confirmation check for \(location.id)")
        
        // Check if still pending
        guard let pending = pendingSmartParkLocation,
              pending.id == location.id else {
            print("⚠️ [Smart Park 2.0] No matching pending location found - may have been cleared")
            return
        }
        
        // Check car connection
        let detector = CarConnectionDetector()
        let isConnected = await detector.isCarConnected(
            type: ParkingTriggerType(rawValue: location.triggerType) ?? .carPlay,
            bluetoothDeviceName: location.bluetoothDeviceName
        )
        
        print("🚗 [Smart Park 2.0] Car connection status after 2 minutes: \(isConnected ? "CONNECTED" : "DISCONNECTED")")
        
        if !isConnected {
            print("✅ [Smart Park 2.0] Car still disconnected - confirming parking location")
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
            print("🚫 [Smart Park 2.0] Car reconnected - cancelling parking detection")
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
        var components: [String] = []
        
        if let streetNumber = placemark.subThoroughfare {
            components.append(streetNumber)
        }
        
        if let streetName = placemark.thoroughfare {
            components.append(streetName)
        }
        
        if components.isEmpty, let name = placemark.name {
            components.append(name)
        }
        
        if let city = placemark.locality {
            components.append(city)
        }
        
        return components.joined(separator: ", ")
    }
    
    func saveToVehicleManager(_ smartParkLocation: SmartParkLocation) async {
        print("🚙 [Smart Park 2.0] Saving to VehicleManager - Address: \(smartParkLocation.address ?? "Unknown")")
        
        // Convert to regular ParkingLocation and save via VehicleManager
        let parkingLocation = ParkingLocation(
            coordinate: smartParkLocation.coordinate,
            address: smartParkLocation.address ?? "Unknown Location",
            timestamp: smartParkLocation.timestamp,
            source: smartParkLocation.triggerType == "carPlay" ? .carplay : .bluetooth
        )
        
        // Get the vehicle manager and update
        if let vehicle = VehicleManager.shared.currentVehicle {
            VehicleManager.shared.setParkingLocation(for: vehicle, location: parkingLocation)
            print("✅ [Smart Park 2.0] Successfully saved to VehicleManager")
        } else {
            print("⚠️ [Smart Park 2.0] No vehicle found in VehicleManager")
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
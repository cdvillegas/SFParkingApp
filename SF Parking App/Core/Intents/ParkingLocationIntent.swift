import AppIntents
import CoreLocation
import SwiftUI
import AVFoundation

// MARK: - Parking Trigger Type
enum ParkingTriggerType: String, AppEnum {
    case carPlay = "CarPlay"
    case bluetooth = "Bluetooth"
    
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Parking Trigger")
    
    static var caseDisplayRepresentations: [ParkingTriggerType: DisplayRepresentation] = [
        .carPlay: "CarPlay Disconnection",
        .bluetooth: "Bluetooth Disconnection"
    ]
}

// MARK: - Save Parking Location Intent
struct SaveParkingLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Parking Location"
    static var description = IntentDescription("Saves your current location as your parking spot when you disconnect from your car")
    
    // This ensures the intent runs in background without opening the app
    static var openAppWhenRun: Bool = false
    
    // Perform the intent
    func perform() async throws -> some IntentResult & ProvidesDialog {
        print("🚗 [Smart Park 2.0] SaveParkingLocationIntent triggered - using defaults")
        
        // Initialize the parking location manager
        let manager = await ParkingLocationManager.shared
        
        // Get current location
        print("🚗 [Smart Park 2.0] Requesting current location...")
        guard let currentLocation = await manager.getCurrentLocation() else {
            print("❌ [Smart Park 2.0] Failed to get current location")
            throw IntentError.locationUnavailable
        }
        print("🚗 [Smart Park 2.0] Got current location: \(currentLocation.latitude), \(currentLocation.longitude)")
        
        // Save parking location with default settings (CarPlay trigger, delay confirmation enabled)
        let savedLocation = try await manager.saveParkingLocation(
            at: currentLocation,
            triggerType: .carPlay,
            delayConfirmation: true
        )
        
        // Schedule the 2-minute confirmation check
        print("🚗 [Smart Park 2.0] Scheduling 2-minute confirmation check")
        await manager.scheduleConfirmationCheck(for: savedLocation)
        
        return .result(dialog: "Smart Park 2.0 location saved! You'll receive a confirmation in 2 minutes if you don't reconnect to your car.")
    }
}

// MARK: - Check Car Connection Intent
struct CheckCarConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Car Connection"
    static var description = IntentDescription("Checks if you're connected to your car via CarPlay")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        print("🚗 [Smart Park 2.0] CheckCarConnectionIntent triggered - checking CarPlay")
        
        let detector = CarConnectionDetector()
        let isConnected = await detector.isCarConnected(
            type: .carPlay,
            bluetoothDeviceName: nil
        )
        
        print("🚗 [Smart Park 2.0] CarPlay connection check result: \(isConnected)")
        let message = isConnected ? "Connected to CarPlay" : "Not connected to CarPlay"
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Update Parking Location Intent
struct UpdateParkingLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Parking Location"
    static var description = IntentDescription("Updates the saved parking location to your current location")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = await ParkingLocationManager.shared
        
        // Check if there's a pending location to update
        guard let pendingLocation = await manager.pendingSmartParkLocation else {
            throw IntentError.parkingNotFound
        }
        
        // Get current location
        guard let currentLocation = await manager.getCurrentLocation() else {
            throw IntentError.locationUnavailable
        }
        
        // Update the parking location
        let parking = try await manager.updateParkingLocation(
            id: pendingLocation.id,
            newLocation: currentLocation
        )
        
        // Send confirmation notification
        await NotificationManager.shared.sendParkingConfirmation(for: parking)
        
        return .result(dialog: "Parking location updated to current location")
    }
}

// MARK: - Intent Errors
enum IntentError: Swift.Error, LocalizedError {
    case locationUnavailable
    case parkingNotFound
    case saveFailed
    case invalidCoordinates
    
    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Unable to determine current location. Please ensure location services are enabled."
        case .parkingNotFound:
            return "Could not find the parking record to update."
        case .saveFailed:
            return "Failed to save parking location."
        case .invalidCoordinates:
            return "Invalid location coordinates provided."
        }
    }
}


// MARK: - Car Connection Detector
struct CarConnectionDetector {
    func isCarConnected(type: ParkingTriggerType, bluetoothDeviceName: String?) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let audioSession = AVAudioSession.sharedInstance()
                let currentRoute = audioSession.currentRoute
                
                print("🚗 [Smart Park 2.0] CarConnectionDetector checking audio routes...")
                print("🚗 [Smart Park 2.0] Current route outputs: \(currentRoute.outputs.map { "\($0.portType.rawValue): \($0.portName)" })")
                
                switch type {
                case .carPlay:
                    // Check if any output is CarPlay
                    let hasCarPlay = currentRoute.outputs.contains { output in
                        output.portType == .carAudio
                    }
                    print("🚗 [Smart Park 2.0] CarPlay check result: \(hasCarPlay)")
                    continuation.resume(returning: hasCarPlay)
                    
                case .bluetooth:
                    // Check for specific Bluetooth device if name provided
                    guard let deviceName = bluetoothDeviceName, !deviceName.isEmpty else {
                        print("❌ [Smart Park 2.0] No Bluetooth device name provided")
                        continuation.resume(returning: false)
                        return
                    }
                    
                    print("🚗 [Smart Park 2.0] Looking for Bluetooth device: \(deviceName)")
                    
                    // Check if the specific Bluetooth device is connected
                    let hasSpecificBluetooth = currentRoute.outputs.contains { output in
                        let bluetoothTypes: [AVAudioSession.Port] = [
                            .bluetoothA2DP,
                            .bluetoothHFP,
                            .bluetoothLE
                        ]
                        let isBluetoothType = bluetoothTypes.contains(output.portType)
                        let nameMatches = output.portName == deviceName
                        
                        if isBluetoothType {
                            print("🚗 [Smart Park 2.0] Found Bluetooth device: \(output.portName) (looking for: \(deviceName))")
                        }
                        
                        return isBluetoothType && nameMatches
                    }
                    
                    print("🚗 [Smart Park 2.0] Specific Bluetooth device check result: \(hasSpecificBluetooth)")
                    continuation.resume(returning: hasSpecificBluetooth)
                }
            }
        }
    }
}
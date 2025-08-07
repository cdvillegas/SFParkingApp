import AppIntents
import CoreLocation
import SwiftUI
import AVFoundation

// MARK: - Smart Park 2.0 Configuration
struct SmartParkConfig: Codable {
    let isEnabled: Bool
    let triggerType: SmartParkTriggerType
    let bluetoothDeviceName: String?
    let delayConfirmation: Bool
    let configuredConnections: Set<SmartParkTriggerType>?
    
    static var current: SmartParkConfig {
        if let data = UserDefaults.standard.data(forKey: "smartPark2Config"),
           let config = try? JSONDecoder().decode(SmartParkConfig.self, from: data) {
            return config
        }
        // Default configuration
        return SmartParkConfig(
            isEnabled: false,
            triggerType: .carPlay,
            bluetoothDeviceName: nil,
            delayConfirmation: true,
            configuredConnections: []
        )
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "smartPark2Config")
        }
    }
}

// MARK: - Smart Park Trigger Type
enum SmartParkTriggerType: String, AppEnum, CaseIterable, Codable {
    case carPlay = "CarPlay"
    case bluetooth = "Bluetooth"
    
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Connection Type")
    
    static var caseDisplayRepresentations: [SmartParkTriggerType: DisplayRepresentation] = [
        .carPlay: "CarPlay",
        .bluetooth: "Bluetooth"
    ]
}

// MARK: - Legacy Parking Trigger Type (for compatibility with ParkingLocationManager)
enum ParkingTriggerType: String, CaseIterable, Codable {
    case carPlay = "CarPlay"
    case bluetooth = "Bluetooth"
}

// MARK: - Main Smart Park 2.0 Intent
struct SmartParkIntent: AppIntent {
    static var title: LocalizedStringResource = "Smart Park 2.0"
    static var description = IntentDescription("Automatically saves your parking location when you disconnect from your car")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        print("🚗 [Smart Park 2.0] ========== SMART PARK INTENT TRIGGERED ==========")
        print("🚗 [Smart Park 2.0] Main intent triggered")
        
        // Check if Smart Park 2.0 is enabled
        let hasSetup = UserDefaults.standard.bool(forKey: "smartParkSetupCompleted")
        let isEnabled = UserDefaults.standard.object(forKey: "smartParkEnabled") == nil ? hasSetup : UserDefaults.standard.bool(forKey: "smartParkEnabled")
        
        guard hasSetup else {
            print("🚗 [Smart Park 2.0] Smart Park not set up")
            return .result(dialog: "Smart Park needs to be set up first in the SF Parking App.")
        }
        
        guard isEnabled else {
            print("🚗 [Smart Park 2.0] Feature is disabled")
            return .result(dialog: "Smart Park is disabled. Enable it in the SF Parking App settings.")
        }
        
        let config = SmartParkConfig.current
        print("🚗 [Smart Park 2.0] Config - Type: \(config.triggerType.rawValue), Delay: \(config.delayConfirmation)")
        
        // Check if we're actually disconnected from the car
        let detector = CarConnectionDetector()
        let parkingTriggerType = ParkingTriggerType(rawValue: config.triggerType.rawValue) ?? .carPlay
        let isConnected = await detector.isCarConnected(type: parkingTriggerType)
        
        if isConnected {
            print("🚗 [Smart Park 2.0] Still connected to car - not saving location")
            return .result(dialog: "Still connected to your car. Smart Park will activate when you disconnect.")
        }
        
        print("🚗 [Smart Park 2.0] Car disconnected - saving parking location")
        
        // Get parking location manager
        let manager = await ParkingLocationManager.shared
        
        // Get current location
        guard let currentLocation = await manager.getCurrentLocation() else {
            print("❌ [Smart Park 2.0] Failed to get current location")
            throw SmartParkError.locationUnavailable
        }
        
        // Save parking location (TESTING: disable 2-minute delay)
        let savedLocation = try await manager.saveParkingLocation(
            at: currentLocation,
            triggerType: parkingTriggerType,
            delayConfirmation: false // TESTING: Force immediate confirmation
        )
        
        // Track successful Smart Park usage
        UserDefaults.standard.set(Date(), forKey: "smartParkLastTriggered")
        
        return .result(dialog: "Parking location saved at \(savedLocation.address ?? "current location")")
    }
}


// MARK: - Smart Park Errors
enum SmartParkError: Swift.Error, LocalizedError {
    case locationUnavailable
    case notConfigured
    case featureDisabled
    
    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Unable to get your current location. Please ensure location services are enabled."
        case .notConfigured:
            return "Smart Park 2.0 is not configured. Please run the setup first."
        case .featureDisabled:
            return "Smart Park 2.0 is disabled. Enable it in the app settings."
        }
    }
}

// MARK: - Legacy Intent Errors (for compatibility with ParkingLocationManager)
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
    func isCarConnected(type: ParkingTriggerType) async -> Bool {
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
                    // Check for any Bluetooth audio connection
                    // The Shortcuts automation already filtered to the specific device
                    let hasAnyBluetooth = currentRoute.outputs.contains { output in
                        let bluetoothTypes: [AVAudioSession.Port] = [
                            .bluetoothA2DP,
                            .bluetoothHFP,
                            .bluetoothLE
                        ]
                        return bluetoothTypes.contains(output.portType)
                    }
                    
                    print("🚗 [Smart Park 2.0] Bluetooth audio check result: \(hasAnyBluetooth)")
                    continuation.resume(returning: hasAnyBluetooth)
                }
            }
        }
    }
}


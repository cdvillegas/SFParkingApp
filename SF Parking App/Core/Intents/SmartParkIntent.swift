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
            delayConfirmation: true
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

// MARK: - Main Smart Park 2.0 Intent
struct SmartParkIntent: AppIntent {
    static var title: LocalizedStringResource = "Smart Park 2.0"
    static var description = IntentDescription("Automatically saves your parking location when you disconnect from your car")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        print("🚗 [Smart Park 2.0] Main intent triggered")
        
        // Check if Smart Park 2.0 is enabled
        let config = SmartParkConfig.current
        guard config.isEnabled else {
            print("🚗 [Smart Park 2.0] Feature is disabled")
            return .result(dialog: "Smart Park 2.0 is disabled. Enable it in the SF Parking App settings.")
        }
        
        print("🚗 [Smart Park 2.0] Config - Type: \(config.triggerType.rawValue), Delay: \(config.delayConfirmation)")
        
        // Check if we're actually disconnected from the car
        let detector = CarConnectionDetector()
        let parkingTriggerType = ParkingTriggerType(rawValue: config.triggerType.rawValue) ?? .carPlay
        let isConnected = await detector.isCarConnected(
            type: parkingTriggerType,
            bluetoothDeviceName: config.bluetoothDeviceName
        )
        
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
        
        // Save parking location
        let savedLocation = try await manager.saveParkingLocation(
            at: currentLocation,
            triggerType: parkingTriggerType,
            delayConfirmation: config.delayConfirmation
        )
        
        // Schedule confirmation check if delay is enabled
        if config.delayConfirmation {
            await manager.scheduleConfirmationCheck(for: savedLocation)
            return .result(dialog: "Smart Park 2.0 activated! You'll get a confirmation in 2 minutes if you don't reconnect.")
        } else {
            return .result(dialog: "Parking location saved at \(savedLocation.address ?? "current location")")
        }
    }
}

// MARK: - Setup Smart Park Intent (for initial configuration)
struct SetupSmartParkIntent: AppIntent {
    static var title: LocalizedStringResource = "Setup Smart Park 2.0"
    static var description = IntentDescription("Initial setup for Smart Park 2.0 - run this once to configure")
    
    static var openAppWhenRun: Bool = true // Open app for guided setup
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        print("🚗 [Smart Park 2.0] Setup intent triggered - opening app for guided setup")
        
        // Set a flag to show setup screen when app opens
        UserDefaults.standard.set(true, forKey: "showSmartParkSetup")
        
        return .result(dialog: "Opening SF Parking App for Smart Park 2.0 setup...")
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


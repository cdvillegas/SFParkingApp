import Foundation
import SwiftUI
import Combine

// MARK: - Smart Park Manager
@MainActor
class SmartParkManager: ObservableObject {
    static let shared = SmartParkManager()
    
    @Published var isEnabled: Bool = false
    @Published var triggerType: SmartParkTriggerType = .carPlay
    // Always use 2-minute delay for safety - no user configuration needed
    private let delayConfirmation: Bool = true
    @Published var showSetup: Bool = false
    
    // Setup progress tracking
    @Published var isSetupComplete: Bool = false
    @Published var setupStep: SetupStep = .connectionType
    
    // Track which connection types have been configured
    @Published var configuredConnections: Set<SmartParkTriggerType> = []
    
    private init() {
        loadConfiguration()
        
        // Check if we should show setup screen
        if UserDefaults.standard.bool(forKey: "showSmartParkSetup") {
            showSetup = true
            UserDefaults.standard.removeObject(forKey: "showSmartParkSetup")
        }
    }
    
    // MARK: - Configuration Management
    
    func loadConfiguration() {
        let config = SmartParkConfig.current
        isEnabled = config.isEnabled
        triggerType = config.triggerType
        configuredConnections = config.configuredConnections ?? []
        isSetupComplete = config.isEnabled || !configuredConnections.isEmpty // If enabled or has configured connections
        
        print("🚗 [Smart Park] Loaded config - Enabled: \(isEnabled), Type: \(triggerType.rawValue), Configured: \(configuredConnections)")
    }
    
    func saveConfiguration() {
        let config = SmartParkConfig(
            isEnabled: isEnabled,
            triggerType: triggerType,
            bluetoothDeviceName: nil, // No device name needed
            delayConfirmation: true, // Always use 2-minute delay
            configuredConnections: configuredConnections
        )
        config.save()
        print("🚗 [Smart Park] Saved config - Enabled: \(isEnabled), Type: \(triggerType.rawValue), Configured: \(configuredConnections)")
    }
    
    // MARK: - Setup Flow Management
    
    func startSetup() {
        showSetup = true
        setupStep = .connectionType
    }
    
    func completeSetup() {
        isSetupComplete = true
        isEnabled = true
        showSetup = false
        saveConfiguration()
        
        print("🚗 [Smart Park] Setup completed successfully")
    }
    
    func cancelSetup() {
        showSetup = false
        setupStep = .connectionType
    }
    
    // MARK: - Feature Toggle
    
    func toggleSmartPark() {
        isEnabled.toggle()
        saveConfiguration()
        
        if isEnabled {
            print("🚗 [Smart Park] Feature enabled")
        } else {
            print("🚗 [Smart Park] Feature disabled")
        }
    }
    
    // MARK: - Validation
    
    var isConfigurationValid: Bool {
        // Both CarPlay and Bluetooth are valid - no device name needed for Bluetooth
        return true
    }
    
    var configurationStatus: String {
        if !isSetupComplete {
            return "Not configured"
        } else if !isEnabled {
            return "Disabled"
        } else if !isConfigurationValid {
            return "Invalid configuration"
        } else {
            return "Active"
        }
    }
    
    // MARK: - Shortcut Creation Helper
    
    func createShortcutInstructions() -> [String] {
        return [
            "Open the Shortcuts App",
            "Search for 'Smart Park'",
            "Tap it",
            "Make sure 'Show When Run' is disabled",
            "Tap 'Done'",
            "Return to Smart Park Setup guide"
        ]
    }
    
    func createAutomationInstructions() -> [String] {
        switch triggerType {
        case .carPlay:
            return [
                "Open Shortcuts app and go to Automation tab",
                "Select 'New Automation'",
                "Choose 'CarPlay' as the trigger",
                "Ensure 'Disconnects' is selected and 'Connects' is not",
                "Select 'Run Immediately'",
                "Hit Next",
                "Search for 'Smart Park'",
                "Make sure 'Show When Run' is NOT selected",
                "Return to App"
            ]
        case .bluetooth:
            return [
                "Open Shortcuts app and go to Automation tab",
                "Select 'New Automation'", 
                "Choose 'Bluetooth' as the trigger",
                "Tap 'Choose' and select your car's Bluetooth name from the device list",
                "Ensure 'Disconnects' is selected and 'Connects' is not",
                "Select 'Run Immediately'",
                "Hit Next",
                "Search for 'Smart Park'",
                "Make sure 'Show When Run' is NOT selected",
                "Return to App"
            ]
        }
    }
}

// MARK: - Setup Steps
enum SetupStep: CaseIterable {
    case connectionType
    case instructions
    
    var title: String {
        switch self {
        case .connectionType:
            return "Connection Type"
        case .instructions:
            return "Setup Instructions"
        }
    }
    
    var description: String {
        switch self {
        case .connectionType:
            return "Select your car's connection type."
        case .instructions:
            return "Follow these steps to set up Smart Park automation."
        }
    }
    
    var isOptional: Bool {
        // All steps are required
        return false
    }
}
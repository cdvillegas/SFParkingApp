import Foundation
import SwiftUI
import Combine

// MARK: - Smart Park 2.0 Manager
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
    @Published var setupStep: SetupStep = .welcome
    
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
        
        print("🚗 [Smart Park 2.0] Loaded config - Enabled: \(isEnabled), Type: \(triggerType.rawValue), Configured: \(configuredConnections)")
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
        print("🚗 [Smart Park 2.0] Saved config - Enabled: \(isEnabled), Type: \(triggerType.rawValue), Configured: \(configuredConnections)")
    }
    
    // MARK: - Setup Flow Management
    
    func startSetup() {
        showSetup = true
        setupStep = .welcome
    }
    
    func completeSetup() {
        isSetupComplete = true
        isEnabled = true
        showSetup = false
        saveConfiguration()
        
        print("🚗 [Smart Park 2.0] Setup completed successfully")
    }
    
    func cancelSetup() {
        showSetup = false
        setupStep = .welcome
    }
    
    // MARK: - Feature Toggle
    
    func toggleSmartPark() {
        isEnabled.toggle()
        saveConfiguration()
        
        if isEnabled {
            print("🚗 [Smart Park 2.0] Feature enabled")
        } else {
            print("🚗 [Smart Park 2.0] Feature disabled")
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
            "Search for 'Smart Park 2.0'",
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
                "Search for 'Smart Park 2.0'",
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
                "Search for 'Smart Park 2.0'",
                "Make sure 'Show When Run' is NOT selected",
                "Return to App"
            ]
        }
    }
}

// MARK: - Setup Steps
enum SetupStep: CaseIterable {
    case welcome
    case permissions
    case shortcut
    case connectionType
    case automation
    case complete
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .connectionType:
            return "Connection Type"
        case .permissions:
            return "Permissions"
        case .shortcut:
            return "Add Shortcut"
        case .automation:
            return "Create Automation"
        case .complete:
            return "Complete"
        }
    }
    
    var description: String {
        switch self {
        case .welcome:
            return "It automatically saves your location and updates your sweep reminders whenever you park so you don't have to remember to do it!"
        case .connectionType:
            return "Select your car's connection type. You can set up multiple connections if needed."
        case .permissions:
            return "Grant required permissions."
        case .shortcut:
            return "First, add Smart Park to your shortcuts."
        case .automation:
            return "Now create the automation trigger."
        case .complete:
            return "Smart Park is ready to use!"
        }
    }
    
    var isOptional: Bool {
        // All steps are required
        return false
    }
}
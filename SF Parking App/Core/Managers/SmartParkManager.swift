import Foundation
import SwiftUI
import Combine

// MARK: - Smart Park 2.0 Manager
@MainActor
class SmartParkManager: ObservableObject {
    static let shared = SmartParkManager()
    
    @Published var isEnabled: Bool = false
    @Published var triggerType: SmartParkTriggerType = .carPlay
    @Published var bluetoothDeviceName: String = ""
    // Always use 2-minute delay for safety - no user configuration needed
    private let delayConfirmation: Bool = true
    @Published var showSetup: Bool = false
    
    // Setup progress tracking
    @Published var isSetupComplete: Bool = false
    @Published var setupStep: SetupStep = .welcome
    
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
        bluetoothDeviceName = config.bluetoothDeviceName ?? ""
        isSetupComplete = config.isEnabled // If enabled, setup was completed
        
        print("🚗 [Smart Park 2.0] Loaded config - Enabled: \(isEnabled), Type: \(triggerType.rawValue)")
    }
    
    func saveConfiguration() {
        let config = SmartParkConfig(
            isEnabled: isEnabled,
            triggerType: triggerType,
            bluetoothDeviceName: bluetoothDeviceName.isEmpty ? nil : bluetoothDeviceName,
            delayConfirmation: true // Always use 2-minute delay
        )
        config.save()
        print("🚗 [Smart Park 2.0] Saved config - Enabled: \(isEnabled), Type: \(triggerType.rawValue)")
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
        switch triggerType {
        case .carPlay:
            return true
        case .bluetooth:
            return !bluetoothDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
    
    func createAutomationInstructions() -> [String] {
        switch triggerType {
        case .carPlay:
            return [
                "1. Open the Shortcuts app",
                "2. Tap the 'Automation' tab at the bottom",
                "3. Tap the '+' button to create a new automation",
                "4. Choose 'CarPlay' as the trigger",
                "5. Select 'When CarPlay Disconnects'",
                "6. Add the 'Smart Park 2.0' shortcut",
                "7. Turn off 'Ask Before Running' for automatic operation"
            ]
        case .bluetooth:
            return [
                "1. Open the Shortcuts app",
                "2. Tap the 'Automation' tab at the bottom",
                "3. Tap the '+' button to create a new automation",
                "4. Choose 'Bluetooth' as the trigger",
                "5. Select 'When \(bluetoothDeviceName) Disconnects'",
                "6. Add the 'Smart Park 2.0' shortcut",
                "7. Turn off 'Ask Before Running' for automatic operation"
            ]
        }
    }
}

// MARK: - Setup Steps
enum SetupStep: CaseIterable {
    case welcome
    case connectionType
    case bluetoothConfig
    case permissions
    case automation
    case complete
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Smart Park 2.0"
        case .connectionType:
            return "How do you connect to your car?"
        case .bluetoothConfig:
            return "Bluetooth Configuration"
        case .permissions:
            return "Permissions"
        case .automation:
            return "Create Automation"
        case .complete:
            return "Setup Complete!"
        }
    }
    
    var description: String {
        switch self {
        case .welcome:
            return "Smart Park 2.0 automatically saves your parking location when you disconnect from your car."
        case .connectionType:
            return "Choose how your phone connects to your car's audio system."
        case .bluetoothConfig:
            return "Enter the exact name of your car's Bluetooth connection."
        case .permissions:
            return "Smart Park needs location and notification permissions to work properly."
        case .automation:
            return "Create a Shortcuts automation to trigger Smart Park automatically."
        case .complete:
            return "Smart Park 2.0 is now ready to use!"
        }
    }
    
    var isOptional: Bool {
        switch self {
        case .bluetoothConfig:
            return false // Required if Bluetooth is selected
        default:
            return false
        }
    }
}
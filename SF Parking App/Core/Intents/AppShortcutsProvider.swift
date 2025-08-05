import AppIntents

// MARK: - App Shortcuts Provider
struct SmartParkAppShortcutsProvider: AppShortcutsProvider {
    
    static func updateAppShortcutParameters() {
        // This method can be called to update app shortcuts
        // Automatically handled by the system for AppShortcutsProvider
        print("🚗 [Smart Park 2.0] App Shortcuts registered")
    }
    
    // Ensure this provider is discoverable by the system
    static var appShortcuts: [AppShortcut] {
        print("🚗 [Smart Park 2.0] App Shortcuts Provider called - returning shortcuts")
        return [
        // Main Smart Park 2.0 Intent - the one users will use in automations
        AppShortcut(
            intent: SmartParkIntent(),
            phrases: [], // Empty phrases for Personal Team
            shortTitle: "Smart Park 2.0",
            systemImageName: "car.fill"
        ),
        
        // Setup intent for initial configuration
        AppShortcut(
            intent: SetupSmartParkIntent(),
            phrases: [], // Empty phrases for Personal Team
            shortTitle: "Setup Smart Park",
            systemImageName: "gear"
        ),
        
        // Keep test intent for debugging
        AppShortcut(
            intent: TestSmartParkIntent(),
            phrases: [],
            shortTitle: "Test Smart Park",
            systemImageName: "testtube.2"
        )
        ]
    }
}


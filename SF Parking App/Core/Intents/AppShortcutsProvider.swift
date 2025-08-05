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
        // Test intent first to verify App Intents are working
        AppShortcut(
            intent: TestSmartParkIntent(),
            phrases: [],
            shortTitle: "Test Smart Park",
            systemImageName: "testtube.2"
        ),
        
        // Note: Siri voice phrases won't work with Personal Team
        // But shortcuts will still appear in Shortcuts app for manual use
        AppShortcut(
            intent: SaveParkingLocationIntent(),
            phrases: [], // Empty phrases for Personal Team
            shortTitle: "Save Parking",
            systemImageName: "car.fill"
        ),
        
        AppShortcut(
            intent: CheckCarConnectionIntent(),
            phrases: [], // Empty phrases for Personal Team  
            shortTitle: "Check Car Connection",
            systemImageName: "car.side.air.circulate.fill"
        )
        ]
    }
}


import AppIntents

// MARK: - App Shortcuts Provider
struct SmartParkAppShortcutsProvider: AppShortcutsProvider {
    
    static func updateAppShortcutParameters() {
        // This method can be called to update app shortcuts
        // Automatically handled by the system for AppShortcutsProvider
        print("🚗 [Smart Park] App Shortcuts registered")
    }
    
    // Ensure this provider is discoverable by the system
    static var appShortcuts: [AppShortcut] {
        print("🚗 [Smart Park] App Shortcuts Provider called - returning shortcuts")
        return [
        // Main Smart Park Intent - the one users will use in automations
        AppShortcut(
            intent: SmartParkIntent(),
            phrases: [], // Empty phrases for Personal Team
            shortTitle: "Smart Park",
            systemImageName: "car.fill"
        )
        ]
    }
}


import AppIntents

// Simple test intent to verify App Intents are working
struct TestSmartParkIntent: AppIntent {
    static var title: LocalizedStringResource = "Test Smart Park"
    static var description = IntentDescription("Test if Smart Park intents are working")
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        print("🧪 [Smart Park 2.0] Test intent executed successfully!")
        return .result(dialog: "Smart Park 2.0 is working!")
    }
}
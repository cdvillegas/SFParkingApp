import SwiftUI

struct OnboardingStep {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
    let color: Color
    let permissionType: PermissionType?
    let buttonText: String
    
    enum PermissionType {
        case location
        case notifications
        case smartParking
    }
    
    static let allSteps: [OnboardingStep] = [
        OnboardingStep(
            title: "Hello, San Francisco!",
            description: "Never get another parking ticket again. The smartest way to navigate the city's complex street rules.",
            systemImage: "car.fill",
            color: .blue,
            permissionType: nil,
            buttonText: "Continue"
        ),
        OnboardingStep(
            title: "Find Your Parking Spot",
            description: "We'll help you track where you parked and show you the street cleaning rules for that exact location.",
            systemImage: "location.fill",
            color: .green,
            permissionType: .location,
            buttonText: "Enable Location"
        ),
        OnboardingStep(
            title: "Stay One Step Ahead",
            description: "Get perfectly timed reminders before street cleaning starts. Never rush to move your car again.",
            systemImage: "bell.badge.fill",
            color: .orange,
            permissionType: .notifications,
            buttonText: "Enable Notifications"
        ),
        OnboardingStep(
            title: "Smart Parking Detection",
            description: "Automatically detect when you park by connecting to your car's Bluetooth or CarPlay. No more forgetting to set your location!",
            systemImage: "sparkles",
            color: .purple,
            permissionType: .smartParking,
            buttonText: "Enable Smart Parking"
        )
    ]
}

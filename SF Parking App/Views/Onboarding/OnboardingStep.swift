import SwiftUI

struct OnboardingStep {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
    let gradientColors: [Color]
    let permissionType: PermissionType?
    let buttonText: String
    
    enum PermissionType {
        case location
        case motion
        case bluetooth
        case notifications
    }
    
    static let allSteps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to SF Parking",
            description: "Never worry about street cleaning tickets again. We'll help you track your parking and remind you when it's time to move.",
            systemImage: "car.fill",
            gradientColors: [Color.blue, Color.cyan],
            permissionType: nil,
            buttonText: "Get Started"
        ),
        OnboardingStep(
            title: "Find Your Location",
            description: "We'll use your location to show you exactly where you parked and provide accurate street cleaning information for your area.",
            systemImage: "location.fill",
            gradientColors: [Color.green, Color.mint],
            permissionType: .location,
            buttonText: "Enable Location"
        ),
        OnboardingStep(
            title: "Smart Parking Detection",
            description: "We can automatically detect when you stop driving and set your parking location, making the process seamless and effortless.",
            systemImage: "figure.walk.motion",
            gradientColors: [Color.orange, Color.yellow],
            permissionType: .motion,
            buttonText: "Enable Auto Detection"
        ),
        OnboardingStep(
            title: "Car Connection Awareness",
            description: "When you disconnect from your car's Bluetooth, we'll automatically mark your parking spot so you never forget where you parked.",
            systemImage: "car.side.and.exclamationmark",
            gradientColors: [Color.purple, Color.pink],
            permissionType: .bluetooth,
            buttonText: "Enable Car Detection"
        ),
        OnboardingStep(
            title: "Street Cleaning Reminders",
            description: "Get timely notifications before street cleaning so you can move your car and avoid expensive tickets. Stay informed, stay ticket-free.",
            systemImage: "bell.fill",
            gradientColors: [Color.red, Color.orange],
            permissionType: .notifications,
            buttonText: "Enable Notifications"
        ),
        OnboardingStep(
            title: "You're All Set!",
            description: "Your SF Parking app is ready to help you stay ticket-free. Park with confidence knowing we've got your back.",
            systemImage: "checkmark.circle.fill",
            gradientColors: [Color.blue, Color.green],
            permissionType: nil,
            buttonText: "Start Parking Smart"
        )
    ]
}
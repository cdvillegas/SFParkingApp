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
        case motion
    }
    
    static let allSteps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to SF Parking",
            description: "Never get another parking ticket. We've built the smartest way to navigate San Francisco's complex parking rules.",
            systemImage: "car.fill",
            color: .blue,
            permissionType: nil,
            buttonText: "Next"
        ),
        OnboardingStep(
            title: "Find Your Spot Instantly",
            description: "We use your location to show nearby parking rules and help you find safe spots faster. Your location stays private and on your device.",
            systemImage: "location.fill",
            color: .green,
            permissionType: .location,
            buttonText: "Enable Location"
        ),
        OnboardingStep(
            title: "Never Miss Street Cleaning",
            description: "Get perfectly timed street cleaning alerts. You control when and how you're notified. No ads, no spam, just helpful reminders that save you money.",
            systemImage: "bell.badge.fill",
            color: .orange,
            permissionType: .notifications,
            buttonText: "Enable Notifications"
        ),
        OnboardingStep(
            title: "Smart Parking Detection",
            description: "We intelligently detect when you finish driving and automatically update your parking location. Street cleaning alerts set up automatically.",
            systemImage: "car.fill",
            color: .purple,
            permissionType: .motion,
            buttonText: "Enable Parking Detection"
        )
    ]
}

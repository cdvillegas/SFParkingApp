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
        case smartParking
    }
    
    static let allSteps: [OnboardingStep] = [
        OnboardingStep(
            title: "Hello, San Francisco!",
            description: "We know parking here can be tough. We're committed to helping you avoid tickets and park safely.",
            systemImage: "car.fill",
            color: .blue,
            permissionType: nil,
            buttonText: "Continue"
        ),
        OnboardingStep(
            title: "Find Your Parking Spot",
            description: "We'll help you track where you parked and show you the street cleaning rules for that exact location.",
            systemImage: "location.fill",
            color: .blue,
            permissionType: .location,
            buttonText: "Enable Location"
        ),
        OnboardingStep(
            title: "Stay One Step Ahead",
            description: "Get perfectly timed reminders before street cleaning starts. Never rush to move your car again.",
            systemImage: "bell.badge.fill",
            color: .blue,
            permissionType: .notifications,
            buttonText: "Enable Notifications"
        ),
        OnboardingStep(
            title: "Automatic Parking Detection",
            description: "Automatically update your parking location using motion and vehicle connection data.",
            systemImage: "sparkles",
            color: .blue,
            permissionType: .smartParking,
            buttonText: "Enable Smart Park"
        )
    ]

}

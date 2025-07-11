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
    }
    
    static let allSteps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to SF Parking",
            description: "Leave parking tickets in the past. We've built the smartest way to park in San Francisco.",
            systemImage: "car.fill",
            color: .blue,
            permissionType: nil,
            buttonText: "Get Started"
        ),
        OnboardingStep(
            title: "Know Your Spot",
            description: "See street cleaning schedules right where you are. Location data stays on your device and is never tracked or stored.",
            systemImage: "location.fill",
            color: .green,
            permissionType: .location,
            buttonText: "Enable Location"
        ),
        OnboardingStep(
            title: "Get Timely Reminders",
            description: "Get perfectly timed reminders before street cleaning starts. Choose when and how you want to be notified—we'll handle the rest.",
            systemImage: "bell.badge.fill",
            color: .orange,
            permissionType: .notifications,
            buttonText: "Enable Notifications"
        )
    ]
}

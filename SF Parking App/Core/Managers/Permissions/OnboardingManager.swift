import Foundation

class OnboardingManager {
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    
    static var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey)
        }
    }
    
    static func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
    }
    
    static func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}
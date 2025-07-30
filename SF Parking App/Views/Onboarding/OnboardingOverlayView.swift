import SwiftUI

struct OnboardingOverlayView: View {
    @State private var currentStep = 0
    @State private var showingContent = true
    @State private var hasLoggedStart = false
    
    let onCompleted: () -> Void
    let onboardingSteps = OnboardingStep.allSteps
    
    var body: some View {
        ZStack {
            // Blurry glass overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(.all)
            
            // Onboarding content
            if showingContent {
                VStack(spacing: 0) {
                    // Progress indicator at the top
                    VStack {
                        OnboardingProgressView(
                            currentStep: currentStep,
                            totalSteps: onboardingSteps.count,
                            color: onboardingSteps[currentStep].color
                        )
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                    }
                    
                    // Main content
                    if currentStep < onboardingSteps.count {
                        OnboardingStepView(
                            step: onboardingSteps[currentStep],
                            isLastStep: currentStep == onboardingSteps.count - 1,
                            onNext: {
                                AnalyticsManager.shared.logOnboardingStepCompleted(stepName: onboardingSteps[currentStep].title)
                                if currentStep < onboardingSteps.count - 1 {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentStep += 1
                                    }
                                } else {
                                    completeOnboarding()
                                }
                            },
                            onSkip: {
                                AnalyticsManager.shared.logOnboardingSkipped()
                                completeOnboarding()
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .id(currentStep)
                    }
                }
                .onAppear {
                    if !hasLoggedStart {
                        AnalyticsManager.shared.logOnboardingStarted()
                        hasLoggedStart = true
                    }
                }
            }
        }
    }
    
    private func completeOnboarding() {
        AnalyticsManager.shared.logOnboardingCompleted()
        OnboardingManager.completeOnboarding()
        
        // Simple fade out - no complex timing
        withAnimation(.easeOut(duration: 0.4)) {
            showingContent = false
        }
        
        // Complete immediately after content fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onCompleted()
        }
    }
}

#Preview("Light Mode") {
    OnboardingOverlayView(onCompleted: {})
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    OnboardingOverlayView(onCompleted: {})
        .preferredColorScheme(.dark)
}
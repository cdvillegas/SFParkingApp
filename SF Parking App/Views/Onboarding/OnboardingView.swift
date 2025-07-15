import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var showingOnboarding = true
    @State private var showingCompletion = false
    
    let onboardingSteps = OnboardingStep.allSteps
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            if showingCompletion {
                OnboardingCompletionView {
                    completeOnboarding()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 1.1))
                ))
            } else if showingOnboarding {
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
                                if currentStep < onboardingSteps.count - 1 {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        currentStep += 1
                                    }
                                } else {
                                    showCompletionView()
                                }
                            },
                            onSkip: {
                                showCompletionView()
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .id(currentStep)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
    }
    
    private func showCompletionView() {
        withAnimation(.easeInOut(duration: 0.6)) {
            showingCompletion = true
        }
    }
    
    private func completeOnboarding() {
        OnboardingManager.completeOnboarding()
        
        // Add a subtle pause before transitioning
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Notify that onboarding completed
            NotificationCenter.default.post(name: NSNotification.Name("OnboardingCompleted"), object: nil)
            
            withAnimation(.easeInOut(duration: 0.6)) {
                showingOnboarding = false
            }
        }
    }
}

#Preview("Light Mode") {
    OnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    OnboardingView()
        .preferredColorScheme(.dark)
}

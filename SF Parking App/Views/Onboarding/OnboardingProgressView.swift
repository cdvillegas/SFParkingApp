import SwiftUI

struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    let gradientColors: [Color]
    
    var body: some View {
        // Page dots only
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? 
                          LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing) :
                          LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentStep ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }
    
    private var progress: CGFloat {
        guard totalSteps > 0 else { return 0 }
        return CGFloat(currentStep + 1) / CGFloat(totalSteps)
    }
}

#Preview("Light Mode") {
    OnboardingProgressView(
        currentStep: 2,
        totalSteps: 6,
        gradientColors: [Color.blue, Color.cyan]
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    OnboardingProgressView(
        currentStep: 2,
        totalSteps: 6,
        gradientColors: [Color.blue, Color.cyan]
    )
    .padding()
    .preferredColorScheme(.dark)
}
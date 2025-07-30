import SwiftUI

struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    let color: Color
    
    var body: some View {
        // Beautiful glass-like progress dots
        HStack(spacing: 12) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? 
                          LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(colors: [Color.white.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: index == currentStep ? 12 : 8, height: index == currentStep ? 12 : 8)
                    .shadow(color: index == currentStep ? color.opacity(0.4) : Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
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
        color: Color.blue
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    OnboardingProgressView(
        currentStep: 2,
        totalSteps: 6,
        color: Color.blue
    )
    .padding()
    .preferredColorScheme(.dark)
}

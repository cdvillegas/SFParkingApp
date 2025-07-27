import SwiftUI

struct OnboardingCompletionView: View {
    let onComplete: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 100) // Push content higher
            
            // Icon or illustration
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 120))
                .foregroundColor(.blue)
                .scaleEffect(isAnimating ? 1.0 : 0.5)
                .opacity(isAnimating ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: isAnimating)
            
            // Title
            Text("You're All Set!")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
                .animation(.easeInOut(duration: 0.6).delay(0.5), value: isAnimating)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            // Trigger animations
            withAnimation {
                isAnimating = true
            }
            
            // Auto-complete after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onComplete()
            }
        }
    }
}

// Alternative with GeometryReader for more control
struct OnboardingCompletionViewAlt: View {
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                VStack(spacing: 25) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.green)
                    
                    Text("You're All Set!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Smart parking detection is now active.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: geometry.size.width * 0.85)
                
                Spacer()
                
                Button("Get Started") {
                    // Action
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 50)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

import SwiftUI

struct OnboardingCompletionView: View {
    let onComplete: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer(minLength: 60) // Reduced to move content higher
            
            // Beautiful SF-themed completion icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(.ultraThinMaterial, lineWidth: 2)
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(isAnimating ? 1.0 : 0.3)
            .opacity(isAnimating ? 1.0 : 0.0)
            .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2), value: isAnimating)
            
            VStack(spacing: 12) {
                // Title
                Text("Welcome to San Francisco!")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 20)
                    .animation(.easeInOut(duration: 0.6).delay(0.5), value: isAnimating)
                
                // Subtitle
                Text("You're ready to park smarter and never get another ticket.")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 20)
                    .animation(.easeInOut(duration: 0.6).delay(0.7), value: isAnimating)
            }
            
            Spacer()
            Spacer() // Extra spacer to push content even higher
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

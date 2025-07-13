import SwiftUI

struct OnboardingCompletionView: View {
    @State private var showingCheckmark = false
    @State private var showingText = false
    @State private var isComplete = false
    
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Animated checkmark
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 100, height: 100)
                        .scaleEffect(showingCheckmark ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.4), value: showingCheckmark)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(showingCheckmark ? 1.0 : 0.1)
                        .animation(.easeInOut(duration: 0.4).delay(0.1), value: showingCheckmark)
                }
                
                // Success text
                VStack(spacing: 16) {
                    Text("You're All Set!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(showingText ? 1.0 : 0.0)
                        .offset(y: showingText ? 0 : 20)
                        .animation(.easeInOut(duration: 0.4).delay(0.2), value: showingText)
                }
                
                Spacer()
                Spacer()
            }
            
        }
        .onAppear {
            // Haptic feedback for success
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
            
            withAnimation {
                showingCheckmark = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    showingText = true
                }
            }
            
            // Auto-complete after showing the success state - faster
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                // Final haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                withAnimation {
                    isComplete = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onComplete()
                }
            }
        }
    }
}

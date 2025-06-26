import SwiftUI

struct OnboardingCompletionView: View {
    @State private var showingCheckmark = false
    @State private var showingText = false
    @State private var isComplete = false
    
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Beautiful gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.green.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Animated checkmark
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(showingCheckmark ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.6), value: showingCheckmark)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(showingCheckmark ? 1.0 : 0.1)
                        .animation(.easeInOut(duration: 0.6).delay(0.2), value: showingCheckmark)
                }
                
                // Success text
                VStack(spacing: 16) {
                    Text("You're All Set!")
                        .font(.title)
                        .fontWeight(.bold)
                        .opacity(showingText ? 1.0 : 0.0)
                        .offset(y: showingText ? 0 : 20)
                        .animation(.easeInOut(duration: 0.6).delay(0.4), value: showingText)
                    
                    Text("Welcome to the future of parking")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .opacity(showingText ? 1.0 : 0.0)
                        .offset(y: showingText ? 0 : 20)
                        .animation(.easeInOut(duration: 0.6).delay(0.6), value: showingText)
                }
                
                Spacer()
                Spacer()
            }
        }
        .onAppear {
            withAnimation {
                showingCheckmark = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    showingText = true
                }
            }
            
            // Auto-complete after showing the success state
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    isComplete = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}
import SwiftUI
import CoreLocation

struct UserDirectionCone: View {
    let heading: CLLocationDirection
    
    var body: some View {
        ZStack {
            // Flashlight beam - wider and more spread out
            FlashlightBeam()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.8),
                            Color.blue.opacity(0.4),
                            Color.blue.opacity(0.1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 32, height: 22)
                .offset(y: -15) // Position beam pointing outward from center
                .rotationEffect(.degrees(heading))
            
            // User location dot - centered
            Circle()
                .fill(Color.blue)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 0.5)
                )
        }
        .shadow(color: Color.blue.opacity(0.2), radius: 3, x: 0, y: 1)
    }
}

// Custom flashlight beam shape - wider and more realistic
struct FlashlightBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start at the bottom center (where the user is located)
        let startPoint = CGPoint(x: rect.midX, y: rect.maxY)
        path.move(to: startPoint)
        
        // Create a wider beam that spreads out like a flashlight
        let beamWidth = rect.width * 0.8 // 80% of the frame width
        let leftEdge = rect.midX - (beamWidth / 2)
        let rightEdge = rect.midX + (beamWidth / 2)
        
        // Draw to top left of beam
        path.addLine(to: CGPoint(x: leftEdge, y: rect.minY))
        
        // Draw across the top
        path.addLine(to: CGPoint(x: rightEdge, y: rect.minY))
        
        // Draw back to start point
        path.addLine(to: startPoint)
        
        path.closeSubpath()
        
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        UserDirectionCone(heading: 0)   // North
        UserDirectionCone(heading: 90)  // East
        UserDirectionCone(heading: 180) // South
        UserDirectionCone(heading: 270) // West
    }
    .padding()
}
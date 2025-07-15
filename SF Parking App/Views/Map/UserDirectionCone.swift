import SwiftUI
import CoreLocation

struct UserDirectionCone: View {
    let heading: CLLocationDirection
    let mapHeading: CLLocationDirection
    
    var body: some View {
        ZStack {
            // Flashlight beam - bigger and more visible with fade at tip
            FlashlightBeam()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.blue.opacity(0.9), location: 0.0),    // Strong at base
                            .init(color: Color.blue.opacity(0.7), location: 0.3),    // Still visible
                            .init(color: Color.blue.opacity(0.4), location: 0.6),    // Fading
                            .init(color: Color.blue.opacity(0.15), location: 0.85),  // Nearly transparent
                            .init(color: Color.blue.opacity(0.0), location: 1.0)     // Fully transparent at tip
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 40, height: 28) // Bigger cone
                .offset(y: -18) // Position beam pointing outward from center
                .rotationEffect(.degrees(heading - mapHeading)) // Relative to map rotation
                .animation(.easeInOut(duration: 0.3), value: heading - mapHeading)
            
            // User location dot - bigger and more visible
            Circle()
                .fill(Color.blue)
                .frame(width: 18, height: 18) // A tiny bit bigger dot
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                )
        }
        .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
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
        UserDirectionCone(heading: 0, mapHeading: 0)   // North
        UserDirectionCone(heading: 90, mapHeading: 0)  // East
        UserDirectionCone(heading: 180, mapHeading: 0) // South
        UserDirectionCone(heading: 270, mapHeading: 0) // West
    }
    .padding()
}
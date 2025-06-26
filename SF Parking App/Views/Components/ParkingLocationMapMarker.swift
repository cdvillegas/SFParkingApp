import SwiftUI
import MapKit

struct ParkingLocationMapMarker: View {
    let location: ParkingLocation
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer glow for selected location
                if isSelected {
                    Circle()
                        .fill(location.color.color.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                }
                
                // Main marker circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                location.color.color,
                                location.color.color.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Car icon
                Image(systemName: "car.fill")
                    .font(.system(size: isSelected ? 16 : 14, weight: .semibold))
                    .foregroundColor(.white)
                
                // Name badge for custom named locations
                if let name = location.name, !name.isEmpty {
                    VStack {
                        Spacer()
                        Text(name)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(location.color.color)
                                    .opacity(0.9)
                            )
                            .offset(y: 30)
                    }
                }
            }
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onAppear {
            if isSelected {
                isAnimating = true
            }
        }
        .onChange(of: isSelected) { selected in
            isAnimating = selected
        }
    }
}

struct ParkingLocationAnnotation: Identifiable {
    let id: UUID
    let location: ParkingLocation
    let coordinate: CLLocationCoordinate2D
    
    init(location: ParkingLocation) {
        self.id = location.id
        self.location = location
        self.coordinate = location.coordinate
    }
}

#Preview {
    ParkingLocationMapMarker(
        location: ParkingLocation.sample,
        isSelected: true,
        onTap: {}
    )
    .padding()
    .background(Color.gray.opacity(0.1))
}
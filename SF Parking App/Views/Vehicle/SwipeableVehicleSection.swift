import SwiftUI
import CoreLocation

struct SwipeableVehicleSection: View {
    let vehicles: [Vehicle]
    let selectedVehicle: Vehicle?
    let onVehicleSelected: (Vehicle) -> Void
    let onVehicleTap: (Vehicle) -> Void
    let onShareLocation: ((ParkingLocation) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            if !vehicles.isEmpty {
                // Single vehicle card - no swiping
                if let vehicle = vehicles.first {
                    VehicleSwipeCard(
                        vehicle: vehicle,
                        isSelected: selectedVehicle?.id == vehicle.id,
                        onTap: {
                            impactFeedback()
                            onVehicleTap(vehicle)
                        },
                        onShare: onShareLocation
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "car.circle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("No Vehicles")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Add your first vehicle to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(height: 120)
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

struct VehicleSwipeCard: View {
    let vehicle: Vehicle
    let isSelected: Bool
    let onTap: () -> Void
    let onShare: ((ParkingLocation) -> Void)?
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Vehicle icon with color
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    vehicle.color.color,
                                    vehicle.color.color.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: vehicle.type.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: vehicle.color.color.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Vehicle info
                VStack(alignment: .leading, spacing: 4) {
                    // Parking address
                    if let parkingLocation = vehicle.parkingLocation {
                        Text(parkingLocation.address.components(separatedBy: ",").prefix(2).joined(separator: ","))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Text("View In Maps")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else {
                        Text("No vehicle location set")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Text("Tap to set location")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(
                    color: vehicle.color.color.opacity(0.2), // Always show vehicle glow
                    radius: 6,
                    x: 0,
                    y: 3
                )
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                        isPressed = false
                    }
                    
                    // Enhanced haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.prepare()
                    impactFeedback.impactOccurred()
                    
                    onTap()
                }
        )
        .overlay(
            // Share button overlay - completely outside the card layout
            Group {
                if let parkingLocation = vehicle.parkingLocation, let onShare = onShare {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            ZStack {
                                // Visual button
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .offset(y: -1) // Slight upward offset to visually center the icon
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(Color(.systemGray6))
                                    )
                                
                                // Invisible larger tap area overlay
                                Button(action: {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    onShare(parkingLocation)
                                }) {
                                    Color.clear
                                        .frame(width: 60, height: 60) // Larger tap area
                                        .contentShape(Rectangle())
                                }
                            }
                            Spacer()
                        }
                        .padding(.trailing, 20) // Match card padding
                    }
                }
            },
            alignment: .topTrailing
        )
    }
}

#Preview("Light Mode") {
    VehicleParkingView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VehicleParkingView()
        .preferredColorScheme(.dark)
}

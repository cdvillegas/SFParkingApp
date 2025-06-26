import SwiftUI
import CoreLocation

struct SwipeableVehicleSection: View {
    let vehicles: [Vehicle]
    let selectedVehicle: Vehicle?
    let onVehicleSelected: (Vehicle) -> Void
    let onVehicleTap: (Vehicle) -> Void
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false
    
    private let cardWidth: CGFloat = UIScreen.main.bounds.width - 32 // Just small side margins
    private let cardSpacing: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            if !vehicles.isEmpty {
                // Cards container
                GeometryReader { geometry in
                    HStack(spacing: cardSpacing) {
                        ForEach(Array(vehicles.enumerated()), id: \.element.id) { index, vehicle in
                            VehicleSwipeCard(
                                vehicle: vehicle,
                                isSelected: selectedVehicle?.id == vehicle.id,
                                onTap: {
                                    impactFeedback()
                                    onVehicleTap(vehicle)
                                }
                            )
                            .frame(width: cardWidth)
                            .scaleEffect(scaleForCard(at: index))
                            .opacity(opacityForCard(at: index))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentIndex)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: dragOffset)
                        }
                    }
                    .offset(x: offsetForCurrentIndex() + dragOffset)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            if !isAnimating {
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            handleDragEnd(value: value)
                        }
                )
                .frame(height: 120)
                .clipped()
                
                // Page indicators
                if vehicles.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<vehicles.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? vehicles[currentIndex].color.color : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentIndex ? 1.2 : 1.0)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
                        }
                    }
                    .padding(.top, 12)
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
        .onAppear {
            updateCurrentIndex()
        }
        .onChange(of: selectedVehicle) {
            updateCurrentIndex()
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateCurrentIndex() {
        if let selectedVehicle = selectedVehicle,
           let index = vehicles.firstIndex(where: { $0.id == selectedVehicle.id }) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentIndex = index
            }
        }
    }
    
    private func offsetForCurrentIndex() -> CGFloat {
        let totalWidth = cardWidth + cardSpacing
        let screenWidth = UIScreen.main.bounds.width
        let centerOffset = (screenWidth - cardWidth) / 2
        return centerOffset - (CGFloat(currentIndex) * totalWidth)
    }
    
    private func scaleForCard(at index: Int) -> CGFloat {
        let distance = abs(index - currentIndex)
        if distance == 0 {
            return 1.0
        } else if distance == 1 {
            return 0.95
        } else {
            return 0.9
        }
    }
    
    private func opacityForCard(at index: Int) -> Double {
        let distance = abs(index - currentIndex)
        if distance == 0 {
            return 1.0
        } else if distance == 1 {
            return 0.7
        } else {
            return 0.4
        }
    }
    
    private func handleDragEnd(value: DragGesture.Value) {
        isAnimating = true
        
        let threshold: CGFloat = 50
        let velocity = value.predictedEndTranslation.width - value.translation.width
        
        if value.translation.width > threshold || velocity > 500 {
            // Swipe right - go to previous
            if currentIndex > 0 {
                currentIndex -= 1
                selectCurrentVehicle()
            }
        } else if value.translation.width < -threshold || velocity < -500 {
            // Swipe left - go to next
            if currentIndex < vehicles.count - 1 {
                currentIndex += 1
                selectCurrentVehicle()
            }
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            dragOffset = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isAnimating = false
        }
    }
    
    private func selectCurrentVehicle() {
        if currentIndex >= 0 && currentIndex < vehicles.count {
            let vehicle = vehicles[currentIndex]
            onVehicleSelected(vehicle)
            impactFeedback()
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
                    Text(vehicle.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(vehicle.type.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(vehicle.color.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Parking status
            HStack(spacing: 16) {
                // Parking indicator
                HStack(spacing: 4) {
                    Image(systemName: vehicle.parkingLocation != nil ? "location.fill" : "location.slash")
                        .font(.caption)
                        .foregroundColor(vehicle.parkingLocation != nil ? .green : .secondary)
                    
                    Text(vehicle.parkingLocation != nil ? "Parked" : "Not Parked")
                        .font(.caption)
                        .foregroundColor(vehicle.parkingLocation != nil ? .green : .secondary)
                }
                
                Spacer()
                
                // Time stamp or parking address
                if let parkingLocation = vehicle.parkingLocation {
                    Text(parkingLocation.address.components(separatedBy: ",").first ?? "Unknown Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(RelativeDateTimeFormatter().localizedString(for: vehicle.createdAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(
                    color: isSelected ? vehicle.color.color.opacity(0.2) : Color.black.opacity(0.08),
                    radius: isSelected ? 6 : 3,
                    x: 0,
                    y: isSelected ? 3 : 1
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
            onTap()
        }
    }
}

#Preview {
    VStack {
        SwipeableVehicleSection(
            vehicles: [
                Vehicle.sample,
                Vehicle(
                    name: "My Truck",
                    type: .truck,
                    color: .red
                ),
                Vehicle(
                    name: "My Bike",
                    type: .motorcycle,
                    color: .green
                )
            ],
            selectedVehicle: Vehicle.sample,
            onVehicleSelected: { _ in },
            onVehicleTap: { _ in }
        )
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

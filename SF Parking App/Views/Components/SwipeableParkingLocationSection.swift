import SwiftUI
import CoreLocation

struct SwipeableParkingLocationSection: View {
    let locations: [ParkingLocation]
    let selectedLocation: ParkingLocation?
    let onLocationSelected: (ParkingLocation) -> Void
    let onLocationTap: (ParkingLocation) -> Void
    let onLocationEdit: (ParkingLocation) -> Void
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false
    
    private let cardWidth: CGFloat = UIScreen.main.bounds.width - 32 // Just small side margins
    private let cardSpacing: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            if !locations.isEmpty {
                // Cards container
                GeometryReader { geometry in
                    HStack(spacing: cardSpacing) {
                        ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                            ParkingLocationSwipeCard(
                                location: location,
                                isSelected: selectedLocation?.id == location.id,
                                onTap: {
                                    impactFeedback()
                                    onLocationTap(location)
                                },
                                onEdit: {
                                    onLocationEdit(location)
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
                if locations.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<locations.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? locations[currentIndex].color.color : Color.gray.opacity(0.3))
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
                        Text("No Parking Locations")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Add your first parking location to get started")
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
        .onChange(of: selectedLocation) {
            updateCurrentIndex()
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateCurrentIndex() {
        if let selectedLocation = selectedLocation,
           let index = locations.firstIndex(where: { $0.id == selectedLocation.id }) {
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
                selectCurrentLocation()
            }
        } else if value.translation.width < -threshold || velocity < -500 {
            // Swipe left - go to next
            if currentIndex < locations.count - 1 {
                currentIndex += 1
                selectCurrentLocation()
            }
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            dragOffset = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isAnimating = false
        }
    }
    
    private func selectCurrentLocation() {
        if currentIndex >= 0 && currentIndex < locations.count {
            let location = locations[currentIndex]
            onLocationSelected(location)
            impactFeedback()
        }
    }
    
    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

struct ParkingLocationSwipeCard: View {
    let location: ParkingLocation
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Color indicator with car icon
                ZStack {
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
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: location.color.color.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Location info
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(location.address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Location details
            HStack(spacing: 16) {
                // Source indicator
                HStack(spacing: 4) {
                    Image(systemName: sourceIcon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(location.source.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Time stamp
                Text(RelativeDateTimeFormatter().localizedString(for: location.timestamp, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(
                    color: isSelected ? location.color.color.opacity(0.2) : Color.black.opacity(0.08),
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
    
    private var sourceIcon: String {
        switch location.source {
        case .manual:
            return "hand.tap"
        case .motionActivity:
            return "figure.walk"
        case .carDisconnect:
            return "car.side.and.exclamationmark"
        }
    }
}

#Preview {
    VStack {
        SwipeableParkingLocationSection(
            locations: [
                ParkingLocation.sample,
                ParkingLocation(
                    coordinate: CLLocationCoordinate2D(latitude: 37.785, longitude: -122.442),
                    address: "1234 Market Street, San Francisco, CA",
                    name: "Work",
                    color: .red
                ),
                ParkingLocation(
                    coordinate: CLLocationCoordinate2D(latitude: 37.786, longitude: -122.443),
                    address: "555 California Street, San Francisco, CA",
                    name: "Gym",
                    color: .green
                )
            ],
            selectedLocation: ParkingLocation.sample,
            onLocationSelected: { _ in },
            onLocationTap: { _ in },
            onLocationEdit: { _ in }
        )
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
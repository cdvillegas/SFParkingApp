import SwiftUI

struct VehicleParkingMapMarker: View {
    let vehicle: Vehicle
    let isSelected: Bool
    let streetDataManager: StreetDataManager?
    let originalUrgencyColor: Color?
    let onTap: () -> Void
    
    init(vehicle: Vehicle, isSelected: Bool, streetDataManager: StreetDataManager?, originalUrgencyColor: Color? = nil, onTap: @escaping () -> Void) {
        self.vehicle = vehicle
        self.isSelected = isSelected
        self.streetDataManager = streetDataManager
        self.originalUrgencyColor = originalUrgencyColor
        self.onTap = onTap
    }

    @State private var isAnimating = false

    var body: some View {
        Button(action: {
            onTap()
            impactFeedback()
        }) {
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                getUrgencyColor(for: vehicle),
                                getUrgencyColor(for: vehicle).opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28) // A tiny bit bigger

                // Vehicle icon
                Image(systemName: vehicle.type.iconName)
                    .font(.system(size: 13, weight: .semibold)) // A tiny bit bigger icon
                    .foregroundColor(.white)
            }
            .shadow(
                color: getUrgencyColor(for: vehicle).opacity(0.4),
                radius: isSelected ? 6 : 3,
                x: 0,
                y: isSelected ? 3 : 1.5
            )
            .scaleEffect(1.0) // No scaling on selection
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isAnimating)
        }
        .buttonStyle(PlainButtonStyle())
        .onChange(of: isSelected) { _, selected in
            if selected {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    isAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAnimating = false
                    }
                }
            }
        }
    }

    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Helper Functions
    
    private func getUrgencyColor(for vehicle: Vehicle) -> Color {
        // If we have an original urgency color (during location setting), use that
        if let originalColor = originalUrgencyColor {
            return originalColor
        }
        
        // Otherwise, calculate based on current schedule
        guard let streetDataManager = streetDataManager,
              let nextSchedule = streetDataManager.nextUpcomingSchedule,
              vehicle.parkingLocation != nil else {
            return vehicle.color.color
        }
        
        let urgencyLevel = getUrgencyLevel(for: nextSchedule.date)
        switch urgencyLevel {
        case .critical:
            return .red
        case .safe:
            return .green
        }
    }
    
    private enum UrgencyLevel {
        case critical  // < 24 hours
        case safe      // >= 24 hours
    }
    
    private func getUrgencyLevel(for date: Date) -> UrgencyLevel {
        let timeInterval = date.timeIntervalSinceNow
        let hours = timeInterval / 3600
        
        if hours < 24 {
            return .critical
        } else {
            return .safe
        }
    }
    
}

#Preview("Light Mode") {
    VStack(spacing: 20) {
        VehicleParkingMapMarker(
            vehicle: Vehicle.sample,
            isSelected: false,
            streetDataManager: nil,
            onTap: {}
        )

        VehicleParkingMapMarker(
            vehicle: Vehicle.sample,
            isSelected: true,
            streetDataManager: nil,
            onTap: {}
        )
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        VehicleParkingMapMarker(
            vehicle: Vehicle.sample,
            isSelected: false,
            streetDataManager: nil,
            onTap: {}
        )

        VehicleParkingMapMarker(
            vehicle: Vehicle.sample,
            isSelected: true,
            streetDataManager: nil,
            onTap: {}
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}

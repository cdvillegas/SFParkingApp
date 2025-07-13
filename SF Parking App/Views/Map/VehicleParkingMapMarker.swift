import SwiftUI

struct VehicleParkingMapMarker: View {
    let vehicle: Vehicle
    let isSelected: Bool
    let onTap: () -> Void

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
                                vehicle.color.color,
                                vehicle.color.color.opacity(0.8)
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
                color: vehicle.color.color.opacity(0.4),
                radius: isSelected ? 6 : 3,
                x: 0,
                y: isSelected ? 3 : 1.5
            )
            .scaleEffect(1.0) // No scaling on selection
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isAnimating)
        }
        .buttonStyle(PlainButtonStyle())
        .onChange(of: isSelected) { selected in
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
}

#Preview("Light Mode") {
    VStack(spacing: 20) {
        VehicleParkingMapMarker(
            vehicle: Vehicle.sample,
            isSelected: false,
            onTap: {}
        )

        VehicleParkingMapMarker(
            vehicle: Vehicle.sample,
            isSelected: true,
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
            onTap: {}
        )

        VehicleParkingMapMarker(
            vehicle: Vehicle.sample,
            isSelected: true,
            onTap: {}
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}

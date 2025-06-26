import SwiftUI

struct VehicleListRow: View {
    let vehicle: Vehicle
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSetLocation: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Vehicle icon
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
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: vehicle.type.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: vehicle.color.color.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Vehicle info
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
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
                    
                    // Parking status
                    HStack(spacing: 4) {
                        Image(systemName: vehicle.parkingLocation != nil ? "location.fill" : "location.slash")
                            .font(.caption)
                            .foregroundColor(vehicle.parkingLocation != nil ? .green : .secondary)
                        
                        if let parkingLocation = vehicle.parkingLocation {
                            Text("Parked at \(parkingLocation.address.components(separatedBy: ",").first ?? "Unknown Location")")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Not parked")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    if vehicle.parkingLocation == nil {
                        Button("Set Location") {
                            onSetLocation()
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    
                    Button(action: onEdit) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: isSelected ? vehicle.color.color.opacity(0.2) : Color.black.opacity(0.08),
                        radius: isSelected ? 6 : 3,
                        x: 0,
                        y: isSelected ? 3 : 1
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? vehicle.color.color : Color.clear,
                                lineWidth: isSelected ? 2 : 0
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    VStack(spacing: 12) {
        VehicleListRow(
            vehicle: Vehicle.sample,
            isSelected: false,
            onTap: {},
            onEdit: {},
            onSetLocation: {}
        )
        
        VehicleListRow(
            vehicle: Vehicle(name: "My Truck", type: .truck, color: .red),
            isSelected: true,
            onTap: {},
            onEdit: {},
            onSetLocation: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
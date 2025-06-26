import SwiftUI
import CoreLocation

struct ParkingLocationListView: View {
    let locations: [ParkingLocation]
    let selectedLocation: ParkingLocation?
    let onLocationSelected: (ParkingLocation) -> Void
    let onLocationEdit: (ParkingLocation) -> Void
    let onLocationDelete: (ParkingLocation) -> Void
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(locations) { location in
                ParkingLocationCard(
                    location: location,
                    isSelected: selectedLocation?.id == location.id,
                    onTap: { onLocationSelected(location) },
                    onEdit: { onLocationEdit(location) },
                    onDelete: { onLocationDelete(location) }
                )
            }
        }
        .padding(.horizontal, 16)
    }
}

struct ParkingLocationCard: View {
    let location: ParkingLocation
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showingOptions = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Color indicator
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
                    .overlay(
                        Image(systemName: "car.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
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
                    
                    HStack(spacing: 8) {
                        Label(location.source.displayName, systemImage: sourceIcon)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(RelativeDateTimeFormatter().localizedString(for: location.timestamp, relativeTo: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Selection indicator and options
                VStack(spacing: 8) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(location.color.color)
                    }
                    
                    Button(action: { showingOptions = true }) {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? location.color.color : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Location Options", isPresented: $showingOptions, titleVisibility: .visible) {
            Button("Edit Location") { onEdit() }
            Button("Delete Location", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
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
    ScrollView {
        ParkingLocationListView(
            locations: [
                ParkingLocation.sample,
                ParkingLocation(
                    coordinate: CLLocationCoordinate2D(latitude: 37.785, longitude: -122.442),
                    address: "1234 Market Street, San Francisco, CA",
                    name: "Home",
                    color: .red
                )
            ],
            selectedLocation: ParkingLocation.sample,
            onLocationSelected: { _ in },
            onLocationEdit: { _ in },
            onLocationDelete: { _ in }
        )
    }
    .background(Color(.systemGroupedBackground))
}
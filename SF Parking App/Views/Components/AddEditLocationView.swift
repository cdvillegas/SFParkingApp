import SwiftUI
import CoreLocation

struct AddEditLocationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var parkingManager: ParkingLocationManager
    
    let editingLocation: ParkingLocation?
    let coordinate: CLLocationCoordinate2D
    let address: String
    
    @State private var locationName: String = ""
    @State private var selectedColor: ParkingLocationColor = .blue
    @State private var showingColorPicker = false
    
    private var isEditing: Bool {
        editingLocation != nil
    }
    
    init(parkingManager: ParkingLocationManager, editingLocation: ParkingLocation? = nil, coordinate: CLLocationCoordinate2D, address: String) {
        self.parkingManager = parkingManager
        self.editingLocation = editingLocation
        self.coordinate = coordinate
        self.address = address
        
        if let location = editingLocation {
            _locationName = State(initialValue: location.name ?? "")
            _selectedColor = State(initialValue: location.color)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    // Color preview
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        selectedColor.color,
                                        selectedColor.color.opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "car.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text(isEditing ? "Edit Location" : "Add Location")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                // Form
                VStack(spacing: 20) {
                    // Location name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location Name (Optional)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("e.g., Home, Work, Gym", text: $locationName)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                    
                    // Address display
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Address")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(address)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                            )
                    }
                    
                    // Color selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Button(action: { showingColorPicker.toggle() }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(selectedColor.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                
                                Text(selectedColor.displayName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                            )
                        }
                        
                        if showingColorPicker {
                            ColorSelectionGrid(selectedColor: $selectedColor)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: saveLocation) {
                        Text(isEditing ? "Update Location" : "Add Location")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [selectedColor.color, selectedColor.color.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
        .animation(.easeInOut(duration: 0.3), value: showingColorPicker)
    }
    
    private func saveLocation() {
        let name = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? nil : name
        
        if let editingLocation = editingLocation {
            // Update existing location
            let updatedLocation = ParkingLocation(
                coordinate: editingLocation.coordinate,
                address: editingLocation.address,
                timestamp: editingLocation.timestamp,
                source: editingLocation.source,
                name: finalName,
                color: selectedColor,
                isActive: editingLocation.isActive
            )
            parkingManager.updateParkingLocation(updatedLocation)
        } else {
            // Add new location
            parkingManager.setManualParkingLocation(
                coordinate: coordinate,
                address: address,
                name: finalName,
                color: selectedColor
            )
        }
        
        dismiss()
    }
}

struct ColorSelectionGrid: View {
    @Binding var selectedColor: ParkingLocationColor
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ParkingLocationColor.allCases, id: \.self) { color in
                Button(action: { selectedColor = color }) {
                    Circle()
                        .fill(color.color)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .overlay(
                            Circle()
                                .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedColor)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    AddEditLocationView(
        parkingManager: ParkingLocationManager(),
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        address: "1234 Example Street, San Francisco, CA"
    )
}
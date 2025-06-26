import SwiftUI

struct AddEditVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vehicleManager: VehicleManager
    
    let editingVehicle: Vehicle?
    let onVehicleCreated: ((Vehicle) -> Void)?
    
    @State private var vehicleName: String = ""
    @State private var selectedType: VehicleType = .car
    @State private var selectedColor: VehicleColor = .blue
    @State private var useCustomName: Bool = false
    
    private var isEditing: Bool {
        editingVehicle != nil
    }
    
    private var title: String {
        isEditing ? "Edit Vehicle" : "Add Vehicle"
    }
    
    private var actionButtonTitle: String {
        isEditing ? "Save Changes" : "Add Vehicle"
    }
    
    private var generatedName: String {
        vehicleManager.generateVehicleName(for: selectedType)
    }
    
    private var finalVehicleName: String {
        if useCustomName && !vehicleName.trimmingCharacters(in: .whitespaces).isEmpty {
            return vehicleName.trimmingCharacters(in: .whitespaces)
        } else {
            return generatedName
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Vehicle Preview
                Section {
                    HStack {
                        // Vehicle icon preview
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
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: selectedType.iconName)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: selectedColor.color.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finalVehicleName)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 4) {
                                Text(selectedType.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("•")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(selectedColor.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Vehicle Name
                Section(header: Text("Vehicle Name")) {
                    Toggle("Use custom name", isOn: $useCustomName)
                    
                    if useCustomName {
                        TextField("Enter vehicle name", text: $vehicleName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    } else {
                        HStack {
                            Text(generatedName)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Auto-generated")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Vehicle Type
                Section(header: Text("Vehicle Type")) {
                    Picker("Type", selection: $selectedType) {
                        ForEach(VehicleType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.iconName)
                                    .frame(width: 20)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(height: 120)
                }
                
                // Vehicle Color
                Section(header: Text("Vehicle Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(VehicleColor.allCases, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                                impactFeedback()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                        )
                                        .shadow(color: color.color.opacity(0.3), radius: 3, x: 0, y: 2)
                                    
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(color == .white ? .black : .white)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(actionButtonTitle) {
                        saveVehicle()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            setupInitialValues()
        }
    }
    
    private func setupInitialValues() {
        if let vehicle = editingVehicle {
            selectedType = vehicle.type
            selectedColor = vehicle.color
            if let customName = vehicle.name {
                vehicleName = customName
                useCustomName = true
            }
        }
    }
    
    private func saveVehicle() {
        let finalName: String?
        if useCustomName {
            let trimmedName = vehicleName.trimmingCharacters(in: .whitespaces)
            finalName = trimmedName.isEmpty ? nil : trimmedName
        } else {
            finalName = nil
        }
        
        if let editingVehicle = editingVehicle {
            // Update existing vehicle
            var updatedVehicle = editingVehicle
            updatedVehicle.name = finalName
            updatedVehicle.type = selectedType
            updatedVehicle.color = selectedColor
            vehicleManager.updateVehicle(updatedVehicle)
        } else {
            // Create new vehicle
            let newVehicle = Vehicle(
                name: finalName,
                type: selectedType,
                color: selectedColor
            )
            vehicleManager.addVehicle(newVehicle)
            
            // Notify parent that vehicle was created
            onVehicleCreated?(newVehicle)
        }
        
        dismiss()
    }
    
    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

#Preview {
    AddEditVehicleView(
        vehicleManager: VehicleManager(),
        editingVehicle: nil,
        onVehicleCreated: nil
    )
}

#Preview("Editing") {
    AddEditVehicleView(
        vehicleManager: VehicleManager(),
        editingVehicle: Vehicle.sample,
        onVehicleCreated: nil
    )
}
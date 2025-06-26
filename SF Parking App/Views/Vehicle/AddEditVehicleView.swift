import SwiftUI

struct AddEditVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vehicleManager: VehicleManager
    
    let editingVehicle: Vehicle?
    let onVehicleCreated: ((Vehicle) -> Void)?
    
    @State private var vehicleName: String = ""
    @State private var originalName: String = "" // Track original name for canceling edits
    @State private var selectedType: VehicleType = .car
    @State private var selectedColor: VehicleColor = .blue
    @State private var isEditingName: Bool = false
    @FocusState private var isNameFieldFocused: Bool
    
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
    
    private var displayName: String {
        let trimmedName = vehicleName.trimmingCharacters(in: .whitespaces)
        return trimmedName.isEmpty ? generatedName : trimmedName
    }
    
    // Curated Apple-inspired color palette - 10 colors for 2x5 grid
    private let availableColors: [VehicleColor] = [
        .blue, .red, .green, .orange, .purple
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Hero Vehicle Preview
                        vehiclePreviewSection
                        
                        // Type and Color Selection
                        typeAndColorSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                }
                .background(Color(.systemGroupedBackground))
                .onTapGesture {
                    // Dismiss name editing when tapping outside
                    if isEditingName {
                        cancelNameEditing()
                    }
                }
                
                // Bottom Save Button
                VStack(spacing: 0) {
                    
                    Button(action: {
                        saveVehicle()
                    }) {
                        Text(actionButtonTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.blue)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, max(16, UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0))
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .onAppear {
            setupInitialValues()
        }
        .onChange(of: isNameFieldFocused) { _, newValue in
            if !newValue && isEditingName {
                commitNameEdit()
            }
        }
    }
    
    private var vehiclePreviewSection: some View {
        HStack(alignment: .center, spacing: 16) {
            // Large vehicle icon with sophisticated styling
            ZStack {
                // Main vehicle icon circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                selectedColor.color,
                                selectedColor.color.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(
                        color: selectedColor.color.opacity(0.4),
                        radius: 20,
                        x: 0,
                        y: 8
                    )
                
                // Vehicle icon
                Image(systemName: selectedType.iconName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: selectedColor)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: selectedType)
            
            // Vehicle info - leading aligned
            VStack(alignment: .leading, spacing: 8) {
                if isEditingName {
                    TextField("Vehicle name", text: $vehicleName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .focused($isNameFieldFocused)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit {
                            commitNameEdit()
                        }
                        .transition(.opacity)
                } else {
                    Button(action: {
                        startNameEditing()
                    }) {
                        Text(displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .transition(.opacity)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .contentShape(Rectangle()) // Make the whole area tappable
        .onTapGesture {
            // Start editing when tapping the preview section
            if !isEditingName {
                startNameEditing()
            }
        }
    }
    
    private var typeAndColorSection: some View {
        VStack(spacing: 28) {
            // Vehicle Type Selector
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Type")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                VStack(spacing: 4) {
                    ForEach(VehicleType.allCases, id: \.self) { type in
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                selectedType = type
                            }
                            impactFeedback()
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(selectedType == type ? Color.blue : Color(.systemGray5))
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: type.iconName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(selectedType == type ? .white : .secondary)
                                }
                                
                                Text(type.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(selectedType == type ? .primary : .secondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedType == type ? Color.blue.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            Divider()
            
            // Vehicle Color Selector
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Color")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 16) {
                    ForEach(availableColors, id: \.self) { color in
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                selectedColor = color
                            }
                            impactFeedback()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(
                                        width: selectedColor == color ? 48 : 40,
                                        height: selectedColor == color ? 48 : 40
                                    )
                                    .shadow(
                                        color: color.color.opacity(0.4),
                                        radius: selectedColor == color ? 8 : 4,
                                        x: 0,
                                        y: selectedColor == color ? 4 : 2
                                    )
                                
                                if selectedColor == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(color == .white || color == .yellow ? .black : .white)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedColor)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private func setupInitialValues() {
        if let vehicle = editingVehicle {
            selectedType = vehicle.type
            selectedColor = vehicle.color
            vehicleName = vehicle.name ?? ""
            originalName = vehicle.name ?? ""
        }
    }
    
    private func startNameEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingName = true
            // Store the current display name as original
            originalName = displayName == generatedName ? "" : vehicleName
            // Set the field to show current custom name or empty for generated names
            vehicleName = displayName == generatedName ? "" : displayName
        }
        // Delay focus to allow animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
    
    private func commitNameEdit() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingName = false
        }
    }
    
    private func cancelNameEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            vehicleName = originalName
            isEditingName = false
        }
    }
    
    private func saveVehicle() {
        let finalName: String?
        let trimmedName = vehicleName.trimmingCharacters(in: .whitespaces)
        finalName = trimmedName.isEmpty ? nil : trimmedName
        
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

#Preview("Light Mode") {
    AddEditVehicleView(
        vehicleManager: VehicleManager(),
        editingVehicle: nil,
        onVehicleCreated: nil
    )
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    AddEditVehicleView(
        vehicleManager: VehicleManager(),
        editingVehicle: nil,
        onVehicleCreated: nil
    )
    .preferredColorScheme(.dark)
}

#Preview("Editing - Light") {
    AddEditVehicleView(
        vehicleManager: VehicleManager(),
        editingVehicle: Vehicle.sample,
        onVehicleCreated: nil
    )
    .preferredColorScheme(.light)
}

#Preview("Editing - Dark") {
    AddEditVehicleView(
        vehicleManager: VehicleManager(),
        editingVehicle: Vehicle.sample,
        onVehicleCreated: nil
    )
    .preferredColorScheme(.dark)
}

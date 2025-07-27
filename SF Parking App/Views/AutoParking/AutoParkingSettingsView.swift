//
//  AutoParkingSettingsView.swift
//  SF Parking App
//
//  Auto parking detection settings with Bluetooth and CarPlay
//

import SwiftUI
import CoreBluetooth

struct AutoParkingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bluetoothManager = BluetoothCarPlayManager.shared
    @State private var showingPermissionAlert = false
    @State private var hasRequestedBluetoothPermission = false
    @State private var showingDeviceSelector = false
    @State private var selectedCarDevice: String?
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea(.all)
            
            ScrollView {
                    VStack(spacing: 0) {
                        // Fixed header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Smart Parking")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text("Use Bluetooth and CarPlay to automatically detect when you park.")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 40)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 20)
                        
                        // Fixed auto parking status card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STATUS")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                            
                            autoParkingStatusCard
                                .background(.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 24)
                        
                        // Show car and permissions sections only when enabled
                        if bluetoothManager.isAutoParkingEnabled {
                            // Fixed car selection card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("VEHICLE BLUETOOTH")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 20)
                                
                                carDeviceCard
                                    .background(.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                                    .padding(.horizontal, 20)
                            }
                            .padding(.bottom, 24)
                            
                            // Fixed permissions section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PERMISSIONS")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 20)
                                
                                permissionsSection
                                    .padding(.horizontal, 20)
                            }
                            .padding(.bottom, 120)
                        } else {
                            // Empty state when auto parking is disabled
                            VStack(spacing: 0) {
                                Spacer(minLength: 60)
                                AutoParkingEmptyStateView()
                                Spacer(minLength: 120)
                            }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .overlay(alignment: .bottom) {
                    // Fixed bottom button with gradient fade
                    VStack(spacing: 0) {
                        // Smooth gradient fade
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(.systemBackground)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 50)
                        
                        // Button area with solid background
                        VStack(spacing: 0) {
                            doneButton
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }
                        .background(Color(.systemBackground))
                    }
                }
        }
        .onAppear {
            checkBluetoothPermissions()
            loadSelectedCarDevice()
        }
        .alert("Bluetooth Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To detect when you park, please enable Bluetooth in Settings.")
        }
        .sheet(isPresented: $showingDeviceSelector) {
            DeviceSelectorView(
                selectedDevice: $selectedCarDevice,
                availableDevices: bluetoothManager.getAllAvailableDevices(),
                bluetoothManager: bluetoothManager
            )
        }
        .onChange(of: selectedCarDevice) { _, _ in
            saveSelectedCarDevice()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Parking")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Use Bluetooth and CarPlay to automatically detect when you park.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
    
    private var autoParkingStatusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(bluetoothManager.isAutoParkingEnabled ? Color.blue : Color.gray)
                    .frame(width: 40, height: 40)
                
                Image(systemName: bluetoothManager.isAutoParkingEnabled ? "car.fill" : "car")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Parking")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(bluetoothManager.isAutoParkingEnabled ? "On" : "Off")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { bluetoothManager.isAutoParkingEnabled },
                set: { enabled in
                    if enabled {
                        bluetoothManager.enableAutoParkingDetection()
                    } else {
                        bluetoothManager.disableAutoParkingDetection()
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(16)
    }
    
    
    private var carDeviceCard: some View {
        Button(action: {
            showingDeviceSelector = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCarDevice ?? "Select Bluetooth Device")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(selectedCarDevice != nil ? "Tap to change" : "Select your vehicle's bluetooth")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var permissionsSection: some View {
        VStack(spacing: 0) {
            // Bluetooth permission
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(bluetoothPermissionColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: bluetoothPermissionIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(bluetoothPermissionColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bluetooth")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(bluetoothPermissionText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isBluetoothPermissionGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                } else {
                    Button("Allow") {
                        requestBluetoothPermission()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
            .padding(16)
            
            Divider()
                .padding(.leading, 52)
            
            // Location permission
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(locationPermissionColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: locationPermissionIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(locationPermissionColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(locationPermissionText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isLocationPermissionGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                } else {
                    Button("Allow") {
                        // Handle location permission request
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
            .padding(16)
        }
        .background(.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    
    private var doneButton: some View {
        Button(action: {
            dismiss()
        }) {
            Text("Looks Good")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.blue)
                .cornerRadius(16)
        }
    }
    
    // MARK: - Computed Properties
    
    private var bluetoothPermissionIcon: String {
        switch bluetoothManager.bluetoothAuthorizationStatus {
        case .allowedAlways:
            return "bluetooth"
        case .denied, .notDetermined:
            return "bluetooth"
        default:
            return "bluetooth"
        }
    }
    
    private var bluetoothPermissionColor: Color {
        switch bluetoothManager.bluetoothAuthorizationStatus {
        case .allowedAlways:
            return .blue
        case .denied, .notDetermined:
            return .gray
        default:
            return .gray
        }
    }
    
    private var bluetoothPermissionText: String {
        return "Required to detect car disconnection"
    }
    
    private var isBluetoothPermissionGranted: Bool {
        return bluetoothManager.bluetoothAuthorizationStatus == .allowedAlways
    }
    
    private var locationPermissionIcon: String {
        return "location.fill"
    }
    
    private var locationPermissionColor: Color {
        return isLocationPermissionGranted ? .green : .gray
    }
    
    private var locationPermissionText: String {
        return "Required to save parking location"
    }
    
    private var isLocationPermissionGranted: Bool {
        // For demonstration, let's assume it can be not granted sometimes
        // You can connect this to actual CoreLocation permission status
        return true // Change this based on actual location permission
    }
    
    // MARK: - Helper Methods
    
    private func checkBluetoothPermissions() {
        // Check if we need to request Bluetooth permission
        if !hasRequestedBluetoothPermission && bluetoothManager.bluetoothAuthorizationStatus == .notDetermined {
            hasRequestedBluetoothPermission = true
        }
    }
    
    private func loadSelectedCarDevice() {
        selectedCarDevice = UserDefaults.standard.string(forKey: "selectedCarDevice")
    }
    
    private func saveSelectedCarDevice() {
        if let device = selectedCarDevice {
            UserDefaults.standard.set(device, forKey: "selectedCarDevice")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedCarDevice")
        }
    }
    
    private func requestBluetoothPermission() {
        switch bluetoothManager.bluetoothAuthorizationStatus {
        case .notDetermined:
            // Request permission through the manager
            let success = bluetoothManager.requestBluetoothPermission()
            if !success {
                showingPermissionAlert = true
            }
        case .denied:
            // If denied, send user to Settings
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        default:
            break
        }
    }
    
}

// MARK: - Empty State View

private struct AutoParkingEmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                VStack(spacing: 12) {
                    Text("Smart Parking Disabled")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("Automatically detect when you park using your car's Bluetooth and CarPlay.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
}

// MARK: - Device Selector View

struct DeviceSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDevice: String?
    let availableDevices: [String]
    let bluetoothManager: BluetoothCarPlayManager
    @State private var showingAddDevice = false
    @State private var newDeviceName = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if availableDevices.isEmpty {
                    // Empty state
                    VStack(spacing: 24) {
                        Spacer()
                        
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "bluetooth")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        VStack(spacing: 12) {
                            Text("No Devices Found")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text("Tap \"Add Device\" to manually add your car, or connect to your car's Bluetooth first")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                } else {
                    // Device list
                    List {
                        ForEach(availableDevices, id: \.self) { device in
                            Button(action: {
                                selectedDevice = device
                                dismiss()
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.1))
                                            .frame(width: 36, height: 36)
                                        
                                        Image(systemName: "car.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text(device)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if selectedDevice == device {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let deviceToRemove = availableDevices[index]
                                bluetoothManager.removePairedDevice(deviceToRemove)
                                if selectedDevice == deviceToRemove {
                                    selectedDevice = nil
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Select Your Car")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Add Device") {
                    showingAddDevice = true
                }
                .foregroundColor(.blue),
                trailing: Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.blue)
            )
            .alert("Add Car Device", isPresented: $showingAddDevice) {
                TextField("Car name (e.g., My BMW)", text: $newDeviceName)
                Button("Add") {
                    if !newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        bluetoothManager.addCustomDevice(newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines))
                        selectedDevice = newDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        newDeviceName = ""
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {
                    newDeviceName = ""
                }
            } message: {
                Text("Enter the name of your car's Bluetooth device")
            }
        }
    }
}

#Preview {
    AutoParkingSettingsView()
}

import SwiftUI

struct SmartParkingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var parkingDetector = ParkingDetector.shared
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .padding(.bottom, 24)
                
                // Smart parking toggle card
                carPlayStatusCard
                    .background(.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                
                // How it works section (always visible)
                howItWorksSection
                    .padding(.bottom, 16)
                
                // Troubleshooting note
                troubleshootingNote
                    .padding(.bottom, 20)
                
                Spacer()
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
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Park")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Automatically updates your parking location when you move your car.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var carPlayStatusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(parkingDetector.isMonitoring ? Color.blue : Color.gray)
                    .frame(width: 40, height: 40)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Park")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(parkingDetector.isMonitoring ? "Enabled" : "Disabled")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { parkingDetector.isMonitoring },
                set: { enabled in
                    if enabled {
                        parkingDetector.startMonitoring()
                    } else {
                        parkingDetector.stopMonitoring()
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(16)
    }
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW IT WORKS")
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            
            howItWorksCard
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 20)
        }
    }
    
    private var howItWorksCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "car")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vehicle Detection")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Smart Park detects when your phone connects to car audio")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            
            Divider()
            
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "speedometer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Driving Detection")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Smart Park monitors your speed to confirm when you're driving")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            
            Divider()
            
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "lock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data Privacy")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("All data stays private on your device, nothing is stored remotely")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
        }
    }
    
    private var troubleshootingNote: some View {
        Button(action: openBluetoothSettings) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Park not working correctly?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Set your car's Bluetooth device type to 'Car Stereo'")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
    
    private func openBluetoothSettings() {
        if let settingsUrl = URL(string: "App-Prefs:Bluetooth") {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    private var detectionStatusCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: statusIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(statusDescription)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
        }
    }
    
    private var statusColor: Color {
        switch parkingDetector.currentState {
        case .idle: return .gray
        case .connected: return .blue
        case .driving: return .orange
        case .parked: return .green
        }
    }
    
    private var statusIcon: String {
        switch parkingDetector.currentState {
        case .idle: return "car"
        case .connected: return "car.fill"
        case .driving: return "speedometer"
        case .parked: return "parkingsign.circle.fill"
        }
    }
    
    private var statusTitle: String {
        switch parkingDetector.currentState {
        case .idle: return "No Connection"
        case .connected: return "Car Connected"
        case .driving: return "Driving Detected"
        case .parked: return "Parking Saved"
        }
    }
    
    private var statusDescription: String {
        switch parkingDetector.currentState {
        case .idle: return "Waiting for car audio connection"
        case .connected: return "Monitoring speed and location"
        case .driving: return "Speed threshold exceeded"
        case .parked: return "Location automatically saved"
        }
    }
    
    
    private var doneButton: some View {
        Button(action: {
            dismiss()
        }) {
            Text("Done")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.blue)
                .cornerRadius(16)
        }
    }
}

#Preview {
    SmartParkingSettingsView()
}

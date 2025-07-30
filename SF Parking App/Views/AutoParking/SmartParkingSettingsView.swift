import SwiftUI

struct SmartParkingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var parkingDetector = ParkingDetector.shared
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 24)
            
            // Smart parking toggle card
            VStack(spacing: 0) {
                smartParkToggleCard
                    .padding(20)
            }
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            
            // How it works section
            VStack(alignment: .leading, spacing: 12) {
                Text("HOW IT WORKS")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                
                VStack(spacing: 0) {
                    howItWorksCard
                }
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
            
            Spacer()
        }
        .presentationBackground(.thinMaterial)
        .presentationBackgroundInteraction(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            // Fixed bottom button
            VStack(spacing: 0) {
                doneButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .background(Color.clear)
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
    
    private var smartParkToggleCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(parkingDetector.isMonitoring ? Color.blue : Color.gray)
                    .frame(width: 40, height: 40)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
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
                    impactFeedbackLight.impactOccurred()
                    if enabled {
                        parkingDetector.startMonitoring()
                    } else {
                        parkingDetector.stopMonitoring()
                    }
                }
            ))
            .labelsHidden()
            .tint(.blue)
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
            .padding(20)
            
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
            .padding(20)
            
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
            .padding(20)
            
            Divider()
            
            Button(action: {
                impactFeedbackLight.impactOccurred()
                if let url = URL(string: "App-Prefs:root=Bluetooth") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not working?")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Add car's make (ex: Toyota) to its bluetooth name")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var doneButton: some View {
        Button(action: {
            impactFeedbackLight.impactOccurred()
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
}

#Preview {
    SmartParkingSettingsView()
}

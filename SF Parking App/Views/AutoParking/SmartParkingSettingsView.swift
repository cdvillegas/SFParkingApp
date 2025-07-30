import SwiftUI
import CoreMotion

struct SmartParkingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var parkingDetector = ParkingDetector.shared
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    @State private var motionPermissionEnabled = false
    
    // For preview purposes
    var requirePermissions: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 24)
            
            // Content based on motion permission state
            if !motionPermissionEnabled {
                // Motion permission disabled - floating empty state (same as RemindersSheet)
                Spacer()
                SmartParkingEmptyStateView()
                Spacer()
                    .frame(maxHeight: 120)
            } else {
                // Motion permission enabled - show toggle and how it works
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
                
                // How it works section - only when motion permission is enabled
                VStack(alignment: .leading, spacing: 12) {
                    Text("HOW IT WORKS")
                        .font(.system(size: 11, weight: .medium))
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
        }
        .presentationBackground(.thinMaterial)
        .presentationBackgroundInteraction(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            // Fixed bottom button
            VStack(spacing: 0) {
                if !motionPermissionEnabled {
                    // User needs to enable motion permission first
                    enableMotionPermissionButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                } else {
                    // User has motion permission enabled, show the normal done button
                    doneButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .background(Color.clear)
        }
        .onAppear {
            if requirePermissions {
                checkMotionPermission()
            } else {
                // For preview - show as if permission is enabled
                motionPermissionEnabled = true
            }
            
            // Listen for app becoming active (user returning from Settings)
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                checkMotionPermission(autoEnable: true)
            }
        }
        .onDisappear {
            // Remove notification observer
            NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
            
            // Clear the flag if user manually dismisses the sheet
            UserDefaults.standard.removeObject(forKey: "smartParkingSheetWasOpen")
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
            // Always show: Vehicle Detection
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Smart Park detects when your phone connects to car audio")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            
            Divider()
            
            // Always show: Driving Detection
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Smart Park monitors your speed to confirm when you're driving")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            
            // Only show Data Privacy section when motion permission is enabled
            if motionPermissionEnabled {
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("All data stays private on your device, nothing is stored remotely")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
            }
            
            Divider()
            
            // Troubleshooting
            Button(action: {
                impactFeedbackLight.impactOccurred()
                if let url = URL(string: UIApplication.openSettingsURLString) {
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Add car's make (ex: Toyota) to its bluetooth name")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
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
    
    private var enableMotionPermissionButton: some View {
        Button(action: {
            impactFeedbackLight.impactOccurred()
            requestMotionPermission()
        }) {
            Text("Enable Motion Access")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
    
    // MARK: - Helper Methods
    private func checkMotionPermission() {
        checkMotionPermission(autoEnable: false)
    }
    
    private func checkMotionPermission(autoEnable: Bool = false) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionPermissionEnabled = false
            return
        }
        
        let status = CMMotionActivityManager.authorizationStatus()
        let wasMotionPermissionEnabled = motionPermissionEnabled
        motionPermissionEnabled = status == .authorized
        
        print("🔥 checkMotionPermission - status: \(status.rawValue), wasMotionEnabled: \(wasMotionPermissionEnabled), nowMotionEnabled: \(motionPermissionEnabled), autoEnable: \(autoEnable)")
        
        // Only auto-enable Smart Parking if explicitly requested (when returning from Settings)
        if autoEnable && !wasMotionPermissionEnabled && motionPermissionEnabled {
            print("🔥 Auto-enabling Smart Parking after permission granted")
            parkingDetector.startMonitoring()
            // Clear the flag since we successfully got permission
            UserDefaults.standard.removeObject(forKey: "smartParkingSheetWasOpen")
        }
    }
    
    private func requestMotionPermission() {
        print("🔥 requestMotionPermission called")
        
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("🔥 Motion not available")
            return
        }
        
        let currentStatus = CMMotionActivityManager.authorizationStatus()
        print("🔥 Current motion status: \(currentStatus.rawValue)")
        
        // If already denied, go straight to settings (like RemindersSheet does)
        if currentStatus == .denied || currentStatus == .restricted {
            print("🔥 Already denied - going to settings")
            // Save that we're going to settings so we can reopen the sheet
            UserDefaults.standard.set(true, forKey: "smartParkingSheetWasOpen")
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
            return
        }
        
        // If already authorized, enable immediately
        if currentStatus == .authorized {
            print("🔥 Already authorized - enabling Smart Parking")
            self.motionPermissionEnabled = true
            self.parkingDetector.startMonitoring()
            return
        }
        
        // For not determined, go directly to settings (matching RemindersSheet pattern)
        print("🔥 Not determined - going to settings")
        // Save that we're going to settings so we can reopen the sheet
        UserDefaults.standard.set(true, forKey: "smartParkingSheetWasOpen")
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

// MARK: - Smart Parking Empty State
private struct SmartParkingEmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                VStack(spacing: 12) {
                    Text("Motion Access Required")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("Enable motion access to automatically detect when you've parked and update your parking location.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
}

#Preview {
    SmartParkingSettingsView(requirePermissions: false)
}

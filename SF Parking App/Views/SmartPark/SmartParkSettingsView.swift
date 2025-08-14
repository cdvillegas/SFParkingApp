import SwiftUI

struct SmartParkSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    @State private var showingSetupFlow = false
    @State private var smartParkIsEnabled = false
    @State private var requiresLocationConfirmation = true
    @State private var showingLocationInfo = false
    
    // For preview purposes
    var requirePermissions: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 24)
            
            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // Smart Park status card (now scrollable)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("STATUS")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 0) {
                            smartParkStatusCard
                                .padding(20)
                        }
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)
                    // Location Update Mode section (only show if Smart Park is configured)
                    if hasSmartParkConfigured {
                        VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("LOCATION UPDATE MODE")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Button {
                                impactFeedbackLight.impactOccurred()
                                showingLocationInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .popover(isPresented: $showingLocationInfo) {
                                HStack(spacing: 12) {
                                    Image(systemName: "location.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.blue)
                                        .frame(width: 28, height: 28)
                                    
                                    Text("Location detection isn't always accurate. Enable confirmation for best results.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(16)
                                .frame(maxWidth: 280)
                                .background(Color(UIColor.secondarySystemBackground))
                                .presentationCompactAdaptation(.popover)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(spacing: 0) {
                            locationUpdateModeCard
                        }
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)
                    }
                    
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
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
            .mask(
                VStack(spacing: 0) {
                    // Middle is fully visible (no top fade)
                    Color.black
                    
                    // Bottom fade - from opaque to transparent
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black, Color.clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                }
            )
            .padding(.bottom, 96)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            // Fixed bottom button
            VStack(spacing: 0) {
                if !hasSmartParkConfigured {
                    // User hasn't set up Smart Park yet
                    getStartedButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                } else {
                    // User has Smart Park configured, show the normal done button
                    doneButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .background(Color.clear)
        }
        .sheet(isPresented: $showingSetupFlow) {
            SmartParkSetupView()
        }
        .onChange(of: showingSetupFlow) { _, isShowing in
            if !isShowing {
                // Check if setup was completed while we were away
                let wasCompletedBefore = UserDefaults.standard.bool(forKey: "smartParkSetupCompleted")
                // Reload state when returning from setup
                loadSmartParkState()
                // If setup was just completed, log it
                let isCompletedNow = UserDefaults.standard.bool(forKey: "smartParkSetupCompleted")
                if !wasCompletedBefore && isCompletedNow {
                    AnalyticsManager.shared.logSmartParkSetupCompleted()
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationBackgroundInteraction(.enabled)
        .onAppear {
            // Initialize toggle state
            loadSmartParkState()
            // Track Smart Park tab access
            AnalyticsManager.shared.logSmartParkTabClicked()
        }
        .onDisappear {
            // Smart Park cleanup if needed
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Smart Park")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Show setup button only after initial setup is complete
                if hasSmartParkConfigured {
                    Button {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        AnalyticsManager.shared.logSmartParkSetupStarted()
                        showingSetupFlow = true
                    } label: {
                        Text("Setup")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(20)
                            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                }
            }
            
            Text("Automatically update your parking location when you move your car.")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var smartParkStatusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(smartParkStatusColor)
                    .frame(width: 40, height: 40)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Park")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(smartParkStatusText)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Show toggle only if Smart Park has been set up at least once
            if hasSmartParkConfigured {
                Toggle("", isOn: $smartParkIsEnabled)
                    .labelsHidden()
                    .tint(.blue)
                    .onChange(of: smartParkIsEnabled) { _, newValue in
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        if newValue {
                            AnalyticsManager.shared.logSmartParkEnabled()
                        } else {
                            AnalyticsManager.shared.logSmartParkDisabled()
                        }
                        UserDefaults.standard.set(newValue, forKey: "smartParkEnabled")
                    }
            }
        }
    }
    
    private var locationUpdateModeCard: some View {
        VStack(spacing: 16) {
            // Option 1: Update automatically
            Button(action: {
                impactFeedbackLight.impactOccurred()
                if requiresLocationConfirmation {
                    AnalyticsManager.shared.logSmartParkModeChanged(mode: "automatic")
                }
                requiresLocationConfirmation = false
                UserDefaults.standard.set(false, forKey: "smartParkRequiresConfirmation")
            }) {
                HStack(spacing: 16) {
                    Image(systemName: requiresLocationConfirmation ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(requiresLocationConfirmation ? .secondary : .blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Update Automatically")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Smart Park saves your location immediately")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(!requiresLocationConfirmation ? Color.blue.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Option 2: Require confirmation
            Button(action: {
                impactFeedbackLight.impactOccurred()
                if !requiresLocationConfirmation {
                    AnalyticsManager.shared.logSmartParkModeChanged(mode: "confirmation")
                }
                requiresLocationConfirmation = true
                UserDefaults.standard.set(true, forKey: "smartParkRequiresConfirmation")
            }) {
                HStack(spacing: 16) {
                    Image(systemName: requiresLocationConfirmation ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(requiresLocationConfirmation ? .blue : .secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Require Confirmation")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Review and confirm location before saving")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(requiresLocationConfirmation ? Color.blue.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
        }
        .padding(4)
    }
    
    private var howItWorksCard: some View {
        VStack(spacing: 0) {
            // Step 1
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detect Parking Updates")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Smart Park detects when your vehicle's Bluetooth or CarPlay disconnects.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            
            Divider()
            
            // Step 2
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Location")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Smart Park automatically updates your parking location and street cleaning reminders.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            
            Divider()
            
            // Step 3
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("100% Private")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Everything stays on your iPhone. No servers. No tracking.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
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
    
    
    private var getStartedButton: some View {
        Button(action: {
            impactFeedbackLight.impactOccurred()
            AnalyticsManager.shared.logSmartParkSetupStarted()
            showingSetupFlow = true
        }) {
            Text("Get Started")
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
    
    // MARK: - Computed Properties
    
    private var hasSmartParkConfigured: Bool {
        // Check if user has completed setup flow at least once
        // Since we can't reliably detect if shortcuts/automations still exist,
        // we'll assume they're configured if they've done setup before
        let completed = UserDefaults.standard.bool(forKey: "smartParkSetupCompleted")
        print("🔥 hasSmartParkConfigured: \(completed)")
        return completed
    }
    
    private var smartParkEnabled: Bool {
        // Default to true if setup is completed and no explicit disabled state
        guard hasSmartParkConfigured else { return false }
        // If the key has never been set, default to true (enabled)
        if UserDefaults.standard.object(forKey: "smartParkEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "smartParkEnabled")
    }
    
    private var smartParkStatusText: String {
        let status: String
        if !hasSmartParkConfigured {
            status = "Needs Setup"
        } else if !smartParkIsEnabled {
            status = "Disabled"
        } else {
            status = "Enabled"
        }
        print("🔥 smartParkStatusText: \(status)")
        return status
    }
    
    private var smartParkStatusColor: Color {
        if !hasSmartParkConfigured {
            return .gray
        } else if !smartParkIsEnabled {
            return .gray
        } else {
            return .blue
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadSmartParkState() {
        smartParkIsEnabled = smartParkEnabled
        
        // Load confirmation preference (default to true for safety)
        if UserDefaults.standard.object(forKey: "smartParkRequiresConfirmation") == nil {
            // First time - set default to true (require confirmation)
            UserDefaults.standard.set(true, forKey: "smartParkRequiresConfirmation")
            requiresLocationConfirmation = true
        } else {
            requiresLocationConfirmation = UserDefaults.standard.bool(forKey: "smartParkRequiresConfirmation")
        }
    }
    
    private func timeAgoText(for date: Date) -> String {
        let timeInterval = Date().timeIntervalSince(date)
        let days = Int(timeInterval / 86400)
        let hours = Int(timeInterval / 3600)
        let minutes = Int(timeInterval / 60)
        
        if days > 365 {
            let years = days / 365
            return "\(years) year\(years == 1 ? "" : "s") ago"
        } else if days > 30 {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else if days > 7 {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if minutes > 5 {
            return "\(minutes) minutes ago"
        } else {
            return "just now"
        }
    }
}


#Preview {
    SmartParkSettingsView(requirePermissions: false)
}

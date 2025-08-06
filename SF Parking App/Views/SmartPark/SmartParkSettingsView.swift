import SwiftUI

struct SmartParkSettingsView: View {
    @StateObject private var manager = SmartParkManager.shared
    @State private var showingSetup = false
    
    var body: some View {
        List {
            // Status Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Smart Park 2.0")
                            .font(.headline)
                        
                        Text(manager.configurationStatus)
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $manager.isEnabled)
                        .disabled(!manager.isSetupComplete)
                        .onChange(of: manager.isEnabled) { oldValue, newValue in
                            manager.saveConfiguration()
                        }
                }
                
                if !manager.isSetupComplete {
                    Button("Setup Smart Park 2.0") {
                        showingSetup = true
                    }
                    .foregroundColor(.blue)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Automatically saves your parking location when you disconnect from your car.")
            }
            
            // Configuration Section (only show if setup is complete)
            if manager.isSetupComplete {
                Section("Configuration") {
                    ConfigurationRow(
                        icon: manager.triggerType == .carPlay ? "carplay" : "bluetooth",
                        title: "Connection Type",
                        value: manager.triggerType.rawValue,
                        systemImage: true
                    )
                    
                    
                    ConfigurationRow(
                        icon: "clock",
                        title: "Confirmation Delay",
                        value: "2 minutes (always enabled)",
                        systemImage: true
                    )
                    
                    Button("Reconfigure") {
                        showingSetup = true
                    }
                    .foregroundColor(.blue)
                }
            }
            
            // How It Works Section
            Section("How It Works") {
                VStack(alignment: .leading, spacing: 16) {
                    StepView(
                        number: 1,
                        title: "Car Disconnection",
                        description: "Smart Park detects when you disconnect from \(manager.triggerType.rawValue.lowercased())"
                    )
                    
                    StepView(
                        number: 2,
                        title: "2-Minute Safety Wait",
                        description: "Waits 2 minutes to avoid false detections if you reconnect to your car"
                    )
                    
                    StepView(
                        number: 3,
                        title: "Location Saved",
                        description: "Your parking spot is saved and you receive a notification"
                    )
                }
                .padding(.vertical, 8)
            }
            
            // Automation Setup Section
            if manager.isSetupComplete {
                Section("Automation") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "shortcuts")
                                .foregroundColor(.blue)
                            
                            Text("iOS Shortcuts Automation")
                                .font(.headline)
                        }
                        
                        Text("Create an automation in the Shortcuts app to trigger Smart Park 2.0 automatically when you disconnect from your car.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Button("View Setup Instructions") {
                            showingSetup = true
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // Recent Activity Section (if there's activity to show)
            Section("Recent Activity") {
                if manager.isEnabled {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        
                        Text("No recent Smart Park activity")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                } else {
                    HStack {
                        Image(systemName: "pause.circle")
                            .foregroundColor(.orange)
                        
                        Text("Smart Park is disabled")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Smart Park 2.0")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingSetup) {
            SmartParkSetupView()
        }
        .onAppear {
            manager.loadConfiguration()
        }
    }
    
    private var statusColor: Color {
        switch manager.configurationStatus {
        case "Active":
            return .green
        case "Disabled":
            return .orange
        case "Not configured", "Invalid configuration":
            return .red
        default:
            return .secondary
        }
    }
}

// MARK: - Supporting Views

struct ConfigurationRow: View {
    let icon: String
    let title: String
    let value: String
    let systemImage: Bool
    
    var body: some View {
        HStack {
            if systemImage {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 24)
            } else {
                Text(icon)
                    .frame(width: 24)
            }
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

struct StepView: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

#Preview {
    NavigationView {
        SmartParkSettingsView()
    }
}
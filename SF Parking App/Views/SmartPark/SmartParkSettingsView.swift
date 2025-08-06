import SwiftUI

struct SmartParkSettingsView: View {
    @StateObject private var manager = SmartParkManager.shared
    @State private var showingSetup = false
    
    var body: some View {
        List {
            // Enable/Disable Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Smart Park")
                            .font(.headline)
                        
                        Text(statusText)
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
            } footer: {
                Text("Automatically saves your parking location when you disconnect from your car.")
            }
            
            // How It Works Section
            Section("How It Works") {
                VStack(alignment: .leading, spacing: 16) {
                    StepView(
                        number: 1,
                        title: "Car Disconnection",
                        description: "Detects when you disconnect from CarPlay or Bluetooth"
                    )
                    
                    StepView(
                        number: 2,
                        title: "Safety Wait",
                        description: "Waits 2 minutes to avoid false detections"
                    )
                    
                    StepView(
                        number: 3,
                        title: "Location Saved",
                        description: "Saves your parking spot and sends a notification"
                    )
                }
                .padding(.vertical, 8)
            }
            
            // Setup Section
            Section {
                if manager.isSetupComplete {
                    Button("Setup Instructions") {
                        showingSetup = true
                    }
                    .foregroundColor(.blue)
                } else {
                    Button("Set Up Smart Park") {
                        showingSetup = true
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            
        }
        .navigationTitle("Smart Park")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingSetup) {
            SmartParkSetupView()
        }
        .onAppear {
            manager.loadConfiguration()
        }
    }
    
    private var statusText: String {
        if !manager.isSetupComplete {
            return "Not Set Up"
        } else if manager.isEnabled {
            return "Active"
        } else {
            return "Disabled"
        }
    }
    
    private var statusColor: Color {
        if !manager.isSetupComplete {
            return .blue
        } else if manager.isEnabled {
            return .green
        } else {
            return .orange
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
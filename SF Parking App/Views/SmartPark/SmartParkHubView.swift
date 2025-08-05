import SwiftUI

struct SmartParkHubView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var smartParkManager = SmartParkManager.shared
    @State private var showingSmartPark1Settings = false
    @State private var showingSmartPark2Settings = false
    
    var body: some View {
        NavigationView {
            List {
                // Header Section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Smart Parking")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text("Automatic parking detection")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        Text("Choose how you want your parking location to be detected automatically.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                // Smart Park 2.0 (Recommended)
                Section {
                    SmartParkOptionCard(
                        title: "Smart Park 2.0",
                        subtitle: "Recommended",
                        description: "Uses CarPlay or Bluetooth disconnection to detect when you park. More reliable and works with iOS Shortcuts automation.",
                        icon: "car.fill",
                        status: smartPark2Status,
                        statusColor: smartPark2StatusColor,
                        isRecommended: true,
                        onTap: {
                            if smartParkManager.isSetupComplete {
                                showingSmartPark2Settings = true
                            } else {
                                smartParkManager.startSetup()
                            }
                        }
                    )
                } header: {
                    Text("Latest Version")
                } footer: {
                    Text("Smart Park 2.0 is our newest parking detection system with better accuracy and reliability.")
                }
                
                // Smart Park 1.0 (Legacy)
                Section {
                    SmartParkOptionCard(
                        title: "Smart Park 1.0",
                        subtitle: "Legacy version",
                        description: "Uses motion sensors and location changes to detect parking. May have false detections in stop-and-go traffic.",
                        icon: "location.fill",
                        status: "Available",
                        statusColor: .secondary,
                        isRecommended: false,
                        onTap: {
                            showingSmartPark1Settings = true
                        }
                    )
                } header: {
                    Text("Previous Version")
                } footer: {
                    Text("Smart Park 1.0 is the original parking detection system. We recommend upgrading to 2.0 for better performance.")
                }
                
                // Migration Section (if applicable)
                if smartParkManager.isSetupComplete {
                    Section("Settings") {
                        NavigationLink(destination: SmartParkSettingsView()) {
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundColor(.blue)
                                
                                Text("Smart Park 2.0 Settings")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Smart Parking")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $smartParkManager.showSetup) {
            SmartParkSetupView()
        }
        .sheet(isPresented: $showingSmartPark1Settings) {
            SmartParkingSettingsView()
        }
        .sheet(isPresented: $showingSmartPark2Settings) {
            SmartParkSettingsView()
        }
        .onAppear {
            smartParkManager.loadConfiguration()
        }
    }
    
    private var smartPark2Status: String {
        smartParkManager.configurationStatus
    }
    
    private var smartPark2StatusColor: Color {
        switch smartParkManager.configurationStatus {
        case "Active":
            return .green
        case "Disabled":
            return .orange
        case "Not configured":
            return .blue
        default:
            return .red
        }
    }
}

// MARK: - Smart Park Option Card

struct SmartParkOptionCard: View {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let status: String
    let statusColor: Color
    let isRecommended: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if isRecommended {
                                Text("RECOMMENDED")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(status)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Description
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SmartParkHubView()
}
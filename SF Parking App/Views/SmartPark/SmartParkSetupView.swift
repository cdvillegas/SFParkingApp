import SwiftUI

struct SmartParkSetupView: View {
    @StateObject private var manager = SmartParkManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: Double(currentStepIndex), total: Double(totalSteps - 1))
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()
                
                // Current step content
                ScrollView {
                    VStack(spacing: 24) {
                        stepContent
                    }
                    .padding()
                }
                
                Spacer()
                
                // Navigation buttons
                navigationButtons
                    .padding()
            }
            .navigationTitle(manager.setupStep.title)
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        manager.cancelSetup()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch manager.setupStep {
        case .welcome:
            welcomeStep
        case .connectionType:
            connectionTypeStep
        case .bluetoothConfig:
            bluetoothConfigStep
        case .confirmationDelay:
            confirmationDelayStep
        case .permissions:
            permissionsStep
        case .automation:
            automationStep
        case .complete:
            completeStep
        }
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "location.fill", title: "Automatic Detection", description: "Saves your parking spot when you disconnect")
                FeatureRow(icon: "bell.fill", title: "Smart Confirmation", description: "2-minute delay to avoid false detections")
                FeatureRow(icon: "map.fill", title: "Precise Location", description: "Uses GPS for accurate parking spots")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var connectionTypeStep: some View {
        VStack(spacing: 24) {
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                ConnectionTypeCard(
                    type: .carPlay,
                    isSelected: manager.triggerType == .carPlay,
                    onSelect: { manager.triggerType = .carPlay }
                )
                
                ConnectionTypeCard(
                    type: .bluetooth,
                    isSelected: manager.triggerType == .bluetooth,
                    onSelect: { manager.triggerType = .bluetooth }
                )
            }
        }
    }
    
    private var bluetoothConfigStep: some View {
        VStack(spacing: 24) {
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Bluetooth Device Name")
                    .font(.headline)
                
                TextField("e.g., BMW, Toyota, My Car", text: $manager.bluetoothDeviceName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 How to find your device name:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("1. Go to Settings → Bluetooth\n2. Look for your car in the list\n3. The name shown is what you should enter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBlue).opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    private var confirmationDelayStep: some View {
        VStack(spacing: 24) {
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                DelayOptionCard(
                    title: "Enable 2-Minute Delay",
                    subtitle: "Recommended for most users",
                    description: "Smart Park waits 2 minutes before confirming your parking spot. If you reconnect to your car within that time, it cancels the detection.",
                    isSelected: manager.delayConfirmation,
                    onSelect: { manager.delayConfirmation = true }
                )
                
                DelayOptionCard(
                    title: "Immediate Confirmation",
                    subtitle: "For advanced users",
                    description: "Smart Park immediately saves your parking spot when you disconnect. This may cause false detections if you briefly disconnect.",
                    isSelected: !manager.delayConfirmation,
                    onSelect: { manager.delayConfirmation = false }
                )
            }
        }
    }
    
    private var permissionsStep: some View {
        VStack(spacing: 24) {
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "location.fill",
                    title: "Location Access",
                    description: "Required to save your parking location",
                    status: .granted // TODO: Check actual permission status
                )
                
                PermissionCard(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Alerts you when parking is detected",
                    status: .granted // TODO: Check actual permission status
                )
            }
        }
    }
    
    private var automationStep: some View {
        VStack(spacing: 24) {
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Follow these steps to create the automation:")
                    .font(.headline)
                
                ForEach(Array(manager.createAutomationInstructions().enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.blue)
                            .clipShape(Circle())
                        
                        Text(instruction)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Button("Open Shortcuts App") {
                if let url = URL(string: "shortcuts://create-automation") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var completeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text("Smart Park 2.0 is now configured with:")
                    .font(.headline)
                
                ConfigSummaryRow(label: "Trigger", value: manager.triggerType.rawValue)
                
                if manager.triggerType == .bluetooth {
                    ConfigSummaryRow(label: "Device", value: manager.bluetoothDeviceName)
                }
                
                ConfigSummaryRow(
                    label: "Confirmation",
                    value: manager.delayConfirmation ? "2-minute delay" : "Immediate"
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Navigation
    
    private var navigationButtons: some View {
        HStack {
            if currentStepIndex > 0 {
                Button("Back") {
                    previousStep()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            Button(isLastStep ? "Complete Setup" : "Continue") {
                if isLastStep {
                    manager.completeSetup()
                    dismiss()
                } else {
                    nextStep()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceed)
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentStepIndex: Int {
        let allSteps = SetupStep.allCases
        return allSteps.firstIndex(of: manager.setupStep) ?? 0
    }
    
    private var totalSteps: Int {
        SetupStep.allCases.count
    }
    
    private var isLastStep: Bool {
        manager.setupStep == .complete
    }
    
    private var canProceed: Bool {
        switch manager.setupStep {
        case .welcome, .connectionType, .confirmationDelay, .permissions, .automation, .complete:
            return true
        case .bluetoothConfig:
            return manager.triggerType != .bluetooth || !manager.bluetoothDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    // MARK: - Navigation Methods
    
    private func nextStep() {
        let allSteps = SetupStep.allCases
        let currentIndex = currentStepIndex
        
        if currentIndex < allSteps.count - 1 {
            var nextIndex = currentIndex + 1
            
            // Skip Bluetooth config if CarPlay is selected
            if allSteps[nextIndex] == .bluetoothConfig && manager.triggerType == .carPlay {
                nextIndex += 1
            }
            
            if nextIndex < allSteps.count {
                manager.setupStep = allSteps[nextIndex]
            }
        }
    }
    
    private func previousStep() {
        let allSteps = SetupStep.allCases
        let currentIndex = currentStepIndex
        
        if currentIndex > 0 {
            var previousIndex = currentIndex - 1
            
            // Skip Bluetooth config if CarPlay is selected
            if allSteps[previousIndex] == .bluetoothConfig && manager.triggerType == .carPlay {
                previousIndex -= 1
            }
            
            if previousIndex >= 0 {
                manager.setupStep = allSteps[previousIndex]
            }
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct ConnectionTypeCard: View {
    let type: SmartParkTriggerType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: type == .carPlay ? "carplay" : "bluetooth")
                            .font(.title2)
                        
                        Text(type.rawValue)
                            .font(.headline)
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text(type == .carPlay ? 
                         "Uses Apple CarPlay connection detection" : 
                         "Uses specific Bluetooth device detection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct DelayOptionCard: View {
    let title: String
    let subtitle: String
    let description: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(status == .granted ? .green : .orange)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ConfigSummaryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

enum PermissionStatus {
    case granted
    case denied
    case notRequested
}

#Preview {
    SmartParkSetupView()
}
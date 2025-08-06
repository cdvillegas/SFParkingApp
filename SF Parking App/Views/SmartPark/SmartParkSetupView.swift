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
        case .permissions:
            permissionsStep
        case .shortcut:
            shortcutStep
        case .automation:
            automationStep
        case .complete:
            completeStep
        }
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Welcome to Smart Park")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            // How It Works section
            VStack(alignment: .leading, spacing: 16) {
                Text("How It Works")
                    .font(.headline)
                
                HowItWorksRow(
                    number: 1,
                    title: "Uses iOS Shortcuts",
                    description: "Built with iOS Shortcuts for automation"
                )
                
                HowItWorksRow(
                    number: 2,
                    title: "Car Disconnection", 
                    description: "Detects when you disconnect from CarPlay or Bluetooth"
                )
                
                HowItWorksRow(
                    number: 3,
                    title: "Safety Wait",
                    description: "Waits 2 minutes to avoid false detections"
                )
                
                HowItWorksRow(
                    number: 4,
                    title: "Location Saved",
                    description: "Saves your parking spot and updates sweep reminders"
                )
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
    
    private var shortcutStep: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Follow these steps:")
                    .font(.headline)
                
                ForEach(Array(manager.createShortcutInstructions().enumerated()), id: \.offset) { index, instruction in
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
                if let url = URL(string: "shortcuts://") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var automationStep: some View {
        VStack(spacing: 24) {
            // Special note for Bluetooth users
            if manager.triggerType == .bluetooth {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("Important: Select YOUR CAR'S Bluetooth from the device list")
                        .font(.footnote)
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Now create the automation:")
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
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("All Set!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(manager.setupStep.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            // Show configured connections
            if !manager.configuredConnections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configured Connections:")
                        .font(.headline)
                    
                    ForEach(Array(manager.configuredConnections), id: \.self) { connection in
                        HStack {
                            Image(systemName: connection == .carPlay ? "carplay" : "bluetooth")
                                .foregroundColor(.blue)
                            Text(connection.rawValue)
                                .font(.body)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal)
                    }
                    
                    Button("Set Up Another Connection") {
                        // Go back to connection type selection
                        manager.setupStep = .connectionType
                    }
                    .foregroundColor(.blue)
                    .padding(.top, 8)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Navigation
    
    @ViewBuilder
    private var navigationButtons: some View {
        if manager.setupStep == .welcome {
            // Special layout for welcome screen - centered setup button
            VStack(spacing: 16) {
                Button("Set Up Smart Park") {
                    nextStep()
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
        } else {
            // All screens - consistent back and main action button with fixed positioning
            HStack(spacing: 12) {
                // Always reserve space for back button to maintain consistent positioning
                if currentStepIndex > 0 {
                    Button("Back") {
                        previousStep()
                    }
                    .buttonStyle(.bordered)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                } else {
                    // Invisible spacer to maintain positioning when no back button
                    Spacer()
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                }
                
                Button(isLastStep ? "Complete Setup" : "Continue") {
                    if isLastStep {
                        manager.completeSetup()
                        dismiss()
                    } else {
                        nextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .disabled(!canProceed)
            }
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
        // All steps can proceed without additional validation
        return true
    }
    
    // MARK: - Navigation Methods
    
    private func nextStep() {
        let allSteps = SetupStep.allCases
        let currentIndex = currentStepIndex
        
        if currentIndex < allSteps.count - 1 {
            let nextIndex = currentIndex + 1
            
            // If we just finished automation, mark this connection type as configured
            if manager.setupStep == .automation {
                manager.configuredConnections.insert(manager.triggerType)
            }
            
            manager.setupStep = allSteps[nextIndex]
        }
    }
    
    private func previousStep() {
        let allSteps = SetupStep.allCases
        let currentIndex = currentStepIndex
        
        if currentIndex > 0 {
            let previousIndex = currentIndex - 1
            manager.setupStep = allSteps[previousIndex]
        }
    }
}

// MARK: - Supporting Views

struct HowItWorksRow: View {
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
                HStack {
                    Image(systemName: type == .carPlay ? "carplay" : "bluetooth")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    Text(type.rawValue)
                        .font(.headline)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
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
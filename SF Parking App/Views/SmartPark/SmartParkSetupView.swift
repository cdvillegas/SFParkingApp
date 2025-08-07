import SwiftUI

struct SmartParkSetupView: View {
    @StateObject private var manager = SmartParkManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed header - matching SmartParkSettingsView style
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 24)
            
            // Scrollable content
            ScrollView {
                VStack(spacing: 32) {
                    stepContent
                }
                .padding(.horizontal, 20)
            }
            .mask(
                VStack(spacing: 0) {
                    // Top fade
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.black]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                    
                    Color.black
                    
                    // Bottom fade
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black, Color.clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                }
            )
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            // Fixed bottom navigation - only show for connection type step
            if manager.setupStep == .connectionType {
                navigationButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationBackgroundInteraction(.enabled)
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch manager.setupStep {
        case .connectionType:
            connectionTypeStep
        case .instructions:
            instructionsStep
        }
    }
    
    private var connectionTypeStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Text("Choose how Smart Park should detect when you've parked")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                ConnectionTypeCard(
                    type: .carPlay,
                    isSelected: manager.triggerType == .carPlay,
                    onSelect: { 
                        impactFeedbackLight.impactOccurred()
                        print("🔥 Selected CarPlay, setting triggerType")
                        manager.triggerType = .carPlay 
                    }
                )
                
                ConnectionTypeCard(
                    type: .bluetooth,
                    isSelected: manager.triggerType == .bluetooth,
                    onSelect: { 
                        impactFeedbackLight.impactOccurred()
                        print("🔥 Selected Bluetooth, setting triggerType")
                        manager.triggerType = .bluetooth 
                    }
                )
            }
        }
    }
    
    private var instructionsStep: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Helper button to open Shortcuts app
                VStack(spacing: 12) {
                    Text("Ready to set up Smart Park? Let's start by opening the Shortcuts app.")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        impactFeedbackLight.impactOccurred()
                        if let url = URL(string: "shortcuts://") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Open Shortcuts App")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.blue)
                            .cornerRadius(16)
                    }
                }
                
                // Setup instructions
                VStack(alignment: .leading, spacing: 32) {
                    let instructions = getSetupInstructions()
                    
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .center, spacing: 16) {
                            // Step number - centered
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 32, height: 32)
                                
                                Text("\(index + 1)")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            // Instruction text - aligned to left of number
                            VStack(alignment: .leading, spacing: 8) {
                                Text(instruction.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                if let subtitle = instruction.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(24)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                // Done button at bottom
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    // Mark setup as completed
                    manager.completeSetup()
                    UserDefaults.standard.set(true, forKey: "smartParkSetupCompleted")
                    UserDefaults.standard.set(true, forKey: "smartParkEnabled")
                    manager.configuredConnections.insert(manager.triggerType)
                    
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
                
                Spacer(minLength: 10)
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
    }
    
    private func getSetupInstructions() -> [(title: String, subtitle: String?)] {
        let connectionType = manager.triggerType.rawValue
        
        if manager.triggerType == .carPlay {
            return [
                ("Navigate to 'Automations'", "Tap the 'Automation' tab at the bottom of the Shortcuts app"),
                ("Create New Automation", "Tap 'New Automation' then select 'CarPlay'"),
                ("Configure Trigger", "Make sure only 'Is Disconnected' is selected and 'Run Immediately' is checked"),
                ("Add Smart Park Action", "Tap 'New Blank Automation' and search for 'Smart Park'"),
                ("Finalize Settings", "Deselect 'Show When Run' then tap 'Done'")
            ]
        } else {
            return [
                ("Navigate to 'Automations'", "Tap the 'Automation' tab at the bottom of the Shortcuts app"),
                ("Create New Automation", "Tap 'New Automation' then select 'Bluetooth'"),
                ("Select Your Car", "Choose your vehicle's Bluetooth from the device list"),
                ("Configure Trigger", "Make sure only 'Is Disconnected' is selected and 'Run Immediately' is checked"),
                ("Add Smart Park Action", "Tap 'New Blank Automation' and search for 'Smart Park'"),
                ("Finalize Settings", "Deselect 'Show When Run' then tap 'Done'")
            ]
        }
    }
    
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stepTitle)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    manager.cancelSetup()
                    dismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                }
            }
        }
    }
    
    // MARK: - Navigation
    
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                impactFeedbackLight.impactOccurred()
                if currentStepIndex > 0 {
                    previousStep()
                } else {
                    // If on first step, dismiss
                    manager.cancelSetup()
                    dismiss()
                }
            }) {
                Text("Back")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(.systemGray5))
                    .cornerRadius(16)
            }
            
            Button(action: {
                print("🔥 Continue button pressed! Current step: \(manager.setupStep)")
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                print("🔥 Calling nextStep()...")
                nextStep()
                print("🔥 After nextStep(), new step: \(manager.setupStep)")
            }) {
                Text("Continue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(canProceed ? Color.blue : Color.secondary)
                    .cornerRadius(16)
            }
            // .disabled(!canProceed) // Temporarily disabled for debugging
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentStepIndex: Int {
        return SetupStep.allCases.firstIndex(of: manager.setupStep) ?? 0
    }
    
    private var isLastStep: Bool {
        manager.setupStep == .instructions
    }
    
    private var canProceed: Bool {
        // Always allow proceeding - user can change connection type if needed
        return true
    }
    
    private var stepTitle: String {
        return "Smart Park Setup"
    }
    
    // MARK: - Navigation Methods
    
    private func nextStep() {
        print("🔥 nextStep() called from step: \(manager.setupStep)")
        
        // From connectionType, go to instructions
        if manager.setupStep == .connectionType {
            print("🔥 Moving from connectionType to instructions")
            manager.setupStep = .instructions
            return
        }
        
        print("🔥 No valid next step found for: \(manager.setupStep)")
    }
    
    private func previousStep() {
        let allSteps = SetupStep.allCases
        let currentIndex = allSteps.firstIndex(of: manager.setupStep) ?? 0
        
        if currentIndex > 0 {
            let previousIndex = currentIndex - 1
            manager.setupStep = allSteps[previousIndex]
        }
    }
}

// MARK: - Supporting Views

struct ConnectionTypeCard: View {
    let type: SmartParkTriggerType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(type == .carPlay ? "Carplay" : "Bluetooth")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 0.5)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(status == .granted ? .green : .orange)
        }
        .padding(20)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
    }
    
    private var statusColor: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .red
        case .notRequested:
            return .blue
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

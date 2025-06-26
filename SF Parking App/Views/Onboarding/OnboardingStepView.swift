import SwiftUI
import CoreLocation
import CoreMotion
import CoreBluetooth
import UserNotifications

struct OnboardingStepView: View {
    let step: OnboardingStep
    let isLastStep: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    
    @State private var isAnimating = false
    @State private var showingPermissionDeniedAlert = false
    @State private var permissionDeniedMessage = ""
    @State private var locationDelegate: LocationPermissionDelegate?
    @State private var bluetoothDelegate: BluetoothPermissionDelegate?
    @State private var locationManager: CLLocationManager?
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Hero Image/Icon Section
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: step.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .animation(.easeInOut(duration: 0.8).delay(0.2), value: isAnimating)
                    
                    Image(systemName: step.systemImage)
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(.white)
                        .scaleEffect(isAnimating ? 1.0 : 0.6)
                        .animation(.easeInOut(duration: 0.8).delay(0.4), value: isAnimating)
                        .id(step.systemImage) // Ensure stable identity
                }
                
                VStack(spacing: 16) {
                    Text(step.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(.easeInOut(duration: 0.6).delay(0.6), value: isAnimating)
                    
                    Text(step.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(.easeInOut(duration: 0.6).delay(0.8), value: isAnimating)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Button Section
            VStack(spacing: 12) {
                Button(action: handleMainAction) {
                    HStack {
                        Text(step.buttonText)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if step.permissionType != nil {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: step.gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: step.gradientColors.first?.opacity(0.3) ?? Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
                }
                .scaleEffect(isAnimating ? 1.0 : 0.9)
                .opacity(isAnimating ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(1.0), value: isAnimating)
                
                if !isLastStep && step.permissionType != nil {
                    Button("Skip for now") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            onNext()
                        }
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.6).delay(1.2), value: isAnimating)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .onAppear {
            // Reset animation state first
            isAnimating = false
            // Then trigger animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    isAnimating = true
                }
            }
        }
        .alert("Permission Required", isPresented: $showingPermissionDeniedAlert) {
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Skip", role: .cancel) {
                onNext()
            }
        } message: {
            Text(permissionDeniedMessage)
        }
    }
    
    private func handleMainAction() {
        // Haptic feedback for button press
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        guard let permissionType = step.permissionType else {
            withAnimation(.easeInOut(duration: 0.3)) {
                onNext()
            }
            return
        }
        
        requestPermission(for: permissionType)
    }
    
    private func requestPermission(for type: OnboardingStep.PermissionType) {
        switch type {
        case .location:
            requestLocationPermission()
        case .motion:
            requestMotionPermission()
        case .bluetooth:
            requestBluetoothPermission()
        case .notifications:
            requestNotificationPermission()
        }
    }
    
    private func requestLocationPermission() {
        locationManager = CLLocationManager()
        let authorizationStatus = locationManager!.authorizationStatus
        
        switch authorizationStatus {
        case .notDetermined:
            // Create a delegate to listen for authorization changes
            locationDelegate = LocationPermissionDelegate { [self] authorized in
                DispatchQueue.main.async {
                    if authorized {
                        let successFeedback = UINotificationFeedbackGenerator()
                        successFeedback.notificationOccurred(.success)
                        self.onNext()
                    } else {
                        self.showPermissionDeniedAlert(message: "Location access is required to show your parking location and provide accurate street cleaning information. Please enable it in Settings.")
                    }
                }
            }
            
            locationManager!.delegate = locationDelegate
            locationManager!.requestWhenInUseAuthorization()
            
        case .denied, .restricted:
            showPermissionDeniedAlert(message: "Location access is required to show your parking location and provide accurate street cleaning information. Please enable it in Settings.")
        default:
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
            onNext()
        }
    }
    
    private func requestMotionPermission() {
        let motionManager = CMMotionActivityManager()
        
        if CMMotionActivityManager.isActivityAvailable() {
            motionManager.queryActivityStarting(from: Date(), to: Date(), to: .main) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let cmError = error as NSError
                        if cmError.domain == CMErrorDomain && cmError.code == CMErrorMotionActivityNotAuthorized.rawValue {
                            showPermissionDeniedAlert(message: "Motion activity access helps us automatically detect when you've finished driving. Please enable it in Settings for the best experience.")
                        } else {
                            onNext()
                        }
                    } else {
                        onNext()
                    }
                }
            }
        } else {
            onNext()
        }
    }
    
    private func requestBluetoothPermission() {
        // Create a delegate to handle Bluetooth permission request
        bluetoothDelegate = BluetoothPermissionDelegate { [self] in
            DispatchQueue.main.async {
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
                self.onNext()
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    onNext()
                } else {
                    showPermissionDeniedAlert(message: "Notifications help you avoid parking tickets by reminding you about street cleaning. Please enable them in Settings.")
                }
            }
        }
    }
    
    private func showPermissionDeniedAlert(message: String) {
        permissionDeniedMessage = message
        showingPermissionDeniedAlert = true
    }
}

#Preview {
    OnboardingStepView(
        step: OnboardingStep.allSteps[1],
        isLastStep: false,
        onNext: {},
        onSkip: {}
    )
}

import SwiftUI
import CoreLocation
import UserNotifications

struct OnboardingStepView: View {
    let step: OnboardingStep
    let isLastStep: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    
    @State private var isAnimating = false
    @State private var showingPermissionDeniedAlert = false
    @State private var permissionDeniedMessage = ""
    @State private var locationDelegate: OnboardingLocationDelegate?
    @State private var locationManager: CLLocationManager?
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Hero Image/Icon Section
            VStack(spacing: 24) {
                ZStack {
                    if step.title == "Hello, San Francisco!" {
                        // Use app icon for welcome step with animations
                        Image("AppIconImage")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .scaleEffect(isAnimating ? 1.0 : 0.8)
                            .animation(.easeInOut(duration: 0.8).delay(0.2), value: isAnimating)
                    } else {
                        // Use system icons for other steps - no animations
                        Circle()
                            .fill(step.color)
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: step.systemImage)
                            .font(.system(size: 50, weight: .medium))
                            .foregroundColor(.white)
                            .id(step.systemImage) // Ensure stable identity
                    }
                }
                
                VStack(spacing: 16) {
                    Text(step.title)
                        .font(step.title == "Hello, San Francisco!" ? .largeTitle : .title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .opacity(step.title == "Hello, San Francisco!" ? (isAnimating ? 1.0 : 0.0) : 1.0)
                        .offset(y: step.title == "Hello, San Francisco!" ? (isAnimating ? 0 : 20) : 0)
                        .animation(step.title == "Hello, San Francisco!" ? .easeInOut(duration: 0.6).delay(0.6) : .none, value: isAnimating)
                    
                    Text(step.description)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .opacity(step.title == "Hello, San Francisco!" ? (isAnimating ? 1.0 : 0.0) : 1.0)
                        .offset(y: step.title == "Hello, San Francisco!" ? (isAnimating ? 0 : 20) : 0)
                        .animation(step.title == "Hello, San Francisco!" ? .easeInOut(duration: 0.6).delay(0.8) : .none, value: isAnimating)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Button Section
            VStack(spacing: 24) {
                Button(action: handleMainAction) {
                    Text(step.buttonText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [step.color, step.color.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: step.color.opacity(0.4), radius: 15, x: 0, y: 8)
                }
                .scaleEffect(step.title == "Hello, San Francisco!" ? (isAnimating ? 1.0 : 0.9) : 1.0)
                .opacity(step.title == "Hello, San Francisco!" ? (isAnimating ? 1.0 : 0.0) : 1.0)
                .animation(step.title == "Hello, San Francisco!" ? .easeInOut(duration: 0.6).delay(1.0) : .none, value: isAnimating)
                
                if step.permissionType != nil {
                    Button("Skip for now") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            onNext()
                        }
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                    .opacity(step.title == "Hello, San Francisco!" ? (isAnimating ? 1.0 : 0.0) : 1.0)
                    .animation(step.title == "Hello, San Francisco!" ? .easeInOut(duration: 0.6).delay(1.2) : .none, value: isAnimating)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .onAppear {
            triggerAnimation()
        }
        .onChange(of: step.id) { _, _ in
            triggerAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Re-trigger animation when app becomes active (after system dialogs dismiss)
            if !isAnimating {
                triggerAnimation()
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
        case .notifications:
            requestNotificationPermission()
        case .smartParking:
            requestSmartParkingPermission()
        }
    }
    
    private func requestLocationPermission() {
        locationManager = CLLocationManager()
        let authorizationStatus = locationManager!.authorizationStatus
        
        switch authorizationStatus {
        case .notDetermined:
            // Create a delegate to listen for authorization changes
            locationDelegate = OnboardingLocationDelegate { [self] authorized in
                DispatchQueue.main.async {
                    if authorized {
                        let successFeedback = UINotificationFeedbackGenerator()
                        successFeedback.notificationOccurred(.success)
                        self.onNext()
                    } else {
                        self.showPermissionDeniedAlert(message: "Location access helps us track where you parked and show you the street cleaning rules for that location. Please enable it in Settings.")
                    }
                }
            }
            
            locationManager!.delegate = locationDelegate
            locationManager!.requestWhenInUseAuthorization()
            
        case .denied, .restricted:
            showPermissionDeniedAlert(message: "Location access helps us track where you parked and show you the street cleaning rules for that location. Please enable it in Settings.")
        default:
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
            onNext()
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
    
    private func requestSmartParkingPermission() {
        // Smart parking is an app setting, not a system permission
        // Enable it by default and move to next step
        ParkingDetector.shared.startMonitoring()
        
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.success)
        
        AnalyticsManager.shared.logPermissionGranted(permissionType: "smart_parking")
        onNext()
    }
    
    
    private func showPermissionDeniedAlert(message: String) {
        permissionDeniedMessage = message
        showingPermissionDeniedAlert = true
    }
    
    private func triggerAnimation() {
        // Reset animation state first
        isAnimating = false
        // Then trigger animations with delay to allow transition to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                isAnimating = true
            }
        }
    }
}

// Custom delegate that only calls completion once for onboarding flow
class OnboardingLocationDelegate: NSObject, CLLocationManagerDelegate {
    private let completion: (Bool) -> Void
    private var hasCompleted = false
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !hasCompleted else { return } // Prevent multiple calls
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            // Only complete on "when in use" - ignore subsequent "always" prompts
            hasCompleted = true
            AnalyticsManager.shared.logPermissionGranted(permissionType: "location")
            completion(true)
        case .denied, .restricted:
            hasCompleted = true
            AnalyticsManager.shared.logPermissionDenied(permissionType: "location")
            completion(false)
        case .authorizedAlways:
            // Ignore "always" changes during onboarding - user already granted "when in use"
            break
        case .notDetermined:
            // Still waiting for user decision
            break
        @unknown default:
            hasCompleted = true
            completion(false)
        }
    }
}

#Preview("Light Mode") {
    OnboardingStepView(
        step: OnboardingStep.allSteps[1],
        isLastStep: false,
        onNext: {},
        onSkip: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    OnboardingStepView(
        step: OnboardingStep.allSteps[1],
        isLastStep: false,
        onNext: {},
        onSkip: {}
    )
    .preferredColorScheme(.dark)
}

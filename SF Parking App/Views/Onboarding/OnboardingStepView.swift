import SwiftUI
import CoreLocation
import UserNotifications
import CoreMotion

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
    
    private var attributedWelcomeText: AttributedString {
        var attributedString = AttributedString("We know parking here can be tough. We're committed to helping you avoid tickets and park safely.")
        
        // Set the base styling for all text
        let fullRange = attributedString.startIndex..<attributedString.endIndex
        attributedString[fullRange].font = .title3.weight(.medium)
        attributedString[fullRange].foregroundColor = .secondary
        
        // Make "avoid tickets" bold
        if let range = attributedString.range(of: "avoid tickets") {
            attributedString[range].font = .title3.weight(.bold)
            attributedString[range].foregroundColor = .primary
        }
        
        // Make "park safely" bold
        if let range = attributedString.range(of: "park safely") {
            attributedString[range].font = .title3.weight(.bold)
            attributedString[range].foregroundColor = .primary
        }
        
        return attributedString
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Hero Image/Icon Section
            VStack(spacing: 24) {
                ZStack {
                    if step.permissionType == nil {
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
                        .font(step.permissionType == nil ? .largeTitle : .title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .opacity(step.permissionType == nil ? (isAnimating ? 1.0 : 0.0) : 1.0)
                        .offset(y: step.permissionType == nil ? (isAnimating ? 0 : 20) : 0)
                        .animation(step.permissionType == nil ? .easeInOut(duration: 0.6).delay(0.6) : .none, value: isAnimating)
                    
                    if step.permissionType == nil {
                        // Welcome step with bold text
                        Text(attributedWelcomeText)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .opacity(isAnimating ? 1.0 : 0.0)
                            .offset(y: isAnimating ? 0 : 20)
                            .animation(.easeInOut(duration: 0.6).delay(0.8), value: isAnimating)
                    } else {
                        // Regular permission steps
                        Text(step.description)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Button Section - Fixed height container for consistent positioning
            VStack(spacing: 0) {
                VStack(spacing: 16) {
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
                    
                    // Fixed height space for skip button to ensure consistent main button positioning
                    if step.permissionType != nil {
                        Button("Skip for now") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                onNext()
                            }
                        }
                        .font(.body)
                        .foregroundColor(.secondary)
                    } else {
                        // Invisible spacer to maintain same height
                        Text("Skip for now")
                            .font(.body)
                            .opacity(0)
                    }
                }
                .frame(height: 100) // Fixed height for consistent button positioning
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 0) // As low as possible
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
        case .motion:
            requestMotionPermission()
        case .smartParking:
            enableSmartParking()
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
            locationManager!.requestAlwaysAuthorization()
            
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
    
    private func requestMotionPermission() {
        // Check if motion is available
        guard CMMotionActivityManager.isActivityAvailable() else {
            showPermissionDeniedAlert(message: "Motion tracking is not available on this device. Smart Parking will not be enabled.")
            return
        }
        
        let motionManager = CMMotionActivityManager()
        
        // Request motion permission by starting activity updates
        motionManager.startActivityUpdates(to: .main) { activity in
            // Stop immediately after permission is granted
            motionManager.stopActivityUpdates()
            
            DispatchQueue.main.async {
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
                AnalyticsManager.shared.logPermissionGranted(permissionType: "motion")
                self.onNext()
            }
        }
        
        // Handle permission denial with a timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            motionManager.stopActivityUpdates()
            // If we haven't moved to next step yet, assume permission was denied
            if !self.showingPermissionDeniedAlert {
                self.showPermissionDeniedAlert(message: "Motion access is required for Smart Parking to work. Please enable it in Settings.")
                AnalyticsManager.shared.logPermissionDenied(permissionType: "motion")
            }
        }
    }
    
    private func enableSmartParking() {
        // Check if motion is available
        guard CMMotionActivityManager.isActivityAvailable() else {
            showPermissionDeniedAlert(message: "Motion tracking is not available on this device. Smart Parking cannot be enabled.")
            return
        }
        
        // Check current permission status
        let currentStatus = CMMotionActivityManager.authorizationStatus()
        
        if currentStatus == .authorized {
            // Already authorized, enable Smart Parking
            ParkingDetector.shared.startMonitoring()
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)
            AnalyticsManager.shared.logPermissionGranted(permissionType: "smart_parking")
            onNext()
            return
        }
        
        if currentStatus == .denied || currentStatus == .restricted {
            showPermissionDeniedAlert(message: "Motion access was denied. Smart Parking requires motion permission to detect when you've parked. Please enable it in Settings.")
            return
        }
        
        // Request motion permission
        let motionManager = CMMotionActivityManager()
        
        motionManager.startActivityUpdates(to: .main) { activity in
            // Stop immediately after permission is granted
            motionManager.stopActivityUpdates()
            
            DispatchQueue.main.async {
                // Enable Smart Parking now that we have permission
                ParkingDetector.shared.startMonitoring()
                
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
                
                AnalyticsManager.shared.logPermissionGranted(permissionType: "smart_parking")
                self.onNext()
            }
        }
        
        // Handle timeout for permission request
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if CMMotionActivityManager.authorizationStatus() != .authorized {
                motionManager.stopActivityUpdates()
                self.showPermissionDeniedAlert(message: "Motion access is required for Smart Parking to automatically detect when you've parked. Please enable it in Settings.")
                AnalyticsManager.shared.logPermissionDenied(permissionType: "motion")
            }
        }
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
        case .authorizedWhenInUse, .authorizedAlways:
            // Complete on either permission level
            hasCompleted = true
            AnalyticsManager.shared.logPermissionGranted(permissionType: "location")
            completion(true)
        case .denied, .restricted:
            hasCompleted = true
            AnalyticsManager.shared.logPermissionDenied(permissionType: "location")
            completion(false)
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

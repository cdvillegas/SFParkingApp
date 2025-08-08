import SwiftUI
import MapKit
import CoreLocation

struct VehicleParkingView: View {
    @StateObject private var viewModel = VehicleParkingViewModel()
    @State private var showingRemindersSheet = false
    @State private var showingAutoParkingSettings = false
    @State private var showingParkingDetailsSheet = false
    @State private var showingHistorySheet = false
    @EnvironmentObject var parkingDetectionHandler: ParkingDetectionHandler
    @StateObject private var parkingDetector = ParkingDetector.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var wasHandlingAutoParking = false
    @State private var showingOnboarding = !OnboardingManager.hasCompletedOnboarding
    @State private var isComingFromOnboarding = false
    
    // Smart Park confirmation state
    @State private var showingSmartParkConfirmation = false
    @State private var pendingParkingLocation: SmartParkLocation?
    
    // Optional parameters for auto-parking detection
    var autoDetectedLocation: CLLocationCoordinate2D?
    var autoDetectedAddress: String?
    var autoDetectedSource: ParkingSource?
    var onAutoParkingHandled: (() -> Void)?
    
    // Calculate the height needed for bottom content
    private var bottomContentHeight: CGFloat {
        // Dynamic height based on content state
        if viewModel.isConfirmingSchedule {
            return 280 // More space for schedule confirmation
        } else if viewModel.isSettingLocation {
            return 220 // Same as normal mode for consistency
        } else if viewModel.vehicleManager.currentVehicle?.parkingLocation != nil {
            return 220 // Space for parked vehicle info
        } else {
            return 180 // Minimum space for empty state
        }
    }
    
    var body: some View {
        ZStack {
            // Map extends to absolute bottom edge
            VehicleParkingMapView(viewModel: viewModel)
                .ignoresSafeArea(.all)
            
            
            // Top status buttons or instructions (hidden during onboarding)
            if !showingOnboarding {
                VStack {
                    if viewModel.isSettingLocation || viewModel.isConfirmingSchedule {
                        instructionWindow
                            .padding(.horizontal, 12)
                            .padding(.top, 20)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    } else {
                        // History button in top left when not setting/confirming location
                        HStack {
                            historyButton
                                .padding(.leading, 12)
                                .padding(.top, 20)
                            
                            Spacer()
                        }
                    }
                    
                    Spacer()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isSettingLocation)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isConfirmingSchedule)
                .transition(.opacity)
            }
            
            // Content overlay at bottom (hidden during onboarding)
            if !showingOnboarding {
                VStack {
                    Spacer()
                    
                    // Map control buttons positioned above content
                    HStack {
                        parkingDetailsButton
                            .padding(.leading, 12)
                            .padding(.bottom, 6) // Reduced gap above content
                        
                        Spacer()
                        
                        mapControlButtons
                            .padding(.trailing, 12)
                            .padding(.bottom, 6) // Reduced gap above content
                    }
                    
                    // Vehicle interface section - always present
                    VStack(spacing: 0) {
                        VehicleLocationSetting(
                            viewModel: viewModel,
                            onShowReminders: {
                                showingRemindersSheet = true
                            },
                            onShowSmartParking: {
                                showingAutoParkingSettings = true
                            }
                        )
                        
                        // Bottom tab bar - only show in normal mode
                        if !viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
                            bottomTabBar
                                .transition(.opacity)
                        }
                    }
                }
                .transition(.opacity)
            }
            
            // Onboarding overlay
            if showingOnboarding {
                OnboardingOverlayView(
                    onCompleted: {
                        isComingFromOnboarding = true
                        withAnimation(.easeInOut(duration: 0.8)) {
                            showingOnboarding = false
                        }
                    }
                )
                .transition(.opacity)
            }
            
            // Smart Park confirmation overlay
            if showingSmartParkConfirmation, let location = pendingParkingLocation {
                smartParkConfirmationOverlay(for: location)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $viewModel.showingAddVehicle) {
            AddEditVehicleView(
                vehicleManager: viewModel.vehicleManager,
                editingVehicle: nil,
                onVehicleCreated: { vehicle in
                    if viewModel.vehicleManager.activeVehicles.count == 1 {
                        viewModel.vehicleManager.selectVehicle(vehicle)
                    }
                }
            )
        }
        .sheet(item: $viewModel.showingEditVehicle) { vehicle in
            AddEditVehicleView(
                vehicleManager: viewModel.vehicleManager,
                editingVehicle: vehicle,
                onVehicleCreated: nil
            )
        }
        .onAppear {
            setupView()
            handleAutoDetectedParking()
            // Check notification permission status on view appear
            notificationManager.checkPermissionStatus()
            
            // Set up initial map position based on context
            if showingOnboarding {
                // If showing onboarding, start with SF view for smooth transition
                setupOnboardingMapView()
            }
        }
        .onChange(of: showingOnboarding) { _, isShowing in
            if !isShowing && isComingFromOnboarding {
                // Onboarding just completed, do smooth zoom transition
                performPostOnboardingTransition()
            }
        }
        .onChange(of: autoDetectedAddress) { _, newAddress in
            print("🎯 VehicleParkingView - autoDetectedAddress changed to: \(newAddress ?? "nil")")
            if newAddress != nil && autoDetectedLocation != nil {
                handleAutoDetectedParking()
            }
        }
        .onChange(of: autoDetectedSource) { _, newSource in
            print("🎯 VehicleParkingView - autoDetectedSource changed: \(newSource?.rawValue ?? "nil")")
            if newSource != nil && autoDetectedAddress != nil && autoDetectedLocation != nil {
                handleAutoDetectedParking()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .parkingDetected)) { notification in
            // Handle parking detection notification when app is already open
            if let userInfo = notification.userInfo,
               let coordinate = userInfo["coordinate"] as? CLLocationCoordinate2D,
               let address = userInfo["address"] as? String {
                handleAutoDetectedParking()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartParkConfirmationRequired)) { notification in
            // Handle Smart Park confirmation required notification
            handleSmartParkConfirmationRequired(notification: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh notification permission status when returning from Settings
            notificationManager.checkPermissionStatus()
            
            // Check if we should reopen Smart Parking sheet after returning from Settings
            if UserDefaults.standard.bool(forKey: "smartParkingSheetWasOpen") {
                UserDefaults.standard.removeObject(forKey: "smartParkingSheetWasOpen")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingAutoParkingSettings = true
                }
            }
        }
        .onChange(of: viewModel.isSettingLocation) { oldValue, newValue in
            // When location setting completes and we were handling auto parking, clear the data
            if oldValue == true && newValue == false && wasHandlingAutoParking {
                wasHandlingAutoParking = false
                onAutoParkingHandled?()
            }
        }
        .onReceive(viewModel.locationManager.$userLocation) { newUserLocation in
            // Only center on user location if not showing onboarding and no parking location is set
            if !showingOnboarding,
               let userLocation = newUserLocation,
               viewModel.vehicleManager.currentVehicle?.parkingLocation == nil {
                viewModel.centerMapOnLocation(userLocation.coordinate)
            }
        }
        .alert("Enable Notifications", isPresented: $viewModel.showingNotificationPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Enable notifications to get reminders about street cleaning and avoid parking tickets.")
        }
        .sheet(isPresented: $showingRemindersSheet) {
            RemindersSheet(
                schedule: viewModel.streetDataManager.nextUpcomingSchedule,
                parkingLocation: viewModel.vehicleManager.currentVehicle?.parkingLocation
            )
        }
        .onChange(of: showingRemindersSheet) { _, isShowing in
            if !isShowing {
                // Sheet was dismissed, show details for 5 seconds
                expandButtonDetails()
            }
        }
        .sheet(isPresented: $showingAutoParkingSettings) {
            SmartParkSettingsView()
        }
        .sheet(isPresented: $showingParkingDetailsSheet) {
            if let vehicle = viewModel.vehicleManager.currentVehicle,
               let parkingLocation = vehicle.parkingLocation {
                SchedulesView(
                    vehicle: vehicle,
                    parkingLocation: parkingLocation,
                    schedule: viewModel.streetDataManager.nextUpcomingSchedule,
                    originalSchedule: viewModel.streetDataManager.selectedSchedule ?? viewModel.streetDataManager.schedule
                )
            }
        }
        .sheet(isPresented: $showingHistorySheet) {
            ParkingHistorySheet(
                vehicleManager: viewModel.vehicleManager,
                onSelectLocation: { location in
                    // Set the selected location for the current vehicle
                    viewModel.confirmVehicleLocation(at: location.coordinate, address: location.address)
                }
            )
        }
        .onChange(of: showingAutoParkingSettings) { _, isShowing in
            if !isShowing {
                // Sheet was dismissed, show details for 5 seconds
                expandButtonDetails()
            }
        }
    }
    
    // MARK: - Instruction Window
    
    private var instructionWindow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.isConfirmingSchedule ? "Confirm Schedule" : "Set Location")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(instructionText)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Schedule information with smooth transitions
            if shouldShowUrgencyWarning {
                HStack(spacing: 8) {
                    Image(systemName: scheduleWarningIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(scheduleWarningColor)
                        .animation(.smooth(duration: 0.4, extraBounce: 0.1), value: scheduleWarningColor)
                        .animation(.smooth(duration: 0.3, extraBounce: 0.15), value: scheduleWarningIcon)
                    
                    Text(urgentScheduleWarningText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(scheduleWarningColor)
                        .lineLimit(1)
                        .animation(.smooth(duration: 0.4, extraBounce: 0.1), value: scheduleWarningColor)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.35, extraBounce: 0.08), value: urgentScheduleWarningText)
                    
                    Spacer()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .top)),
                    removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom))
                ))
                .animation(.smooth(duration: 0.5, extraBounce: 0.2), value: shouldShowUrgencyWarning)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, shouldShowUrgencyWarning ? 16 : 20)
        .animation(.smooth(duration: 0.3), value: shouldShowUrgencyWarning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }
    
    private var instructionText: String {
        if viewModel.isConfirmingSchedule {
            if viewModel.nearbySchedules.isEmpty {
                return "No parking restrictions found. Tap Confirm to save location."
            } else {
                return "Select your side of the street below, then tap Confirm."
            }
        } else {
            return "Drag the map to position the pin at your vehicle's location."
        }
    }
    
    private var shouldShowUrgencyWarning: Bool {
        // Show warning during schedule confirmation when we have a selected schedule
        guard viewModel.isConfirmingSchedule else { return false }
        
        // Check if we have a selected schedule
        if viewModel.hasSelectedSchedule,
           viewModel.selectedScheduleIndex < viewModel.nearbySchedules.count {
            return true
        }
        
        return false
    }
    
    private var urgentScheduleWarningText: String {
        guard viewModel.hasSelectedSchedule,
              viewModel.selectedScheduleIndex < viewModel.nearbySchedules.count else {
            return "Street cleaning soon"
        }
        
        let selectedSchedule = viewModel.nearbySchedules[viewModel.selectedScheduleIndex].schedule
        guard let nextOccurrence = viewModel.streetDataManager.calculateNextScheduleImmediate(for: selectedSchedule) else {
            return "Street cleaning soon"
        }
        
        let timeInterval = nextOccurrence.date.timeIntervalSinceNow
        let totalSeconds = Int(timeInterval)
        
        // Handle past/current times
        if totalSeconds <= 0 {
            return "Street cleaning starting now"
        }
        
        // Handle very soon (under 2 minutes)
        if totalSeconds < 120 {
            if totalSeconds < 60 {
                return "Street cleaning in under 1 minute"
            } else {
                return "Street cleaning in 1 minute"
            }
        }
        
        let minutes = totalSeconds / 60
        let hours = minutes / 60
        let days = hours / 24
        
        // Under 1 hour - show minutes only
        if hours < 1 {
            return "Street cleaning in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        
        // Under 24 hours - show hours only
        if hours < 24 {
            return "Street cleaning in \(hours) hour\(hours == 1 ? "" : "s")"
        }
        
        // 1 day
        if days == 1 {
            return "Street cleaning in 1 day"
        }
        
        // 2 days
        if days == 2 {
            return "Street cleaning in 2 days"
        }
        
        // 3-6 days - show day count
        if days >= 3 && days <= 6 {
            return "Street cleaning in \(days) days"
        }
        
        // 7-10 days - roughly 1 week
        if days >= 7 && days <= 10 {
            return "Street cleaning in 1 week"
        }
        
        // 11-17 days - roughly 2 weeks
        if days >= 11 && days <= 17 {
            return "Street cleaning in 2 weeks"
        }
        
        // 18-24 days - roughly 3 weeks
        if days >= 18 && days <= 24 {
            return "Street cleaning in 3 weeks"
        }
        
        // 25-31 days - roughly 4 weeks
        if days >= 25 && days <= 31 {
            return "Street cleaning in 4 weeks"
        }
        
        // Over a month
        let weeks = (days + 3) / 7  // Rough rounding
        return "Street cleaning in \(weeks) weeks"
    }
    
    private func getUrgencyColor(for schedule: SweepSchedule) -> Color {
        // Calculate next occurrence of this specific schedule
        guard let nextOccurrence = viewModel.streetDataManager.calculateNextScheduleImmediate(for: schedule) else {
            return .green
        }
        
        let timeInterval = nextOccurrence.date.timeIntervalSinceNow
        let hours = timeInterval / 3600
        
        if hours < 24 {
            return .red
        } else {
            return .green
        }
    }
    
    private var scheduleWarningColor: Color {
        guard viewModel.hasSelectedSchedule,
              viewModel.selectedScheduleIndex < viewModel.nearbySchedules.count else {
            return .green
        }
        
        let selectedSchedule = viewModel.nearbySchedules[viewModel.selectedScheduleIndex].schedule
        return getUrgencyColor(for: selectedSchedule)
    }
    
    private var scheduleWarningIcon: String {
        let color = scheduleWarningColor
        return color == .red ? "exclamationmark.triangle.fill" : "calendar"
    }
    
    // MARK: - Top Status Buttons
    
    @State private var showStatusDetails = true
    @State private var detailsTimer: Timer?
    
    private var topStatusButtons: some View {
        HStack(alignment: .top, spacing: 12) {
            // Smart Park button (left side)
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                showingAutoParkingSettings = true
            }) {
                HStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(smartParkingIsOn ? Color.blue : Color.gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Park")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if showStatusDetails {
                            Text(smartParkingIsOn ? "Enabled" : "Disabled")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, showStatusDetails ? 16 : 12)
                .frame(maxWidth: .infinity)
                .frame(height: showStatusDetails ? 56 : 48)
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showStatusDetails)
            }
            
            // Reminders button (right side)
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                showingRemindersSheet = true
            }) {
                HStack(spacing: 16) {
                    Image(systemName: remindersAreEffective ? "bell.fill" : "bell.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(remindersAreEffective ? Color.blue : Color.gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminders")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if showStatusDetails {
                            Text(remindersStatusText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, showStatusDetails ? 16 : 12)
                .frame(maxWidth: .infinity)
                .frame(height: showStatusDetails ? 56 : 48)
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showStatusDetails)
            }
        }
        .onAppear {
            startDetailsTimer()
        }
        .onDisappear {
            detailsTimer?.invalidate()
        }
    }
    
    private func startDetailsTimer() {
        detailsTimer?.invalidate()
        showStatusDetails = true
        
        detailsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showStatusDetails = false
            }
        }
    }
    
    private func expandButtonDetails() {
        detailsTimer?.invalidate()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showStatusDetails = true
        }
        
        detailsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showStatusDetails = false
            }
        }
    }
    
    private var activeRemindersCount: Int {
        return notificationManager.customReminders.filter { $0.isActive }.count
    }
    
    private var notificationsEnabled: Bool {
        return notificationManager.notificationPermissionStatus == .authorized
    }
    
    private var remindersAreEffective: Bool {
        return activeRemindersCount > 0 && notificationsEnabled
    }
    
    private var remindersStatusText: String {
        if !notificationsEnabled {
            return "Disabled"
        } else if activeRemindersCount == 0 {
            return "Disabled"
        } else {
            return "\(activeRemindersCount) Enabled"
        }
    }
    
    private func getScheduleUrgencyColor(for date: Date) -> Color {
        let timeInterval = date.timeIntervalSinceNow
        let hours = timeInterval / 3600
        
        if hours < 24 {
            return .red
        } else {
            return .green
        }
    }
    
    private func getScheduleTimeText(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeInterval = date.timeIntervalSince(now)
        let hours = timeInterval / 3600
        
        // Very close (less than 2 hours)
        if hours < 2 {
            let minutes = Int(timeInterval / 60)
            if minutes <= 30 {
                return "\(minutes)m"
            } else if minutes <= 60 {
                return "1h"
            } else {
                let roundedHours = Int(ceil(hours))
                return "\(roundedHours)h"
            }
        }
        
        // Today
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        // Tomorrow
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        
        // This week
        let daysUntil = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        
        if daysUntil <= 6 {
            let formatter = DateFormatter()
            formatter.dateFormat = "E" // Short day name
            return formatter.string(from: date)
        }
        
        return "Schedule"
    }
    
    
    private var smartParkingIsOn: Bool {
        let hasSetup = UserDefaults.standard.bool(forKey: "smartParkSetupCompleted")
        let isEnabled = UserDefaults.standard.object(forKey: "smartParkEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "smartParkEnabled")
        return hasSetup && isEnabled
    }
    
    private var smartParkingStatus: String {
        let hasSetup = UserDefaults.standard.bool(forKey: "smartParkSetupCompleted")
        if !hasSetup {
            return "Needs Setup"
        } else if !smartParkingIsOn {
            return "Disabled"
        } else {
            return "Enabled"
        }
    }
    
    // MARK: - Map Control Buttons
    
    private var mapControlButtons: some View {
        Group {
            if !viewModel.isConfirmingSchedule || viewModel.isSettingLocation {
                HStack(spacing: 16) {
                    vehicleButton
                    userLocationButton
                    enableLocationButton
                }
            }
        }
    }
    
    @ViewBuilder
    private var historyButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            showingHistorySheet = true
        }) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
                )
        }
    }
    
    @ViewBuilder
    private var parkingDetailsButton: some View {
        if let currentVehicle = viewModel.vehicleManager.currentVehicle,
           currentVehicle.parkingLocation != nil,
           viewModel.streetDataManager.nextUpcomingSchedule != nil,
           !viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                showingParkingDetailsSheet = true
            }) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
                    )
            }
        }
    }
    
    @ViewBuilder
    private var vehicleButton: some View {
        if let currentVehicle = viewModel.vehicleManager.currentVehicle,
           currentVehicle.parkingLocation != nil {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                centerOnVehicle()
            }) {
                Image(systemName: "car.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
                    )
            }
        }
    }
    
    // Check if user location is effectively available (both permission and coordinate)
    private var isUserLocationAvailable: Bool {
        let hasPermission = viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || 
                           viewModel.locationManager.authorizationStatus == .authorizedAlways
        let hasLocation = viewModel.locationManager.userLocation != nil
        return hasPermission && hasLocation
    }
    
    @ViewBuilder
    private var userLocationButton: some View {
        if isUserLocationAvailable {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                centerOnUser()
            }) {
                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
                    )
            }
        }
    }
    
    @ViewBuilder
    private var enableLocationButton: some View {
        if !isUserLocationAvailable && !viewModel.isConfirmingSchedule && !showingOnboarding {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                enableLocationAction()
            }) {
                Image(systemName: "location.slash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
                    )
            }
        }
    }
    
    private func enableLocationAction() {
        if viewModel.locationManager.authorizationStatus == .denied || 
           viewModel.locationManager.authorizationStatus == .restricted {
            // Open settings if permission was denied
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        } else {
            // Request permission if not determined
            viewModel.locationManager.requestLocationPermission()
        }
    }
    
    // MARK: - Helper Functions
    
    private func centerOnVehicle() {
        if let currentVehicle = viewModel.vehicleManager.currentVehicle,
           let parkingLocation = currentVehicle.parkingLocation {
            viewModel.centerMapOnLocation(parkingLocation.coordinate)
        }
    }
    
    private func centerOnUser() {
        if let userLocation = viewModel.locationManager.userLocation {
            viewModel.centerMapOnLocation(userLocation.coordinate)
        }
    }
    
    // MARK: - Helper Functions
    
    private func moveToUserLocation() {
        viewModel.locationManager.requestLocationPermission()
        
        if let userLocation = viewModel.locationManager.userLocation {
            // Move map to user location
            viewModel.centerMapOnLocation(userLocation.coordinate)
            
            // If setting location, update the setting coordinate
            if viewModel.isSettingLocation {
                viewModel.settingCoordinate = userLocation.coordinate
                viewModel.debouncedGeocoder.reverseGeocode(coordinate: userLocation.coordinate) { address, _ in
                    DispatchQueue.main.async {
                        viewModel.settingAddress = address
                    }
                }
            }
        }
    }
    
    private func showRemindersSheet() {
        showingRemindersSheet = true
    }
    
    
    // MARK: - Bottom Button Group
    
    private var bottomTabBar: some View {
        HStack(spacing: 12) {
            // Status indicators group
            HStack(spacing: 12) {
                // Smart Park Status
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    showingAutoParkingSettings = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(smartParkingIsOn ? Color.blue : Color.secondary)
                            .strikethrough(smartParkingIsOn)
                        
                        Text("Smart Park")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Reminders Status
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    showingRemindersSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: remindersAreEffective ? "bell.fill" : "bell.slash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(remindersAreEffective ? Color.blue : Color.secondary)
                        
                        Text("Reminders")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Action button (only show when vehicle exists)
            if let currentVehicle = viewModel.vehicleManager.currentVehicle {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    viewModel.isSettingLocationForNewVehicle = false
                    viewModel.startSettingLocationForVehicle(currentVehicle)
                }) {
                    Text("Move")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .background(.regularMaterial)
        .ignoresSafeArea(edges: .bottom)
    }
    
    
    // MARK: - Setup
    
    private func setupView() {
        // Start location services to get user location
        if viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || 
           viewModel.locationManager.authorizationStatus == .authorizedAlways {
            viewModel.locationManager.requestLocation()
        }
        
        // Only set up map position if not showing onboarding
        guard !showingOnboarding else { return }
        
        // Center map on vehicle or user location
        if let selectedVehicle = viewModel.vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
            viewModel.centerMapOnLocation(parkingLocation.coordinate)
            
            // Load user's selected schedule if available
            if let persistedSchedule = parkingLocation.selectedSchedule {
                let schedule = StreetDataService.shared.convertToSweepSchedule(from: persistedSchedule)
                viewModel.streetDataManager.schedule = schedule
                viewModel.streetDataManager.processNextSchedule(for: schedule)
            } else {
                // Only fetch fresh data if no selected schedule is persisted
                viewModel.streetDataManager.forceFetchSchedules(for: parkingLocation.coordinate)
            }
        } else if let userLocation = viewModel.locationManager.userLocation {
            viewModel.centerMapOnLocation(userLocation.coordinate)
        }
        // If no parking location and no user location, leave map at default (nothing to zoom to)
    }
    
    private func setupOnboardingMapView() {
        // Start with wider SF view for smooth transition effect
        viewModel.mapPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF center
                span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3) // Wider view
            )
        )
    }
    
    private func performPostOnboardingTransition() {
        // After onboarding completes, zoom to user location if available, otherwise stay in SF
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Small delay for overlay to fade
            
            withAnimation(.easeInOut(duration: 1.0)) {
                if let userLocation = self.viewModel.locationManager.userLocation {
                    // User location is available - zoom in on user
                    self.viewModel.mapPosition = .region(
                        MKCoordinateRegion(
                            center: userLocation.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // Close zoom on user
                        )
                    )
                } else {
                    // No user location - stay at SF level but closer than onboarding
                    self.viewModel.mapPosition = .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF center
                            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.20) // Medium SF view
                        )
                    )
                }
            }
            
            // Reset the flag
            self.isComingFromOnboarding = false
        }
    }
    
    private func isLocationInSanFrancisco(_ coordinate: CLLocationCoordinate2D) -> Bool {
        // SF boundaries (approximate)
        let sfLatRange = 37.70...37.84
        let sfLonRange = (-122.52)...(-122.35)
        
        return sfLatRange.contains(coordinate.latitude) && 
               sfLonRange.contains(coordinate.longitude)
    }
    
    private func handleAutoDetectedParking() {
        print("🎯 VehicleParkingView.handleAutoDetectedParking called")
        print("🎯 autoDetectedLocation: \(autoDetectedLocation?.latitude ?? 0), \(autoDetectedLocation?.longitude ?? 0)")
        print("🎯 autoDetectedAddress: \(autoDetectedAddress ?? "nil")")
        print("🎯 autoDetectedSource: \(autoDetectedSource?.rawValue ?? "nil")")
        
        // Check if we have auto-detected parking data
        guard let coordinate = autoDetectedLocation,
              let address = autoDetectedAddress else { 
            print("🎯 VehicleParkingView - No auto-detected parking data available")
            return 
        }
        
        // Ensure we have a vehicle to check
        guard let currentVehicle = viewModel.vehicleManager.currentVehicle else {
            print("🎯 VehicleParkingView - No current vehicle available")
            return
        }
        
        // SMART PARK 2.0 FIX: Check if the parking location is already saved with a schedule
        if let existingLocation = currentVehicle.parkingLocation,
           let existingSchedule = existingLocation.selectedSchedule {
            
            print("🎯 Smart Park location already saved with schedule: \(existingSchedule.streetName) - \(existingSchedule.weekday) \(existingSchedule.startTime)-\(existingSchedule.endTime)")
            
            // Update the UI to show the saved location and schedule
            setupView()
            
            // Set up StreetDataManager with the saved schedule
            let sweepSchedule = StreetDataService.shared.convertToSweepSchedule(from: existingSchedule)
            viewModel.streetDataManager.schedule = sweepSchedule
            viewModel.streetDataManager.nextUpcomingSchedule = viewModel.streetDataManager.calculateNextScheduleImmediate(for: sweepSchedule)
            
            // Center map on saved location
            viewModel.centerMapOnLocation(existingLocation.coordinate)
            
            print("🎯 Smart Park UI updated with existing schedule")
        } else {
            print("🎯 No saved schedule found, using legacy auto-detection flow")
            
            // Legacy flow for cases where no schedule was detected
            // Start the location setting flow with the auto-detected location
            viewModel.startSettingLocation()
            viewModel.settingCoordinate = coordinate
            viewModel.settingAddress = address
            viewModel.centerMapOnLocation(coordinate)
            
            // Immediately detect schedules and show confirmation
            viewModel.performScheduleDetection(for: coordinate)
            
            // Set the confirmation mode to show the schedule selection
            viewModel.isConfirmingSchedule = true
            viewModel.confirmedLocation = coordinate
            viewModel.confirmedAddress = address
        }
        
        // Show a subtle notification that parking was detected
        if let source = autoDetectedSource {
            let sourceText: String
            switch source {
            case .bluetooth:
                sourceText = "Bluetooth disconnection"
            case .carplay:
                sourceText = "CarPlay disconnection"
            case .carDisconnect:
                sourceText = "car disconnection"
            case .manual:
                sourceText = "manual input"
            }
            print("🎯 Auto-detected parking via \(sourceText) at \(address)")
        }
        
        // Mark that we're handling auto parking so we can clear data when done
        wasHandlingAutoParking = true
        
        // Don't clear immediately - wait for user to confirm or cancel
        // parkingDetectionHandler will be cleared when user confirms the location
    }
    
    // MARK: - Smart Park Confirmation UI
    
    private func handleSmartParkConfirmationRequired(notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        // Extract parking location data from notification
        guard let parkingId = userInfo["parkingId"] as? String,
              let latitude = userInfo["latitude"] as? Double,
              let longitude = userInfo["longitude"] as? Double,
              let address = userInfo["address"] as? String,
              let triggerType = userInfo["triggerType"] as? String else {
            print("❌ Invalid Smart Park confirmation required notification data")
            return
        }
        
        // Create SmartParkLocation from notification data
        let location = SmartParkLocation(
            id: parkingId,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            address: address,
            timestamp: Date(timeIntervalSince1970: userInfo["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970),
            triggerType: triggerType,
            bluetoothDeviceName: userInfo["bluetoothDeviceName"] as? String
        )
        
        // Show confirmation UI
        DispatchQueue.main.async {
            self.pendingParkingLocation = location
            withAnimation(.easeInOut(duration: 0.3)) {
                self.showingSmartParkConfirmation = true
            }
        }
    }
    
    @ViewBuilder
    private func smartParkConfirmationOverlay(for location: SmartParkLocation) -> some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Allow dismissing by tapping outside
                    dismissSmartParkConfirmation()
                }
            
            // Confirmation card
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text("Smart Park Detected")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    let triggerText = location.triggerType == "carPlay" ? "CarPlay" : "Bluetooth"
                    Text("via \(triggerText) disconnection")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Location info
                if let address = location.address {
                    VStack(spacing: 4) {
                        Text("Detected Location")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Text(address)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    // Confirm button
                    Button(action: {
                        confirmSmartParkLocation(location)
                    }) {
                        Text("Confirm & Save")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.blue)
                            .cornerRadius(16)
                    }
                    
                    // Dismiss button
                    Button(action: {
                        dismissSmartParkConfirmation()
                    }) {
                        Text("Not Parked Here")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.clear)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 20)
        }
    }
    
    private func confirmSmartParkLocation(_ location: SmartParkLocation) {
        Task { @MainActor in
            // Confirm the location using ParkingLocationManager
            let manager = await ParkingLocationManager.shared
            await manager.confirmPendingLocation()
            
            print("✅ Smart Park location confirmed: \(location.address ?? "location")")
            
            // Update the UI to show the confirmed location
            setupView()
            
            // Hide confirmation UI
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSmartParkConfirmation = false
                pendingParkingLocation = nil
            }
        }
    }
    
    private func dismissSmartParkConfirmation() {
        Task { @MainActor in
            if let location = pendingParkingLocation {
                // Cancel the pending location
                let manager = await ParkingLocationManager.shared
                await manager.cancelPendingLocation()
                
                print("✅ Smart Park location dismissed")
            }
            
            // Hide confirmation UI
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSmartParkConfirmation = false
                pendingParkingLocation = nil
            }
        }
    }
    
}

#Preview("Light Mode") {
    VehicleParkingView(
        autoDetectedLocation: nil,
        autoDetectedAddress: nil,
        autoDetectedSource: nil,
        onAutoParkingHandled: nil
    )
        .environmentObject(ParkingDetectionHandler())
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VehicleParkingView(
        autoDetectedLocation: nil,
        autoDetectedAddress: nil,
        autoDetectedSource: nil,
        onAutoParkingHandled: nil
    )
        .environmentObject(ParkingDetectionHandler())
        .preferredColorScheme(.dark)
}

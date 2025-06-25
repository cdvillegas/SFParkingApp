//
//  ParkingLocationView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import _MapKit_SwiftUI
import CoreLocation

struct ParkingLocationView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var streetDataManager = StreetDataManager()
    @StateObject private var parkingManager = ParkingLocationManager()
    @StateObject private var debouncedGeocoder = DebouncedGeocodingHandler()
    @StateObject private var motionActivityManager = MotionActivityManager()
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    
    // MARK: - Setting Location State
    @State private var isSettingLocation = false
    @State private var settingAddress: String?
    @State private var settingNeighborhood: String?
    @State private var settingCoordinate = CLLocationCoordinate2D()
    
    // Auto-center functionality
    @State private var autoResetTimer: Timer?
    @State private var lastInteractionTime = Date()
    
    // Notification permission tracking
    @State private var showingNotificationPermissionAlert = false
    
    // Add tracking for notification scheduling
    @State private var lastNotificationLocationId: UUID?
    @State private var hasScheduledNotifications = false
    
    // MARK: - Haptic Feedback
    private let impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 4) {
            // Map Section
            ZStack {
                if isSettingLocation {
                    settingModeMap
                } else {
                    normalModeMap
                }
            }
            
            // Bottom UI Section
            VStack(spacing: 4) {
                if !isSettingLocation {
                    UpcomingRemindersSection(
                        streetDataManager: streetDataManager,
                        parkingLocation: parkingManager.currentLocation
                    )
                    
                    Divider().padding(.horizontal, 20)
                }
                
                // Parking Location Section - unified interface
                ParkingLocationSection(
                    parkingLocation: parkingManager.currentLocation,
                    onLocationTap: openInMaps,
                    isSettingMode: isSettingLocation,
                    settingAddress: settingAddress,
                    settingNeighborhood: settingNeighborhood,
                    settingCoordinate: isSettingLocation ? settingCoordinate : nil
                )
                
                // Button Section
                buttonSection
            }
            .ignoresSafeArea(.all, edges: .top)
            .background(Color(UIColor.systemBackground))
            .onAppear {
                setupView()
                prepareHaptics()
                setupNotificationHandling()
            }
            .onDisappear {
                cleanupResources()
            }
            .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
                Button("Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enable notifications in Settings to receive street cleaning reminders for your parked car.")
            }
            .onReceive(streetDataManager.$schedule) { schedule in
                // Only schedule notifications once per location change
                if let schedule = schedule,
                   let _ = parkingManager.currentLocation,
                   !hasScheduledNotifications,
                   notificationManager.notificationPermissionStatus == .authorized {
                    
                    print("📅 Scheduling notifications for new schedule...")
                    scheduleNotificationsIfNeeded(schedule: schedule)
                    hasScheduledNotifications = true
                }
            }
        }
    }
    
    // MARK: - Map Views
    
    private var settingModeMap: some View {
        Map(position: $mapPosition) {
            // User location annotation
            if let userLocation = locationManager.userLocation {
                Annotation("Your Location", coordinate: userLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 20, height: 20)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                }
            }
        }
        .onMapCameraChange { context in
            let newCoordinate = context.camera.centerCoordinate
            settingCoordinate = newCoordinate
            
            // Use debounced geocoding
            debouncedGeocoder.reverseGeocode(coordinate: newCoordinate) { address, neighborhood in
                DispatchQueue.main.async {
                    settingAddress = address
                    settingNeighborhood = neighborhood
                }
            }
        }
        .overlay(
            // Fixed center pin
            ZStack {
                Image(systemName: "car.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
        .overlay(
            MapControlButtons(
                userLocation: locationManager.userLocation,
                parkingLocation: parkingManager.currentLocation,
                onCenterOnUser: centerOnUser,
                onGoToCar: goToCar,
                onLocationRequest: { locationManager.requestLocation() }
            ),
            alignment: .topTrailing
        )
    }
    
    private var normalModeMap: some View {
        Map(position: $mapPosition) {
            // User location annotation
            if let userLocation = locationManager.userLocation {
                Annotation("Your Location", coordinate: userLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                }
            }
            
            // Parking location annotation
            if let parkingLocation = parkingManager.currentLocation {
                Annotation("Parked Car", coordinate: parkingLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "car.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 8, weight: .bold))
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                }
            }
        }
        .onReceive(locationManager.$userLocation) { location in
            if location != nil {
                centerMapOnBothLocations()
            }
        }
        .onReceive(parkingManager.$currentLocation) { parkingLocation in
            // Only fetch street data if location actually changed
            if let location = parkingLocation,
               lastNotificationLocationId != location.id {
                
                print("🚗 Parking location changed, fetching schedules...")
                streetDataManager.fetchSchedules(for: location.coordinate)
                lastNotificationLocationId = location.id
                hasScheduledNotifications = false
            }
            // Re-center map to show both locations
            centerMapOnBothLocations()
        }
        .onMapCameraChange { context in
            // Track user interaction with map
            handleMapInteraction()
        }
        .overlay(
            MapControlButtons(
                userLocation: locationManager.userLocation,
                parkingLocation: parkingManager.currentLocation,
                onCenterOnUser: centerOnUser,
                onGoToCar: goToCar,
                onLocationRequest: { locationManager.requestLocation() }
            ),
            alignment: .topTrailing
        )
    }
    
    // MARK: - Button Section
    
    private var buttonSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                // Left button - changes based on state
                Button(action: isSettingLocation ? cancelSettingLocation : handleNotificationAction) {
                    Image(systemName: isSettingLocation ? "xmark" : (notificationManager.notificationPermissionStatus == .authorized ? "bell.fill" : "bell.badge.fill"))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(notificationManager.notificationPermissionStatus == .denied ? Color.orange.opacity(0.8) : Color.gray.opacity(0.8))
                        )
                }
                .frame(maxWidth: 52)
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: isSettingLocation)
                
                // Right button - changes based on state
                Button(action: isSettingLocation ? setParkingLocation : startSettingLocation) {
                    Text(isSettingLocation ? "Set Location" : "Update Parking Location")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(
                                    LinearGradient(
                                        colors: isSettingLocation ?
                                            [Color.green, Color.green.opacity(0.8)] :
                                            [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(
                                    color: isSettingLocation ?
                                        Color.green.opacity(0.3) :
                                        Color.blue.opacity(0.3),
                                    radius: 10,
                                    x: 0,
                                    y: 5
                                )
                        )
                }
                .scaleEffect(1.0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, max(8, UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first?.safeAreaInsets.bottom ?? 0))
    }
    
    // MARK: - Resource Cleanup
    
    private func cleanupResources() {
        // Clean up timers and cancel pending requests
        autoResetTimer?.invalidate()
        autoResetTimer = nil
        
        debouncedGeocoder.cancel()
        
        // Clean up expired cache entries
        GeocodingCacheManager.shared.clearExpiredCache()
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notification Handling
    
    private func setupNotificationHandling() {
        // Listen for notification taps
        NotificationCenter.default.addObserver(
            forName: .streetCleaningNotificationTapped,
            object: nil,
            queue: .main
        ) { notification in
            handleNotificationTap(notification.userInfo)
        }
        
        // Request notification permission on first launch if we have a parking location
        if notificationManager.notificationPermissionStatus == .notDetermined,
           parkingManager.currentLocation != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                notificationManager.requestNotificationPermission()
            }
        }
    }
    
    private func handleNotificationAction() {
        switch notificationManager.notificationPermissionStatus {
        case .notDetermined:
            notificationManager.requestNotificationPermission()
        case .denied:
            showingNotificationPermissionAlert = true
        case .authorized, .provisional:
            // Show notification status or allow user to manage notifications
            notificationManager.getPendingNotifications()
        case .ephemeral:
            // Handle ephemeral authorization if needed
            notificationManager.getPendingNotifications()
        @unknown default:
            break
        }
    }
    
    private func formatScheduleDescription(_ schedule: SweepSchedule) -> String {
        guard let weekday = schedule.weekday,
              let startTime = schedule.fromhour,
              let endTime = schedule.tohour,
              !weekday.isEmpty,
              !startTime.isEmpty,
              !endTime.isEmpty else {
            return "Street Cleaning"
        }
        
        let dayAbbrev = weekday.prefix(3).uppercased()
        return "\(dayAbbrev) \(startTime)-\(endTime)"
    }

    private func scheduleNotificationsIfNeeded(schedule: SweepSchedule) {
        guard let parkingLocation = parkingManager.currentLocation,
              notificationManager.notificationPermissionStatus == .authorized,
              let weekday = schedule.weekday,
              let startTime = schedule.fromhour,
              let endTime = schedule.tohour else {
            return
        }
        
        // Cancel existing notifications for this location before scheduling new ones
        notificationManager.cancelNotifications(for: parkingLocation)
        
        let streetCleaningSchedule = StreetCleaningSchedule(
            id: "\(schedule.fullname ?? "unknown")_\(weekday)",
            description: formatScheduleDescription(schedule),
            dayOfWeek: dayStringToWeekday(weekday),
            startTime: startTime,
            endTime: endTime
        )
        
        notificationManager.scheduleStreetCleaningNotifications(
            for: parkingLocation,
            schedules: [streetCleaningSchedule]
        )
        
        print("✅ Scheduled notifications for parking location: \(parkingLocation.address)")
    }
    
    private func dayStringToWeekday(_ dayString: String) -> Int {
        let normalizedDay = dayString.lowercased().trimmingCharacters(in: .whitespaces)
        
        switch normalizedDay {
        case "sun", "sunday": return 1
        case "mon", "monday": return 2
        case "tue", "tues", "tuesday": return 3
        case "wed", "wednesday": return 4
        case "thu", "thur", "thursday": return 5
        case "fri", "friday": return 6
        case "sat", "saturday": return 7
        default: return 2 // Default to Monday
        }
    }
    
    private func handleNotificationTap(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo = userInfo,
              let locationIdString = userInfo["locationId"] as? String,
              let locationId = UUID(uuidString: locationIdString) else {
            return
        }
        
        // Center map on the parking location if it matches
        if let parkingLocation = parkingManager.currentLocation,
           parkingLocation.id == locationId {
            centerMap(on: parkingLocation.coordinate, zoomLevel: .close)
        }
    }
    
    // MARK: - Auto-Center Functionality
    
    private func handleMapInteraction() {
        guard !isSettingLocation else { return }
        
        lastInteractionTime = Date()
        autoResetTimer?.invalidate()
        
        autoResetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                let timeSinceLastInteraction = Date().timeIntervalSince(lastInteractionTime)
                if timeSinceLastInteraction >= 5.0 && !isSettingLocation {
                    centerMapOnBothLocations()
                }
            }
        }
    }
    
    private func centerMapOnBothLocations() {
        guard !isSettingLocation else { return }
        
        let userLocation = locationManager.userLocation
        let parkingLocation = parkingManager.currentLocation
        
        switch (userLocation, parkingLocation) {
        case (let user?, let parking?):
            centerMapOnBothCoordinates(user.coordinate, parking.coordinate)
        case (let user?, nil):
            centerMap(on: user.coordinate)
        case (nil, let parking?):
            centerMap(on: parking.coordinate)
        case (nil, nil):
            break
        }
    }
    
    private func centerMapOnBothCoordinates(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) {
        let centerLat = (coord1.latitude + coord2.latitude) / 2
        let centerLon = (coord1.longitude + coord2.longitude) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        
        let latDelta = abs(coord1.latitude - coord2.latitude)
        let lonDelta = abs(coord1.longitude - coord2.longitude)
        
        // Reduced minimum delta for closer zoom
        let paddedLatDelta = max(latDelta * 1.8, 0.001)
        let paddedLonDelta = max(lonDelta * 1.8, 0.001)
        
        let finalDelta = max(paddedLatDelta, paddedLonDelta)
        let span = MKCoordinateSpan(latitudeDelta: finalDelta, longitudeDelta: finalDelta)
        
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .region(MKCoordinateRegion(center: centerCoordinate, span: span))
        }
    }
    
    // MARK: - Haptic Preparation
    
    private func prepareHaptics() {
        impactFeedbackLight.prepare()
        notificationFeedback.prepare()
    }
    
    // MARK: - Actions
    
    private func setupView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            locationManager.requestLocationPermission()
            
            // Link managers together
            motionActivityManager.parkingLocationManager = parkingManager
            motionActivityManager.locationManager = locationManager
            bluetoothManager.parkingLocationManager = parkingManager
            bluetoothManager.locationManager = locationManager
            
            // Request motion permission
            motionActivityManager.requestMotionPermission()
            
            // Only fetch schedules if we have a parking location and haven't already done so
            if let parkingLocation = parkingManager.currentLocation {
                lastNotificationLocationId = parkingLocation.id
                streetDataManager.fetchSchedules(for: parkingLocation.coordinate)
            }
            
            centerMapOnBothLocations()
        }
    }
    
    private func startSettingLocation() {
        autoResetTimer?.invalidate()
        impactFeedbackLight.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = true
        }
        
        let startCoordinate: CLLocationCoordinate2D
        if let parkingLocation = parkingManager.currentLocation {
            startCoordinate = parkingLocation.coordinate
            settingAddress = parkingLocation.address
            settingNeighborhood = nil // Will be loaded via geocoding
        } else if let userLocation = locationManager.userLocation {
            startCoordinate = userLocation.coordinate
            settingAddress = nil // Will be loaded via geocoding
            settingNeighborhood = nil
        } else {
            startCoordinate = CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232)
            settingAddress = "San Francisco, CA"
            settingNeighborhood = nil
        }
        
        settingCoordinate = startCoordinate
        centerMap(on: startCoordinate, zoomLevel: .close)
        
        // Trigger initial geocoding if needed
        if settingAddress == nil || settingNeighborhood == nil {
            debouncedGeocoder.reverseGeocode(coordinate: startCoordinate) { address, neighborhood in
                DispatchQueue.main.async {
                    if settingAddress == nil {
                        settingAddress = address
                    }
                    if settingNeighborhood == nil {
                        settingNeighborhood = neighborhood
                    }
                }
            }
        }
    }
    
    private func setParkingLocation() {
        guard let address = settingAddress else { return }
        
        notificationFeedback.notificationOccurred(.success)
        
        // Cancel existing notifications for the old location
        if let oldLocation = parkingManager.currentLocation {
            notificationManager.cancelNotifications(for: oldLocation)
        }
        
        // Reset notification tracking
        hasScheduledNotifications = false
        
        // Set the new parking location
        parkingManager.setManualParkingLocation(
            coordinate: settingCoordinate,
            address: address
        )
        
        // Request notification permission if not already granted
        if notificationManager.notificationPermissionStatus == .notDetermined {
            notificationManager.requestNotificationPermission()
        }
        
        // Clear setting state
        settingAddress = nil
        settingNeighborhood = nil
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            centerMapOnBothLocations()
            
            // Note: Street data will be fetched automatically via the onReceive handler
        }
    }
    
    private func cancelSettingLocation() {
        debouncedGeocoder.cancel()
        
        // Clear setting state
        settingAddress = nil
        settingNeighborhood = nil
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            centerMapOnBothLocations()
        }
    }
    
    private func centerOnUser() {
        autoResetTimer?.invalidate()
        
        if let location = locationManager.userLocation {
            centerMap(on: location.coordinate)
            handleMapInteraction()
        }
    }
    
    private func goToCar() {
        autoResetTimer?.invalidate()
        
        if let parkingLocation = parkingManager.currentLocation {
            centerMap(on: parkingLocation.coordinate)
            handleMapInteraction()
        }
    }
    
    private func centerMap(on coordinate: CLLocationCoordinate2D, zoomLevel: MapZoomLevel = .medium) {
        let span = zoomLevel.span
        
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
        }
    }
    
    private func openInMaps(coordinate: CLLocationCoordinate2D) {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        destination.name = "Parked Car"
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    
    enum MapZoomLevel {
        case veryClose   // 0.0005
        case close       // 0.002
        case medium      // 0.01
        case far         // 0.03
        case veryFar     // 0.1
        
        var span: MKCoordinateSpan {
            switch self {
            case .veryClose:
                return MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
            case .close:
                return MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            case .medium:
                return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            case .far:
                return MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            case .veryFar:
                return MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            }
        }
    }
}

#Preview {
    ParkingLocationView()
}

#Preview("Light Mode") {
    ParkingLocationView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ParkingLocationView()
        .preferredColorScheme(.dark)
}

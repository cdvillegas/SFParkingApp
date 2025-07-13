import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit

struct VehicleParkingView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var streetDataManager = StreetDataManager()
    @StateObject private var vehicleManager = VehicleManager()
    @StateObject private var debouncedGeocoder = DebouncedGeocodingHandler()
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7551, longitude: -122.4528), // Sutro Tower
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18) // More zoomed out city view
        )
    )
    
    // MARK: - UI State
    @State private var showingVehiclesList = false
    @State private var showingAddVehicle = false
    @State private var showingEditVehicle: Vehicle?
    @State private var isSettingLocation = false
    @State private var settingAddress: String?
    @State private var settingCoordinate = CLLocationCoordinate2D()
    @State private var showingVehicleActions: Vehicle?
    @State private var isSettingLocationForNewVehicle = false
    
    // Unified location setting
    @State private var detectedSchedule: SweepSchedule?
    @State private var scheduleConfidence: Float = 0.0
    @State private var isAutoDetectingSchedule = false
    @State private var lastDetectionCoordinate: CLLocationCoordinate2D?
    @State private var detectionDebounceTimer: Timer?
    
    // Side-of-street selection
    @State private var nearbySchedules: [SweepScheduleWithSide] = []
    @State private var selectedScheduleIndex: Int = 0
    @State private var hasSelectedSchedule: Bool = true
    @State private var showingScheduleSelection = false
    
    // Auto-center functionality
    @State private var autoResetTimer: Timer?
    @State private var lastInteractionTime = Date()
    
    // Notification tracking
    @State private var showingNotificationPermissionAlert = false
    @State private var lastNotificationLocationId: UUID?
    @State private var showingReminderSheet = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // Map camera tracking for direction cone
    @State private var currentMapHeading: CLLocationDirection = 0
    
    // MARK: - Haptic Feedback
    private let impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .top) {
                    mapView
                    topControls
                }
                
                // Map buttons - bottom area
                VStack {
                    Spacer()
                    ZStack {
                        // Location permission button (center bottom)
                        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .notDetermined {
                            Button(action: {
                                impactFeedbackLight.impactOccurred()
                                handleLocationPermission()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: locationManager.authorizationStatus == .denied ? "location.slash" : "location")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Enable Location")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.blue.opacity(0.9))
                                        .shadow(color: .blue, radius: 6, x: 0, y: 3)
                                )
                            }
                        }
                        
                        // Center on vehicles button (bottom right)
                        HStack {
                            Spacer()
                            if !vehicleManager.activeVehicles.isEmpty && vehicleManager.activeVehicles.contains(where: { $0.parkingLocation != nil }) {
                                Button(action: {
                                    impactFeedbackLight.impactOccurred()
                                    centerMapOnVehiclesWithConsistentZoom()
                                }) {
                                    Image(systemName: "scope")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                                            )
                                }
                                .padding(.trailing, 20)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }

            bottomInterface
        }
        .sheet(isPresented: $showingVehiclesList) {
            // Vehicle list sheet not used in single-vehicle mode
        }
        .sheet(isPresented: $showingAddVehicle) {
            AddEditVehicleView(
                vehicleManager: vehicleManager,
                editingVehicle: nil,
                onVehicleCreated: { newVehicle in
                    // Auto-start parking location setup for new vehicle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSettingLocationForNewVehicle = true
                        startSettingLocationForVehicle(newVehicle)
                    }
                }
            )
        }
        .sheet(item: $showingEditVehicle) { vehicle in
            AddEditVehicleView(
                vehicleManager: vehicleManager,
                editingVehicle: vehicle,
                onVehicleCreated: nil
            )
        }
        .sheet(isPresented: $showingReminderSheet) {
            if let currentVehicle = vehicleManager.currentVehicle {
                // Always use the same NotificationSettingsSheet, create dummy schedule if needed
                let schedule = streetDataManager.nextUpcomingSchedule ?? UpcomingSchedule(
                    streetName: currentVehicle.parkingLocation?.address ?? "Your Location",
                    date: Date().addingTimeInterval(7 * 24 * 3600), // 1 week from now
                    endDate: Date().addingTimeInterval(7 * 24 * 3600 + 7200), // 2 hours later
                    dayOfWeek: "Next Week",
                    startTime: "8:00 AM",
                    endTime: "10:00 AM"
                )
                NotificationSettingsSheet(
                    schedule: schedule,
                    parkingLocation: currentVehicle.parkingLocation
                )
            }
        }
        .onAppear {
            setupView()
            prepareHaptics()
            setupNotificationHandling()
            NotificationManager.shared.validateAndRecoverNotifications()
            
            // Note: Removed auto-start in location setting mode to avoid forcing users
        }
        .onDisappear {
            cleanupResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OnboardingCompleted"))) { _ in
            setupPermissionsAfterOnboarding()
        }
        .onReceive(locationManager.$userLocation) { userLocation in
            // Center on user location when it becomes available (only if no parking location exists)
            if let userLocation = userLocation {
                // Check if any vehicle has a parking location
                let hasAnyParkingLocation = vehicleManager.activeVehicles.contains { $0.parkingLocation != nil }
                
                // Only center on user location if no vehicles have parking locations
                if !hasAnyParkingLocation {
                    // Just center without dramatic zoom
                    withAnimation(.easeInOut(duration: 0.8)) {
                        mapPosition = .region(
                            MKCoordinateRegion(
                                center: userLocation.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005) // Standard zoom level
                            )
                        )
                    }
                }
            }
        }
        .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Enable notifications to get reminders about street cleaning and avoid parking tickets.")
        }
    }
    
    private var mapView: some View {
        Map(position: $mapPosition, interactionModes: .all) {
            // User location - only show when permission is granted
            if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways,
               let userLocation = locationManager.userLocation {
                Annotation("", coordinate: userLocation.coordinate) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                }
            }
            
            if !isSettingLocation {
                vehicleAnnotations
            }
            
            // User location with direction cone - only show when permission is granted
            if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                userLocationAnnotation
            }
            
            // Street sweeping schedule edge lines (when detected)
            if isSettingLocation && !nearbySchedules.isEmpty {
                streetEdgeScheduleLines
            }
        }
        .overlay(
            Group {
                if isSettingLocation, let vehicle = vehicleManager.selectedVehicle {
                    // Unified location pin with schedule confidence indicator
                    ZStack {
                        VehicleParkingMapMarker(
                            vehicle: vehicle,
                            isSelected: true,
                            onTap: {}
                        )
                        .frame(width: 24, height: 24)
                        .offset(y: -12) // Bottom of marker aligns with map center
                        
                        // Schedule selected glow
                        if !nearbySchedules.isEmpty && hasSelectedSchedule {
                            ZStack {
                                // Outer glow ring
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                                    .frame(width: 36, height: 36)
                                
                                // Main glow ring  
                                Circle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .frame(width: 28, height: 28)
                            }
                            .offset(y: -12) // Match marker position
                            .animation(.easeInOut(duration: 0.3), value: !nearbySchedules.isEmpty)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        )
        .mapStyle(.standard)
        .onMapCameraChange(frequency: .continuous) { context in
            // Track map heading for direction cone with continuous updates
            currentMapHeading = context.camera.heading
            
            if isSettingLocation {
                let newCoordinate = context.camera.centerCoordinate
                settingCoordinate = newCoordinate
                geocodeLocation(newCoordinate)
                
                // Smart selection between existing drawn lines
                smartSelectBetweenDrawnLines(for: newCoordinate)
                
                // Keep original schedule detection for initial discovery
                autoDetectSchedule(for: newCoordinate)
            }
        }
        #if DEBUG
        .onLongPressGesture(minimumDuration: 3.0) {
            OnboardingManager.resetOnboarding()
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
        }
        #endif
    }
    
    // MARK: - User Location Annotation
    
    @MapContentBuilder
    private var userLocationAnnotation: some MapContent {
        if let userLocation = locationManager.userLocation {
            Annotation("", coordinate: userLocation.coordinate) {
                UserDirectionCone(heading: locationManager.userHeading, mapHeading: currentMapHeading)
            }
        }
    }
    
    // MARK: - Vehicle Annotations
    
    @MapContentBuilder
    private var vehicleAnnotations: some MapContent {
        ForEach(vehicleManager.activeVehicles, id: \.id) { vehicle in
            if let parkingLocation = vehicle.parkingLocation {
                Annotation("My Vehicle", coordinate: parkingLocation.coordinate) {
                    VehicleParkingMapMarker(
                        vehicle: vehicle,
                        isSelected: vehicleManager.selectedVehicle?.id == vehicle.id,
                        onTap: {
                            // Center map on vehicle with tighter zoom than target button
                            impactFeedbackLight.impactOccurred()
                            centerMapOnVehicleWithTightZoom(parkingLocation.coordinate)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Street Schedule Lines
    
    @MapContentBuilder
    private var detectedScheduleLines: some MapContent {
        if let schedule = detectedSchedule, let line = schedule.line {
            ForEach(0..<line.coordinates.count-1, id: \.self) { segmentIndex in
                let startCoord = line.coordinates[segmentIndex]
                let endCoord = line.coordinates[segmentIndex + 1]
                
                if startCoord.count >= 2 && endCoord.count >= 2 {
                    MapPolyline(coordinates: [
                        CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0]),
                        CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0])
                    ])
                    .stroke(
                        scheduleConfidence > 0.7 ? Color.green :
                        scheduleConfidence > 0.4 ? Color.orange : Color.red,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
    
    // MARK: - Street Edge Schedule Lines
    
    @MapContentBuilder
    private var streetEdgeScheduleLines: some MapContent {
        ForEach(Array(nearbySchedules.enumerated()), id: \.0) { index, scheduleWithSide in
            if let line = scheduleWithSide.schedule.line {
                // Create street-edge parking lines that are tappable
                ForEach(0..<line.coordinates.count-1, id: \.self) { segmentIndex in
                    let startCoord = line.coordinates[segmentIndex]
                    let endCoord = line.coordinates[segmentIndex + 1]
                    
                    if startCoord.count >= 2 && endCoord.count >= 2 {
                        let streetEdgeCoords = calculateStreetEdgeCoordinates(
                            start: CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0]),
                            end: CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0]),
                            blockSide: scheduleWithSide.side
                        )
                        
                        // Main parking zone line
                        MapPolyline(coordinates: streetEdgeCoords)
                            .stroke(
                                (index == selectedScheduleIndex && hasSelectedSchedule) ? Color.blue : Color.secondary.opacity(0.4),
                                style: StrokeStyle(
                                    lineWidth: (index == selectedScheduleIndex && hasSelectedSchedule) ? 8 : 6,
                                    lineCap: .round, 
                                    lineJoin: .round
                                )
                            )
                        
                        // Add multiple invisible tap areas along the line for easier tapping
                        ForEach(0..<min(streetEdgeCoords.count, 5), id: \.self) { tapIndex in
                            let coordIndex = (streetEdgeCoords.count - 1) * tapIndex / max(1, 4) // Distribute evenly
                            Annotation("", coordinate: streetEdgeCoords[coordIndex]) {
                                Button(action: {
                                    impactFeedbackLight.impactOccurred()
                                    selectScheduleOption(index)
                                }) {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: 100, height: 40) // Much larger tap area
                                }
                            }
                        }
                        
                        // Elegant selection indicator with subtle glow
                        if index == selectedScheduleIndex && hasSelectedSchedule {
                            MapPolyline(coordinates: streetEdgeCoords)
                                .stroke(
                                    Color.blue.opacity(0.3),
                                    style: StrokeStyle(
                                        lineWidth: 16,
                                        lineCap: .round, 
                                        lineJoin: .round
                                    )
                                )
                        }
                    }
                }
            }
        }
    }
    
    // Calculate street edge coordinates based on block side
    private func calculateStreetEdgeCoordinates(
        start: CLLocationCoordinate2D, 
        end: CLLocationCoordinate2D, 
        blockSide: String
    ) -> [CLLocationCoordinate2D] {
        
        // Calculate the street direction vector
        let streetVector = (
            longitude: end.longitude - start.longitude,
            latitude: end.latitude - start.latitude
        )
        
        // Calculate perpendicular vector (rotate 90 degrees)
        let perpVector = (
            longitude: -streetVector.latitude,
            latitude: streetVector.longitude
        )
        
        // Normalize the perpendicular vector
        let perpLength = sqrt(perpVector.longitude * perpVector.longitude + perpVector.latitude * perpVector.latitude)
        guard perpLength > 0 else { return [start, end] }
        
        let normalizedPerp = (
            longitude: perpVector.longitude / perpLength,
            latitude: perpVector.latitude / perpLength
        )
        
        // Determine offset direction and distance based on block side
        let (offsetDirection, offsetDistance) = getStreetEdgeOffset(blockSide: blockSide)
        
        // Apply offset to both start and end points to create parking edge line
        let offsetStart = CLLocationCoordinate2D(
            latitude: start.latitude + (normalizedPerp.latitude * offsetDistance * offsetDirection),
            longitude: start.longitude + (normalizedPerp.longitude * offsetDistance * offsetDirection)
        )
        
        let offsetEnd = CLLocationCoordinate2D(
            latitude: end.latitude + (normalizedPerp.latitude * offsetDistance * offsetDirection),
            longitude: end.longitude + (normalizedPerp.longitude * offsetDistance * offsetDirection)
        )
        
        return [offsetStart, offsetEnd]
    }
    
    // Get proper street edge offset for realistic parking zone positioning
    private func getStreetEdgeOffset(blockSide: String) -> (direction: Double, distance: Double) {
        let side = blockSide.lowercased()
        
        // Street parking is typically 8-12 feet from the center line
        // Using coordinate degrees: roughly 0.00003 = ~10 feet
        let parkingLaneOffset = 0.00003
        
        // Determine which side of the street the parking is on
        // NOTE: The perpendicular vector calculation rotates 90 degrees counterclockwise
        // So we need to flip the direction to get the correct side
        if side.contains("north") || side.contains("northeast") || side.contains("northwest") {
            return (-1.0, parkingLaneOffset)  // North side - negative offset (flipped)
        } else if side.contains("south") || side.contains("southeast") || side.contains("southwest") {
            return (1.0, parkingLaneOffset) // South side - positive offset (flipped)
        } else if side.contains("east") {
            return (-1.0, parkingLaneOffset)   // East side - negative offset (flipped)
        } else if side.contains("west") {
            return (1.0, parkingLaneOffset)  // West side - positive offset (flipped)
        } else {
            // Default: slight offset to distinguish from street center
            return (1.0, parkingLaneOffset * 0.5)
        }
    }
    
    // Calculate midpoint of a line for annotation placement
    private func calculateMidpoint(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !coordinates.isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        
        if coordinates.count == 2 {
            let lat = (coordinates[0].latitude + coordinates[1].latitude) / 2
            let lon = (coordinates[0].longitude + coordinates[1].longitude) / 2
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        // For multiple coordinates, return the middle one
        let midIndex = coordinates.count / 2
        return coordinates[midIndex]
    }
    
    // MARK: - Top Controls
    
    private var topControls: some View {
        HStack {
            if vehicleManager.activeVehicles.isEmpty {
                // Add vehicle button when there are no vehicles
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    // In single-vehicle mode, edit the existing vehicle instead of adding
                    if let currentVehicle = vehicleManager.currentVehicle {
                        showingEditVehicle = currentVehicle
                    } else {
                        showingAddVehicle = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text("Add Vehicle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    // MARK: - Bottom Interface
    
    private var bottomInterface: some View {
        VStack(spacing: 0) {
            // Unified interface - handles both location setting and normal modes
            enhancedNormalVehicleInterface()
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
        )
    }
    
    // MARK: - Enhanced Vehicle Actions Interface
    // Removed enhancedVehicleActionsInterface - vehicle tap now just centers map
    
    // MARK: - Helper function to open vehicle in Maps
    private func openVehicleInMaps(_ vehicle: Vehicle) {
        guard let parkingLocation = vehicle.parkingLocation else { 
            // Provide haptic feedback when no parking location is set
            impactFeedbackLight.impactOccurred()
            return 
        }
        
        // Haptic feedback for successful action
        impactFeedbackLight.prepare()
        impactFeedbackLight.impactOccurred()
        
        let coordinate = parkingLocation.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Parking Location"
        
        // Open in Maps without starting navigation - just show the pin
        mapItem.openInMaps(launchOptions: [:])
    }
    
    private func shareParkingLocation(_ parkingLocation: ParkingLocation) {
        // Create a shareable link for Apple Maps
        let coordinate = parkingLocation.coordinate
        let mapLink = "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=Parking%20Location"
        
        // Create share items - just the link, no text
        let shareItems: [Any] = [
            URL(string: mapLink)!
        ]
        
        // Present share sheet
        let activityViewController = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
        
        // Get the current window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // For iPad, set the popover presentation
            if let popover = activityViewController.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootViewController.present(activityViewController, animated: true)
        }
    }
    
    
    // MARK: - Detected Schedule Card
    private func detectedScheduleCard(_ schedule: SweepSchedule) -> some View {
        let confidenceColor = scheduleConfidence > 0.7 ? Color.green : scheduleConfidence > 0.4 ? Color.orange : Color.red
        let confidenceText = scheduleConfidence > 0.7 ? "High Confidence" : scheduleConfidence > 0.4 ? "Medium Confidence" : "Low Confidence"
        let (timeUntil, nextDate) = calculateTimeUntilNextCleaning(schedule: schedule)
        
        return VStack(spacing: 16) {
            // Header with animated icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(confidenceColor.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(confidenceColor)
                }
                .scaleEffect(scheduleConfidence > 0.7 ? 1.1 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: scheduleConfidence)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Street Cleaning \(timeUntil)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if let nextDate = nextDate {
                        Text(formatFullDateTime(nextDate))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Subtle confidence badge
                Text(confidenceText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(confidenceColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(confidenceColor.opacity(0.15))
                    )
            }
            
            // Main alert content
            VStack(spacing: 16) {
                // Street name and location  
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(confidenceColor)
                    
                    Text(schedule.streetName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Day badge
                    Text(schedule.sweepDay)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(confidenceColor)
                        )
                }
                
                // Time range display
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Range")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 14))
                                .foregroundColor(confidenceColor)
                            
                            Text("\(schedule.startTime) - \(schedule.endTime)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    // Prominent warning
                    VStack(spacing: 2) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                        Text("NO PARKING")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color.red, Color.red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6).opacity(0.5))
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [confidenceColor.opacity(0.4), confidenceColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(
                    color: confidenceColor.opacity(0.2),
                    radius: 12,
                    x: 0,
                    y: 4
                )
        )
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: schedule.cnn)
    }
    
    // MARK: - Enhanced Normal Vehicle Interface
    private func enhancedNormalVehicleInterface() -> some View {
        VStack(spacing: 0) {
            if !vehicleManager.activeVehicles.isEmpty {
                // Show upcoming reminders for current vehicle - only when NOT setting location
                if !isSettingLocation,
                   let currentVehicle = vehicleManager.currentVehicle,
                   let parkingLocation = currentVehicle.parkingLocation {
                    UpcomingRemindersSection(
                        streetDataManager: streetDataManager,
                        parkingLocation: parkingLocation
                    )
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                }
                
                // Unified content container
                unifiedContentContainer()
                
            } else {
                // Enhanced empty state
                enhancedEmptyStateInterface()
            }
        }
    }
    
    // MARK: - Unified Content Container
    private func unifiedContentContainer() -> some View {
        VStack(spacing: 0) {
            // Header section with conditional top padding
            HStack {
                Text(isSettingLocation ? "Move Vehicle" : "My Vehicle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.top, 6) // Consistent padding for both modes
                
                Spacer()
                
                if isSettingLocation {
                    HStack(spacing: 12) {
                        // Move To Me / Enable Location button
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                                centerMapOnUserLocation()
                            } else {
                                handleLocationPermission()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: (locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways) ? "location.fill" : "location")
                                    .font(.system(size: 14, weight: .medium))
                                Text((locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways) ? "Move To Me" : "Enable Location")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue)
                            )
                        }
                        
                        if isAutoDetectingSchedule {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.blue)
                        }
                    }
                } else {
                    // Reminders button - show when vehicle exists regardless of parking location
                    if let currentVehicle = vehicleManager.currentVehicle {
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            showingReminderSheet = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Reminders")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray6))
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // Cards section - EXACT same structure as SwipeableVehicleSection
            VStack(spacing: 0) {
                if isSettingLocation {
                    // Location setting cards - match SwipeableVehicleSection structure exactly
                    // Fixed height container for ALL middle views
                    ZStack {
                        if nearbySchedules.isEmpty {
                            // No schedules state - wrapped in consistent container
                            VStack(spacing: 0) {
                                VStack(spacing: 12) {
                                    HStack(spacing: 12) {
                                        // Icon with same structure as vehicle icon
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            settingAddress != nil ? Color.green : Color.blue.opacity(0.7),
                                                            settingAddress != nil ? Color.green.opacity(0.8) : Color.blue.opacity(0.5)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 40, height: 40)
                                            
                                            Image(systemName: settingAddress != nil ? "checkmark" : "location")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        .shadow(color: (settingAddress != nil ? Color.green : Color.blue).opacity(0.3), radius: 4, x: 0, y: 2)
                                        
                                        // Text with same structure as vehicle info
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(settingAddress != nil ? "No parking restrictions" : "Move map to check area")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                                .lineLimit(2)
                                            
                                            Text(settingAddress != nil ? "Safe to park here" : "Position to detect schedule")
                                                .font(.caption)
                                                .foregroundColor(.secondary) // Changed from .blue to .secondary
                                        }
                                        
                                        Spacer()
                                    }
                                }
                                .padding(20)  // Same as VehicleSwipeCard
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(
                                            color: settingAddress != nil ? Color.green.opacity(0.2) : Color.black.opacity(0.08),
                                            radius: settingAddress != nil ? 6 : 3,
                                            x: 0,
                                            y: settingAddress != nil ? 3 : 1
                                        )
                                )
                                .padding(.horizontal, 4)  // Same as VehicleSwipeCard
                                .padding(.vertical, 2)    // Same as VehicleSwipeCard
                            }
                            .padding(.horizontal, 16) // Same as schedule cards
                            .padding(.bottom, 12)     // Same as schedule cards
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        } else {
                            // Schedule selection cards - elegant style with no left padding
                            VStack(spacing: 0) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(nearbySchedules.enumerated()), id: \.0) { index, scheduleWithSide in
                                            scheduleSelectionCard(scheduleWithSide, index: index)
                                        }
                                    }
                                    .padding(.leading, 4) // Align with title (20pt title padding - 16pt scroll padding = 4pt)
                                    .padding(.trailing, 20) // Right padding for scroll
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            ))
                        }
                    }
                    .frame(minHeight: 100) // Flexible height for Move Vehicle mode
                } else {
                    // Vehicle card section - ALSO fixed height
                    ZStack {
                        SwipeableVehicleSection(
                            vehicles: vehicleManager.activeVehicles,
                            selectedVehicle: vehicleManager.currentVehicle,
                            onVehicleSelected: { vehicle in
                                // In single-vehicle mode, do nothing since there's only one vehicle
                            },
                            onVehicleTap: { vehicle in
                                if vehicle.parkingLocation != nil {
                                    // Open vehicle location in Maps
                                    openVehicleInMaps(vehicle)
                                } else {
                                    // Start location setting if no parking location
                                    impactFeedbackLight.impactOccurred()
                                    isSettingLocationForNewVehicle = false
                                    startSettingLocationForVehicle(vehicle)
                                }
                            },
                            onShareLocation: shareParkingLocation
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                    }
                    .frame(minHeight: 100) // Flexible height to accommodate extra spacing
                }
            }
            .padding(.vertical, 4) // Further reduced spacing above and below cards
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isSettingLocation)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: nearbySchedules.isEmpty)
            
            // Bottom buttons section - consistent spacing
            VStack(spacing: 0) {
                if isSettingLocation {
                    // Location setting buttons
                    HStack(spacing: 12) {
                        // Cancel/Set Later button
                        if vehicleManager.currentVehicle?.parkingLocation != nil || isSettingLocationForNewVehicle || vehicleManager.currentVehicle?.parkingLocation == nil {
                            Button(action: {
                                impactFeedbackLight.impactOccurred()
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    cancelSettingLocation()
                                }
                            }) {
                                Text(isSettingLocationForNewVehicle || vehicleManager.currentVehicle?.parkingLocation == nil ? "Set Later" : "Cancel")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color(.systemGray6))
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Confirm button
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                confirmUnifiedLocation()
                            }
                        }) {
                            Text("Confirm")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(settingAddress == nil)
                        .opacity(settingAddress == nil ? 0.6 : 1.0)
                    }
                } else {
                    // Move Vehicle button - full width with consistent height
                    if let currentVehicle = vehicleManager.currentVehicle {
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            isSettingLocationForNewVehicle = false
                            startSettingLocationForVehicle(currentVehicle)
                        }) {
                            Text("Move Vehicle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
    
    private func enhancedEmptyStateInterface() -> some View {
        VStack(spacing: 0) {
            // Empty state content
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(.systemGray5), Color(.systemGray6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "car.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Vehicles Yet")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Add a vehicle to track parking and get cleaning reminders.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            
            // Enhanced add vehicle button
            Button(action: {
                impactFeedbackLight.impactOccurred()
                // In single-vehicle mode, should not reach here since currentVehicle should exist
                showingAddVehicle = true
            }) {
                HStack(spacing: 10) {
                    Text("Add Vehicle")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Enhanced Vehicle List Sheet
    
    private var vehicleListSheet: some View {
        VStack(spacing: 0) {
            // Enhanced header
            HStack {
                Text("My Vehicles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button("Done") {
                    impactFeedbackLight.impactOccurred()
                    showingVehiclesList = false
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            
            Divider()
            
            // Enhanced vehicles list
            if vehicleManager.activeVehicles.isEmpty {
                enhancedEmptyStateInterface()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vehicleManager.activeVehicles) { vehicle in
                            EnhancedVehicleListRow(
                                vehicle: vehicle,
                                isSelected: vehicleManager.selectedVehicle?.id == vehicle.id,
                                onTap: {
                                    impactFeedbackLight.impactOccurred()
                                    selectVehicle(vehicle)
                                    showingVehiclesList = false
                                },
                                onEdit: {
                                    impactFeedbackLight.impactOccurred()
                                    showingEditVehicle = vehicle
                                },
                                onSetLocation: {
                                    impactFeedbackLight.impactOccurred()
                                    isSettingLocationForNewVehicle = false
                                    startSettingLocationForVehicle(vehicle)
                                    showingVehiclesList = false
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                
                // Not used in single-vehicle mode
            }
        }
    }
    
    // MARK: - Methods (keeping existing functionality)
    
    private func selectVehicle(_ vehicle: Vehicle) {
        impactFeedbackLight.impactOccurred()
        vehicleManager.selectVehicle(vehicle)
        
        if let parkingLocation = vehicle.parkingLocation {
            centerMapOnLocation(parkingLocation.coordinate)
            // Load persisted schedule if available, otherwise fetch new data
            if let persistedSchedule = parkingLocation.selectedSchedule {
                let schedule = StreetDataService.shared.convertToSweepSchedule(from: persistedSchedule)
                streetDataManager.schedule = schedule
                streetDataManager.processNextSchedule(for: schedule)
                print("🎯 Loaded persisted schedule: \(schedule.streetName) (\(persistedSchedule.blockSide))")
            } else if streetDataManager.schedule == nil {
                fetchStreetDataAndScheduleNotifications(for: parkingLocation)
            }
        }
    }
    
    // Removed showVehicleActions - vehicle tap now just centers map
    
    private func centerMapOnVehicle(_ vehicle: Vehicle) {
        guard let parkingLocation = vehicle.parkingLocation else { return }
        centerMapOnLocation(parkingLocation.coordinate)
    }
    
    private func centerMapOnLocation(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            )
        }
    }
    
    private func centerMapOnLocationWithoutZoom(_ coordinate: CLLocationCoordinate2D) {
        // Just center without changing zoom - use the same function but shorter animation
        withAnimation(.easeInOut(duration: 0.6)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005) // Standard zoom
                )
            )
        }
    }
    
    private func centerMapOnLocationWithoutAnyZoomChange(_ coordinate: CLLocationCoordinate2D) {
        // Only center, don't change zoom level at all
        withAnimation(.easeInOut(duration: 0.6)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: mapPosition.region?.span ?? MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            )
        }
    }
    
    private func centerMapOnLocationForVehicleMove(_ coordinate: CLLocationCoordinate2D) {
        // Focused zoom specifically for moving vehicles - street-level view
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005) // Standard zoom
                )
            )
        }
    }
    
    private func centerMapOnVehicles() {
        let parkedVehicles = vehicleManager.activeVehicles.compactMap { vehicle in
            vehicle.parkingLocation?.coordinate
        }
        
        guard !parkedVehicles.isEmpty else { return }
        
        if parkedVehicles.count == 1 {
            centerMapOnLocation(parkedVehicles[0])
            return
        }
        
        // Calculate region that includes all parked vehicles
        let minLat = parkedVehicles.map { $0.latitude }.min() ?? 37.7749
        let maxLat = parkedVehicles.map { $0.latitude }.max() ?? 37.7749
        let minLon = parkedVehicles.map { $0.longitude }.min() ?? -122.4194
        let maxLon = parkedVehicles.map { $0.longitude }.max() ?? -122.4194
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latDelta = max((maxLat - minLat) * 1.3, 0.01)
        let lonDelta = max((maxLon - minLon) * 1.3, 0.01)
        
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                )
            )
        }
    }
    
    private func centerMapOnVehiclesWithConsistentZoom() {
        let parkedVehicles = vehicleManager.activeVehicles.compactMap { vehicle in
            vehicle.parkingLocation?.coordinate
        }
        
        guard !parkedVehicles.isEmpty else { return }
        
        // Always use consistent tight zoom for parking locations
        let targetCoordinate = parkedVehicles.first!
        
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: targetCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005) // Standard zoom
                )
            )
        }
    }
    
    private func centerMapOnVehicleWithTightZoom(_ coordinate: CLLocationCoordinate2D) {
        // Tighter zoom than target button for individual vehicle focus
        withAnimation(.easeInOut(duration: 0.6)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005) // Standard zoom
                )
            )
        }
    }
    
    private func startSettingLocationForVehicle(_ vehicle: Vehicle) {
        vehicleManager.selectVehicle(vehicle)
        startSettingLocation()
    }
    
    private func startSettingLocation() {
        impactFeedbackLight.impactOccurred()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isSettingLocation = true
        }
        
        // Prioritize current vehicle parking location when moving a vehicle
        let startCoordinate: CLLocationCoordinate2D
        if let selectedVehicle = vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
            // Moving existing vehicle - start from current parking location
            startCoordinate = parkingLocation.coordinate
            centerMapOnLocationForVehicleMove(startCoordinate)
        } else if let userLocation = locationManager.userLocation {
            // New vehicle or no current location - start from user
            startCoordinate = userLocation.coordinate
            centerMapOnLocation(startCoordinate)
        } else {
            // Fallback to San Francisco city center
            startCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            centerMapOnLocation(startCoordinate)
        }
        
        settingCoordinate = startCoordinate
        geocodeLocation(startCoordinate)
        
        // Trigger initial schedule detection
        autoDetectSchedule(for: startCoordinate)
    }
    
    private func cancelSettingLocation() {
        impactFeedbackLight.impactOccurred()
        completeUnifiedLocationSetting()
    }
    
    
    private func geocodeLocation(_ coordinate: CLLocationCoordinate2D) {
        debouncedGeocoder.reverseGeocode(coordinate: coordinate) { address, _ in
            DispatchQueue.main.async {
                self.settingAddress = address
            }
        }
    }
    
    // MARK: - Unified Location Setting Functions
    
    private func autoDetectSchedule(for coordinate: CLLocationCoordinate2D) {
        // Check if we need to skip this detection (debouncing)
        if let lastCoordinate = lastDetectionCoordinate {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude))
            
            // Only detect if we've moved more than 10 meters
            if distance < 10 {
                return
            }
        }
        
        // Cancel any existing timer
        detectionDebounceTimer?.invalidate()
        
        // Start new detection timer
        detectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            self.performScheduleDetection(for: coordinate)
        }
    }
    
    private func performScheduleDetection(for coordinate: CLLocationCoordinate2D) {
        guard !isAutoDetectingSchedule else { return }
        
        isAutoDetectingSchedule = true
        lastDetectionCoordinate = coordinate
        
        print("🔍 Detecting schedule at: \(coordinate.latitude), \(coordinate.longitude)")
        
        StreetDataService.shared.getNearbySchedulesForSelection(for: coordinate) { result in
            DispatchQueue.main.async {
                self.isAutoDetectingSchedule = false
                
                switch result {
                case .success(let schedulesWithSides):
                    if !schedulesWithSides.isEmpty {
                        print("🎯 Found \(schedulesWithSides.count) nearby schedules")
                        self.nearbySchedules = schedulesWithSides
                        
                        // Use smart selection to pick the closest schedule and provide haptic feedback
                        self.initialSmartSelection(for: coordinate, schedulesWithSides: schedulesWithSides)
                    } else {
                        print("⚠️ No schedules found at coordinate: \(coordinate)")
                        self.nearbySchedules = []
                        self.selectedScheduleIndex = 0
                        self.detectedSchedule = nil
                        self.scheduleConfidence = 0.0
                    }
                case .failure(let error):
                    print("❌ Schedule detection failed: \(error)")
                    self.nearbySchedules = []
                    self.selectedScheduleIndex = 0
                    self.detectedSchedule = nil
                    self.scheduleConfidence = 0.0
                }
            }
        }
    }
    
    
    private func confirmUnifiedLocation() {
        guard let selectedVehicle = vehicleManager.selectedVehicle,
              let address = settingAddress else { return }
        
        // Create persisted schedule if user selected one
        let persistedSchedule = (!nearbySchedules.isEmpty && hasSelectedSchedule) ? 
            PersistedSweepSchedule(from: nearbySchedules[selectedScheduleIndex].schedule, side: nearbySchedules[selectedScheduleIndex].side) :
            nil
        
        vehicleManager.setManualParkingLocation(
            for: selectedVehicle,
            coordinate: settingCoordinate,
            address: address,
            selectedSchedule: persistedSchedule
        )
        
        // Use the user's selected schedule for notifications
        if !nearbySchedules.isEmpty && hasSelectedSchedule {
            let selectedSchedule = nearbySchedules[selectedScheduleIndex].schedule
            streetDataManager.schedule = selectedSchedule
            streetDataManager.processNextSchedule(for: selectedSchedule)
            print("🎯 Using user-selected schedule: \(selectedSchedule.streetName) (\(nearbySchedules[selectedScheduleIndex].side))")
        } else {
            // No schedule selected or no schedules detected - clear the street data manager
            streetDataManager.schedule = nil
            streetDataManager.nextUpcomingSchedule = nil
            print("🟢 No restrictions - clearing upcoming reminders")
        }
        
        // Complete location setting (this clears detected schedules)
        completeUnifiedLocationSetting()
        
        // Don't fetch fresh street data since we're using the user's explicit selection or lack thereof
        // The upcoming reminders will use the schedule we just set above (or nil for no restrictions)
    }
    
    private func completeUnifiedLocationSetting() {
        isSettingLocation = false
        isSettingLocationForNewVehicle = false
        settingAddress = nil
        detectedSchedule = nil
        scheduleConfidence = 0.0
        isAutoDetectingSchedule = false
        lastDetectionCoordinate = nil
        detectionDebounceTimer?.invalidate()
        detectionDebounceTimer = nil
        
        // Clear side-of-street selection
        nearbySchedules = []
        selectedScheduleIndex = 0
        showingScheduleSelection = false
    }
    
    // MARK: - Time Calculation
    private func calculateTimeUntilNextCleaning(schedule: SweepSchedule) -> (String, Date?) {
        let now = Date()
        let calendar = Calendar.current
        
        guard let weekdayStr = schedule.weekday,
              let fromHourStr = schedule.fromhour,
              let toHourStr = schedule.tohour,
              let fromHour = Int(fromHourStr),
              let toHour = Int(toHourStr) else {
            return ("Unknown", nil)
        }
        
        let targetWeekday = dayStringToWeekday(weekdayStr)
        guard targetWeekday > 0 else { return ("Unknown", nil) }
        
        // Find next valid occurrence based on week pattern
        let nextOccurrence = findNextValidOccurrence(
            targetWeekday: targetWeekday,
            schedule: schedule,
            from: now
        )
        
        guard let nextDate = nextOccurrence,
              let cleaningStart = calendar.date(bySettingHour: fromHour, minute: 0, second: 0, of: nextDate),
              let _ = calendar.date(bySettingHour: toHour, minute: 0, second: 0, of: nextDate) else {
            return ("Unknown", nil)
        }
        
        let timeInterval = cleaningStart.timeIntervalSince(now)
        let timeUntilText = formatTimeUntil(timeInterval)
        
        return (timeUntilText, cleaningStart)
    }
    
    private func findNextValidOccurrence(targetWeekday: Int, schedule: SweepSchedule, from date: Date) -> Date? {
        let calendar = Calendar.current
        
        // Check next 8 weeks to find a valid occurrence
        for weekOffset in 0..<8 {
            guard let futureDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: date) else { continue }
            
            let targetDate = nextOccurrence(of: targetWeekday, from: futureDate, allowSameDay: weekOffset == 0)
            let weekOfMonth = calendar.component(.weekOfMonth, from: targetDate)
            
            let appliesThisWeek: Bool
            switch weekOfMonth {
            case 1: appliesThisWeek = schedule.week1 == "1"
            case 2: appliesThisWeek = schedule.week2 == "1"
            case 3: appliesThisWeek = schedule.week3 == "1"
            case 4: appliesThisWeek = schedule.week4 == "1"
            case 5: appliesThisWeek = schedule.week5 == "1"
            default: appliesThisWeek = false
            }
            
            if appliesThisWeek {
                return targetDate
            }
        }
        
        return nil
    }
    
    private func nextOccurrence(of weekday: Int, from date: Date, allowSameDay: Bool = false) -> Date {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        
        var daysToAdd = weekday - currentWeekday
        
        if daysToAdd < 0 || (daysToAdd == 0 && !allowSameDay) {
            daysToAdd += 7
        }
        
        return calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
    }
    
    private func dayStringToWeekday(_ dayString: String) -> Int {
        let normalized = dayString.lowercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "sun", "sunday": return 1
        case "mon", "monday": return 2
        case "tue", "tues", "tuesday": return 3
        case "wed", "wednesday": return 4
        case "thu", "thur", "thursday": return 5
        case "fri", "friday": return 6
        case "sat", "saturday": return 7
        default: return 0
        }
    }
    
    private func formatTimeUntil(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        
        // Handle past/current times
        if totalSeconds <= 0 {
            return "happening now"
        }
        
        // Handle very soon (under 2 minutes)
        if totalSeconds < 120 {
            if totalSeconds < 60 {
                return "in under 1 minute"
            } else {
                return "in 1 minute"
            }
        }
        
        let minutes = totalSeconds / 60
        let hours = minutes / 60  
        let days = hours / 24
        let remainingHours = hours % 24
        let remainingMinutes = minutes % 60
        
        // Under 1 hour - show minutes
        if hours < 1 {
            return "in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        
        // Under 12 hours - show hours and be precise
        if hours < 12 {
            if remainingMinutes < 10 {
                return "in \(hours) hour\(hours == 1 ? "" : "s")"
            } else if remainingMinutes < 40 {
                return "in \(hours)½ hours"
            } else {
                return "in \(hours + 1) hours"
            }
        }
        
        // 12-36 hours - special handling for "tomorrow"
        if hours >= 12 && hours < 36 {
            // Check if it's actually tomorrow
            let calendar = Calendar.current
            let targetDate = Date().addingTimeInterval(timeInterval)
            if calendar.isDateInTomorrow(targetDate) {
                return "tomorrow"
            } else if hours < 24 {
                return "in \(hours) hours"
            }
        }
        
        // 1.5 - 2.5 days - be more precise
        if hours >= 36 && hours < 60 {
            // Round to nearest half day
            if remainingHours < 6 {
                return "in \(days) day\(days == 1 ? "" : "s")"
            } else if remainingHours < 18 {
                return "in \(days)½ days"
            } else {
                return "in \(days + 1) days"
            }
        }
        
        // 2.5 - 6.5 days - round to nearest day
        if days >= 2 && days < 7 {
            if remainingHours < 12 {
                return "in \(days) days"
            } else {
                return "in \(days + 1) days"
            }
        }
        
        // 1-3 weeks
        let weeks = days / 7
        if weeks < 4 {
            let remainingDays = days % 7
            if weeks == 1 && remainingDays <= 1 {
                return "in 1 week"
            } else if remainingDays == 0 {
                return "in \(weeks) week\(weeks == 1 ? "" : "s")"
            } else if remainingDays <= 2 {
                return "in \(weeks) week\(weeks == 1 ? "" : "s")"
            } else {
                return "in \(weeks + 1) weeks"
            }
        }
        
        // 1+ months
        let months = days / 30
        if months < 12 {
            return "in \(months) month\(months == 1 ? "" : "s")"
        }
        
        // 1+ years
        let years = days / 365
        return "in \(years) year\(years == 1 ? "" : "s")"
    }
    
    private func formatFullDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        let isToday = calendar.isDateInToday(date)
        let isTomorrow = calendar.isDateInTomorrow(date)
        let isThisWeek = calendar.component(.weekOfYear, from: date) == calendar.component(.weekOfYear, from: Date())
        
        if isToday {
            formatter.dateFormat = "'Today,' h:mm a"
        } else if isTomorrow {
            formatter.dateFormat = "'Tomorrow,' h:mm a"  
        } else if isThisWeek {
            formatter.dateFormat = "EEEE, h:mm a"
        } else {
            formatter.dateFormat = "EEE, MMM d, h:mm a"
        }
        
        return formatter.string(from: date)
    }
    
    
    // MARK: - Setup and Lifecycle
    
    private func setupView() {
        // Note: Removed automatic location permission request - users can use the button
        
        // Note: Removed auto-start in location setting mode to avoid forcing users
        
        // Center map in priority order: 1) parking location 2) user location 3) Sutro Tower
        if let selectedVehicle = vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
            // Priority 1: Center on parking location
            centerMapOnLocation(parkingLocation.coordinate)
            // Load persisted schedule if available, otherwise fetch new data
            if let persistedSchedule = parkingLocation.selectedSchedule {
                let schedule = StreetDataService.shared.convertToSweepSchedule(from: persistedSchedule)
                streetDataManager.schedule = schedule
                streetDataManager.processNextSchedule(for: schedule)
                print("🎯 Setup loaded persisted schedule: \(schedule.streetName) (\(persistedSchedule.blockSide))")
            } else if streetDataManager.schedule == nil {
                fetchStreetDataAndScheduleNotifications(for: parkingLocation)
            }
        } else if let userLocation = locationManager.userLocation {
            // Priority 2: Center on user location if no parking location
            centerMapOnUserLocation()
        } else {
            // Priority 3: Center on Sutro Tower with beautiful city view
            centerMapOnSutroTower()
        }
    }
    
    private func setupPermissionsAfterOnboarding() {
        // Note: Removed automatic location permission request after onboarding
        // Users can manually request location via the map button if needed
    }
    
    private func handleLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Request location permission
            locationManager.requestLocationPermission()
        case .denied, .restricted:
            // Open Settings app for user to manually enable location
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        default:
            break
        }
    }
    
    private func centerMapOnSutroTower() {
        // Beautiful framed view of San Francisco from Sutro Tower
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7551, longitude: -122.4528), // Sutro Tower
                    span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18) // More zoomed out city view
                )
            )
        }
    }
    
    private func centerMapOnUserLocation() {
        guard let userLocation = locationManager.userLocation else { 
            // Fall back to Sutro Tower if user location not available
            centerMapOnSutroTower()
            return 
        }
        
        let userHeading = locationManager.userHeading
        
        // Simple: Just center on user location with rotation
        settingCoordinate = userLocation.coordinate
        geocodeLocation(userLocation.coordinate)
        
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .camera(
                MapCamera(
                    centerCoordinate: userLocation.coordinate,
                    distance: 500, // Moderately closer for Move To Me but not jarring
                    heading: userHeading,
                    pitch: 0
                )
            )
        }
    }
    
    private func findNearestStreetInBackground(userLocation: CLLocationCoordinate2D, userHeading: CLLocationDirection) {
        // Background search - don't block UI, automatically move when found
        StreetDataService.shared.getNearbySchedulesForSelection(for: userLocation) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let schedulesWithSides):
                    if !schedulesWithSides.isEmpty {
                        // Found nearby streets - smoothly transition to the closest one
                        print("🎯 Found \(schedulesWithSides.count) nearby streets, auto-moving to closest")
                        self.autoMoveToNearestStreet(schedulesWithSides: schedulesWithSides, userHeading: userHeading)
                        return
                    }
                    
                    // No streets in normal range, try expanded search
                    print("🔍 No streets found in normal range, expanding search...")
                    self.findClosestStreetInExpandedArea(userLocation: userLocation, userHeading: userHeading)
                    
                case .failure:
                    // Error - try expanded search as fallback
                    self.findClosestStreetInExpandedArea(userLocation: userLocation, userHeading: userHeading)
                }
            }
        }
    }
    
    private func findClosestStreetInExpandedArea(userLocation: CLLocationCoordinate2D, userHeading: CLLocationDirection) {
        // Use the area schedules method which has a larger radius (5 grid cells ~= 200ft)
        StreetDataService.shared.getSchedulesInArea(for: userLocation) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let areaSchedules):
                    if !areaSchedules.isEmpty {
                        // Convert to schedules with sides format for consistency
                        let schedulesWithSides = self.convertToSchedulesWithSides(schedules: areaSchedules, fromLocation: userLocation)
                        
                        if !schedulesWithSides.isEmpty {
                            print("🎯 Found \(schedulesWithSides.count) streets in expanded area")
                            self.autoMoveToNearestStreet(schedulesWithSides: schedulesWithSides, userHeading: userHeading)
                            return
                        }
                    }
                    
                    // Still no streets found - fallback to user location
                    print("⚠️ No streets found even in expanded area")
                    self.centerMapOnLocationForVehicleMove(userLocation)
                    self.settingCoordinate = userLocation
                    self.geocodeLocation(userLocation)
                    
                case .failure:
                    // Error - fallback to user location
                    self.centerMapOnLocationForVehicleMove(userLocation)
                    self.settingCoordinate = userLocation
                    self.geocodeLocation(userLocation)
                }
            }
        }
    }
    
    private func convertToSchedulesWithSides(schedules: [SweepSchedule], fromLocation: CLLocationCoordinate2D) -> [SweepScheduleWithSide] {
        var schedulesWithSides: [SweepScheduleWithSide] = []
        
        for schedule in schedules {
            guard let line = schedule.line, !line.coordinates.isEmpty else { continue }
            
            // Find closest point on this schedule's line
            var closestPoint = CLLocationCoordinate2D(latitude: line.coordinates[0][1], longitude: line.coordinates[0][0])
            var minDistance = Double.infinity
            
            for i in 0..<(line.coordinates.count - 1) {
                let start = CLLocationCoordinate2D(latitude: line.coordinates[i][1], longitude: line.coordinates[i][0])
                let end = CLLocationCoordinate2D(latitude: line.coordinates[i+1][1], longitude: line.coordinates[i+1][0])
                
                let segment = LineSegment(start: start, end: end)
                let (point, distance) = segment.closestPoint(to: fromLocation)
                
                if distance < minDistance {
                    minDistance = distance
                    closestPoint = point
                }
            }
            
            // Create a schedule with side (using the street line coordinate)
            let scheduleWithSide = SweepScheduleWithSide(
                schedule: schedule,
                offsetCoordinate: closestPoint, side: "Center", // We'll place on center line
                distance: minDistance
            )
            
            schedulesWithSides.append(scheduleWithSide)
        }
        
        // Sort by distance
        return schedulesWithSides.sorted { $0.distance < $1.distance }
    }
    
    private func autoMoveToNearestStreet(schedulesWithSides: [SweepScheduleWithSide], userHeading: CLLocationDirection) {
        // Find the closest schedule
        let closestSchedule = schedulesWithSides.min { $0.distance < $1.distance }!
        
        // Place marker directly on the street sweeping line (not offset to parking side)
        let streetLineCoordinate = getStreetLineCoordinate(from: closestSchedule)
        
        // Update state
        nearbySchedules = schedulesWithSides
        selectedScheduleIndex = 0
        hasSelectedSchedule = true
        detectedSchedule = closestSchedule.schedule
        scheduleConfidence = 0.8
        
        // Interrupt current animation and redirect to street location
        withAnimation(.easeInOut(duration: 0.8)) { // Shorter redirect animation
            settingCoordinate = streetLineCoordinate
            mapPosition = .camera(
                MapCamera(
                    centerCoordinate: streetLineCoordinate,
                    distance: 150,
                    heading: userHeading,
                    pitch: 0
                )
            )
        }
        
        geocodeLocation(streetLineCoordinate)
        print("🎯 Redirected mid-flight to \(closestSchedule.side) side of \(closestSchedule.schedule.streetName)")
    }
    
    private func getStreetLineCoordinate(from scheduleWithSide: SweepScheduleWithSide) -> CLLocationCoordinate2D {
        // Return the point on the actual street line (not the parking offset)
        guard let line = scheduleWithSide.schedule.line,
              !line.coordinates.isEmpty else {
            return scheduleWithSide.offsetCoordinate // Fallback to offset if no line data
        }
        
        // Find the closest point on the street line
        let userLocation = locationManager.userLocation?.coordinate ?? scheduleWithSide.offsetCoordinate
        var closestPoint = CLLocationCoordinate2D(latitude: line.coordinates[0][1], longitude: line.coordinates[0][0])
        var minDistance = Double.infinity
        
        for i in 0..<(line.coordinates.count - 1) {
            let start = CLLocationCoordinate2D(latitude: line.coordinates[i][1], longitude: line.coordinates[i][0])
            let end = CLLocationCoordinate2D(latitude: line.coordinates[i+1][1], longitude: line.coordinates[i+1][0])
            
            let segment = LineSegment(start: start, end: end)
            let (point, distance) = segment.closestPoint(to: userLocation)
            
            if distance < minDistance {
                minDistance = distance
                closestPoint = point
            }
        }
        
        return closestPoint
    }
    
    private func centerMapOnStreetWithRotation(coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        // Center and rotate map to the street location
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 150, // Close street-level view
                    heading: heading,
                    pitch: 0
                )
            )
        }
    }
    
    
    // MARK: - Smart Selection Between Drawn Lines
    
    private func initialSmartSelection(for coordinate: CLLocationCoordinate2D, schedulesWithSides: [SweepScheduleWithSide]) {
        // Find the closest schedule when first landing on schedules
        var closestIndex = 0
        var closestDistance = Double.infinity
        
        for (index, scheduleWithSide) in schedulesWithSides.enumerated() {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: scheduleWithSide.offsetCoordinate.latitude, 
                                         longitude: scheduleWithSide.offsetCoordinate.longitude))
            
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        
        // Apply the same flip logic as the dynamic selection
        let flippedIndex = schedulesWithSides.count - 1 - closestIndex
        let finalIndex = flippedIndex < schedulesWithSides.count ? flippedIndex : closestIndex
        
        // Set initial selection
        selectedScheduleIndex = finalIndex
        hasSelectedSchedule = true
        detectedSchedule = schedulesWithSides[finalIndex].schedule
        scheduleConfidence = Float(max(0.3, min(0.9, 1.0 - (closestDistance / 50.0))))
        
        // Haptic feedback for initial schedule detection
        impactFeedbackLight.impactOccurred()
        
        print("🎯 Initial selection: \(schedulesWithSides[finalIndex].side) side (index \(finalIndex)) - \(Int(closestDistance))m away")
    }
    
    private func smartSelectBetweenDrawnLines(for coordinate: CLLocationCoordinate2D) {
        // Only work with existing nearby schedules (the drawn lines)
        guard !nearbySchedules.isEmpty else { return }
        
        // Debug: Print what sides we have
        print("📍 Available sides: \(nearbySchedules.enumerated().map { "[\($0.offset)] \($0.element.side)" }.joined(separator: ", "))")
        
        // Find which of the existing drawn lines is closest to current marker position
        var closestIndex = 0
        var closestDistance = Double.infinity
        
        for (index, scheduleWithSide) in nearbySchedules.enumerated() {
            // Calculate distance from marker to this schedule's offset coordinate
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: scheduleWithSide.offsetCoordinate.latitude, 
                                         longitude: scheduleWithSide.offsetCoordinate.longitude))
            
            print("📏 Distance to \(scheduleWithSide.side) side (index \(index)): \(Int(distance))m")
            
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        
        // Try flipping the selection - if north/south are mixed up, use the opposite index
        let flippedIndex = nearbySchedules.count - 1 - closestIndex
        let finalIndex = flippedIndex < nearbySchedules.count ? flippedIndex : closestIndex
        
        // Only update if we're switching to a different line
        if selectedScheduleIndex != finalIndex {
            selectedScheduleIndex = finalIndex
            hasSelectedSchedule = true
            detectedSchedule = nearbySchedules[finalIndex].schedule
            
            // Update confidence based on how close we are
            scheduleConfidence = Float(max(0.3, min(0.9, 1.0 - (closestDistance / 50.0))))
            
            // Subtle haptic feedback for switching between lines
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
            
            print("🎯 Selected \(nearbySchedules[finalIndex].side) side (flipped from closest to index \(finalIndex))")
        }
    }
    
    private func fetchStreetDataAndScheduleNotifications(for location: ParkingLocation) {
        streetDataManager.fetchSchedules(for: location.coordinate)
    }
    
    private func prepareHaptics() {
        impactFeedbackLight.prepare()
        notificationFeedback.prepare()
    }
    
    private func setupNotificationHandling() {
        // Monitor schedule changes and auto-update notifications
        streetDataManager.$nextUpcomingSchedule
            .receive(on: DispatchQueue.main)
            .sink { newSchedule in
                handleScheduleChange(newSchedule)
            }
            .store(in: &cancellables)
    }
    
    private func handleScheduleChange(_ newSchedule: UpcomingSchedule?) {
        guard let schedule = newSchedule,
              let currentVehicle = vehicleManager.currentVehicle,
              let parkingLocation = currentVehicle.parkingLocation else {
            return
        }
        
        // Only update if we have existing static notification preferences
        let staticPrefsKey = "StaticNotificationPreferences"
        let hasExistingPreferences = UserDefaults.standard.data(forKey: staticPrefsKey) != nil
        
        if hasExistingPreferences {
            print("🔔 Schedule changed - auto-updating notifications for \(schedule.streetName)")
            Task {
                await autoUpdateNotificationsForNewSchedule(schedule: schedule, parkingLocation: parkingLocation)
            }
        }
    }
    
    private func autoUpdateNotificationsForNewSchedule(schedule: UpcomingSchedule, parkingLocation: ParkingLocation) async {
        let center = UNUserNotificationCenter.current()
        
        do {
            // Check if we have notification permission
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            
            // Get the static notification types
            let staticTypes = NotificationOption.staticTypes
            
            // Load static preferences to see which types were enabled
            let staticPrefsKey = "StaticNotificationPreferences"
            var enabledTypes: [String] = []
            
            if let data = UserDefaults.standard.data(forKey: staticPrefsKey),
               let preferences = try? JSONDecoder().decode([String: Bool].self, from: data) {
                enabledTypes = preferences.compactMap { key, isEnabled in
                    isEnabled ? key : nil
                }
            }
            
            // Clear existing notifications
            center.removeAllPendingNotificationRequests()
            
            // Re-schedule notifications with new schedule but same preferences
            for option in staticTypes {
                if enabledTypes.contains(option.title) {
                    // Calculate dynamic timing based on the new schedule
                    let calculatedOffset = NotificationOption.calculateTiming(for: option, schedule: schedule)
                    let notificationDate = schedule.date.addingTimeInterval(-calculatedOffset)
                    guard notificationDate > Date() else { continue }
                    
                    let content = UNMutableNotificationContent()
                    content.title = getStaticNotificationTitle(for: option)
                    content.body = getStaticNotificationBody(for: option, schedule: schedule)
                    content.sound = calculatedOffset <= 1800 ? .defaultCritical : .default
                    
                    var calendar = Calendar.current
                    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
                    var dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
                    dateComponents.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                    
                    let request = UNNotificationRequest(
                        identifier: "parking-\(option.id.uuidString)",
                        content: content,
                        trigger: trigger
                    )
                    
                    do {
                        try await center.add(request)
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .short
                        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
                        print("✅ Auto-scheduled: \(option.title) at \(formatter.string(from: notificationDate)) PST")
                    } catch {
                        print("❌ Failed to auto-schedule \(option.title): \(error)")
                    }
                }
            }
            
            // Static preferences don't need to be re-saved per street
            // They persist globally across all locations
            
            print("✅ Auto-updated notifications for new location: \(schedule.streetName)")
            
        } catch {
            print("❌ Failed to auto-update notifications: \(error)")
        }
    }
    
    private func getStaticNotificationTitle(for option: NotificationOption) -> String {
        switch option.title {
        case "3 Days Before":
            return "📅 Street Sweeping This Week"
        case "Day Before":
            return "🕐 Street Sweeping Tomorrow"
        case "Day Of":
            return "⏰ Street Sweeping TODAY"
        case "Final Warning":
            return "🚨 Move Your Car NOW"
        case "All Clear":
            return "✅ Street Sweeping Has Ended"
        default:
            return "🅿️ Parking Reminder"
        }
    }
    
    private func getStaticNotificationBody(for option: NotificationOption, schedule: UpcomingSchedule) -> String {
        switch option.title {
        case "3 Days Before":
            return "Street cleaning on \(schedule.dayOfWeek) at \(schedule.startTime) on \(schedule.streetName)"
        case "Day Before":
            return "Street cleaning tomorrow at \(schedule.startTime) on \(schedule.streetName)"
        case "Day Of":
            return "Street cleaning today at \(schedule.startTime) on \(schedule.streetName)"
        case "Final Warning":
            return "Street cleaning starts in 30 minutes on \(schedule.streetName)"
        case "All Clear":
            return "Street cleaning finished on \(schedule.streetName) - safe to park back"
        default:
            return "Parking reminder for \(schedule.streetName)"
        }
    }
    
    
    // MARK: - Elegant Schedule Card (redesigned for beautiful light/dark mode)
    private func elegantScheduleCard(_ scheduleWithSide: SweepScheduleWithSide, index: Int) -> some View {
        let isSelected = index == selectedScheduleIndex && hasSelectedSchedule
        let schedule = scheduleWithSide.schedule
        
        return Button(action: {
            impactFeedbackLight.impactOccurred()
            selectScheduleOption(index)
        }) {
            VStack(alignment: .leading, spacing: 4) {
                // Street name with side indicator
                HStack(spacing: 6) {
                    Text(schedule.streetName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Side badge
                    Text(formatSideDescription(scheduleWithSide.side))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray5))
                        )
                }
                
                // Schedule timing with cleaner format
                Text(formatConciseSchedule(schedule))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: isSelected ? Color.blue.opacity(0.2) : Color.black.opacity(0.08),
                        radius: isSelected ? 6 : 3,
                        x: 0,
                        y: isSelected ? 3 : 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: isSelected ? 2 : 0)
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Schedule Selection Card (EXACT SwipeableVehicleSection structure)
    private func scheduleSelectionCard(_ scheduleWithSide: SweepScheduleWithSide, index: Int) -> some View {
        let isSelected = index == selectedScheduleIndex && hasSelectedSchedule
        let schedule = scheduleWithSide.schedule
        
        return Button(action: {
            impactFeedbackLight.impactOccurred()
            selectScheduleOption(index)
        }) {
            VStack(spacing: 12) { // EXACT same as VehicleSwipeCard
                HStack(spacing: 12) { // EXACT same as VehicleSwipeCard
                    // NO ICON/CIRCLE - skip the left side
                    
                    // Schedule info - EXACT same structure as vehicle info
                    VStack(alignment: .leading, spacing: 4) {
                        // Street name with side indicator pill - PRIMARY TEXT
                        HStack(spacing: 6) {
                            Text(schedule.streetName)
                                .font(.headline) // EXACT same as vehicle primary text
                                .fontWeight(.semibold) // EXACT same as vehicle primary text
                                .foregroundColor(.primary) // EXACT same as vehicle primary text
                                .lineLimit(2) // EXACT same as vehicle primary text
                            
                            // Side badge pill
                            Text(formatSideDescription(scheduleWithSide.side))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray5))
                                )
                        }
                        
                        // Schedule timing - SECONDARY TEXT
                        Text(formatConciseSchedule(schedule))
                            .font(.caption) // EXACT same as vehicle secondary text
                            .foregroundColor(.secondary) // Changed from .blue to .secondary
                    }
                    
                    Spacer() // EXACT same as VehicleSwipeCard
                }
            }
            .padding(20) // EXACT same as VehicleSwipeCard
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.05) : Color(.systemBackground))
                    .shadow(
                        color: isSelected ? Color.blue.opacity(0.4) : Color.blue.opacity(0.25), // Same glow as vehicle
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: isSelected ? 2 : 0)
            )
            .padding(.horizontal, 4) // EXACT same as VehicleSwipeCard
            .padding(.vertical, 2)   // EXACT same as VehicleSwipeCard
            .frame(width: 280) // Slightly wider for schedule text
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Concise Schedule Formatter
    private func formatConciseSchedule(_ schedule: SweepSchedule) -> String {
        let pattern = getSimpleWeekPattern(schedule)
        return "\(pattern) \(schedule.sweepDay), \(schedule.startTime)–\(schedule.endTime)"
    }
    
    // MARK: - Schedule Option Box (matches "no restrictions" styling)
    // MARK: - Schedule Card (elegant, longer format with street name)
    private func scheduleCard(_ scheduleWithSide: SweepScheduleWithSide, index: Int) -> some View {
        let isSelected = index == selectedScheduleIndex
        let schedule = scheduleWithSide.schedule
        
        return Button(action: {
            impactFeedbackLight.impactOccurred()
            selectScheduleOption(index)
        }) {
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Street name + side
                Text("\(schedule.streetName) (\(formatSideDescription(scheduleWithSide.side)))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Line 2: Schedule pattern
                Text(formatElegantSchedule(schedule))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 200, height: 48)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                    }
                }
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .allowsHitTesting(true)
            .drawingGroup() // Prevents clipping issues with scaling
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Elegant Schedule Formatter
    private func formatElegantSchedule(_ schedule: SweepSchedule) -> String {
        let pattern = getSimpleWeekPattern(schedule)
        let time = "\(schedule.startTime)-\(schedule.endTime)"
        return "\(pattern) \(schedule.sweepDay), \(time)"
    }
    
    private func getSimpleWeekPattern(_ schedule: SweepSchedule) -> String {
        let weeks = [
            schedule.week1 == "1",
            schedule.week2 == "1", 
            schedule.week3 == "1",
            schedule.week4 == "1",
            schedule.week5 == "1"
        ]
        
        if weeks == [true, false, true, false, true] {
            return "1st, 3rd, 5th"
        } else if weeks == [false, true, false, true, false] {
            return "2nd, 4th"
        } else if weeks == [true, false, true, false, false] {
            return "1st, 3rd"
        } else if weeks.allSatisfy({ $0 }) {
            return "Every"
        } else {
            return "Select"
        }
    }
    
    // MARK: - Schedule Description Formatter
    private func formatScheduleDescription(_ schedule: SweepSchedule) -> String {
        let day = schedule.sweepDay
        let time = "\(schedule.startTime) - \(schedule.endTime)"
        
        // Format week pattern for readability
        let weekPattern = getWeekPattern(schedule)
        
        if weekPattern.isEmpty {
            return "\(day), \(time)"
        } else {
            return "\(weekPattern) \(day), \(time)"
        }
    }
    
    private func getWeekPattern(_ schedule: SweepSchedule) -> String {
        let weeks = [
            schedule.week1 == "1",
            schedule.week2 == "1", 
            schedule.week3 == "1",
            schedule.week4 == "1",
            schedule.week5 == "1"
        ]
        
        // Check common patterns
        if weeks == [true, false, true, false, true] {
            return "1st, 3rd, 5th"
        } else if weeks == [false, true, false, true, false] {
            return "2nd & 4th"
        } else if weeks == [true, false, true, false, false] {
            return "1st & 3rd"
        } else if weeks == [false, true, false, true, true] {
            return "2nd, 4th, 5th"
        } else if weeks.allSatisfy({ $0 }) {
            return "Every"
        } else {
            // Build custom pattern
            let activeWeeks = weeks.enumerated().compactMap { index, isActive in
                isActive ? getOrdinal(index + 1) : nil
            }
            return activeWeeks.joined(separator: ", ")
        }
    }
    
    private func getOrdinal(_ number: Int) -> String {
        switch number {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        case 5: return "5th"
        default: return "\(number)th"
        }
    }
    
    // MARK: - Helper Methods
    private func formatSideDescription(_ side: String) -> String {
        let cleaned = side.lowercased()
        if cleaned.contains("north") { return "North" }
        if cleaned.contains("south") { return "South" }
        if cleaned.contains("east") { return "East" }
        if cleaned.contains("west") { return "West" }
        return side.capitalized
    }
    
    
    // MARK: - Schedule Selection Methods
    private func selectScheduleOption(_ index: Int) {
        guard index >= 0 && index < nearbySchedules.count else { return }
        
        impactFeedbackLight.impactOccurred()
        
        // Toggle selection if the same index is selected
        if selectedScheduleIndex == index && hasSelectedSchedule {
            hasSelectedSchedule = false
            detectedSchedule = nil
        } else {
            selectedScheduleIndex = index
            detectedSchedule = nearbySchedules[index].schedule
            hasSelectedSchedule = true
        }
        
        // Update the main pin location and confidence only if a schedule is selected
        if hasSelectedSchedule {
            settingCoordinate = nearbySchedules[index].offsetCoordinate
            // Update confidence based on distance (closer = higher confidence)
            let distance = nearbySchedules[index].distance
            scheduleConfidence = Float(max(0.3, min(0.9, 1.0 - (distance / 50.0)))) // Scale from 50ft max distance
        } else {
            scheduleConfidence = 0.0
        }
        
        if hasSelectedSchedule {
            print("🎯 Selected schedule option \(index + 1): \(nearbySchedules[index].side) side")
        } else {
            print("🎯 Deselected schedule - no parking restrictions")
        }
    }
    
    private func getStatusColor() -> Color {
        if isAutoDetectingSchedule {
            return .blue
        } else if detectedSchedule != nil {
            return scheduleConfidence > 0.7 ? .green : scheduleConfidence > 0.4 ? .orange : .red
        } else if settingAddress != nil {
            return .green
        } else {
            return .gray
        }
    }
    
    private func getStatusTitle() -> String {
        if isAutoDetectingSchedule {
            return "Checking schedule..."
        } else if !nearbySchedules.isEmpty {
            if nearbySchedules.count == 1 {
                let (timeUntil, _) = calculateTimeUntilNextCleaning(schedule: nearbySchedules[0].schedule)
                return "Street sweeping \(timeUntil)"
            } else {
                return "Multiple restrictions found"
            }
        } else if settingAddress != nil {
            return "No restrictions"
        } else {
            return "Move map to check"
        }
    }
    
    private func getStatusSubtitle() -> String {
        if isAutoDetectingSchedule {
            return "Looking for street cleaning times"
        } else if !nearbySchedules.isEmpty {
            if nearbySchedules.count == 1 {
                let schedule = nearbySchedules[0].schedule
                return "\(schedule.streetName) • \(schedule.startTime)-\(schedule.endTime)"
            } else {
                return "Choose your parking side below"
            }
        } else if settingAddress != nil {
            return "Clear to park"
        } else {
            return "Position pin to detect schedule"
        }
    }
    
    private func cleanupResources() {
        autoResetTimer?.invalidate()
        detectionDebounceTimer?.invalidate()
        cancellables.removeAll()
    }
}

// MARK: - Enhanced Vehicle List Row Component

struct EnhancedVehicleListRow: View {
    let vehicle: Vehicle
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSetLocation: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Vehicle icon with gradient - consistent with card style
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    vehicle.color.color,
                                    vehicle.color.color.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: vehicle.type.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: vehicle.color.color.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Vehicle info
                VStack(alignment: .leading, spacing: 6) {
                    Text(vehicle.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(vehicle.type.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(vehicle.color.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    // Parking status
                    HStack(spacing: 6) {
                        Image(systemName: vehicle.parkingLocation != nil ? "location.fill" : "location.slash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(vehicle.parkingLocation != nil ? .green : .secondary)
                        
                        Text(vehicle.parkingLocation != nil ? "Parked" : "Not Parked")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(vehicle.parkingLocation != nil ? .green : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray6))
                    )
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color(.systemGray6))
                            )
                    }
                    
                    Button(action: onSetLocation) {
                        Image(systemName: vehicle.parkingLocation != nil ? "arrow.triangle.2.circlepath" : "location")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(vehicle.parkingLocation != nil ? Color.blue : Color.green)
                            )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: isSelected ? vehicle.color.color.opacity(0.2) : Color.black.opacity(0.06),
                        radius: isSelected ? 8 : 4,
                        x: 0,
                        y: isSelected ? 4 : 2
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? vehicle.color.color.opacity(0.3) : Color.clear,
                                lineWidth: isSelected ? 2 : 0
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


#Preview("Light Mode") {
    VehicleParkingView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VehicleParkingView()
        .preferredColorScheme(.dark)
}

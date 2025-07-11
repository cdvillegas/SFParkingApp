import SwiftUI
import MapKit
import CoreLocation
import Combine

struct VehicleParkingView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var streetDataManager = StreetDataManager()
    @StateObject private var vehicleManager = VehicleManager()
    @StateObject private var debouncedGeocoder = DebouncedGeocodingHandler()
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
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
                
                // Center on vehicles button - bottom right of map
                if !vehicleManager.activeVehicles.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                impactFeedbackLight.impactOccurred()
                                centerMapOnVehicles()
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
                            .padding(.bottom, 20) // Bottom right of map area
                        }
                    }
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
            if let currentVehicle = vehicleManager.currentVehicle,
               let parkingLocation = currentVehicle.parkingLocation {
                // Always use the same NotificationSettingsSheet, create dummy schedule if needed
                let schedule = streetDataManager.nextUpcomingSchedule ?? UpcomingSchedule(
                    streetName: parkingLocation.address,
                    date: Date().addingTimeInterval(7 * 24 * 3600), // 1 week from now
                    endDate: Date().addingTimeInterval(7 * 24 * 3600 + 7200), // 2 hours later
                    dayOfWeek: "Next Week",
                    startTime: "8:00 AM",
                    endTime: "10:00 AM"
                )
                NotificationSettingsSheet(
                    schedule: schedule,
                    parkingLocation: parkingLocation
                )
            }
        }
        .onAppear {
            setupView()
            prepareHaptics()
            setupNotificationHandling()
            NotificationManager.shared.validateAndRecoverNotifications()
            
            // Check if we should start in location setting mode
            if vehicleManager.currentVehicle?.parkingLocation == nil {
                isSettingLocation = true
            }
        }
        .onDisappear {
            cleanupResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OnboardingCompleted"))) { _ in
            setupPermissionsAfterOnboarding()
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
            // User location
            if let userLocation = locationManager.userLocation {
                Annotation("Your Location", coordinate: userLocation.coordinate) {
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
                        .offset(y: -24)
                        
                        // Schedule selected glow
                        if !nearbySchedules.isEmpty && hasSelectedSchedule {
                            ZStack {
                                // Outer glow ring
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 6)
                                    .frame(width: 50, height: 50)
                                
                                // Main glow ring  
                                Circle()
                                    .stroke(Color.blue, lineWidth: 3)
                                    .frame(width: 40, height: 40)
                            }
                            .offset(y: -24)
                            .animation(.easeInOut(duration: 0.3), value: !nearbySchedules.isEmpty)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        )
        .mapStyle(.standard)
        .onMapCameraChange { context in
            if isSettingLocation {
                settingCoordinate = context.camera.centerCoordinate
                geocodeLocation(settingCoordinate)
                autoDetectSchedule(for: settingCoordinate)
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
    
    // MARK: - Vehicle Annotations
    
    @MapContentBuilder
    private var vehicleAnnotations: some MapContent {
        ForEach(vehicleManager.activeVehicles, id: \.id) { vehicle in
            if let parkingLocation = vehicle.parkingLocation {
                Annotation(vehicle.displayName, coordinate: parkingLocation.coordinate) {
                    VehicleParkingMapMarker(
                        vehicle: vehicle,
                        isSelected: vehicleManager.selectedVehicle?.id == vehicle.id,
                        onTap: {
                            showVehicleActions(vehicle)
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
                        
                        // Add invisible annotations for tapping along the line
                        let midPoint = calculateMidpoint(streetEdgeCoords)
                        Annotation("", coordinate: midPoint) {
                            Button(action: {
                                selectScheduleOption(index)
                            }) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 60, height: 20)
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
            if let vehicleForActions = showingVehicleActions {
                // Expanded Vehicle Card Interface
                enhancedVehicleActionsInterface(for: vehicleForActions)
            } else if isSettingLocation {
                // Unified location setting interface
                unifiedLocationSettingInterface()
            } else {
                // Normal mode - show vehicles
                enhancedNormalVehicleInterface()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
        )
    }
    
    // MARK: - Enhanced Vehicle Actions Interface
    private func enhancedVehicleActionsInterface(for vehicle: Vehicle) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // Header Section
            HStack {
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showingVehicleActions = nil
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Compact Vehicle Card
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    // Vehicle icon with gradient shadow
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
                    .shadow(color: vehicle.color.color.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    // Compact vehicle details
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vehicle.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // Compact parking status
                        HStack(spacing: 6) {
                            Image(systemName: vehicle.parkingLocation != nil ? "location.fill" : "location.slash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(vehicle.parkingLocation != nil ? .green : .secondary)
                            
                            Text(vehicle.parkingLocation != nil ? "Parked" : "Not Parked")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(vehicle.parkingLocation != nil ? .green : .secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // View in Maps button (only if parked)
                    if vehicle.parkingLocation != nil {
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            openVehicleInMaps(vehicle)
                        }) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.blue)
                                        .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                                )
                        }
                    }
                }
                
                // Compact location info if parked
                if let parkingLocation = vehicle.parkingLocation {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                        
                        Text(parkingLocation.address.components(separatedBy: ",").prefix(2).joined(separator: ","))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
            .padding(.horizontal, 20)
            
            // Action Buttons
            HStack(spacing: 12) {
                // Edit Button
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        showingEditVehicle = vehicle
                        showingVehicleActions = nil
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("Edit")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemGray2))
                    )
                }
                
                // Move/Park Button
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        isSettingLocationForNewVehicle = false
                        startSettingLocationForVehicle(vehicle)
                        showingVehicleActions = nil
                    }
                }) {
                    HStack(spacing: 8) {
                        Text(vehicle.parkingLocation != nil ? "Move" : "Park")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.primary)
                    .cornerRadius(14)
                    .shadow(color: (vehicle.parkingLocation != nil ? Color.orange : Color.green).opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Additional Action Buttons
            if vehicle.parkingLocation != nil {
                // Reminders Button
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    showingReminderSheet = true
                    showingVehicleActions = nil
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Reminders")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            
            Spacer()
                .frame(height: 28)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
    
    // MARK: - Helper function to open vehicle in Maps
    private func openVehicleInMaps(_ vehicle: Vehicle) {
        guard let parkingLocation = vehicle.parkingLocation else { 
            // Provide haptic feedback when no parking location is set
            impactFeedbackLight.impactOccurred()
            return 
        }
        
        let coordinate = parkingLocation.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "\(vehicle.displayName) - Parked Location"
        
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    // MARK: - Unified Location Setting Interface
    private func unifiedLocationSettingInterface() -> some View {
        VStack(spacing: 0) {
            unifiedLocationContent()
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
    
    // MARK: - Unified Location Content
    private func unifiedLocationContent() -> some View {
        VStack(spacing: 0) {
            // Fixed-height status section
            setParkingLocationSection()
            
            // Action buttons
            HStack(spacing: 12) {
                // Only show cancel button if parking location exists
                if vehicleManager.currentVehicle?.parkingLocation != nil {
                    Button(action: {
                        impactFeedbackLight.impactOccurred()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            cancelSettingLocation()
                        }
                    }) {
                        Text(isSettingLocationForNewVehicle ? "Skip for Now" : "Cancel")
                            .font(.system(size: 16, weight: .semibold))
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
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
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
                // Show upcoming reminders for current vehicle
                if let currentVehicle = vehicleManager.currentVehicle,
                   let parkingLocation = currentVehicle.parkingLocation {
                    UpcomingRemindersSection(
                        streetDataManager: streetDataManager,
                        parkingLocation: parkingLocation
                    )
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                }
                
                // Enhanced header with three-dot menu (Edit/Move)
                HStack {
                    Text("My Vehicle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Three-dot menu for single vehicle
                    if let currentVehicle = vehicleManager.currentVehicle {
                        Menu {
                            Button(action: {
                                impactFeedbackLight.impactOccurred()
                                showingEditVehicle = currentVehicle
                            }) {
                                HStack {
                                    Text("Edit")
                                    Image(systemName: "pencil")
                                }
                            }
                            
                            Button(action: {
                                impactFeedbackLight.impactOccurred()
                                isSettingLocationForNewVehicle = false
                                startSettingLocationForVehicle(currentVehicle)
                            }) {
                                HStack {
                                    Text("Move")
                                    Image(systemName: "location")
                                }
                            }
                            
                            if currentVehicle.parkingLocation != nil {
                                Button(action: {
                                    impactFeedbackLight.impactOccurred()
                                    showingReminderSheet = true
                                }) {
                                    HStack {
                                        Text("Reminders")
                                        Image(systemName: "bell")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(.systemGray5))
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                
                // Vehicle section - single card
                SwipeableVehicleSection(
                    vehicles: vehicleManager.activeVehicles,
                    selectedVehicle: vehicleManager.currentVehicle,
                    onVehicleSelected: { vehicle in
                        // In single-vehicle mode, do nothing since there's only one vehicle
                    },
                    onVehicleTap: { vehicle in
                        // Open vehicle location in Maps
                        openVehicleInMaps(vehicle)
                    }
                )
                .padding(.bottom, 20)
                
            } else {
                // Enhanced empty state
                enhancedEmptyStateInterface()
            }
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
    
    private func showVehicleActions(_ vehicle: Vehicle) {
        impactFeedbackLight.impactOccurred()
        selectVehicle(vehicle)
        
        // Center map on vehicle if it has a parking location
        if let parkingLocation = vehicle.parkingLocation {
            centerMapOnLocation(parkingLocation.coordinate)
        }
        
        showingVehicleActions = vehicle
    }
    
    private func centerMapOnVehicle(_ vehicle: Vehicle) {
        guard let parkingLocation = vehicle.parkingLocation else { return }
        centerMapOnLocation(parkingLocation.coordinate)
    }
    
    private func centerMapOnLocation(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
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
    
    private func startSettingLocationForVehicle(_ vehicle: Vehicle) {
        vehicleManager.selectVehicle(vehicle)
        startSettingLocation()
    }
    
    private func startSettingLocation() {
        impactFeedbackLight.impactOccurred()
        isSettingLocation = true
        
        // Start from user location or last known location
        let startCoordinate: CLLocationCoordinate2D
        if let userLocation = locationManager.userLocation {
            startCoordinate = userLocation.coordinate
        } else if let selectedVehicle = vehicleManager.selectedVehicle,
                  let parkingLocation = selectedVehicle.parkingLocation {
            startCoordinate = parkingLocation.coordinate
        } else {
            // Use Market Street near Larkin (from CSV data - known to have street cleaning)
            startCoordinate = CLLocationCoordinate2D(latitude: 37.7775, longitude: -122.4163)
        }
        
        settingCoordinate = startCoordinate
        centerMapOnLocation(startCoordinate)
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
                        self.selectedScheduleIndex = 0 // Default to closest
                        self.hasSelectedSchedule = true // Auto-select first schedule
                        self.detectedSchedule = schedulesWithSides[0].schedule
                        self.scheduleConfidence = 0.8
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
        // Only request location permission if onboarding has been completed
        if OnboardingManager.hasCompletedOnboarding {
            locationManager.requestLocationPermission()
        }
        
        // Auto-start in location setting mode if no vehicle has a parking location
        if vehicleManager.currentVehicle?.parkingLocation == nil {
            isSettingLocation = true
        }
        
        // Center map on selected vehicle or user location
        if let selectedVehicle = vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
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
        } else {
            centerMapOnUserLocation()
        }
    }
    
    private func setupPermissionsAfterOnboarding() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let locationStatus = CLLocationManager().authorizationStatus
            if locationStatus == .notDetermined {
                locationManager.requestLocationPermission()
            }
            
            // Auto-start in location setting mode after onboarding
            if vehicleManager.currentVehicle?.parkingLocation == nil {
                isSettingLocation = true
            }
        }
    }
    
    private func centerMapOnUserLocation() {
        if let userLocation = locationManager.userLocation {
            centerMapOnLocation(userLocation.coordinate)
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
    
    // MARK: - Street Sweeping Section (redesigned for beautiful light/dark mode)
    private func setParkingLocationSection() -> some View {
        VStack(spacing: 12) {
            // Title with refined styling
            HStack {
                Text("Set Parking Location")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isAutoDetectingSchedule {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.blue)
                }
            }
            
            // Schedule cards with consistent height but no background container
            if nearbySchedules.isEmpty {
                // No schedules - centered beautiful state
                VStack(spacing: 8) {
                    Image(systemName: settingAddress != nil ? "checkmark.circle.fill" : "location.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(settingAddress != nil ? .green : .blue.opacity(0.7))
                    
                    Text(settingAddress != nil ? "No parking restrictions" : "Move map to check area")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(settingAddress != nil ? .green : .secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 88)
            } else {
                VStack(spacing: 8) {
                    // Standalone schedule cards with proper padding to prevent clipping
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(nearbySchedules.enumerated()), id: \.0) { index, scheduleWithSide in
                                elegantScheduleCard(scheduleWithSide, index: index)
                            }
                        }
                        .padding(.leading, 4) // Minimal leading padding to prevent clipping
                        .padding(.trailing, 20) // Trailing padding for right side
                        .padding(.vertical, 12) // Extra padding to prevent clipping when cards scale up
                    }
                    .frame(height: 88)
                }
            }
        }.padding(20)
    }
    
    // MARK: - Elegant Schedule Card (redesigned for beautiful light/dark mode)
    private func elegantScheduleCard(_ scheduleWithSide: SweepScheduleWithSide, index: Int) -> some View {
        let isSelected = index == selectedScheduleIndex && hasSelectedSchedule
        let schedule = scheduleWithSide.schedule
        
        return Button(action: {
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
            .frame(width: 220, height: 56)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected ? 
                        Color.blue.opacity(0.12) : 
                        Color(.systemBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? 
                                Color.blue.opacity(0.4) : 
                                Color(.systemGray4).opacity(0.6), 
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isSelected ? 
                        Color.blue.opacity(0.15) : 
                        Color.black.opacity(0.06), 
                        radius: isSelected ? 6 : 2, 
                        x: 0, 
                        y: isSelected ? 3 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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

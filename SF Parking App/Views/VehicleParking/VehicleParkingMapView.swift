import SwiftUI
import MapKit
import CoreLocation

struct VehicleParkingMapView: View {
    @ObservedObject var viewModel: VehicleParkingViewModel
    @State private var currentMapHeading: CLLocationDirection = 0
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    @State private var userLocation: CLLocation?
    @State private var smartSelectionTimer: Timer?
    @State private var markerStillTimer: Timer?
    @State private var lastMapCenterCoordinate: CLLocationCoordinate2D?
    @State private var isAppActive: Bool = true
    
    // Use ViewModel's published heading property
    private var currentHeading: CLLocationDirection {
        viewModel.userHeading
    }
    
    var body: some View {
        Map(position: $viewModel.mapPosition, interactionModes: isAppActive ? .all : []) {
            // User location annotation
            if viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || viewModel.locationManager.authorizationStatus == .authorizedAlways {
                userLocationAnnotation
            }
            
            // Vehicle annotations
            vehicleAnnotations
            
            // Street sweeping schedule edge lines (only show in step 2)
            if viewModel.isConfirmingSchedule && !viewModel.nearbySchedules.isEmpty {
                streetEdgeScheduleLines
            }
        }
        .overlay(settingLocationPin)
        .overlay(mapControlButtons, alignment: .bottomTrailing)
        .overlay(enableLocationButton, alignment: .bottom)
        .mapStyle(.standard)
        .onMapCameraChange(frequency: .continuous) { context in
            guard isAppActive else { return }
            currentMapHeading = context.camera.heading
            handleMapCameraChange(context)
        }
        .onAppear {
            // Initialize user location on view appear
            userLocation = viewModel.locationManager.userLocation
        }
        .onDisappear {
            // Clean up timers to prevent retain cycles
            smartSelectionTimer?.invalidate()
            smartSelectionTimer = nil
            markerStillTimer?.invalidate()
            markerStillTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AppWillResignActive"))) { _ in
            // App going to background - prepare for Metal cleanup
            isAppActive = false
            // Invalidate timers that might cause Metal issues
            smartSelectionTimer?.invalidate()
            markerStillTimer?.invalidate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AppDidBecomeActive"))) { _ in
            // App became active again
            isAppActive = true
        }
        .onReceive(viewModel.locationManager.$userLocation) { newLocation in
            // Keep local state in sync with location manager
            userLocation = newLocation
            
            // Center map on user location if no parking location is set
            if let location = newLocation {
                let hasParkedVehicle = viewModel.vehicleManager.currentVehicle?.parkingLocation != nil
                if !hasParkedVehicle {
                    viewModel.centerMapOnLocation(location.coordinate)
                }
            }
        }
        .onReceive(viewModel.locationManager.$authorizationStatus) { newStatus in
            // Update user location when authorization changes
            userLocation = viewModel.locationManager.userLocation
            
            // If permission was just granted, request location immediately
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                viewModel.locationManager.requestLocation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh when returning from Settings
            viewModel.locationManager.refreshAuthorizationStatus()
            userLocation = viewModel.locationManager.userLocation
        }
        .onDisappear {
            // Clean up timers when view disappears
            markerStillTimer?.invalidate()
            smartSelectionTimer?.invalidate()
        }
    }
    
    // MARK: - Overlay Views
    
    @ViewBuilder
    private var settingLocationPin: some View {
        Group {
            if viewModel.isSettingLocation, let vehicle = viewModel.vehicleManager.selectedVehicle {
                // Setting location pin - positioned so tip aligns with cursor
                VStack {
                    Spacer()
                    
                    // Pin with adaptive color
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green, Color.green.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: vehicle.type.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.green.opacity(0.4), radius: 6, x: 0, y: 3)
                        
                        // Pin tail
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.green)
                            .frame(width: 3, height: 12)
                    }
                    .offset(y: -18) // Move pin up so the tip of the line aligns with center
                    
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
    }
    
    @ViewBuilder
    private var mapControlButtons: some View {
        Group {
            if !viewModel.isConfirmingSchedule || viewModel.isSettingLocation {
                HStack(spacing: 12) {
                    vehicleButton
                    userLocationButton
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
    }
    
    @ViewBuilder
    private var vehicleButton: some View {
        if let currentVehicle = viewModel.vehicleManager.currentVehicle,
           currentVehicle.parkingLocation != nil {
            Button(action: {
                impactFeedbackLight.impactOccurred()
                centerOnVehicle()
            }) {
                Image(systemName: "car.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(.systemGray6))
                    )
            }
        }
    }
    
    @ViewBuilder
    private var userLocationButton: some View {
        if viewModel.locationManager.userLocation != nil &&
           (viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || 
            viewModel.locationManager.authorizationStatus == .authorizedAlways) {
            Button(action: {
                impactFeedbackLight.impactOccurred()
                centerOnUser()
            }) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(.systemGray6))
                    )
            }
        }
    }
    
    @ViewBuilder
    private var enableLocationButton: some View {
        Group {
            if !viewModel.isConfirmingSchedule &&
               viewModel.locationManager.authorizationStatus != .authorizedWhenInUse && 
               viewModel.locationManager.authorizationStatus != .authorizedAlways &&
               viewModel.locationManager.userLocation == nil {
                VStack {
                    Spacer()
                    Button(action: enableLocationAction) {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Enable Location")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.9))
                                .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                        )
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - Map Content Builders
    
    @MapContentBuilder
    private var userLocationAnnotation: some MapContent {
        if let userLocation = userLocation {
            Annotation("", coordinate: userLocation.coordinate) {
                UserDirectionCone(heading: currentHeading, mapHeading: currentMapHeading)
                    .id("userLocation-\(currentHeading)-\(currentMapHeading)")
            }
        }
    }
    
    @MapContentBuilder
    private var vehicleAnnotations: some MapContent {
        ForEach(viewModel.vehicleManager.activeVehicles, id: \.id) { vehicle in
            if let parkingLocation = vehicle.parkingLocation {
                Annotation("My Vehicle", coordinate: parkingLocation.coordinate) {
                    VehicleParkingMapMarker(
                        vehicle: vehicle,
                        isSelected: viewModel.vehicleManager.selectedVehicle?.id == vehicle.id,
                        onTap: {
                            viewModel.centerMapOnLocation(parkingLocation.coordinate)
                        }
                    )
                }
            }
        }
    }
    
    @MapContentBuilder
    private var streetEdgeScheduleLines: some MapContent {
        ForEach(Array(viewModel.nearbySchedules.enumerated()), id: \.0) { index, scheduleWithSide in
            if let line = scheduleWithSide.schedule.line {
                ForEach(0..<line.coordinates.count-1, id: \.self) { segmentIndex in
                    let startCoord = line.coordinates[segmentIndex]
                    let endCoord = line.coordinates[segmentIndex + 1]
                    
                    if startCoord.count >= 2 && endCoord.count >= 2 {
                        let streetEdgeCoords = calculateStreetEdgeCoordinates(
                            start: CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0]),
                            end: CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0]),
                            blockSide: scheduleWithSide.side
                        )
                        
                        // Main parking zone line - improved visibility
                        MapPolyline(coordinates: streetEdgeCoords)
                            .stroke(
                                (index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule) ? Color.blue : Color.secondary.opacity(0.6),
                                style: StrokeStyle(
                                    lineWidth: (index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule) ? 10 : 7,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                        
                        // Tap areas for line interaction
                        ForEach(0..<min(streetEdgeCoords.count, 5), id: \.self) { tapIndex in
                            let coordIndex = (streetEdgeCoords.count - 1) * tapIndex / max(1, 4)
                            Annotation("", coordinate: streetEdgeCoords[coordIndex]) {
                                Button(action: {
                                    if viewModel.isConfirmingSchedule {
                                        viewModel.onScheduleHover(index)
                                    } else {
                                        impactFeedbackLight.impactOccurred()
                                        viewModel.selectScheduleOption(index)
                                    }
                                }) {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: 100, height: 40)
                                }
                            }
                        }
                        
                        // Selection glow - enhanced visibility
                        if index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule {
                            MapPolyline(coordinates: streetEdgeCoords)
                                .stroke(
                                    Color.blue.opacity(0.25),
                                    style: StrokeStyle(
                                        lineWidth: 20,
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
    
    // MARK: - Private Methods
    
    private func enableLocationAction() {
        impactFeedbackLight.impactOccurred()
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
    
    private func centerOnVehicle() {
        if let currentVehicle = viewModel.vehicleManager.currentVehicle,
           let parkingLocation = currentVehicle.parkingLocation {
            viewModel.centerMapOnLocation(parkingLocation.coordinate)
        }
    }
    
    private func centerOnUser() {
        viewModel.locationManager.requestLocationPermission()
        if let userLocation = viewModel.locationManager.userLocation {
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
    
    private func handleMapCameraChange(_ context: MapCameraUpdateContext) {
        currentMapHeading = context.camera.heading
        let newCoordinate = context.camera.centerCoordinate
        
        // Cancel any existing stationary timer
        markerStillTimer?.invalidate()
        
        // Check if the marker has moved significantly
        let hasMovedSignificantly: Bool
        if let lastCoordinate = lastMapCenterCoordinate {
            let distance = CLLocation(latitude: newCoordinate.latitude, longitude: newCoordinate.longitude)
                .distance(from: CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude))
            hasMovedSignificantly = distance > 5 // 5 meters threshold
        } else {
            hasMovedSignificantly = true
        }
        
        // Update the last coordinate
        lastMapCenterCoordinate = newCoordinate
        
        // Start a timer to detect when marker stays still for 0.2 seconds
        if hasMovedSignificantly {
            markerStillTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.handleMarkerStillForDuration(newCoordinate)
                }
            }
        }
        
        if viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
            // Step 1: Location setting with continuous schedule detection
            viewModel.settingCoordinate = newCoordinate
            
            // Geocode the address
            viewModel.debouncedGeocoder.reverseGeocode(coordinate: newCoordinate) { address, _ in
                DispatchQueue.main.async {
                    viewModel.settingAddress = address
                }
            }
            
            // Continuous schedule detection for background loading
            viewModel.autoDetectScheduleWithPreservation(for: newCoordinate)
            
        } else if viewModel.isConfirmingSchedule {
            // Step 2: Schedule confirmation with free movement and dynamic schedule loading
            viewModel.settingCoordinate = newCoordinate
            
            // Immediate smart selection between existing lines (no debounce needed)
            smartSelectBetweenDrawnLines(for: newCoordinate)
            
            // Continuous schedule detection with preservation
            viewModel.autoDetectScheduleWithPreservation(for: newCoordinate)
        }
    }
    
    private func handleMarkerStillForDuration(_ coordinate: CLLocationCoordinate2D) {
        // This function is called when the marker has been still for 0.2 seconds
        // Can be used for more intensive operations when the user stops moving
        // Currently, main detection happens during movement for better responsiveness
    }
    
    private func checkAndLoadNewSchedulesIfNeeded(for coordinate: CLLocationCoordinate2D) {
        // Only load new schedules if we don't have good coverage for this area
        let needsNewSchedules = shouldLoadNewSchedules(for: coordinate)
        
        if needsNewSchedules {
            viewModel.autoDetectSchedule(for: coordinate)
        }
    }
    
    private func shouldLoadNewSchedules(for coordinate: CLLocationCoordinate2D) -> Bool {
        // If we have no schedules, we definitely need them
        guard !viewModel.nearbySchedules.isEmpty else { return true }
        
        let _ = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Check if any existing schedule line is within reasonable distance (50m)
        for scheduleWithSide in viewModel.nearbySchedules {
            guard let line = scheduleWithSide.schedule.line else { continue }
            
            for segmentIndex in 0..<(line.coordinates.count - 1) {
                let startCoord = line.coordinates[segmentIndex]
                let endCoord = line.coordinates[segmentIndex + 1]
                
                guard startCoord.count >= 2 && endCoord.count >= 2 else { continue }
                
                let startCL = CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0])
                let endCL = CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0])
                
                let distance = distanceToLineSegment(point: coordinate, lineStart: startCL, lineEnd: endCL)
                
                // If we're within 50m of any existing schedule line, we don't need new schedules
                if distance < 50 {
                    return false
                }
            }
        }
        
        // If we're more than 50m from all existing schedules, we need new ones
        return true
    }
    
    private func smartSelectBetweenDrawnLines(for coordinate: CLLocationCoordinate2D) {
        guard !viewModel.nearbySchedules.isEmpty else { return }
        
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var bestIndex = 0
        var bestDistance = Double.infinity
        
        // Calculate distance to each schedule's street edge line
        for (index, scheduleWithSide) in viewModel.nearbySchedules.enumerated() {
            guard let line = scheduleWithSide.schedule.line else {
                // If no line data, fall back to offset coordinate
                let distance = userLocation.distance(from: CLLocation(
                    latitude: scheduleWithSide.offsetCoordinate.latitude,
                    longitude: scheduleWithSide.offsetCoordinate.longitude
                ))
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
                continue
            }
            
            // Find the closest point on this schedule's street edge line
            var minDistanceToLine = Double.infinity
            
            for segmentIndex in 0..<(line.coordinates.count - 1) {
                let startCoord = line.coordinates[segmentIndex]
                let endCoord = line.coordinates[segmentIndex + 1]
                
                guard startCoord.count >= 2 && endCoord.count >= 2 else { continue }
                
                let startCL = CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0])
                let endCL = CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0])
                
                // Calculate street edge coordinates for this segment
                let streetEdgeCoords = calculateStreetEdgeCoordinates(
                    start: startCL,
                    end: endCL,
                    blockSide: scheduleWithSide.side
                )
                
                // Find closest point on this street edge segment
                if streetEdgeCoords.count >= 2 {
                    let segmentDistance = distanceToLineSegment(
                        point: coordinate,
                        lineStart: streetEdgeCoords[0],
                        lineEnd: streetEdgeCoords[1]
                    )
                    minDistanceToLine = min(minDistanceToLine, segmentDistance)
                }
            }
            
            if minDistanceToLine < bestDistance {
                bestDistance = minDistanceToLine
                bestIndex = index
            }
        }
        
        // Only update if the selection actually changed and the distance is reasonable (within 100m)
        if viewModel.selectedScheduleIndex != bestIndex && bestDistance < 100 {
            viewModel.selectedScheduleIndex = bestIndex
            viewModel.hasSelectedSchedule = true
            viewModel.detectedSchedule = viewModel.nearbySchedules[bestIndex].schedule
            
            // Calculate confidence based on distance to selected line
            viewModel.scheduleConfidence = Float(max(0.3, min(0.95, 1.0 - (bestDistance / 100.0))))
            
            // Subtle haptic feedback for selection changes
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
    }
    
    // Helper function to calculate distance from a point to a line segment
    private func distanceToLineSegment(point: CLLocationCoordinate2D, lineStart: CLLocationCoordinate2D, lineEnd: CLLocationCoordinate2D) -> Double {
        let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLocation = CLLocation(latitude: lineStart.latitude, longitude: lineStart.longitude)
        let endLocation = CLLocation(latitude: lineEnd.latitude, longitude: lineEnd.longitude)
        
        // Calculate the distance from point to the line segment
        let lineLength = startLocation.distance(from: endLocation)
        
        if lineLength == 0 {
            return pointLocation.distance(from: startLocation)
        }
        
        // Project point onto the line
        let startToPoint = (
            lat: point.latitude - lineStart.latitude,
            lon: point.longitude - lineStart.longitude
        )
        
        let startToEnd = (
            lat: lineEnd.latitude - lineStart.latitude,
            lon: lineEnd.longitude - lineStart.longitude
        )
        
        let dotProduct = startToPoint.lat * startToEnd.lat + startToPoint.lon * startToEnd.lon
        let lineLengthSquared = startToEnd.lat * startToEnd.lat + startToEnd.lon * startToEnd.lon
        
        let t = max(0, min(1, dotProduct / lineLengthSquared))
        
        let projectedPoint = CLLocationCoordinate2D(
            latitude: lineStart.latitude + t * startToEnd.lat,
            longitude: lineStart.longitude + t * startToEnd.lon
        )
        
        let projectedLocation = CLLocation(latitude: projectedPoint.latitude, longitude: projectedPoint.longitude)
        return pointLocation.distance(from: projectedLocation)
    }
    
    private func calculateStreetEdgeCoordinates(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        blockSide: String
    ) -> [CLLocationCoordinate2D] {
        
        let streetVector = (
            longitude: end.longitude - start.longitude,
            latitude: end.latitude - start.latitude
        )
        
        let perpVector = (
            longitude: -streetVector.latitude,
            latitude: streetVector.longitude
        )
        
        let perpLength = sqrt(perpVector.longitude * perpVector.longitude + perpVector.latitude * perpVector.latitude)
        guard perpLength > 0 else { return [start, end] }
        
        let normalizedPerp = (
            longitude: perpVector.longitude / perpLength,
            latitude: perpVector.latitude / perpLength
        )
        
        let (offsetDirection, offsetDistance) = getStreetEdgeOffset(blockSide: blockSide)
        
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
    
    private func getStreetEdgeOffset(blockSide: String) -> (direction: Double, distance: Double) {
        let side = blockSide.lowercased()
        let parkingLaneOffset = 0.00003
        
        if side.contains("north") || side.contains("northeast") || side.contains("northwest") {
            return (-1.0, parkingLaneOffset)
        } else if side.contains("south") || side.contains("southeast") || side.contains("southwest") {
            return (1.0, parkingLaneOffset)
        } else if side.contains("east") {
            return (-1.0, parkingLaneOffset)
        } else if side.contains("west") {
            return (1.0, parkingLaneOffset)
        } else {
            return (1.0, parkingLaneOffset * 0.5)
        }
    }
}

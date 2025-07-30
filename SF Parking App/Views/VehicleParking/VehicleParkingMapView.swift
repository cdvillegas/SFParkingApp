import SwiftUI
import MapKit
import CoreLocation

struct VehicleParkingMapView: View {
    @ObservedObject var viewModel: VehicleParkingViewModel
    @State private var currentMapHeading: CLLocationDirection = 0
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    @State private var userLocation: CLLocation?
    @State private var animatedUserCoordinate: CLLocationCoordinate2D?
    @State private var smartSelectionTimer: Timer?
    @State private var markerStillTimer: Timer?
    @State private var lastMapCenterCoordinate: CLLocationCoordinate2D?
    @State private var isAppActive: Bool = true
    @Namespace private var mapScope
    
    // Use ViewModel's published heading property
    private var currentHeading: CLLocationDirection {
        viewModel.userHeading
    }
    
    var body: some View {
        Map(position: $viewModel.mapPosition, interactionModes: isAppActive ? .all : [], scope: mapScope) {
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
        .overlay(enableLocationButton, alignment: .bottom)
        .overlay(alignment: .topTrailing) {
            MapCompass(scope: mapScope)
                .padding(.top, 140) // Lower position under the buttons
                .padding(.trailing, 12)
        }
        .mapStyle(.standard)
        .mapScope(mapScope)
        .mapControls {
            // Empty mapControls block hides default controls
        }
        .onMapCameraChange(frequency: .continuous) { context in
            guard isAppActive else { return }
            currentMapHeading = context.camera.heading
            handleMapCameraChange(context)
        }
        .onAppear {
            // Initialize user location on view appear
            userLocation = viewModel.locationManager.userLocation
            if let location = userLocation {
                animatedUserCoordinate = location.coordinate
            }
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
            
            // Smoothly animate user location changes
            if let location = newLocation {
                animateUserLocationChange(to: location.coordinate)
                
                // Only center map on user location if not showing onboarding and no parking location is set
                let hasParkedVehicle = viewModel.vehicleManager.currentVehicle?.parkingLocation != nil
                let isShowingOnboarding = !OnboardingManager.hasCompletedOnboarding
                if !hasParkedVehicle && !isShowingOnboarding {
                    viewModel.centerMapOnLocation(location.coordinate)
                }
            }
        }
        .onReceive(viewModel.locationManager.$authorizationStatus) { newStatus in
            // Update user location when authorization changes
            userLocation = viewModel.locationManager.userLocation
            if let location = userLocation {
                animatedUserCoordinate = location.coordinate
            }
            
            // If permission was just granted, request location immediately
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                viewModel.locationManager.requestLocation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh when returning from Settings
            viewModel.locationManager.refreshAuthorizationStatus()
            NotificationManager.shared.checkPermissionStatus()
            userLocation = viewModel.locationManager.userLocation
            if let location = userLocation {
                animatedUserCoordinate = location.coordinate
            }
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
                    
                    // Pin with adaptive urgency color
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            getMovingPinColor(),
                                            getMovingPinColor().opacity(0.8)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: vehicle.type.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: getMovingPinColor().opacity(0.4), radius: 6, x: 0, y: 3)
                        
                        // Pin tail
                        RoundedRectangle(cornerRadius: 1)
                            .fill(getMovingPinColor())
                            .frame(width: 3, height: 12)
                    }
                    .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
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
                    enableLocationMapButton
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
                            .fill(.thinMaterial)
                            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
                    )
            }
        }
    }
    
    @ViewBuilder
    private var userLocationButton: some View {
        if isUserLocationAvailable {
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
                            .fill(.thinMaterial)
                            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
                    )
            }
        }
    }
    
    // Location button is now handled in VehicleParkingView map controls
    @ViewBuilder
    private var enableLocationMapButton: some View {
        EmptyView()
    }
    
    // Check if user location is effectively available (both permission and coordinate)
    private var isUserLocationAvailable: Bool {
        let hasPermission = viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || 
                           viewModel.locationManager.authorizationStatus == .authorizedAlways
        let hasCoordinate = animatedUserCoordinate != nil
        return hasPermission && hasCoordinate
    }
    
    // Location button is now handled in VehicleParkingView map controls
    @ViewBuilder
    private var enableLocationButton: some View {
        EmptyView()
    }
    
    // MARK: - Map Content Builders
    
    @MapContentBuilder
    private var userLocationAnnotation: some MapContent {
        if let animatedCoordinate = animatedUserCoordinate {
            Annotation("", coordinate: animatedCoordinate) {
                UserDirectionCone(heading: currentHeading, mapHeading: currentMapHeading)
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
                        streetDataManager: viewModel.streetDataManager,
                        onTap: {
                            viewModel.centerMapOnLocation(parkingLocation.coordinate)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Urgency Color Logic
    
    private enum UrgencyLevel {
        case critical  // < 24 hours
        case safe      // >= 24 hours
    }
    
    private func getUrgencyLevel(for schedule: SweepSchedule) -> UrgencyLevel {
        let nextOccurrence = calculateNextOccurrenceForSchedule(schedule)
        if let nextDate = nextOccurrence {
            let hoursUntil = nextDate.timeIntervalSinceNow / 3600
            return hoursUntil < 24 ? .critical : .safe
        }
        return .safe
    }
    
    private func calculateNextOccurrenceForSchedule(_ schedule: SweepSchedule) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        
        guard let weekday = schedule.weekday,
              let fromHour = schedule.fromhour,
              let startHour = Int(fromHour) else {
            return nil
        }
        
        let weekdayNum = dayStringToWeekdayMap(weekday)
        guard weekdayNum > 0 else { return nil }
        
        // Look ahead for up to 3 months to find valid occurrences
        for monthOffset in 0..<3 {
            guard let futureMonth = calendar.date(byAdding: .month, value: monthOffset, to: now) else { continue }
            
            // Get all occurrences of the target weekday in this month
            let monthOccurrences = getAllWeekdayOccurrencesInMonthMap(weekday: weekdayNum, month: futureMonth, calendar: calendar)
            
            for (weekNumber, weekdayDate) in monthOccurrences.enumerated() {
                let weekPos = weekNumber + 1
                let applies = doesScheduleApplyToWeekMap(weekNumber: weekPos, schedule: schedule)
                
                if applies {
                    // Create the actual start time for this occurrence
                    guard let scheduleDateTime = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: weekdayDate) else { continue }
                    
                    // Only include if the schedule time is in the future
                    if scheduleDateTime > now {
                        return scheduleDateTime
                    }
                }
            }
        }
        
        return nil
    }
    
    private func getAllWeekdayOccurrencesInMonthMap(weekday: Int, month: Date, calendar: Calendar) -> [Date] {
        var occurrences: [Date] = []
        
        // Get the first day of the month
        let monthComponents = calendar.dateComponents([.year, .month], from: month)
        guard let firstDayOfMonth = calendar.date(from: monthComponents) else { return [] }
        
        // Find the first occurrence of the target weekday in this month
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        var daysToAdd = weekday - firstWeekday
        if daysToAdd < 0 {
            daysToAdd += 7
        }
        
        guard let firstOccurrence = calendar.date(byAdding: .day, value: daysToAdd, to: firstDayOfMonth) else { return [] }
        
        // Add all occurrences of this weekday in the month (typically 4-5 times)
        var currentDate = firstOccurrence
        while calendar.component(.month, from: currentDate) == calendar.component(.month, from: month) {
            occurrences.append(currentDate)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) else { break }
            currentDate = nextWeek
        }
        
        return occurrences
    }
    
    private func doesScheduleApplyToWeekMap(weekNumber: Int, schedule: SweepSchedule) -> Bool {
        switch weekNumber {
        case 1: return schedule.week1 == "1"
        case 2: return schedule.week2 == "1"
        case 3: return schedule.week3 == "1"
        case 4: return schedule.week4 == "1"
        case 5: return schedule.week5 == "1"
        default: return false
        }
    }
    
    private func dayStringToWeekdayMap(_ dayString: String) -> Int {
        let normalizedDay = dayString.lowercased().trimmingCharacters(in: .whitespaces)
        
        switch normalizedDay {
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
    
    private func getUrgencyColor(for schedule: SweepSchedule) -> Color {
        let urgencyLevel = getUrgencyLevel(for: schedule)
        switch urgencyLevel {
        case .critical:
            return .red
        case .safe:
            return .green
        }
    }
    
    private func getMovingPinColor() -> Color {
        // Use the color of the currently selected schedule, or green as default
        if viewModel.hasSelectedSchedule,
           viewModel.selectedScheduleIndex < viewModel.nearbySchedules.count {
            let selectedSchedule = viewModel.nearbySchedules[viewModel.selectedScheduleIndex].schedule
            return getUrgencyColor(for: selectedSchedule)
        }
        return .green  // Default to green when no schedule selected
    }
    
    // Helper function to check if cleaning is today and hasn't ended yet
    private func isCleaningActiveToday(schedule: SweepSchedule) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now) // 1 = Sunday, 7 = Saturday
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeInMinutes = currentHour * 60 + currentMinute
        
        // Map weekday names to numbers (1 = Sunday, 7 = Saturday)
        let weekdayMap: [String: Int] = [
            "Sunday": 1, "Sun": 1,
            "Monday": 2, "Mon": 2,
            "Tuesday": 3, "Tues": 3, "Tue": 3,
            "Wednesday": 4, "Wed": 4,
            "Thursday": 5, "Thu": 5, "Thurs": 5,
            "Friday": 6, "Fri": 6,
            "Saturday": 7, "Sat": 7
        ]
        
        // Check if the schedule is for today
        if let scheduleWeekday = schedule.weekday,
           let scheduleDayNumber = weekdayMap[scheduleWeekday],
           scheduleDayNumber == currentWeekday {
            
            // Parse end time from tohour field (format: "11" for 11 AM, "14" for 2 PM)
            if let endHourString = schedule.tohour,
               let endHour = Int(endHourString) {
                let endTimeInMinutes = endHour * 60
                
                // Debug print
                print("🔴 Checking schedule: \(scheduleWeekday) \(schedule.fromhour ?? "")-\(endHourString), Current time: \(currentHour):\(currentMinute)")
                
                // Return true if current time is before the end time
                return currentTimeInMinutes < endTimeInMinutes
            }
        }
        
        return false
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
                                {
                                    let isSelected = index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule
                                    
                                    if isSelected {
                                        return getUrgencyColor(for: scheduleWithSide.schedule)
                                    } else {
                                        return Color.secondary.opacity(0.6)
                                    }
                                }(),
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
                                    getUrgencyColor(for: scheduleWithSide.schedule).opacity(0.25),
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
    
    private func animateUserLocationChange(to newCoordinate: CLLocationCoordinate2D) {
        // If this is the first location update, set immediately without animation
        guard let currentCoordinate = animatedUserCoordinate else {
            animatedUserCoordinate = newCoordinate
            return
        }
        
        // Calculate distance to determine animation approach
        let currentLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let newLocation = CLLocation(latitude: newCoordinate.latitude, longitude: newCoordinate.longitude)
        let distance = currentLocation.distance(from: newLocation)
        
        // Only animate if movement is significant enough (ignore tiny GPS jitter)
        guard distance > 3 else { return }
        
        // Smooth sliding animations based on distance
        if distance < 20 { // Small movements (3-20 meters) - walking precision
            withAnimation(.easeInOut(duration: 3.0)) {
                animatedUserCoordinate = newCoordinate
            }
        } else if distance < 100 { // Medium movements (20-100 meters) - walking/jogging
            withAnimation(.easeInOut(duration: 4.0)) {
                animatedUserCoordinate = newCoordinate
            }
        } else if distance < 500 { // Large movements (100-500 meters) - fast walking/biking
            withAnimation(.easeInOut(duration: 5.0)) {
                animatedUserCoordinate = newCoordinate
            }
        } else if distance < 2000 { // Very large movements (0.5-2 km) - driving
            withAnimation(.easeInOut(duration: 6.0)) {
                animatedUserCoordinate = newCoordinate
            }
        } else {
            // Very large jumps (10+ km) - long distance travel (LA to SF)
            // Use a smooth but faster animation to avoid jarring immediate jump
            withAnimation(.easeInOut(duration: 3.0)) {
                animatedUserCoordinate = newCoordinate
            }
        }
    }
    
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

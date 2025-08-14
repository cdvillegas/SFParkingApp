import SwiftUI
import MapKit
import CoreLocation
import Combine

@MainActor
class VehicleParkingViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.73143, longitude: -122.44143), // Default view center
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.20)
        )
    )
    
    // UI State
    @Published var showingVehiclesList = false
    @Published var showingAddVehicle = false
    @Published var showingEditVehicle: Vehicle?
    @Published var isSettingLocation = false
    @Published var settingAddress: String?
    @Published var settingCoordinate = CLLocationCoordinate2D()
    @Published var showingVehicleActions: Vehicle?
    @Published var isSettingLocationForNewVehicle = false
    
    // Location setting state
    @Published var detectedSchedule: SweepSchedule?
    @Published var scheduleConfidence: Float = 0.0
    @Published var isAutoDetectingSchedule = false
    @Published var lastDetectionCoordinate: CLLocationCoordinate2D?
    
    // Schedule selection state
    @Published var nearbySchedules: [SweepScheduleWithSide] = []
    @Published var selectedScheduleIndex: Int = 0
    @Published var hasSelectedSchedule: Bool = true
    @Published var showingScheduleSelection = false
    @Published var schedulesLoadedForCurrentLocation = false
    
    // Two-step flow states
    @Published var isConfirmingSchedule = false
    @Published var confirmedLocation: CLLocationCoordinate2D?
    @Published var confirmedAddress: String?
    @Published var hoveredScheduleIndex: Int?
    
    // Schedule update coordination
    @Published var isLoadingNewSchedulesForConfirmation = false
    
    // Notification state
    @Published var showingNotificationPermissionAlert = false
    
    // Location state (forwarded from LocationManager)
    @Published var userHeading: CLLocationDirection = 0
    
    // MARK: - Private Properties
    
    private var detectionDebounceTimer: Timer?
    private var autoResetTimer: Timer?
    private var lastInteractionTime = Date()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Managers (injected)
    let locationManager: LocationManager
    let streetDataManager: StreetDataManager
    let vehicleManager: VehicleManager
    let debouncedGeocoder: DebouncedGeocodingHandler
    let notificationManager: NotificationManager
    
    
    // MARK: - Initialization
    
    init(
        locationManager: LocationManager = LocationManager(),
        streetDataManager: StreetDataManager = StreetDataManager(),
        vehicleManager: VehicleManager = VehicleManager.shared, // CRITICAL FIX: Use shared instance
        debouncedGeocoder: DebouncedGeocodingHandler = DebouncedGeocodingHandler(),
        notificationManager: NotificationManager = NotificationManager.shared
    ) {
        self.locationManager = locationManager
        self.streetDataManager = streetDataManager
        self.vehicleManager = vehicleManager
        self.debouncedGeocoder = debouncedGeocoder
        self.notificationManager = notificationManager
        
        // Subscribe to LocationManager changes to forward them as published properties
        setupLocationSubscriptions()
    }
    
    private func setupLocationSubscriptions() {
        // Forward heading changes from LocationManager
        locationManager.$userHeading
            .receive(on: DispatchQueue.main)
            .assign(to: \.userHeading, on: self)
            .store(in: &cancellables)
        
        // Listen for Smart Park location saves to clear old schedule data
        NotificationCenter.default.publisher(for: .smartParkLocationSaved)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearScheduleDataForSmartPark()
            }
            .store(in: &cancellables)
        
        // Listen for Smart Park automatic updates to refresh schedule with detected data
        NotificationCenter.default.publisher(for: .smartParkAutomaticUpdateCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSmartParkAutomaticUpdate(notification)
            }
            .store(in: &cancellables)
    }
    
    private func clearScheduleDataForSmartPark() {
        print("🚗 Smart Park location saved - clearing old schedule data and detecting new schedules")
        
        // Clear all schedule-related state
        nearbySchedules = []
        selectedScheduleIndex = 0
        hasSelectedSchedule = false
        detectedSchedule = nil
        scheduleConfidence = 0.0
        showingScheduleSelection = false
        schedulesLoadedForCurrentLocation = false
        
        // Clear street data manager state
        streetDataManager.schedule = nil
        streetDataManager.nextUpcomingSchedule = nil
        
        // Get the new parking location and detect schedules for it
        if let currentVehicle = vehicleManager.currentVehicle,
           let parkingLocation = currentVehicle.parkingLocation {
            print("🚗 Detecting schedules for Smart Park location: \(parkingLocation.address)")
            
            // Trigger schedule detection for the new location
            autoDetectSchedule(for: parkingLocation.coordinate)
        }
        
        print("🚗 Schedule data cleared and new schedule detection started")
    }
    
    private func handleSmartParkAutomaticUpdate(_ notification: Notification) {
        print("🚗 [Smart Park] Handling automatic update in ViewModel")
        
        guard let userInfo = notification.userInfo,
              let coordinateData = userInfo["coordinate"] as? [String: Double],
              let latitude = coordinateData["latitude"],
              let longitude = coordinateData["longitude"] else {
            print("❌ [Smart Park] Invalid notification data in ViewModel")
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let address = userInfo["address"] as? String ?? ""
        
        print("🚗 [Smart Park] Processing automatic update for: \(address)")
        
        // Check if schedule data was included in the notification
        if let scheduleData = userInfo["detectedSchedule"] as? [String: Any],
           let streetName = scheduleData["streetName"] as? String,
           let weekday = scheduleData["weekday"] as? String,
           let startTime = scheduleData["startTime"] as? String,
           let endTime = scheduleData["endTime"] as? String,
           let blockSide = scheduleData["blockSide"] as? String {
            
            print("📅 [Smart Park] Using schedule from notification: \(streetName) - \(weekday) \(startTime)-\(endTime)")
            
            // Update street data manager with the detected schedule immediately
            updateStreetDataManagerWithSmartParkSchedule(
                coordinate: coordinate,
                streetName: streetName,
                weekday: weekday,
                startTime: startTime,
                endTime: endTime,
                blockSide: blockSide
            )
        } else {
            print("📅 [Smart Park] No schedule in notification, checking saved parking location first")
            
            // CRITICAL FIX: Check if Smart Park already saved a schedule to the parking location
            if let currentVehicle = vehicleManager.currentVehicle,
               let parkingLocation = currentVehicle.parkingLocation,
               let savedSchedule = parkingLocation.selectedSchedule {
                
                print("📅 [Smart Park] Found saved schedule in parking location: \(savedSchedule.streetName)")
                
                // Convert and use the saved schedule
                let sweepSchedule = StreetDataService.shared.convertToSweepSchedule(from: savedSchedule)
                streetDataManager.schedule = sweepSchedule
                streetDataManager.selectedSchedule = sweepSchedule
                streetDataManager.nextUpcomingSchedule = streetDataManager.calculateNextScheduleImmediate(for: sweepSchedule)
                streetDataManager.processNextSchedule(for: sweepSchedule)
                
                // CRITICAL: Force UI refresh immediately
                objectWillChange.send()
                vehicleManager.objectWillChange.send()
                
                print("✅ [Smart Park] Loaded saved schedule into UI: \(savedSchedule.streetName) - \(savedSchedule.weekday) \(savedSchedule.startTime)-\(savedSchedule.endTime)")
                print("🔄 [Smart Park] UI refresh triggered for saved schedule")
            } else {
                print("📅 [Smart Park] No saved schedule found, performing fresh detection")
                // Fallback: perform schedule detection if no schedule data in notification or saved location
                performScheduleDetection(for: coordinate)
            }
        }
    }
    
    private func updateStreetDataManagerWithSmartParkSchedule(
        coordinate: CLLocationCoordinate2D,
        streetName: String,
        weekday: String,
        startTime: String,
        endTime: String,
        blockSide: String
    ) {
        // Trigger schedule detection for the new coordinate and save it to the parking location
        print("📅 [Smart Park] Triggering fresh schedule detection for updated location")
        
        // Get the address from current parking location or use street name as fallback
        let addressToUse = vehicleManager.currentVehicle?.parkingLocation?.address ?? streetName
        
        Task {
            // Perform schedule detection and save
            await self.performScheduleDetectionAndSave(for: coordinate, address: addressToUse)
            
            await MainActor.run {
                print("✅ [Smart Park] StreetDataManager updated with schedule: \(streetName) - \(weekday) \(startTime)-\(endTime)")
                print("📅 [Smart Park] Next schedule: \(self.streetDataManager.nextUpcomingSchedule?.date.description ?? "none")")
                print("🔄 [Smart Park] UI update triggered")
            }
        }
    }
    
    private func handleRemindersForUpdatedSchedule(_ schedule: PersistedSweepSchedule, at coordinate: CLLocationCoordinate2D) {
        print("🔔 [Smart Park] Handling reminders for updated schedule")
        
        // Get current vehicle for reminder context
        guard vehicleManager.currentVehicle != nil else {
            print("⚠️ [Smart Park] No current vehicle for reminder setup")
            return
        }
        
        // The existing reminder system will automatically pick up the new schedule
        // when the user's active reminders are evaluated against the updated parking location
        // No additional action needed here as reminders are schedule-agnostic and location-based
        
        print("✅ [Smart Park] Schedule updated - existing reminders will use new schedule automatically")
    }
    
    private func performScheduleDetectionAndSave(for coordinate: CLLocationCoordinate2D, address: String) async {
        print("📅 [Smart Park] Performing schedule detection and saving to parking location")
        
        // First, perform the normal schedule detection for UI updates
        await MainActor.run {
            performScheduleDetection(for: coordinate)
        }
        
        // Wait a moment for the detection to complete
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Now check if a schedule was detected and save it to the parking location
        await MainActor.run {
            guard let currentVehicle = vehicleManager.currentVehicle,
                  let parkingLocation = currentVehicle.parkingLocation else {
                print("⚠️ [Smart Park] No current vehicle or parking location for schedule save")
                return
            }
            
            // Check if schedule was detected
            let detectedSchedule = streetDataManager.selectedSchedule
            
            if let schedule = detectedSchedule {
                print("📅 [Smart Park] Detected schedule found, updating parking location: \(schedule.streetName)")
                
                // Convert SweepSchedule to PersistedSweepSchedule
                let persistedSchedule = PersistedSweepSchedule(from: schedule, side: schedule.blockside ?? "Unknown")
                
                // Create updated parking location with the detected schedule
                let updatedParkingLocation = ParkingLocation(
                    coordinate: coordinate,
                    address: address,
                    timestamp: parkingLocation.timestamp,
                    source: parkingLocation.source,
                    name: parkingLocation.name,
                    color: parkingLocation.color,
                    isActive: parkingLocation.isActive,
                    selectedSchedule: persistedSchedule
                )
                
                // Save the updated parking location
                vehicleManager.setParkingLocation(for: currentVehicle, location: updatedParkingLocation)
                print("✅ [Smart Park] Parking location updated with detected schedule")
                
                // CRITICAL: Force UI refresh by triggering objectWillChange on all relevant components
                self.objectWillChange.send()
                vehicleManager.objectWillChange.send()
                
                // Also ensure the next upcoming schedule is calculated and updated
                streetDataManager.nextUpcomingSchedule = streetDataManager.calculateNextScheduleImmediate(for: schedule)
                streetDataManager.processNextSchedule(for: schedule)
                
                // Post notification for any UI components that might be listening
                NotificationCenter.default.post(
                    name: NSNotification.Name("smartParkScheduleRefresh"),
                    object: nil,
                    userInfo: [
                        "schedule": persistedSchedule,
                        "coordinate": [
                            "latitude": coordinate.latitude,
                            "longitude": coordinate.longitude
                        ]
                    ]
                )
                
                print("🔄 [Smart Park] All UI components refreshed with new schedule")
            } else {
                print("📅 [Smart Park] No schedule detected for this location")
                
                // Update parking location to remove any old schedule
                let updatedParkingLocation = ParkingLocation(
                    coordinate: coordinate,
                    address: address,
                    timestamp: parkingLocation.timestamp,
                    source: parkingLocation.source,
                    name: parkingLocation.name,
                    color: parkingLocation.color,
                    isActive: parkingLocation.isActive,
                    selectedSchedule: nil
                )
                
                vehicleManager.setParkingLocation(for: currentVehicle, location: updatedParkingLocation)
                
                // Clear UI schedule data
                streetDataManager.schedule = nil
                streetDataManager.selectedSchedule = nil
                streetDataManager.nextUpcomingSchedule = nil
                
                // Force UI refresh
                self.objectWillChange.send()
                vehicleManager.objectWillChange.send()
                
                // Post notification for UI components
                NotificationCenter.default.post(
                    name: NSNotification.Name("smartParkScheduleRefresh"),
                    object: nil,
                    userInfo: [
                        "schedule": NSNull(),
                        "coordinate": [
                            "latitude": coordinate.latitude,
                            "longitude": coordinate.longitude
                        ]
                    ]
                )
                
                print("✅ [Smart Park] Parking location updated with no schedule, UI cleared")
            }
        }
    }
    
    
    // MARK: - Location Setting Methods
    
    func startSettingLocationForVehicle(_ vehicle: Vehicle) {
        vehicleManager.selectVehicle(vehicle)
        startSettingLocation()
    }
    
    func startSettingLocation() {
        isSettingLocation = true
        
        // Prioritize user location, then vehicle location, then default to SF
        let startCoordinate: CLLocationCoordinate2D
        if let userLocation = locationManager.userLocation {
            startCoordinate = userLocation.coordinate
            centerMapOnLocation(startCoordinate)
        } else if let selectedVehicle = vehicleManager.selectedVehicle,
                  let parkingLocation = selectedVehicle.parkingLocation {
            // If no user location but vehicle has a parking location, center on vehicle
            startCoordinate = parkingLocation.coordinate
            centerMapOnLocation(startCoordinate)
        } else {
            // First time setting location - show wider SF view for easy navigation
            startCoordinate = CLLocationCoordinate2D(latitude: 37.73143, longitude: -122.44143)
            centerMapOnLocationForFirstTime(startCoordinate)
        }
        
        // For existing vehicles, preserve the address but don't center on parking location
        if let selectedVehicle = vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
            settingAddress = parkingLocation.address // Use the current parking location address
        }
        
        settingCoordinate = startCoordinate
        // Only geocode if we don't already have an address from parking location
        if settingAddress == nil {
            geocodeLocation(startCoordinate)
        }
        
        // No schedule detection in step 1
    }
    
    func autoDetectSchedule(for coordinate: CLLocationCoordinate2D) {
        // Check if we need to skip this detection (debouncing)
        if let lastCoordinate = lastDetectionCoordinate {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude))
            
            // Different thresholds for different modes - more responsive
            let threshold: Double = isConfirmingSchedule ? 15 : 3 // Smaller thresholds for faster updates
            if distance < threshold {
                return
            }
        }
        
        // Cancel any existing timer
        detectionDebounceTimer?.invalidate()
        
        // Much more responsive debouncing while keeping conflict prevention
        let debounceTime: TimeInterval = isConfirmingSchedule ? 0.15 : 0.1
        detectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: debounceTime, repeats: false) { _ in
            Task { @MainActor in
                self.performScheduleDetection(for: coordinate)
            }
        }
    }
    
    func autoDetectScheduleWithPreservation(for coordinate: CLLocationCoordinate2D) {
        // Always try to detect schedules as user moves, but preserve selection when schedules are the same
        
        // Check if we need to skip this detection (debouncing for API calls)
        if let lastCoordinate = lastDetectionCoordinate {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude))
            
            // Smaller threshold for more responsive updates
            let threshold: Double = 5 // 5 meters
            if distance < threshold {
                return
            }
        }
        
        // Cancel any existing timer
        detectionDebounceTimer?.invalidate()
        
        // Shorter debounce for continuous updates
        let debounceTime: TimeInterval = 0.05 // 50ms debounce
        detectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: debounceTime, repeats: false) { _ in
            Task { @MainActor in
                self.performScheduleDetectionWithPreservation(for: coordinate)
            }
        }
    }
    
    func performScheduleDetection(for coordinate: CLLocationCoordinate2D) {
        guard !isAutoDetectingSchedule else { return }
        
        isAutoDetectingSchedule = true
        if isConfirmingSchedule {
            isLoadingNewSchedulesForConfirmation = true
        }
        lastDetectionCoordinate = coordinate
        schedulesLoadedForCurrentLocation = false
        
        StreetDataService.shared.getNearbySchedulesForSelection(for: coordinate) { result in
            DispatchQueue.main.async {
                self.isAutoDetectingSchedule = false
                self.isLoadingNewSchedulesForConfirmation = false
                self.schedulesLoadedForCurrentLocation = true
                
                switch result {
                case .success(let schedulesWithSides):
                    if !schedulesWithSides.isEmpty {
                        // Sort schedules for consistent ordering
                        let sortedSchedules = self.sortSchedules(schedulesWithSides)
                        self.nearbySchedules = sortedSchedules
                        if self.isConfirmingSchedule {
                            // During confirmation, set initial selection if we don't have any
                            if self.selectedScheduleIndex >= sortedSchedules.count || !self.hasSelectedSchedule {
                                self.selectedScheduleIndex = 0
                                self.hasSelectedSchedule = true
                                self.hoveredScheduleIndex = 0
                                self.detectedSchedule = sortedSchedules[0].schedule
                                self.scheduleConfidence = 0.8
                            }
                        } else {
                            self.initialSmartSelection(for: coordinate, schedulesWithSides: sortedSchedules)
                        }
                    } else {
                        self.nearbySchedules = []
                        self.selectedScheduleIndex = 0
                        self.detectedSchedule = nil
                        self.scheduleConfidence = 0.0
                        
                        // CRITICAL FIX: Clear street data manager schedule when no schedules found
                        self.streetDataManager.schedule = nil
                        self.streetDataManager.selectedSchedule = nil
                        self.streetDataManager.nextUpcomingSchedule = nil
                        print("🗑️ [Schedule Detection] Cleared all schedule data - no schedules found")
                    }
                case .failure(_):
                    self.nearbySchedules = []
                    self.selectedScheduleIndex = 0
                    self.detectedSchedule = nil
                    self.scheduleConfidence = 0.0
                    
                    // CRITICAL FIX: Clear street data manager schedule on API failure
                    self.streetDataManager.schedule = nil
                    self.streetDataManager.selectedSchedule = nil
                    self.streetDataManager.nextUpcomingSchedule = nil
                    print("🗑️ [Schedule Detection] Cleared all schedule data - API failure")
                }
            }
        }
    }
    
    func performScheduleDetectionWithPreservation(for coordinate: CLLocationCoordinate2D) {
        guard !isAutoDetectingSchedule else { return }
        
        // Store current state to potentially preserve
        let currentSchedules = nearbySchedules
        let currentSelectedIndex = selectedScheduleIndex
        let currentHasSelection = hasSelectedSchedule
        let currentDetectedSchedule = detectedSchedule
        let currentScheduleConfidence = scheduleConfidence
        
        isAutoDetectingSchedule = true
        if isConfirmingSchedule {
            isLoadingNewSchedulesForConfirmation = true
        }
        lastDetectionCoordinate = coordinate
        
        StreetDataService.shared.getNearbySchedulesForSelection(for: coordinate) { result in
            DispatchQueue.main.async {
                self.isAutoDetectingSchedule = false
                self.isLoadingNewSchedulesForConfirmation = false
                self.schedulesLoadedForCurrentLocation = true
                
                switch result {
                case .success(let newSchedulesWithSides):
                    if !newSchedulesWithSides.isEmpty {
                        // Sort both current and new schedules for consistent comparison
                        let sortedCurrent = self.sortSchedules(currentSchedules)
                        let sortedNew = self.sortSchedules(newSchedulesWithSides)
                        
                        // Check if schedules are the same as current ones
                        let schedulesAreSame = self.areSchedulesSame(current: sortedCurrent, new: sortedNew)
                        
                        if schedulesAreSame && !currentSchedules.isEmpty {
                            // Schedules are the same, preserve current selection
                            // Don't update nearbySchedules to avoid disrupting selection
                            return
                        } else {
                            // Schedules are different, update them with sorted list
                            self.nearbySchedules = sortedNew
                            
                            // Try to preserve selection if possible
                            if !currentSchedules.isEmpty && currentHasSelection {
                                // Find the previously selected schedule in the new sorted list
                                if currentSelectedIndex < currentSchedules.count {
                                    let targetSchedule = currentSchedules[currentSelectedIndex]
                                    if let preservedIndex = self.findMatchingScheduleIndex(
                                        target: targetSchedule,
                                        in: sortedNew
                                    ) {
                                        self.selectedScheduleIndex = preservedIndex
                                        self.hasSelectedSchedule = true
                                        self.detectedSchedule = sortedNew[preservedIndex].schedule
                                        self.scheduleConfidence = currentScheduleConfidence
                                    } else {
                                        // Previous selection not found, start fresh
                                        self.initialSmartSelection(for: coordinate, schedulesWithSides: sortedNew)
                                    }
                                } else {
                                    // Invalid index, start fresh
                                    self.initialSmartSelection(for: coordinate, schedulesWithSides: sortedNew)
                                }
                            } else {
                                // No previous selection to preserve
                                self.initialSmartSelection(for: coordinate, schedulesWithSides: sortedNew)
                            }
                        }
                    } else {
                        // No schedules found
                        self.nearbySchedules = []
                        self.selectedScheduleIndex = 0
                        self.detectedSchedule = nil
                        self.scheduleConfidence = 0.0
                        self.hasSelectedSchedule = false
                        
                        // CRITICAL FIX: Clear street data manager schedule when no schedules found
                        self.streetDataManager.schedule = nil
                        self.streetDataManager.selectedSchedule = nil
                        self.streetDataManager.nextUpcomingSchedule = nil
                        print("🗑️ [Schedule Detection w/ Preservation] Cleared all schedule data - no schedules found")
                    }
                case .failure(_):
                    // API failed, keep current schedules if we have them
                    if currentSchedules.isEmpty {
                        self.nearbySchedules = []
                        self.selectedScheduleIndex = 0
                        self.detectedSchedule = nil
                        self.scheduleConfidence = 0.0
                        self.hasSelectedSchedule = false
                        
                        // CRITICAL FIX: Clear street data manager schedule on API failure with no previous data
                        self.streetDataManager.schedule = nil
                        self.streetDataManager.selectedSchedule = nil
                        self.streetDataManager.nextUpcomingSchedule = nil
                        print("🗑️ [Schedule Detection w/ Preservation] Cleared all schedule data - API failure with no previous data")
                    }
                    // If we have current schedules, don't clear them on API failure
                }
            }
        }
    }
    
    func initialSmartSelection(for coordinate: CLLocationCoordinate2D, schedulesWithSides: [SweepScheduleWithSide]) {
        // CRITICAL FIX: Check if Smart Park already detected the correct schedule and use that
        if let currentVehicle = vehicleManager.currentVehicle,
           let parkingLocation = currentVehicle.parkingLocation,
           let savedSchedule = parkingLocation.selectedSchedule {
            
            // Find the matching schedule in the detected schedules list
            let matchingIndex = schedulesWithSides.firstIndex { scheduleWithSide in
                let schedule = scheduleWithSide.schedule
                return schedule.streetName == savedSchedule.streetName &&
                       schedule.weekday == savedSchedule.weekday &&
                       schedule.startTime == savedSchedule.startTime &&
                       schedule.endTime == savedSchedule.endTime
            }
            
            if let index = matchingIndex {
                print("✅ [Smart Park] Found matching schedule at index \(index): \(savedSchedule.streetName) - \(savedSchedule.weekday)")
                selectedScheduleIndex = index
                hasSelectedSchedule = true
                detectedSchedule = schedulesWithSides[index].schedule
                scheduleConfidence = 0.9 // High confidence for Smart Park match
                
                // Use the saved schedule (which has the correct side)
                let sweepSchedule = StreetDataService.shared.convertToSweepSchedule(from: savedSchedule)
                streetDataManager.schedule = sweepSchedule
                streetDataManager.selectedSchedule = sweepSchedule
                streetDataManager.nextUpcomingSchedule = streetDataManager.calculateNextScheduleImmediate(for: sweepSchedule)
                streetDataManager.processNextSchedule(for: sweepSchedule)
                
                print("✅ [Smart Park] Using Smart Park detected schedule: \(savedSchedule.streetName) - \(savedSchedule.weekday) \(savedSchedule.startTime)-\(savedSchedule.endTime)")
                return
            } else {
                print("⚠️ [Smart Park] Could not find matching schedule in detected list, falling back to first")
            }
        }
        
        // Fallback: select the first schedule when no Smart Park match found
        selectedScheduleIndex = 0
        hasSelectedSchedule = true
        detectedSchedule = schedulesWithSides[0].schedule
        scheduleConfidence = 0.8 // Lower confidence for fallback
        
        // Update StreetDataManager with first detected schedule
        let selectedSchedule = schedulesWithSides[0].schedule
        streetDataManager.schedule = selectedSchedule
        streetDataManager.selectedSchedule = selectedSchedule
        streetDataManager.nextUpcomingSchedule = streetDataManager.calculateNextScheduleImmediate(for: selectedSchedule)
        streetDataManager.processNextSchedule(for: selectedSchedule)
        
        print("✅ [Smart Park] Updated StreetDataManager with first detected schedule: \(selectedSchedule.streetName)")
    }
    
    func cancelSettingLocation() {
        // Center map on vehicle if it exists, using the same zoom as the vehicle button
        if let currentVehicle = vehicleManager.currentVehicle,
           let parkingLocation = currentVehicle.parkingLocation {
            centerMapOnLocation(parkingLocation.coordinate)
        }
        
        completeLocationSetting()
    }
    
    // MARK: - Two-Step Flow Methods
    
    func proceedToScheduleConfirmation() {
        let coordinate = settingCoordinate
        
        confirmedLocation = coordinate
        confirmedAddress = settingAddress
        isConfirmingSchedule = true
        
        centerMapOnLocationWithZoomIn(coordinate)
        
        // Ensure we have schedules loaded for this location
        if nearbySchedules.isEmpty {
            // If no schedules were loaded in background, load them now
            autoDetectSchedule(for: coordinate)
        } else {
            // Schedules already exist, sort them and set initial selection
            nearbySchedules = sortSchedules(nearbySchedules)
            selectedScheduleIndex = 0
            hasSelectedSchedule = true
            hoveredScheduleIndex = 0
        }
    }
    
    func goBackToLocationSetting() {
        isConfirmingSchedule = false
        nearbySchedules = []
        hoveredScheduleIndex = nil
        
        if let coordinate = confirmedLocation {
            // Use the standard zoom level when going back to location setting
            centerMapOnLocation(coordinate)
        }
    }
    
    func onScheduleHover(_ index: Int) {
        hoveredScheduleIndex = index
        selectedScheduleIndex = index
        hasSelectedSchedule = true
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Schedule Methods
    
    func selectScheduleOption(_ index: Int) {
        guard index >= 0 && index < nearbySchedules.count else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        if selectedScheduleIndex == index && hasSelectedSchedule {
            hasSelectedSchedule = false
            detectedSchedule = nil
        } else {
            selectedScheduleIndex = index
            detectedSchedule = nearbySchedules[index].schedule
            hasSelectedSchedule = true
        }
        
        if hasSelectedSchedule {
            settingCoordinate = nearbySchedules[index].offsetCoordinate
            let distance = nearbySchedules[index].distance
            scheduleConfidence = Float(max(0.3, min(0.9, 1.0 - (distance / 50.0))))
        } else {
            scheduleConfidence = 0.0
        }
    }
    
    // MARK: - Confirmation Methods
    
    func confirmVehicleLocation(at coordinate: CLLocationCoordinate2D, address: String) {
        guard let selectedVehicle = vehicleManager.selectedVehicle else { return }
        
        // Set the location directly without going through the setting flow
        vehicleManager.setManualParkingLocation(
            for: selectedVehicle,
            coordinate: coordinate,
            address: address,
            selectedSchedule: nil
        )
        
        // Update the map to center on the new location
        centerMapOnLocation(coordinate)
    }
    
    func confirmUnifiedLocation() {
        guard let selectedVehicle = vehicleManager.selectedVehicle,
              let address = settingAddress else { return }
        
        let persistedSchedule = (!nearbySchedules.isEmpty && hasSelectedSchedule) ?
            PersistedSweepSchedule(from: nearbySchedules[selectedScheduleIndex].schedule, side: nearbySchedules[selectedScheduleIndex].side) :
            nil
        
        vehicleManager.setManualParkingLocation(
            for: selectedVehicle,
            coordinate: settingCoordinate,
            address: address,
            selectedSchedule: persistedSchedule
        )
        
        if !nearbySchedules.isEmpty && hasSelectedSchedule {
            let selectedSchedule = nearbySchedules[selectedScheduleIndex].schedule
            // Set schedule immediately for instant UI update
            streetDataManager.schedule = selectedSchedule
            // Calculate next schedule immediately for instant "Move by" date
            streetDataManager.nextUpcomingSchedule = streetDataManager.calculateNextScheduleImmediate(for: selectedSchedule)
            // Also process in background for any additional calculations
            streetDataManager.processNextSchedule(for: selectedSchedule)
        } else {
            streetDataManager.schedule = nil
            streetDataManager.nextUpcomingSchedule = nil
        }
        
        completeLocationSetting()
    }
    
    // MARK: - Map Methods
    
    func centerMapOnLocation(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            )
        }
    }
    
    
    func centerMapOnLocationWithZoomIn(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001) // Zoom in closer for schedule confirmation
                )
            )
        }
    }
    
    func centerMapOnLocationForFirstTime(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.13) // Slightly more zoomed in for location setting
                )
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func completeLocationSetting() {
        isSettingLocation = false
        isConfirmingSchedule = false
        isSettingLocationForNewVehicle = false
        settingAddress = nil
        detectedSchedule = nil
        scheduleConfidence = 0.0
        isAutoDetectingSchedule = false
        isLoadingNewSchedulesForConfirmation = false
        lastDetectionCoordinate = nil
        detectionDebounceTimer?.invalidate()
        schedulesLoadedForCurrentLocation = false
        
        // Reset two-step flow state
        confirmedLocation = nil
        confirmedAddress = nil
        hoveredScheduleIndex = nil
        detectionDebounceTimer = nil
        
        // Clear schedule selection
        nearbySchedules = []
        selectedScheduleIndex = 0
        showingScheduleSelection = false
    }
    
    private func geocodeLocation(_ coordinate: CLLocationCoordinate2D) {
        debouncedGeocoder.reverseGeocode(coordinate: coordinate) { address, _ in
            DispatchQueue.main.async {
                self.settingAddress = address
            }
        }
    }
    
    private func detectSchedulesForConfirmation(at coordinate: CLLocationCoordinate2D) {
        isAutoDetectingSchedule = true
        
        StreetDataService.shared.getNearbySchedulesForSelection(for: coordinate) { result in
            DispatchQueue.main.async {
                self.isAutoDetectingSchedule = false
                
                switch result {
                case .success(let schedulesWithSides):
                    self.nearbySchedules = schedulesWithSides
                    if !schedulesWithSides.isEmpty {
                        self.selectedScheduleIndex = 0
                        self.hasSelectedSchedule = true
                        self.hoveredScheduleIndex = 0
                    }
                case .failure(_):
                    self.nearbySchedules = []
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var canProceedToScheduleConfirmation: Bool {
        // Can proceed if we're not currently detecting schedules AND either:
        // 1. Schedules have been loaded for the current location, OR
        // 2. We've never started detection (e.g., for areas with no API coverage)
        return !isAutoDetectingSchedule && (schedulesLoadedForCurrentLocation || lastDetectionCoordinate == nil)
    }
    
    var locationStatusTitle: String {
        // Show the address if available, otherwise show current parking location address
        if let address = settingAddress {
            let components = address.components(separatedBy: ", ")
            if components.count >= 1 {
                return components[0] // Street address
            } else {
                return address
            }
        } else if let currentVehicle = vehicleManager.currentVehicle,
                  let parkingLocation = currentVehicle.parkingLocation {
            let components = parkingLocation.address.components(separatedBy: ", ")
            if components.count >= 1 {
                return components[0] // Street address from current parking location
            } else {
                return parkingLocation.address
            }
        } else {
            return "Move map to parking location"
        }
    }
    
    var locationStatusSubtitle: String {
        // Show neighborhood and city
        if let address = settingAddress {
            let components = address.components(separatedBy: ", ")
            if components.count >= 2 {
                return components.dropFirst().joined(separator: ", ") // Everything after street
            } else {
                return "San Francisco, CA"
            }
        } else if let currentVehicle = vehicleManager.currentVehicle,
                  let parkingLocation = currentVehicle.parkingLocation {
            let components = parkingLocation.address.components(separatedBy: ", ")
            if components.count >= 2 {
                return components.dropFirst().joined(separator: ", ") // Everything after street
            } else {
                return "San Francisco, CA"
            }
        } else {
            return "San Francisco, CA"
        }
    }
    
    var headerTitle: String {
        if isConfirmingSchedule {
            return "Confirm Schedule"
        } else if isSettingLocation {
            return "Move Vehicle"
        } else {
            return ""
        }
    }
    
    var headerSubtitle: String? {
        if isConfirmingSchedule {
            return generateSmartHeaderSubtitle()
        } else if isSettingLocation {
            return "Position the pin where you parked"
        } else {
            return nil
        }
    }
    
    private func generateSmartHeaderSubtitle() -> String {
        guard !nearbySchedules.isEmpty else {
            return "No schedules found"
        }
        
        // Get unique street names
        let streetNames = Set(nearbySchedules.map { $0.schedule.streetName })
        
        if streetNames.count == 1 {
            // Single street
            let streetName = streetNames.first!
            return "Select which side of \(streetName) you're on"
        } else {
            // Multiple streets
            return "Select which side of which street you're on"
        }
    }
    
    private func formatTimeAgo(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        let minutes = Int(timeInterval / 60)
        let hours = Int(timeInterval / 3600)
        let days = Int(timeInterval / 86400)
        
        if minutes < 60 {
            if minutes < 2 {
                return "just now"
            } else {
                return "\(minutes) minutes ago"
            }
        } else if hours < 24 {
            if hours == 1 {
                return "1 hour ago"
            } else {
                return "\(hours) hours ago"
            }
        } else {
            if days == 1 {
                return "1 day ago"
            } else {
                return "\(days) days ago"
            }
        }
    }
    
    // MARK: - Schedule Comparison Methods
    
    private func areSchedulesSame(current: [SweepScheduleWithSide], new: [SweepScheduleWithSide]) -> Bool {
        guard current.count == new.count else { return false }
        
        // Compare each schedule for equality
        for (index, currentSchedule) in current.enumerated() {
            let newSchedule = new[index]
            
            // Compare key properties that identify a schedule
            if currentSchedule.schedule.streetName != newSchedule.schedule.streetName ||
               currentSchedule.schedule.weekday != newSchedule.schedule.weekday ||
               currentSchedule.schedule.fromhour != newSchedule.schedule.fromhour ||
               currentSchedule.schedule.tohour != newSchedule.schedule.tohour ||
               currentSchedule.side != newSchedule.side ||
               currentSchedule.schedule.cnn != newSchedule.schedule.cnn ||  // Compare unique identifier
               currentSchedule.schedule.limits != newSchedule.schedule.limits {  // Compare block limits
                return false
            }
        }
        
        return true
    }
    
    private func sortSchedules(_ schedules: [SweepScheduleWithSide]) -> [SweepScheduleWithSide] {
        return schedules.sorted { first, second in
            // Sort by street name first
            if first.schedule.streetName != second.schedule.streetName {
                return first.schedule.streetName < second.schedule.streetName
            }
            
            // Then by side
            if first.side != second.side {
                return first.side < second.side
            }
            
            // Then by weekday (if both have weekdays)
            if let firstWeekday = first.schedule.weekday,
               let secondWeekday = second.schedule.weekday,
               firstWeekday != secondWeekday {
                return firstWeekday < secondWeekday
            }
            
            // Then by start hour (if both have fromhour values)
            if let firstHour = first.schedule.fromhour,
               let secondHour = second.schedule.fromhour,
               firstHour != secondHour {
                return firstHour < secondHour
            }
            
            // Finally by distance (closer schedules first)
            return first.distance < second.distance
        }
    }
    
    private func findMatchingScheduleIndex(target: SweepScheduleWithSide, in schedules: [SweepScheduleWithSide]) -> Int? {
        for (index, schedule) in schedules.enumerated() {
            // Check if this schedule matches the target
            if schedule.schedule.streetName == target.schedule.streetName &&
               schedule.schedule.weekday == target.schedule.weekday &&
               schedule.schedule.fromhour == target.schedule.fromhour &&
               schedule.schedule.tohour == target.schedule.tohour &&
               schedule.side == target.side &&
               schedule.schedule.cnn == target.schedule.cnn &&  // Compare unique identifier
               schedule.schedule.limits == target.schedule.limits {  // Compare block limits
                return index
            }
        }
        return nil
    }
    
    // MARK: - Cleanup
    
    deinit {
        detectionDebounceTimer?.invalidate()
        autoResetTimer?.invalidate()
        cancellables.removeAll()
        debouncedGeocoder.cancel()
    }
}

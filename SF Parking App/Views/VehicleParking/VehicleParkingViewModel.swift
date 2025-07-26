import SwiftUI
import MapKit
import CoreLocation
import Combine

@MainActor
class VehicleParkingViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7551, longitude: -122.4528), // Sutro Tower
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
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
        vehicleManager: VehicleManager = VehicleManager(),
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
    }
    
    // MARK: - Location Setting Methods
    
    func startSettingLocationForVehicle(_ vehicle: Vehicle) {
        vehicleManager.selectVehicle(vehicle)
        startSettingLocation()
    }
    
    func startSettingLocation() {
        isSettingLocation = true
        
        // Always center on user location first when moving a vehicle
        let startCoordinate: CLLocationCoordinate2D
        if let userLocation = locationManager.userLocation {
            startCoordinate = userLocation.coordinate
            centerMapOnLocation(startCoordinate)
        } else {
            startCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            centerMapOnLocation(startCoordinate)
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
                        self.nearbySchedules = schedulesWithSides
                        if self.isConfirmingSchedule {
                            // During confirmation, set initial selection if we don't have any
                            if self.selectedScheduleIndex >= schedulesWithSides.count || !self.hasSelectedSchedule {
                                self.selectedScheduleIndex = 0
                                self.hasSelectedSchedule = true
                                self.hoveredScheduleIndex = 0
                                self.detectedSchedule = schedulesWithSides[0].schedule
                                self.scheduleConfidence = 0.8
                            }
                        } else {
                            self.initialSmartSelection(for: coordinate, schedulesWithSides: schedulesWithSides)
                        }
                    } else {
                        self.nearbySchedules = []
                        self.selectedScheduleIndex = 0
                        self.detectedSchedule = nil
                        self.scheduleConfidence = 0.0
                    }
                case .failure(_):
                    self.nearbySchedules = []
                    self.selectedScheduleIndex = 0
                    self.detectedSchedule = nil
                    self.scheduleConfidence = 0.0
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
        let _ = detectedSchedule
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
                        // Check if schedules are the same as current ones
                        let schedulesAreSame = self.areSchedulesSame(current: currentSchedules, new: newSchedulesWithSides)
                        
                        if schedulesAreSame && !currentSchedules.isEmpty {
                            // Schedules are the same, preserve current selection
                            // Don't update nearbySchedules to avoid disrupting selection
                            return
                        } else {
                            // Schedules are different, update them
                            self.nearbySchedules = newSchedulesWithSides
                            
                            // Try to preserve selection if possible
                            if !currentSchedules.isEmpty && currentHasSelection && currentSelectedIndex < newSchedulesWithSides.count {
                                // Check if the previously selected schedule exists in new results
                                if let preservedIndex = self.findMatchingScheduleIndex(
                                    target: currentSchedules[currentSelectedIndex],
                                    in: newSchedulesWithSides
                                ) {
                                    self.selectedScheduleIndex = preservedIndex
                                    self.hasSelectedSchedule = true
                                    self.detectedSchedule = newSchedulesWithSides[preservedIndex].schedule
                                    self.scheduleConfidence = currentScheduleConfidence
                                } else {
                                    // Previous selection not found, start fresh
                                    self.initialSmartSelection(for: coordinate, schedulesWithSides: newSchedulesWithSides)
                                }
                            } else {
                                // No previous selection to preserve
                                self.initialSmartSelection(for: coordinate, schedulesWithSides: newSchedulesWithSides)
                            }
                        }
                    } else {
                        // No schedules found
                        self.nearbySchedules = []
                        self.selectedScheduleIndex = 0
                        self.detectedSchedule = nil
                        self.scheduleConfidence = 0.0
                        self.hasSelectedSchedule = false
                    }
                case .failure(_):
                    // API failed, keep current schedules if we have them
                    if currentSchedules.isEmpty {
                        self.nearbySchedules = []
                        self.selectedScheduleIndex = 0
                        self.detectedSchedule = nil
                        self.scheduleConfidence = 0.0
                        self.hasSelectedSchedule = false
                    }
                    // If we have current schedules, don't clear them on API failure
                }
            }
        }
    }
    
    func initialSmartSelection(for coordinate: CLLocationCoordinate2D, schedulesWithSides: [SweepScheduleWithSide]) {
        // Always select the first schedule when new schedules load
        selectedScheduleIndex = 0
        hasSelectedSchedule = true
        detectedSchedule = schedulesWithSides[0].schedule
        scheduleConfidence = 0.8 // High confidence for auto-selection
    }
    
    func cancelSettingLocation() {
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
            // Schedules already exist, set initial selection
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
            centerMapOnLocationForVehicleMove(coordinate)
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
            streetDataManager.schedule = selectedSchedule
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
    
    func centerMapOnLocationForVehicleMove(_ coordinate: CLLocationCoordinate2D) {
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
            return "My Vehicle"
        }
    }
    
    var headerSubtitle: String? {
        if isConfirmingSchedule {
            return generateSmartHeaderSubtitle()
        } else if isSettingLocation {
            return "Position the pin where you parked"
        } else {
            // Show last parked timing for My Vehicle or initial instruction
            if let currentVehicle = vehicleManager.currentVehicle,
               let parkingLocation = currentVehicle.parkingLocation {
                let timeAgo = formatTimeAgo(from: parkingLocation.timestamp)
                return "Last parked \(timeAgo)"
            } else {
                return "Location not set"
            }
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
               currentSchedule.schedule.startTime != newSchedule.schedule.startTime ||
               currentSchedule.schedule.endTime != newSchedule.schedule.endTime ||
               currentSchedule.side != newSchedule.side {
                return false
            }
        }
        
        return true
    }
    
    private func findMatchingScheduleIndex(target: SweepScheduleWithSide, in schedules: [SweepScheduleWithSide]) -> Int? {
        for (index, schedule) in schedules.enumerated() {
            // Check if this schedule matches the target
            if schedule.schedule.streetName == target.schedule.streetName &&
               schedule.schedule.weekday == target.schedule.weekday &&
               schedule.schedule.startTime == target.schedule.startTime &&
               schedule.schedule.endTime == target.schedule.endTime &&
               schedule.side == target.side {
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

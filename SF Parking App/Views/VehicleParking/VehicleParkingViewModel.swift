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
    
    // Notification state
    @Published var showingNotificationPermissionAlert = false
    
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
    }
    
    // MARK: - Location Setting Methods
    
    func startSettingLocationForVehicle(_ vehicle: Vehicle) {
        vehicleManager.selectVehicle(vehicle)
        startSettingLocation()
    }
    
    func startSettingLocation() {
        isSettingLocation = true
        
        // Prioritize current vehicle parking location when moving a vehicle
        let startCoordinate: CLLocationCoordinate2D
        if let selectedVehicle = vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
            startCoordinate = parkingLocation.coordinate
            settingAddress = parkingLocation.address // Use the current parking location address
            centerMapOnLocationForVehicleMove(startCoordinate)
        } else if let userLocation = locationManager.userLocation {
            startCoordinate = userLocation.coordinate
            centerMapOnLocation(startCoordinate)
        } else {
            startCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            centerMapOnLocation(startCoordinate)
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
            
            // Only detect if we've moved more than 5 meters (reduced for faster response)
            if distance < 5 {
                return
            }
        }
        
        // Cancel any existing timer
        detectionDebounceTimer?.invalidate()
        
        // Reduced debounce time for faster response
        detectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
            self.performScheduleDetection(for: coordinate)
        }
    }
    
    func performScheduleDetection(for coordinate: CLLocationCoordinate2D) {
        guard !isAutoDetectingSchedule else { return }
        
        isAutoDetectingSchedule = true
        lastDetectionCoordinate = coordinate
        schedulesLoadedForCurrentLocation = false
        
        StreetDataService.shared.getNearbySchedulesForSelection(for: coordinate) { result in
            DispatchQueue.main.async {
                self.isAutoDetectingSchedule = false
                self.schedulesLoadedForCurrentLocation = true
                
                switch result {
                case .success(let schedulesWithSides):
                    if !schedulesWithSides.isEmpty {
                        self.nearbySchedules = schedulesWithSides
                        self.initialSmartSelection(for: coordinate, schedulesWithSides: schedulesWithSides)
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
    
    func initialSmartSelection(for coordinate: CLLocationCoordinate2D, schedulesWithSides: [SweepScheduleWithSide]) {
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
        
        let flippedIndex = schedulesWithSides.count - 1 - closestIndex
        let finalIndex = flippedIndex < schedulesWithSides.count ? flippedIndex : closestIndex
        
        selectedScheduleIndex = finalIndex
        hasSelectedSchedule = true
        detectedSchedule = schedulesWithSides[finalIndex].schedule
        scheduleConfidence = Float(max(0.3, min(0.9, 1.0 - (closestDistance / 50.0))))
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
        
        // Schedules should already be loaded from background detection
        // Set initial selection if schedules exist
        if !nearbySchedules.isEmpty {
            selectedScheduleIndex = 0
            hasSelectedSchedule = true
            hoveredScheduleIndex = 0
        }
        // Note: If schedules are empty, it means no restrictions found (which is valid)
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
            return "Select which side of the street you're on"
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
    
    // MARK: - Cleanup
    
    deinit {
        detectionDebounceTimer?.invalidate()
        autoResetTimer?.invalidate()
        cancellables.removeAll()
    }
}

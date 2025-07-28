import SwiftUI
import MapKit
import CoreLocation

struct VehicleParkingView: View {
    @StateObject private var viewModel = VehicleParkingViewModel()
    @State private var showingRemindersSheet = false
    @State private var showingAutoParkingSettings = false
    @EnvironmentObject var parkingDetectionHandler: ParkingDetectionHandler
    @StateObject private var parkingDetector = ParkingDetector.shared
    @State private var wasHandlingAutoParking = false
    
    // Optional parameters for auto-parking detection
    var autoDetectedLocation: CLLocationCoordinate2D?
    var autoDetectedAddress: String?
    var autoDetectedSource: ParkingSource?
    var onAutoParkingHandled: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Map extends to full screen
            VehicleParkingMapView(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Floating interface with buttons above
            VStack {
                Spacer()
                Spacer() // Extra spacer to push container down more
                
                // Map control buttons - positioned above content
                HStack {
                    Spacer()
                    mapControlButtons
                        .padding(.trailing, 12)
                        .padding(.bottom, 16)
                }
                
                bottomInterface
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
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
        .onChange(of: viewModel.isSettingLocation) { oldValue, newValue in
            // When location setting completes and we were handling auto parking, clear the data
            if oldValue == true && newValue == false && wasHandlingAutoParking {
                wasHandlingAutoParking = false
                onAutoParkingHandled?()
            }
        }
        .onReceive(viewModel.locationManager.$userLocation) { newUserLocation in
            // If user location becomes available and no parking location is set, center on user
            if let userLocation = newUserLocation,
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
        .sheet(isPresented: $showingAutoParkingSettings) {
            SmartParkingSettingsView()
        }
    }
    
    // MARK: - Map Control Buttons
    
    private var mapControlButtons: some View {
        Group {
            if !viewModel.isConfirmingSchedule || viewModel.isSettingLocation {
                HStack(spacing: 12) {
                    vehicleButton
                    userLocationButton
                }
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
        if viewModel.locationManager.userLocation != nil &&
           (viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || 
            viewModel.locationManager.authorizationStatus == .authorizedAlways) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
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
    
    
    // MARK: - Bottom Interface
    
    private var bottomInterface: some View {
        VStack(spacing: 0) {
            // Main interface
            VehicleLocationSetting(
                viewModel: viewModel,
                onShowReminders: {
                    showingRemindersSheet = true
                },
                onShowSmartParking: {
                    showingAutoParkingSettings = true
                }
            )
        }
    }
    
    // MARK: - Setup
    
    private func setupView() {
        // Start location services to get user location
        if viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || 
           viewModel.locationManager.authorizationStatus == .authorizedAlways {
            viewModel.locationManager.requestLocation()
        }
        
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
        } else {
            // Default to Sutro Tower view but also try to get user location
            viewModel.mapPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7551, longitude: -122.4528),
                    span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
                )
            )
        }
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
        
        // Ensure we have a vehicle to set the location for
        if viewModel.vehicleManager.currentVehicle == nil {
            // Create a default vehicle if none exists
            if viewModel.vehicleManager.activeVehicles.isEmpty {
                // Will need to show add vehicle sheet first
                viewModel.showingAddVehicle = true
                return
            }
        }
        
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
            print("Auto-detected parking via \(sourceText) at \(address)")
        }
        
        // Mark that we're handling auto parking so we can clear data when done
        wasHandlingAutoParking = true
        
        // Don't clear immediately - wait for user to confirm or cancel
        // parkingDetectionHandler will be cleared when user confirms the location
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

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct VehicleParkingView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var streetDataManager = StreetDataManager()
    @StateObject private var vehicleManager = VehicleManager()
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
    
    // MARK: - UI State
    @State private var showingVehiclesList = false
    @State private var showingAddVehicle = false
    @State private var showingEditVehicle: Vehicle?
    @State private var isSettingLocation = false
    @State private var settingAddress: String?
    @State private var settingCoordinate = CLLocationCoordinate2D()
    @State private var showingVehicleActions: Vehicle?
    
    // Auto-center functionality
    @State private var autoResetTimer: Timer?
    @State private var lastInteractionTime = Date()
    
    // Notification tracking
    @State private var showingNotificationPermissionAlert = false
    @State private var lastNotificationLocationId: UUID?
    
    // MARK: - Haptic Feedback
    private let impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            mapView

            bottomInterface
        }
        .sheet(item: $showingVehicleActions) { vehicle in
            VehicleActionSheet(
                vehicle: vehicle,
                onClose: { showingVehicleActions = nil },
                onEdit: {
                    showingEditVehicle = vehicle
                    showingVehicleActions = nil
                },
                onSetLocation: {
                    startSettingLocationForVehicle(vehicle)
                    showingVehicleActions = nil
                }
            )
            .presentationDragIndicator(.visible)
            .presentationDetents([.height(200)])
            .presentationCompactAdaptation(.none)
        }
        .sheet(isPresented: $showingVehiclesList) {
            NavigationView {
                vehicleListSheet
            }
        }
        .sheet(isPresented: $showingAddVehicle) {
            AddEditVehicleView(
                vehicleManager: vehicleManager,
                editingVehicle: nil
            )
        }
        .sheet(item: $showingEditVehicle) { vehicle in
            AddEditVehicleView(
                vehicleManager: vehicleManager,
                editingVehicle: vehicle
            )
        }
        .onAppear {
            setupView()
            prepareHaptics()
            setupNotificationHandling()
            NotificationManager.shared.validateAndRecoverNotifications()
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
                // Vehicle parking locations
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
        }
        .overlay(
            Group {
                if isSettingLocation, let vehicle = vehicleManager.selectedVehicle {
                    VehicleParkingMapMarker(
                        vehicle: vehicle,
                        isSelected: true,
                        onTap: {} // Do nothing or provide haptic
                    )
                    .frame(width: 20, height: 20)
                    .offset(y: -22) // visually center pin tip
                    .allowsHitTesting(false)
                }
            }
        )
        .mapStyle(.standard)
        .onMapCameraChange { context in
            if isSettingLocation {
                settingCoordinate = context.camera.centerCoordinate
                geocodeLocation(settingCoordinate)
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
    
    // MARK: - Top Controls
    
    private var topControls: some View {
        HStack {
            // Vehicles list button
            Button(action: { showingVehiclesList = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("\(vehicleManager.activeVehicles.count)")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            
            Spacer()
            
            // Center on vehicles button
            if !vehicleManager.activeVehicles.isEmpty {
                Button(action: centerMapOnVehicles) {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    // MARK: - Bottom Interface
    
    private var bottomInterface: some View {
        VStack(spacing: 0) {
            if isSettingLocation {
                // Setting location mode UI
                VStack(spacing: 16) {
                    HStack {
                        Text("Choose Parking Location")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    if let selectedVehicle = vehicleManager.selectedVehicle {
                        HStack {
                            Text("Setting location for \(selectedVehicle.displayName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            cancelSettingLocation()
                        }
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                        
                        Button("Set Location") {
                            confirmSetLocation()
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                // Normal mode - show vehicles
                if !vehicleManager.activeVehicles.isEmpty {
                    // Show upcoming reminders for selected vehicle
                    if let selectedVehicle = vehicleManager.selectedVehicle,
                       let parkingLocation = selectedVehicle.parkingLocation {
                        UpcomingRemindersSection(
                            streetDataManager: streetDataManager,
                            parkingLocation: parkingLocation
                        )
                        
                        Divider().padding(.horizontal, 20)
                    }
                    
                    // Header with title and add button
                    HStack {
                        Text("My Vehicles")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: { showingVehiclesList = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "car.2.fill")
                                    .font(.system(size: 16, weight: .medium))
                                Text("\(vehicleManager.activeVehicles.count)")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray6))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    
                    // Swipeable vehicles section
                    SwipeableVehicleSection(
                        vehicles: vehicleManager.activeVehicles,
                        selectedVehicle: vehicleManager.selectedVehicle,
                        onVehicleSelected: { vehicle in
                            selectVehicle(vehicle)
                        },
                        onVehicleTap: { vehicle in
                            showVehicleActions(vehicle)
                        }
                    )
                    .padding(.bottom, 20)
                    
                    // Set parking location button for selected vehicle
                    if let selectedVehicle = vehicleManager.selectedVehicle {
                        if selectedVehicle.parkingLocation == nil {
                            Button("Set Parking Location") {
                                startSettingLocationForVehicle(selectedVehicle)
                            }
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                } else {
                    // Empty state with add vehicle button
                    VStack(spacing: 20) {
                        emptyStateCard
                        
                        Button(action: { showingAddVehicle = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Add Your First Vehicle")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    private func vehicleActionsInterface(for vehicle: Vehicle) -> some View {
        VStack(spacing: 16) {
            // Header with back button
            HStack {
                Button(action: {
                    showingVehicleActions = nil
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(vehicle.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Balance the layout
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.body)
                        .fontWeight(.medium)
                }
                .opacity(0)
            }
            .padding(.horizontal, 20)
            
            // Action buttons
            VStack(spacing: 12) {
                if vehicle.parkingLocation != nil {
                    Button("Update Parking Location") {
                        startSettingLocationForVehicle(vehicle)
                        showingVehicleActions = nil
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                } else {
                    Button("Set Parking Location") {
                        startSettingLocationForVehicle(vehicle)
                        showingVehicleActions = nil
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                
                Button("Edit Vehicle") {
                    showingEditVehicle = vehicle
                    showingVehicleActions = nil
                }
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Vehicles")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Add your first vehicle to start tracking parking locations and get street cleaning reminders")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
    
    // MARK: - Vehicle List Sheet
    
    private var vehicleListSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("My Vehicles")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    showingVehiclesList = false
                }
                .font(.body)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
            
            // Vehicles list
            if vehicleManager.activeVehicles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "car.circle.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(.secondary)
                    
                    Text("No vehicles yet")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Add your first vehicle to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vehicleManager.activeVehicles) { vehicle in
                            VehicleListRow(
                                vehicle: vehicle,
                                isSelected: vehicleManager.selectedVehicle?.id == vehicle.id,
                                onTap: {
                                    selectVehicle(vehicle)
                                    showingVehiclesList = false
                                },
                                onEdit: {
                                    showingEditVehicle = vehicle
                                },
                                onSetLocation: {
                                    startSettingLocationForVehicle(vehicle)
                                    showingVehiclesList = false
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
    }
    
    // MARK: - Methods
    
    private func selectVehicle(_ vehicle: Vehicle) {
        impactFeedbackLight.impactOccurred()
        vehicleManager.selectVehicle(vehicle)
        
        if let parkingLocation = vehicle.parkingLocation {
            centerMapOnLocation(parkingLocation.coordinate)
            fetchStreetDataAndScheduleNotifications(for: parkingLocation)
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
            startCoordinate = CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232)
        }
        
        settingCoordinate = startCoordinate
        centerMapOnLocation(startCoordinate)
        geocodeLocation(startCoordinate)
    }
    
    private func cancelSettingLocation() {
        impactFeedbackLight.impactOccurred()
        isSettingLocation = false
        settingAddress = nil
    }
    
    private func confirmSetLocation() {
        guard let selectedVehicle = vehicleManager.selectedVehicle,
              let address = settingAddress else { return }
        
        notificationFeedback.notificationOccurred(.success)
        
        vehicleManager.setManualParkingLocation(
            for: selectedVehicle,
            coordinate: settingCoordinate,
            address: address
        )
        
        // Request notification permission if not already granted
        if notificationManager.notificationPermissionStatus == .notDetermined {
            notificationManager.requestNotificationPermission()
        }
        
        isSettingLocation = false
        settingAddress = nil
        
        // Fetch street data for the new location
        if let parkingLocation = selectedVehicle.parkingLocation {
            fetchStreetDataAndScheduleNotifications(for: parkingLocation)
        }
    }
    
    
    private func geocodeLocation(_ coordinate: CLLocationCoordinate2D) {
        debouncedGeocoder.reverseGeocode(coordinate: coordinate) { address, _ in
            DispatchQueue.main.async {
                self.settingAddress = address
            }
        }
    }
    
    // MARK: - Setup and Lifecycle
    
    private func setupView() {
        // Link managers together (for auto-parking detection)
        motionActivityManager.locationManager = locationManager
        bluetoothManager.locationManager = locationManager
        
        // Only request permissions if onboarding has been completed
        if OnboardingManager.hasCompletedOnboarding {
            locationManager.requestLocationPermission()
            motionActivityManager.requestMotionPermission()
            bluetoothManager.requestBluetoothPermission()
        }
        
        // Center map on selected vehicle or user location
        if let selectedVehicle = vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
            centerMapOnLocation(parkingLocation.coordinate)
            fetchStreetDataAndScheduleNotifications(for: parkingLocation)
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
            
            motionActivityManager.requestMotionPermission()
            bluetoothManager.requestBluetoothPermission()
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
        // Handle notifications when vehicles are selected
    }
    
    private func cleanupResources() {
        autoResetTimer?.invalidate()
        cancellables.removeAll()
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

#Preview {
    VehicleParkingView()
}

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
    @State private var isSettingLocationForNewVehicle = false
    
    // Auto-center functionality
    @State private var autoResetTimer: Timer?
    @State private var lastInteractionTime = Date()
    
    // Notification tracking
    @State private var showingNotificationPermissionAlert = false
    @State private var lastNotificationLocationId: UUID?
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
            NavigationView {
                vehicleListSheet
            }
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
            if vehicleManager.activeVehicles.isEmpty {
                // Add vehicle button when there are no vehicles
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    showingAddVehicle = true
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
                // Setting location mode UI
                enhancedLocationSettingInterface()
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
                HStack(spacing: 12) {
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
            .padding(.bottom, 28)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
    
    // MARK: - Helper function to open vehicle in Maps
    private func openVehicleInMaps(_ vehicle: Vehicle) {
        guard let parkingLocation = vehicle.parkingLocation else { return }
        
        let coordinate = parkingLocation.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "\(vehicle.displayName) - Parked Location"
        
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    // MARK: - Enhanced Location Setting Interface
    private func enhancedLocationSettingInterface() -> some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            VStack(spacing: 20) {
                // Header with vehicle info
                VStack(spacing: 16) {
                    HStack {
                        Text("Choose Parking Location")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    if let selectedVehicle = vehicleManager.selectedVehicle {
                        HStack(spacing: 12) {
                            // Mini vehicle icon - consistent style
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                selectedVehicle.color.color,
                                                selectedVehicle.color.color.opacity(0.8)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: selectedVehicle.type.iconName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: selectedVehicle.color.color.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Text("Setting location for \(selectedVehicle.displayName)")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                    }
                    
                    // Address preview if available
                    if let address = settingAddress {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Location")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Text(address)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Enhanced action buttons
                HStack(spacing: 12) {
                    Button(isSettingLocationForNewVehicle ? "Skip for Now" : "Cancel") {
                        impactFeedbackLight.impactOccurred()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            cancelSettingLocation()
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    Button("Set Location") {
                        notificationFeedback.notificationOccurred(.success)
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            confirmSetLocation()
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.green.opacity(0.3), radius: 6, x: 0, y: 3)
                    .disabled(settingAddress == nil)
                    .opacity(settingAddress == nil ? 0.6 : 1.0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
    
    // MARK: - Enhanced Normal Vehicle Interface
    private func enhancedNormalVehicleInterface() -> some View {
        VStack(spacing: 0) {
            if !vehicleManager.activeVehicles.isEmpty {
                // Show upcoming reminders for selected vehicle
                if let selectedVehicle = vehicleManager.selectedVehicle,
                   let parkingLocation = selectedVehicle.parkingLocation {
                    UpcomingRemindersSection(
                        streetDataManager: streetDataManager,
                        parkingLocation: parkingLocation
                    )
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                }
                
                // Enhanced header with vehicles list button
                HStack {
                    Text("My Vehicles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Vehicles list button
                    Button(action: {
                        impactFeedbackLight.impactOccurred()
                        showingVehiclesList = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "car.2.fill")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text("\(vehicleManager.activeVehicles.count)")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                
                // Swipeable vehicles section - already perfectly styled
                SwipeableVehicleSection(
                    vehicles: vehicleManager.activeVehicles,
                    selectedVehicle: vehicleManager.selectedVehicle,
                    onVehicleSelected: { vehicle in
                        selectVehicle(vehicle)
                    },
                    onVehicleTap: { vehicle in
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            showVehicleActions(vehicle)
                        }
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
                
                // Big Add Vehicle Button at bottom
                VStack(spacing: 0) {
                    Divider()
                    
                    Button(action: {
                        impactFeedbackLight.impactOccurred()
                        showingAddVehicle = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
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
                    .padding(.vertical, 20)
                }
                .background(Color(.systemBackground))
            }
        }
    }
    
    // MARK: - Methods (keeping existing functionality)
    
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
        isSettingLocationForNewVehicle = false
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
        isSettingLocationForNewVehicle = false
        
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

#Preview {
    VehicleParkingView()
}

import SwiftUI
import MapKit
import CoreLocation

struct VehicleParkingView: View {
    @StateObject private var viewModel = VehicleParkingViewModel()
    @State private var showingRemindersSheet = false
    
    var body: some View {
        ZStack {
            // Background color
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Map section - clean with no overlays
                VehicleParkingMapView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
                
                // Bottom interface
                bottomInterface
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
            // Always use the same NotificationSettingsSheet, create dummy schedule if needed
            let schedule = viewModel.streetDataManager.nextUpcomingSchedule ?? UpcomingSchedule(
                streetName: viewModel.vehicleManager.currentVehicle?.parkingLocation?.address ?? "Your Location",
                date: Date().addingTimeInterval(7 * 24 * 3600), // 1 week from now
                endDate: Date().addingTimeInterval(7 * 24 * 3600 + 7200), // 2 hours later
                dayOfWeek: "Next Week",
                startTime: "8:00 AM",
                endTime: "10:00 AM"
            )
            NotificationSettingsSheet(
                schedule: schedule,
                parkingLocation: viewModel.vehicleManager.currentVehicle?.parkingLocation
            )
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
            // Upcoming reminders (only when not setting location)
            if !viewModel.isSettingLocation,
               let currentVehicle = viewModel.vehicleManager.currentVehicle,
               let parkingLocation = currentVehicle.parkingLocation,
               !viewModel.vehicleManager.activeVehicles.isEmpty {
                UpcomingRemindersSection(
                    streetDataManager: viewModel.streetDataManager,
                    parkingLocation: parkingLocation
                )
                .padding(.horizontal, 20)
                
                Divider()
                    .padding(.horizontal, 20)
            }
            
            // Main interface
            VehicleLocationSetting(
                viewModel: viewModel,
                onShowReminders: {
                    showingRemindersSheet = true
                }
            )
        }
    }
    
    // MARK: - Setup
    
    private func setupView() {
        // Center map on vehicle or user location
        if let selectedVehicle = viewModel.vehicleManager.selectedVehicle,
           let parkingLocation = selectedVehicle.parkingLocation {
            viewModel.centerMapOnLocation(parkingLocation.coordinate)
            
            // Load persisted schedule if available
            if let persistedSchedule = parkingLocation.selectedSchedule {
                let schedule = StreetDataService.shared.convertToSweepSchedule(from: persistedSchedule)
                viewModel.streetDataManager.schedule = schedule
                viewModel.streetDataManager.processNextSchedule(for: schedule)
            }
        } else if let userLocation = viewModel.locationManager.userLocation {
            viewModel.centerMapOnLocation(userLocation.coordinate)
        } else {
            // Default to Sutro Tower view
            viewModel.mapPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7551, longitude: -122.4528),
                    span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
                )
            )
        }
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
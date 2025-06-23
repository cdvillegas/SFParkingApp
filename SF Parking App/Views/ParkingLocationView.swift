//
//  ParkingLocationView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import _MapKit_SwiftUI
import CoreLocation

struct ParkingLocationView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var streetDataManager = StreetDataManager()
    @StateObject private var parkingManager = ParkingLocationManager()
    
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    @State private var isSettingLocation = false
    @State private var previewAddress = ""
    @State private var previewCoordinate = CLLocationCoordinate2D()
    @State private var debounceTimer: Timer?
    
    // Auto-center functionality
    @State private var autoResetTimer: Timer?
    @State private var lastInteractionTime = Date()
    
    // Geocoder for reverse geocoding
    private let geocoder = CLGeocoder()
    
    // MARK: - Haptic Feedback (Reduced)
    private let impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 4) {
            // Map Section
            ZStack {
                if isSettingLocation {
                    // Setting mode map with fixed center pin and user location
                    Map(position: $mapPosition) {
                        // User location annotation
                        if let userLocation = locationManager.userLocation {
                            Annotation("Your Location", coordinate: userLocation.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 20, height: 20)
                                    
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 8, height: 8)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                            }
                        }
                    }
                    .onMapCameraChange { context in
                        previewCoordinate = context.camera.centerCoordinate
                        reverseGeocodeDebounced(coordinate: previewCoordinate)
                    }
                    
                    // Fixed center pin
                    ZStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    // Map control buttons for edit mode
                    MapControlButtons(
                        userLocation: locationManager.userLocation,
                        parkingLocation: parkingManager.currentLocation,
                        onCenterOnUser: centerOnUser,
                        onGoToCar: goToCar,
                        onLocationRequest: { locationManager.requestLocation() }
                    )
                    
                } else {
                    // Normal view with native Map that's fully swipeable
                    Map(position: $mapPosition) {
                        // User location annotation
                        if let userLocation = locationManager.userLocation {
                            Annotation("Your Location", coordinate: userLocation.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 20, height: 20)
                                    
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 8, height: 8)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                            }
                        }
                        
                        // Parking location annotation - changed from red to blue
                        if let parkingLocation = parkingManager.currentLocation {
                            Annotation("Parked Car", coordinate: parkingLocation.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 24, height: 24)
                                    
                                    Image(systemName: "car.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                            }
                        }
                    }
                    .onReceive(locationManager.$userLocation) { location in
                        if let location = location {
                            centerMapOnBothLocations()
                        }
                    }
                    .onReceive(parkingManager.$currentLocation) { parkingLocation in
                        // Fetch street data whenever parking location changes
                        if let location = parkingLocation {
                            streetDataManager.fetchSchedules(for: location.coordinate)
                        }
                        // Re-center map to show both locations
                        centerMapOnBothLocations()
                    }
                    .onMapCameraChange { context in
                        // Track user interaction with map - this is sufficient for detecting movement
                        handleMapInteraction()
                    }
                    
                    MapControlButtons(
                        userLocation: locationManager.userLocation,
                        parkingLocation: parkingManager.currentLocation,
                        onCenterOnUser: centerOnUser,
                        onGoToCar: goToCar,
                        onLocationRequest: { locationManager.requestLocation() }
                    )
                }
            }
            
            // Bottom UI Section
            VStack(spacing: 4) {
                if isSettingLocation {
                    // Setting mode UI - just show current selection
                    LocationSection(
                        parkingLocation: nil,
                        onLocationTap: openInMaps,
                        isPreviewMode: true,
                        previewAddress: previewAddress,
                        previewCoordinate: previewCoordinate
                    )
                } else {
                    // Normal mode UI
                    UpcomingRemindersSection(
                        streetDataManager: streetDataManager,
                        parkingLocation: parkingManager.currentLocation
                    )
                    
                    Divider().padding(.horizontal, 20)
                    
                    LocationSection(
                        parkingLocation: parkingManager.currentLocation,
                        onLocationTap: openInMaps,
                        isPreviewMode: false,
                        previewAddress: nil,
                        previewCoordinate: nil
                    )
                }
                
                // Button Section with improved styling
                VStack(spacing: 16) {
                    if isSettingLocation {
                        // Two-button layout when setting location
                        HStack(spacing: 12) {
                            // Cancel button - improved design
                            Button(action: cancelSettingLocation) {
                                Text("Cancel")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(height: 52)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 26)
                                            .fill(Color(UIColor.secondarySystemBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 26)
                                                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
                                            )
                                    )
                            }
                            .frame(maxWidth: 120) // Constrain cancel button width
                            
                            // Set location button
                            Button(action: setParkingLocation) {
                                Text("Set Location")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(height: 52)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 26)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.green, Color.green.opacity(0.8)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                            .shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
                                    )
                            }
                        }
                    } else {
                        // Single button layout for normal mode
                        Button(action: startSettingLocation) {
                            Text("Update Parking Location")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(height: 56)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                                )
                        }
                        .scaleEffect(1.0) // Add subtle press animation
                        .animation(.easeInOut(duration: 0.1), value: isSettingLocation)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(8, UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0))
            }
            .ignoresSafeArea(.all, edges: .top)
            .background(Color(UIColor.systemBackground))
            .onAppear {
                setupView()
                prepareHaptics()
            }
            .onDisappear {
                // Clean up timers when view disappears
                autoResetTimer?.invalidate()
                debounceTimer?.invalidate()
            }
        }
    }
    
    // MARK: - Auto-Center Functionality
    
    private func handleMapInteraction() {
        // Don't handle interactions in setting mode
        guard !isSettingLocation else { return }
        
        lastInteractionTime = Date()
        
        // Cancel existing timer
        autoResetTimer?.invalidate()
        
        // Start new timer for auto-reset
        autoResetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                // Only reset if we're still in normal mode and enough time has passed
                let timeSinceLastInteraction = Date().timeIntervalSince(lastInteractionTime)
                if timeSinceLastInteraction >= 5.0 && !isSettingLocation {
                    centerMapOnBothLocations()
                }
            }
        }
    }
    
    private func centerMapOnBothLocations() {
        guard !isSettingLocation else { return }
        
        let userLocation = locationManager.userLocation
        let parkingLocation = parkingManager.currentLocation
        
        // Determine what locations we have
        switch (userLocation, parkingLocation) {
        case (let user?, let parking?):
            // Both locations available - create region that includes both
            centerMapOnBothCoordinates(user.coordinate, parking.coordinate)
            
        case (let user?, nil):
            // Only user location available
            centerMap(on: user.coordinate)
            
        case (nil, let parking?):
            // Only parking location available
            centerMap(on: parking.coordinate)
            
        case (nil, nil):
            // No locations available - keep current position or use default
            break
        }
    }
    
    private func centerMapOnBothCoordinates(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) {
        // Step 1: Find the center point between the two coordinates
        let centerLat = (coord1.latitude + coord2.latitude) / 2
        let centerLon = (coord1.longitude + coord2.longitude) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        
        // Step 2: Calculate the span needed to fit both points
        let latDelta = abs(coord1.latitude - coord2.latitude)
        let lonDelta = abs(coord1.longitude - coord2.longitude)
        
        // Step 3: Add padding so points aren't at the edge (2x padding)
        let paddedLatDelta = max(latDelta * 2.0, 0.008) // Minimum zoom level
        let paddedLonDelta = max(lonDelta * 2.0, 0.008)
        
        // Step 4: Use the larger delta to ensure both points fit
        let finalDelta = max(paddedLatDelta, paddedLonDelta)
        let span = MKCoordinateSpan(latitudeDelta: finalDelta, longitudeDelta: finalDelta)
        
        // Step 5: Center the map on the center point with appropriate zoom
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .region(MKCoordinateRegion(center: centerCoordinate, span: span))
        }
    }
    
    // MARK: - Haptic Preparation (Simplified)
    
    private func prepareHaptics() {
        // Prepare only the haptic generators we actually use
        impactFeedbackLight.prepare()
        notificationFeedback.prepare()
    }
    
    // MARK: - Actions
    
    private func setupView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            locationManager.requestLocationPermission()
            
            if let parkingLocation = parkingManager.currentLocation {
                streetDataManager.fetchSchedules(for: parkingLocation.coordinate)
            }
            
            // Initial centering
            centerMapOnBothLocations()
        }
    }
    
    private func startSettingLocation() {
        // Cancel auto-reset timer when entering setting mode
        autoResetTimer?.invalidate()
        
        // Single light haptic for mode change
        impactFeedbackLight.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = true
        }
        
        // Start from current parking location or user location
        let startCoordinate: CLLocationCoordinate2D
        if let parkingLocation = parkingManager.currentLocation {
            startCoordinate = parkingLocation.coordinate
            previewAddress = parkingLocation.address
        } else if let userLocation = locationManager.userLocation {
            startCoordinate = userLocation.coordinate
            reverseGeocode(coordinate: startCoordinate) { address in
                previewAddress = address
            }
        } else {
            startCoordinate = CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232)
            previewAddress = "San Francisco, CA"
        }
        
        previewCoordinate = startCoordinate
        centerMap(on: startCoordinate)
    }
    
    private func setParkingLocation() {
        // Single success notification for completion
        notificationFeedback.notificationOccurred(.success)
        
        parkingManager.setManualParkingLocation(
            coordinate: previewCoordinate,
            address: previewAddress
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
        
        // Resume auto-centering after setting location
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            centerMapOnBothLocations()
        }
    }
    
    private func cancelSettingLocation() {
        // No haptic for cancel - keep it subtle
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
        
        // Resume auto-centering and reset to both locations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            centerMapOnBothLocations()
        }
    }
    
    private func handleMapScreenTap(_ screenPoint: CGPoint) {
        // Only handle taps in normal mode
        guard !isSettingLocation else { return }
        
        // Light haptic feedback for map interaction
        impactFeedbackLight.impactOccurred()
        
        // Track this as a user interaction
        handleMapInteraction()
        
        // Convert screen point to coordinate (this is a simplified approach)
        // In a real implementation, you might want to use MapReader or similar
        // For now, we'll use the current map center as the tap location
        let currentRegion = mapPosition.region
        if let region = currentRegion {
            let tappedCoordinate = region.center
            
            reverseGeocode(coordinate: tappedCoordinate) { address in
                parkingManager.setManualParkingLocation(
                    coordinate: tappedCoordinate,
                    address: address
                )
            }
        }
    }
    
    // MARK: - Reverse Geocoding
    
    private func reverseGeocodeDebounced(coordinate: CLLocationCoordinate2D) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            reverseGeocode(coordinate: coordinate) { address in
                previewAddress = address
            }
        }
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Reverse geocoding error: \(error.localizedDescription)")
                    completion("Selected Location")
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    completion("Selected Location")
                    return
                }
                
                let address = formatAddress(from: placemark)
                completion(address)
            }
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        // Only return street address (number + street name)
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            return "\(streetNumber) \(streetName)"
        } else if let streetName = placemark.thoroughfare {
            return streetName
        }
        
        // Fallback to name if no street info available
        if let name = placemark.name {
            return name
        }
        
        return "Selected Location"
    }
    
    private func centerOnUser() {
        // Cancel auto-reset when user manually centers
        autoResetTimer?.invalidate()
        
        if let location = locationManager.userLocation {
            centerMap(on: location.coordinate)
            
            // Restart auto-reset timer
            handleMapInteraction()
        }
    }
    
    private func goToCar() {
        // Cancel auto-reset when user manually goes to car
        autoResetTimer?.invalidate()
        
        if let parkingLocation = parkingManager.currentLocation {
            centerMap(on: parkingLocation.coordinate)
            
            // Restart auto-reset timer
            handleMapInteraction()
        }
    }
    
    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        // Simple single-location centering with reasonable zoom
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
        }
    }
    
    private func openInMaps(address: String) {
        let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?address=\(encodedAddress)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Combined Location Section

struct LocationSection: View {
    let parkingLocation: ParkingLocation?
    let onLocationTap: (String) -> Void
    let isPreviewMode: Bool
    let previewAddress: String?
    let previewCoordinate: CLLocationCoordinate2D?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parking Location")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            if isPreviewMode {
                // Preview mode content
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(previewAddress ?? "Selected Location")
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                        
                        if let coordinate = previewCoordinate {
                            Text("Lat: \(coordinate.latitude, specifier: "%.6f"), Lon: \(coordinate.longitude, specifier: "%.6f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Normal mode content
                if let location = parkingLocation {
                    Button(action: { onLocationTap(location.address) }) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "car.fill")
                                .foregroundColor(.blue)
                                .font(.body)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.address)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(nil)
                                
                                Text("Tap to open in Maps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "car")
                            .foregroundColor(.secondary)
                            .font(.body)
                        
                        Text("No parking location set")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.top, 0)
        .padding(.bottom, 0)
    }
}

#Preview {
    ParkingLocationView()
}

#Preview("Light Mode") {
    ParkingLocationView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ParkingLocationView()
        .preferredColorScheme(.dark)
}

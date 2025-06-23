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
    
    // Geocoder for reverse geocoding
    private let geocoder = CLGeocoder()
    
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
                    // Normal view with interactive map
                    ParkingMapView(
                        mapPosition: $mapPosition,
                        userLocation: locationManager.userLocation,
                        parkingLocation: parkingManager.currentLocation,
                        onLocationTap: handleMapTap
                    )
                    .onReceive(locationManager.$userLocation) { location in
                        if let location = location {
                            centerMap(on: location.coordinate)
                        }
                    }
                    .onReceive(parkingManager.$currentLocation) { parkingLocation in
                        // Fetch street data whenever parking location changes
                        if let location = parkingLocation {
                            streetDataManager.fetchSchedules(for: location.coordinate)
                        }
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
                            
                            // Set location button - enhanced
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
            }
        }
    }
    
    // MARK: - Actions
    
    private func setupView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            locationManager.requestLocationPermission()
            
            if let parkingLocation = parkingManager.currentLocation {
                streetDataManager.fetchSchedules(for: parkingLocation.coordinate)
            }
        }
    }
    
    private func startSettingLocation() {
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
        parkingManager.setManualParkingLocation(
            coordinate: previewCoordinate,
            address: previewAddress
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
    }
    
    private func cancelSettingLocation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
        
        // Reset to current parking location if exists
        if let parkingLocation = parkingManager.currentLocation {
            centerMap(on: parkingLocation.coordinate)
        }
    }
    
    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        // Only handle taps in normal mode
        guard !isSettingLocation else { return }
        
        reverseGeocode(coordinate: coordinate) { address in
            parkingManager.setManualParkingLocation(
                coordinate: coordinate,
                address: address
            )
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
        if let location = locationManager.userLocation {
            centerMap(on: location.coordinate)
        }
    }
    
    private func goToCar() {
        if let parkingLocation = parkingManager.currentLocation {
            centerMap(on: parkingLocation.coordinate)
        }
    }
    
    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
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

//
//  ParkingLocationView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import _MapKit_SwiftUI
import CoreLocation

// MARK: - Geocoding Cache Manager
class GeocodingCacheManager: ObservableObject {
    static let shared = GeocodingCacheManager()
    
    private let geocoder = CLGeocoder()
    private var cache: [String: CachedGeocodingResult] = [:]
    private var pendingRequests: Set<String> = []
    private let cacheExpirationInterval: TimeInterval = 3600 // 1 hour
    private let minimumDistance: CLLocationDistance = 50 // 50 meters
    
    // Rate limiting
    private var requestQueue: [GeocodingRequest] = []
    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 0.5 // 500ms between requests
    private var requestTimer: Timer?
    
    private init() {}
    
    struct CachedGeocodingResult {
        let address: String
        let neighborhood: String?
        let timestamp: Date
        let coordinate: CLLocationCoordinate2D
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 3600
        }
    }
    
    struct GeocodingRequest {
        let coordinate: CLLocationCoordinate2D
        let completion: (String, String?) -> Void
        let id: String
    }
    
    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        // Round to ~25m precision to improve cache hits
        let lat = round(coordinate.latitude * 10000) / 10000
        let lon = round(coordinate.longitude * 10000) / 10000
        return "\(lat),\(lon)"
    }
    
    func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String, String?) -> Void) {
        let key = cacheKey(for: coordinate)
        
        // Check cache first
        if let cached = cache[key], !cached.isExpired {
            // Verify the cached result is close enough to the requested coordinate
            let cachedLocation = CLLocation(latitude: cached.coordinate.latitude, longitude: cached.coordinate.longitude)
            let requestedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
            if cachedLocation.distance(from: requestedLocation) < minimumDistance {
                DispatchQueue.main.async {
                    completion(cached.address, cached.neighborhood)
                }
                return
            }
        }
        
        // Don't make duplicate requests
        guard !pendingRequests.contains(key) else { return }
        
        // Add to queue
        let request = GeocodingRequest(
            coordinate: coordinate,
            completion: completion,
            id: key
        )
        
        requestQueue.append(request)
        pendingRequests.insert(key)
        
        processQueue()
    }
    
    private func processQueue() {
        guard !requestQueue.isEmpty else { return }
        guard requestTimer == nil else { return } // Already processing
        
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        
        if timeSinceLastRequest >= minimumRequestInterval {
            executeNextRequest()
        } else {
            // Schedule the next request
            let delay = minimumRequestInterval - timeSinceLastRequest
            requestTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                self.requestTimer = nil
                self.executeNextRequest()
            }
        }
    }
    
    private func executeNextRequest() {
        guard let request = requestQueue.first else { return }
        requestQueue.removeFirst()
        
        lastRequestTime = Date()
        
        let location = CLLocation(latitude: request.coordinate.latitude, longitude: request.coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                self?.pendingRequests.remove(request.id)
                
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    // Return fallback for failed requests
                    request.completion("Selected Location", nil)
                } else if let placemark = placemarks?.first {
                    let address = self?.formatAddress(from: placemark) ?? "Selected Location"
                    let neighborhood = self?.formatNeighborhood(from: placemark)
                    
                    // Cache the result
                    self?.cache[request.id] = CachedGeocodingResult(
                        address: address,
                        neighborhood: neighborhood,
                        timestamp: Date(),
                        coordinate: request.coordinate
                    )
                    
                    request.completion(address, neighborhood)
                } else {
                    request.completion("Selected Location", nil)
                }
                
                // Continue processing queue
                self?.processQueue()
            }
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            return "\(streetNumber) \(streetName)"
        } else if let streetName = placemark.thoroughfare {
            return streetName
        }
        
        if let name = placemark.name {
            return name
        }
        
        return "Selected Location"
    }
    
    private func formatNeighborhood(from placemark: CLPlacemark) -> String? {
        var components: [String] = []
        
        if let subLocality = placemark.subLocality, !subLocality.isEmpty {
            components.append(subLocality)
        }
        
        if let locality = placemark.locality, !locality.isEmpty {
            components.append(locality)
        }
        
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
    
    func clearExpiredCache() {
        cache = cache.filter { !$0.value.isExpired }
    }
}

// MARK: - Debounced Geocoding Handler
class DebouncedGeocodingHandler: ObservableObject {
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.8 // Increased from 0.5s
    
    func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String, String?) -> Void) {
        debounceTimer?.invalidate()
        
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { _ in
            GeocodingCacheManager.shared.reverseGeocode(coordinate: coordinate, completion: completion)
        }
    }
    
    func cancel() {
        debounceTimer?.invalidate()
        debounceTimer = nil
    }
    
    deinit {
        debounceTimer?.invalidate()
    }
}

struct ParkingLocationView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var streetDataManager = StreetDataManager()
    @StateObject private var parkingManager = ParkingLocationManager()
    @StateObject private var debouncedGeocoder = DebouncedGeocodingHandler()
    
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    @State private var isSettingLocation = false
    @State private var previewAddress = ""
    @State private var previewNeighborhood: String?
    @State private var previewCoordinate = CLLocationCoordinate2D()
    
    // Auto-center functionality
    @State private var autoResetTimer: Timer?
    @State private var lastInteractionTime = Date()
    
    // MARK: - Haptic Feedback
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
                        let newCoordinate = context.camera.centerCoordinate
                        previewCoordinate = newCoordinate
                        
                        // Use debounced geocoding
                        debouncedGeocoder.reverseGeocode(coordinate: newCoordinate) { address, neighborhood in
                            DispatchQueue.main.async {
                                previewAddress = address
                                previewNeighborhood = neighborhood
                            }
                        }
                    }
                    
                    // Fixed center pin
                    ZStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
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
                                        .frame(width: 24, height: 24)
                                    
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 8, height: 8)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                            }
                        }
                        
                        // Parking location annotation
                        if let parkingLocation = parkingManager.currentLocation {
                            Annotation("Parked Car", coordinate: parkingLocation.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 24, height: 24)
                                    
                                    Image(systemName: "car.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 8, weight: .bold))
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
                        // Track user interaction with map
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
                    // Setting mode UI
                    LocationSection(
                        parkingLocation: nil,
                        onLocationTap: openInMaps,
                        isPreviewMode: true,
                        previewAddress: previewAddress,
                        previewNeighborhood: previewNeighborhood,
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
                        previewNeighborhood: nil,
                        previewCoordinate: nil
                    )
                }
                
                // Button Section
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        // Left button - changes based on state
                        Button(action: isSettingLocation ? cancelSettingLocation : startSettingLocation) {
                            Image(systemName: isSettingLocation ? "xmark" : "bell.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 26)
                                        .fill(Color.gray.opacity(0.8))
                                )
                        }
                        .frame(maxWidth: 52)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.1), value: isSettingLocation)
                        
                        // Right button - changes based on state
                        Button(action: isSettingLocation ? setParkingLocation : startSettingLocation) {
                            Text(isSettingLocation ? "Set Location" : "Update Parking Location")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(height: 52)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(
                                            LinearGradient(
                                                colors: isSettingLocation ?
                                                    [Color.green, Color.green.opacity(0.8)] :
                                                    [Color.blue, Color.blue.opacity(0.8)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .shadow(
                                            color: isSettingLocation ?
                                                Color.green.opacity(0.3) :
                                                Color.blue.opacity(0.3),
                                            radius: 10,
                                            x: 0,
                                            y: 5
                                        )
                                )
                        }
                        .scaleEffect(1.0)
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
                // Clean up timers and cancel pending requests
                autoResetTimer?.invalidate()
                debouncedGeocoder.cancel()
                
                // Clean up expired cache entries
                GeocodingCacheManager.shared.clearExpiredCache()
            }
        }
    }
    
    // MARK: - Auto-Center Functionality
    
    private func handleMapInteraction() {
        guard !isSettingLocation else { return }
        
        lastInteractionTime = Date()
        autoResetTimer?.invalidate()
        
        autoResetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
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
        
        switch (userLocation, parkingLocation) {
        case (let user?, let parking?):
            centerMapOnBothCoordinates(user.coordinate, parking.coordinate)
        case (let user?, nil):
            centerMap(on: user.coordinate)
        case (nil, let parking?):
            centerMap(on: parking.coordinate)
        case (nil, nil):
            break
        }
    }
    
    private func centerMapOnBothCoordinates(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) {
        let centerLat = (coord1.latitude + coord2.latitude) / 2
        let centerLon = (coord1.longitude + coord2.longitude) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        
        let latDelta = abs(coord1.latitude - coord2.latitude)
        let lonDelta = abs(coord1.longitude - coord2.longitude)
        
        // Reduced minimum delta for closer zoom
        let paddedLatDelta = max(latDelta * 1.8, 0.001)
        let paddedLonDelta = max(lonDelta * 1.8, 0.001)
        
        let finalDelta = max(paddedLatDelta, paddedLonDelta)
        let span = MKCoordinateSpan(latitudeDelta: finalDelta, longitudeDelta: finalDelta)
        
        withAnimation(.easeInOut(duration: 1.0)) {
            mapPosition = .region(MKCoordinateRegion(center: centerCoordinate, span: span))
        }
    }
    
    // MARK: - Haptic Preparation
    
    private func prepareHaptics() {
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
            
            centerMapOnBothLocations()
        }
    }
    
    private func startSettingLocation() {
        autoResetTimer?.invalidate()
        impactFeedbackLight.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = true
        }
        
        let startCoordinate: CLLocationCoordinate2D
        if let parkingLocation = parkingManager.currentLocation {
            startCoordinate = parkingLocation.coordinate
            previewAddress = parkingLocation.address
            previewNeighborhood = nil
        } else if let userLocation = locationManager.userLocation {
            startCoordinate = userLocation.coordinate
            previewAddress = "Loading..."
            previewNeighborhood = nil
            
            GeocodingCacheManager.shared.reverseGeocode(coordinate: startCoordinate) { address, neighborhood in
                DispatchQueue.main.async {
                    previewAddress = address
                    previewNeighborhood = neighborhood
                }
            }
        } else {
            startCoordinate = CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232)
            previewAddress = "San Francisco, CA"
            previewNeighborhood = nil
        }
        
        previewCoordinate = startCoordinate
        centerMap(on: startCoordinate, zoomLevel: .close)
    }
    
    private func setParkingLocation() {
        notificationFeedback.notificationOccurred(.success)
        
        parkingManager.setManualParkingLocation(
            coordinate: previewCoordinate,
            address: previewAddress
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            centerMapOnBothLocations()
        }
    }
    
    private func cancelSettingLocation() {
        debouncedGeocoder.cancel()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSettingLocation = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            centerMapOnBothLocations()
        }
    }
    
    private func centerOnUser() {
        autoResetTimer?.invalidate()
        
        if let location = locationManager.userLocation {
            centerMap(on: location.coordinate)
            handleMapInteraction()
        }
    }
    
    private func goToCar() {
        autoResetTimer?.invalidate()
        
        if let parkingLocation = parkingManager.currentLocation {
            centerMap(on: parkingLocation.coordinate)
            handleMapInteraction()
        }
    }
    
    private func centerMap(on coordinate: CLLocationCoordinate2D, zoomLevel: MapZoomLevel = .medium) {
        let span = zoomLevel.span
        
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
    
    enum MapZoomLevel {
        case veryClose   // 0.0005
        case close       // 0.002
        case medium      // 0.01
        case far         // 0.03
        case veryFar     // 0.1
        
        var span: MKCoordinateSpan {
            switch self {
            case .veryClose:
                return MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
            case .close:
                return MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            case .medium:
                return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            case .far:
                return MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            case .veryFar:
                return MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            }
        }
    }
}

// MARK: - Location Section

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct LocationSection: View {
    let parkingLocation: ParkingLocation?
    let onLocationTap: (String) -> Void
    let isPreviewMode: Bool
    let previewAddress: String?
    let previewNeighborhood: String?
    let previewCoordinate: CLLocationCoordinate2D?
    
    @State private var cachedNeighborhood: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parking Location")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            if isPreviewMode {
                // Preview mode content
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if let address = previewAddress {
                            Text(address)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                        }
                        
                        if let neighborhood = previewNeighborhood {
                            Text(neighborhood)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .transition(.opacity.combined(with: .move(edge: .top)))
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
                                
                                if let neighborhood = cachedNeighborhood {
                                    Text(neighborhood)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .transition(.opacity)
                                } else {
                                    Text("Tap to open in Maps")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onAppear {
                        // Only fetch neighborhood info once for the current location
                        if cachedNeighborhood == nil {
                            GeocodingCacheManager.shared.reverseGeocode(coordinate: location.coordinate) { _, neighborhood in
                                DispatchQueue.main.async {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        cachedNeighborhood = neighborhood
                                    }
                                }
                            }
                        }
                    }
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

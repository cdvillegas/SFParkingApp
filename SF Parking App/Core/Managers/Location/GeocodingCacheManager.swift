//
//  GeocodingCacheManager.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/24/25.
//

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
                    AnalyticsManager.shared.logGeocodingPerformed(success: false)
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
                    AnalyticsManager.shared.logGeocodingPerformed(success: true)
                } else {
                    request.completion("Selected Location", nil)
                    AnalyticsManager.shared.logGeocodingPerformed(success: false)
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

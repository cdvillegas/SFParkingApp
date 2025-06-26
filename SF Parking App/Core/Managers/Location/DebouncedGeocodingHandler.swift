//
//  DebouncedGeocodingHandler.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/24/25.
//

import Foundation
import CoreLocation

// MARK: - Debounced Geocoding Handler
class DebouncedGeocodingHandler: ObservableObject {
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.8
    
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

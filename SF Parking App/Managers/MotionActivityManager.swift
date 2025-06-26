//
//  MotionActivityManager.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import CoreMotion
import CoreLocation
import Combine

class MotionActivityManager: ObservableObject {
    private let motionActivityManager = CMMotionActivityManager()
    private let geocoder = CLGeocoder()
    
    @Published var currentActivity: CMMotionActivity?
    @Published var isDriving = false
    
    private var wasRecentlyDriving = false
    private var lastDrivingLocation: CLLocation?
    private var drivingEndTime: Date?
    
    weak var parkingLocationManager: ParkingLocationManager?
    weak var locationManager: LocationManager?
    
    init() {
        // Don't auto-start monitoring - wait for explicit permission request
    }
    
    private func setupMotionActivityMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("Motion activity is not available on this device")
            return
        }
        
        motionActivityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            
            self.currentActivity = activity
            self.handleActivityUpdate(activity)
        }
    }
    
    private func handleActivityUpdate(_ activity: CMMotionActivity) {
        let currentlyDriving = activity.automotive
        
        // Detect transition from driving to not driving
        if wasRecentlyDriving && !currentlyDriving {
            print("Detected end of driving activity")
            handleDrivingEnd()
        }
        
        // Update driving state
        isDriving = currentlyDriving
        wasRecentlyDriving = currentlyDriving
        
        // Store location while driving
        if currentlyDriving {
            storeCurrentLocationWhileDriving()
        }
    }
    
    private func storeCurrentLocationWhileDriving() {
        guard let location = locationManager?.userLocation else { return }
        lastDrivingLocation = location
    }
    
    private func handleDrivingEnd() {
        drivingEndTime = Date()
        
        // Wait 2 minutes to ensure we're really done driving (not just stopped at a light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.confirmDrivingEnd()
        }
    }
    
    private func confirmDrivingEnd() {
        // Check if we're still not driving after the delay
        guard let currentActivity = currentActivity, !currentActivity.automotive else {
            print("False alarm - still driving")
            return
        }
        
        // Make sure we have a recent location
        guard let drivingLocation = lastDrivingLocation else {
            print("No driving location available")
            return
        }
        
        // Check if location is recent enough (within last 5 minutes)
        let locationAge = Date().timeIntervalSince(drivingLocation.timestamp)
        guard locationAge < 300 else {
            print("Driving location too old: \(locationAge) seconds")
            return
        }
        
        // Reverse geocode the location
        reverseGeocodeAndSetParkingLocation(drivingLocation)
    }
    
    private func reverseGeocodeAndSetParkingLocation(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    self.setParkingLocationWithFallbackAddress(location)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    self.setParkingLocationWithFallbackAddress(location)
                    return
                }
                
                let address = self.formatAddress(from: placemark)
                self.setParkingLocation(coordinate: location.coordinate, address: address)
            }
        }
    }
    
    private func setParkingLocationWithFallbackAddress(_ location: CLLocation) {
        let address = "Parking Location (\(location.coordinate.latitude), \(location.coordinate.longitude))"
        setParkingLocation(coordinate: location.coordinate, address: address)
    }
    
    private func setParkingLocation(coordinate: CLLocationCoordinate2D, address: String) {
        print("Auto-setting parking location via motion detection: \(address)")
        parkingLocationManager?.setCurrentLocationAsParking(coordinate: coordinate, address: address)
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            return "\(streetNumber) \(streetName)"
        } else if let streetName = placemark.thoroughfare {
            return streetName
        } else if let name = placemark.name {
            return name
        } else {
            return "Unknown Location"
        }
    }
    
    func requestMotionPermission() {
        // CMMotionActivity doesn't have a specific permission request method
        // Permission is requested automatically when startActivityUpdates is called
        setupMotionActivityMonitoring()
    }
    
    deinit {
        motionActivityManager.stopActivityUpdates()
    }
}
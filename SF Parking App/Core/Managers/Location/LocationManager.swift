//
//  LocationManager.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var userLocation: CLLocation?
    @Published var userHeading: CLLocationDirection = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.headingFilter = 5 // Update heading every 5 degrees
        
        authorizationStatus = locationManager.authorizationStatus
        print("LocationManager initialized with status: \(authorizationStatus.rawValue)")
        
        // Start location updates if already authorized
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startLocationUpdates()
        }
    }
    
    func requestLocationPermission() {
        print("Requesting location permission. Current status: \(authorizationStatus.rawValue)")
        
        guard CLLocationManager.locationServicesEnabled() else {
            print("Location services are disabled on this device")
            return
        }
        
        if authorizationStatus == .notDetermined {
            print("Status not determined, requesting permission...")
            locationManager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            print("Already authorized, starting location updates")
            startLocationUpdates()
        } else {
            print("Location access denied or restricted")
        }
    }
    
    func requestLocation() {
        print("Manual location request triggered")
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Not authorized, cannot get location")
            return
        }
        
        print("Getting one-time location")
        locationManager.requestLocation()
    }
    
    func refreshAuthorizationStatus() {
        print("Refreshing authorization status")
        let newStatus = locationManager.authorizationStatus
        if newStatus != authorizationStatus {
            print("Authorization status changed from \(authorizationStatus.rawValue) to \(newStatus.rawValue)")
            DispatchQueue.main.async {
                self.authorizationStatus = newStatus
                
                // Start location updates if permission was granted
                if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                    self.startLocationUpdates()
                }
            }
        }
    }
    
    private func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Cannot start location updates - not authorized")
            return
        }
        
        print("Starting continuous location updates")
        locationManager.startUpdatingLocation()
        
        // Start heading updates if available
        if CLLocationManager.headingAvailable() {
            print("Starting heading updates")
            locationManager.startUpdatingHeading()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        DispatchQueue.main.async {
            self.userLocation = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("Location access denied by user")
            case .locationUnknown:
                print("Location service unable to determine location")
            case .network:
                print("Network error while getting location")
            default:
                print("Other location error: \(clError.localizedDescription)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Authorization status changed to: \(status.rawValue)")
        
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            switch status {
            case .notDetermined:
                print("Location permission not determined")
            case .denied, .restricted:
                print("Location permission denied or restricted")
            case .authorizedWhenInUse, .authorizedAlways:
                print("Location permission granted, starting updates")
                self.startLocationUpdates()
            @unknown default:
                print("Unknown authorization status")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use magnetic heading for better accuracy
        let heading = newHeading.magneticHeading >= 0 ? newHeading.magneticHeading : newHeading.trueHeading
        
        DispatchQueue.main.async {
            self.userHeading = heading
        }
    }
    
}

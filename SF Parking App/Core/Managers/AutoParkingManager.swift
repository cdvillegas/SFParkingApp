//
//  AutoParkingManager.swift
//  SF Parking App
//
//  Handles background auto-parking detection
//

import Foundation
import CoreLocation
import CoreMotion
import UIKit

class AutoParkingManager: ObservableObject {
    static let shared = AutoParkingManager()
    
    private let motionActivityManager = MotionActivityManager()
    private let locationManager: LocationManager
    
    private init() {
        // Use the shared LocationManager instance
        self.locationManager = LocationManager()
        
        // Configure motion manager with location manager
        motionActivityManager.locationManager = locationManager
        
        // Start auto parking if enabled
        checkAndStartAutoParkingIfEnabled()
        
        // Listen for app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkAndStartAutoParkingIfEnabled),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc func checkAndStartAutoParkingIfEnabled() {
        // DEBUG: Check current status
        let isEnabled = UserDefaults.standard.bool(forKey: "autoParkingDetectionEnabled")
        print("🚗 Auto parking detection enabled: \(isEnabled)")
        
        // DEBUG: Force enable for testing since Apple Maps works
        #if DEBUG
        if !isEnabled {
            print("🚗 DEBUG: Force enabling auto parking detection for testing")
            UserDefaults.standard.set(true, forKey: "autoParkingDetectionEnabled")
        }
        #endif
        
        if UserDefaults.standard.bool(forKey: "autoParkingDetectionEnabled") {
            print("🚗 Starting auto parking detection...")
            startAutoParkingDetection()
        } else {
            print("🚗 Auto parking detection is disabled")
        }
    }
    
    func startAutoParkingDetection() {
        // Request motion permission and start monitoring
        motionActivityManager.requestMotionPermission()
        
        // Request always location authorization for background updates
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
        
        // Ensure location updates are running
        locationManager.requestLocation()
        
        print("Auto parking detection started successfully")
    }
    
    func stopAutoParkingDetection() {
        // Motion manager will stop in its deinit
        print("Auto parking detection stopped")
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
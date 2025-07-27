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
import UserNotifications

class MotionActivityManager: ObservableObject {
    private let motionActivityManager = CMMotionActivityManager()
    private let geocoder = CLGeocoder()
    
    @Published var currentActivity: CMMotionActivity?
    @Published var isDriving = false
    
    private var wasRecentlyDriving = false
    private var lastDrivingLocation: CLLocation?
    private var drivingEndTime: Date?
    
    weak var locationManager: LocationManager?
    
    init() {
        // Don't auto-start monitoring - wait for explicit permission request
    }
    
    private func setupMotionActivityMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("🚗 Motion activity is not available on this device")
            return
        }
        
        print("🚗 Starting motion activity monitoring...")
        motionActivityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            
            print("🚗 Motion activity update: automotive=\(activity.automotive), walking=\(activity.walking), stationary=\(activity.stationary), confidence=\(activity.confidence.rawValue)")
            
            self.currentActivity = activity
            self.handleActivityUpdate(activity)
        }
        print("🚗 Motion activity monitoring started successfully")
    }
    
    private func handleActivityUpdate(_ activity: CMMotionActivity) {
        let currentlyDriving = activity.automotive
        
        print("🚗 Was driving: \(wasRecentlyDriving), Now driving: \(currentlyDriving)")
        
        // Detect transition from driving to not driving
        if wasRecentlyDriving && !currentlyDriving {
            print("🚗 ✅ Detected end of driving activity - starting parking detection")
            handleDrivingEnd()
        } else if !wasRecentlyDriving && currentlyDriving {
            print("🚗 🚙 Started driving")
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
        
        print("🚗 ⏰ Driving ended, waiting 10 seconds to confirm...")
        // DEBUG: Reduce wait time for testing (normally 120 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            print("🚗 ⏰ 10 seconds elapsed, confirming driving end...")
            self?.confirmDrivingEnd()
        }
    }
    
    private func confirmDrivingEnd() {
        print("🚗 🔍 Confirming driving end...")
        
        // Check if we're still not driving after the delay
        guard let currentActivity = currentActivity, !currentActivity.automotive else {
            print("🚗 ❌ False alarm - still driving (automotive=\(currentActivity?.automotive ?? false))")
            return
        }
        
        print("🚗 ✅ Confirmed not driving")
        
        // Make sure we have a recent location
        guard let drivingLocation = lastDrivingLocation else {
            print("🚗 ❌ No driving location available")
            return
        }
        
        print("🚗 📍 Have driving location: \(drivingLocation.coordinate.latitude), \(drivingLocation.coordinate.longitude)")
        
        // Check if location is recent enough (within last 5 minutes)
        let locationAge = Date().timeIntervalSince(drivingLocation.timestamp)
        guard locationAge < 300 else {
            print("🚗 ❌ Driving location too old: \(locationAge) seconds")
            return
        }
        
        print("🚗 ✅ Location is recent (\(locationAge) seconds old)")
        print("🚗 🗺️ Starting reverse geocoding...")
        
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
        print("🚗 🎯 Auto-setting parking location via motion detection: \(address)")
        
        // Send notification to user to confirm parking
        print("🚗 📱 Sending parking detection notification...")
        sendParkingDetectionNotification(coordinate: coordinate, address: address)
        
        // Store pending parking data for user confirmation
        print("🚗 💾 Storing pending parking data...")
        storePendingParkingData(coordinate: coordinate, address: address, source: .carDisconnect)
    }
    
    private func sendParkingDetectionNotification(coordinate: CLLocationCoordinate2D, address: String) {
        let content = UNMutableNotificationContent()
        content.title = "🚗 Parking Detected"
        content.body = "Confirm your parking location at \(address)"
        content.sound = .default
        content.categoryIdentifier = "PARKING_CONFIRMATION"
        
        // Add location data to notification
        content.userInfo = [
            "type": "parking_detection",
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "address": address,
            "source": "motion_activity"
        ]
        
        // Schedule immediate notification
        let request = UNNotificationRequest(
            identifier: "parking_detection_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🚗 ❌ Failed to send parking detection notification: \(error)")
            } else {
                print("🚗 ✅ Parking detection notification sent successfully!")
            }
        }
    }
    
    private func storePendingParkingData(coordinate: CLLocationCoordinate2D, address: String, source: ParkingSource) {
        let pendingParking = [
            "coordinate": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
            "address": address,
            "source": source.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        UserDefaults.standard.set(pendingParking, forKey: "pendingParkingLocation")
        
        // Post notification to app about pending parking
        NotificationCenter.default.post(
            name: .parkingDetected,
            object: nil,
            userInfo: [
                "coordinate": coordinate,
                "address": address,
                "source": source
            ]
        )
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
        print("🚗 🔐 Requesting motion permission...")
        // CMMotionActivity doesn't have a specific permission request method
        // Permission is requested automatically when startActivityUpdates is called
        setupMotionActivityMonitoring()
    }
    
    deinit {
        motionActivityManager.stopActivityUpdates()
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let parkingDetected = Notification.Name("parkingDetected")
}
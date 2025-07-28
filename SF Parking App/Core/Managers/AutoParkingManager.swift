//
//  AutoParkingManager.swift
//  SF Parking App
//
//  Handles background smart parking detection
//

import Foundation
import UIKit

class AutoParkingManager: ObservableObject {
    static let shared = AutoParkingManager()
    
    private let parkingDetector = ParkingDetector.shared
    
    private init() {
        // Start smart parking if enabled
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
        // Check if smart parking is enabled
        if parkingDetector.isMonitoring {
            print("🚗 Smart parking detection is enabled")
            startAutoParkingDetection()
        } else {
            print("🚗 Smart parking detection is disabled")
        }
    }
    
    func startAutoParkingDetection() {
        // ParkingDetector automatically monitors when enabled
        print("🚗 Smart parking detection is active")
    }
    
    func stopAutoParkingDetection() {
        // ParkingDetector automatically stops when disabled
        print("🚗 Smart parking detection stopped")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
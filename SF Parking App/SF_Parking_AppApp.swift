//
//  SF_Parking_AppApp.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import CoreLocation

@main
struct SF_Parking_AppApp: App {
    @StateObject private var parkingDetectionHandler = ParkingDetectionHandler()
    
    init() {
        // Initialize auto parking detection manager
        _ = AutoParkingManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(parkingDetectionHandler)
                .onAppear {
                    print("🚀 App ContentView onAppear called")
                    // Configure notification manager to use our handler
                    NotificationManager.shared.setParkingDetectionHandler(parkingDetectionHandler)
                    
                    // Check if app was launched from a notification
                    checkForLaunchNotification()
                }
                .onOpenURL { url in
                    // Handle deep links if needed
                    handleDeepLink(url)
                }
        }
    }
    
    private func checkForLaunchNotification() {
        // Check if there's pending notification data stored
        if let pendingData = UserDefaults.standard.dictionary(forKey: "pendingParkingLocation") {
            print("🚀 Found pending parking data on app launch")
            // Wait longer for UI to be fully ready - increase delay to ensure view hierarchy is established
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.handlePendingNotificationData(pendingData)
                
                // Add retry logic in case the first attempt doesn't work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.parkingDetectionHandler.shouldShowParkingConfirmation {
                        print("🚀 RETRY: First attempt failed, retrying parking detection")
                        self.handlePendingNotificationData(pendingData)
                    }
                }
            }
        } else {
            print("🚀 No pending parking data found on app launch")
        }
    }
    
    private func handlePendingNotificationData(_ data: [String: Any]) {
        guard let coordinateData = data["coordinate"] as? [String: Double],
              let latitude = coordinateData["latitude"],
              let longitude = coordinateData["longitude"],
              let address = data["address"] as? String else { 
            print("🚀 Failed to parse pending parking data")
            return 
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let source = ParkingSource.motionActivity
        
        print("🚀 Parsed notification data - Lat: \(latitude), Lng: \(longitude), Address: \(address)")
        print("🚀 Triggering parking detection handler for: \(address)")
        
        // Ensure we're on the main thread and the handler is available
        DispatchQueue.main.async {
            print("🚀 parkingDetectionHandler available: \(self.parkingDetectionHandler)")
            
            // Trigger parking detection handler
            self.parkingDetectionHandler.handleParkingDetection(
                coordinate: coordinate,
                address: address,
                source: source
            )
            
            // Verify the state was set
            print("🚀 After setting - shouldShowParkingConfirmation: \(self.parkingDetectionHandler.shouldShowParkingConfirmation)")
            print("🚀 After setting - pendingParkingAddress: \(self.parkingDetectionHandler.pendingParkingAddress ?? "nil")")
            
            // Clear the pending data only after successful processing
            UserDefaults.standard.removeObject(forKey: "pendingParkingLocation")
            print("🚀 Cleared pending parking data")
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        // Handle any deep links if needed in the future
        print("Deep link received: \(url)")
    }
}

// MARK: - Parking Detection Handler
class ParkingDetectionHandler: ObservableObject {
    @Published var pendingParkingLocation: CLLocationCoordinate2D?
    @Published var pendingParkingAddress: String?
    @Published var pendingParkingSource: ParkingSource?
    @Published var shouldShowParkingConfirmation = false
    
    func handleParkingDetection(coordinate: CLLocationCoordinate2D, address: String, source: ParkingSource) {
        print("🎯 ParkingDetectionHandler.handleParkingDetection called for: \(address)")
        DispatchQueue.main.async {
            self.pendingParkingLocation = coordinate
            self.pendingParkingAddress = address
            self.pendingParkingSource = source
            self.shouldShowParkingConfirmation = true
            print("🎯 Set shouldShowParkingConfirmation = true")
        }
    }
    
    func clearPendingParking() {
        pendingParkingLocation = nil
        pendingParkingAddress = nil
        pendingParkingSource = nil
        shouldShowParkingConfirmation = false
    }
}

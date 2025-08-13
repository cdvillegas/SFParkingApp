//
//  SF_Parking_AppApp.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import CoreLocation
import FirebaseCore
import FirebaseAnalytics
import CarPlay
import AppIntents

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    print("🔥 Firebase configured successfully")
    
    // Check if app was launched due to location event
    if let _ = launchOptions?[.location] {
        print("🚗 App launched from location event")
    }
    
    // Initialize Smart Park Manager for App Intents
    _ = ParkingLocationManager.shared
    _ = SmartParkManager.shared
    print("🚗 [Smart Park] Managers initialized")

    return true
  }
  
  func applicationWillResignActive(_ application: UIApplication) {
    // Help prevent Metal crashes during app transitions
    NotificationCenter.default.post(name: NSNotification.Name("AppWillResignActive"), object: nil)
    AnalyticsManager.shared.logAppBackgrounded()
  }
  
  func applicationDidBecomeActive(_ application: UIApplication) {
    // App became active again
    NotificationCenter.default.post(name: NSNotification.Name("AppDidBecomeActive"), object: nil)
    AnalyticsManager.shared.logAppOpened()
  }
  
  func applicationWillTerminate(_ application: UIApplication) {
    // App will terminate
    AnalyticsManager.shared.logAppBackgrounded()
  }
}

@main
struct SF_Parking_AppApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var parkingDetectionHandler = ParkingDetectionHandler()
    
    init() {
        // Register App Shortcuts for Siri and Shortcuts app
        SmartParkAppShortcutsProvider.updateAppShortcutParameters()
        
        // Force App Intents registration
        Task {
            print("🚗 [Smart Park] Requesting App Intents registration...")
            
            // Force evaluation of our App Shortcuts Provider
            let shortcuts = SmartParkAppShortcutsProvider.appShortcuts
            print("🚗 [Smart Park] Found \(shortcuts.count) shortcut (Smart Park only)")
            
            // The system automatically registers AppShortcutsProvider implementations
            print("🚗 [Smart Park] App Intents registration completed")
        }
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
        
        // CarPlay scene - the delegate will be set automatically when CarPlay connects
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
        }
        // Removed the "No pending parking data" log since it's normal
    }
    
    private func handlePendingNotificationData(_ data: [String: Any]) {
        print("🚀 Attempting to parse notification data: \(data)")
        
        guard let coordinateData = data["coordinate"] as? [String: Double],
              let latitude = coordinateData["latitude"],
              let longitude = coordinateData["longitude"],
              let address = data["address"] as? String else { 
            print("🚀 Failed to parse pending parking data - invalid format")
            print("🚀 Expected: coordinate[latitude/longitude], address")
            print("🚀 Received keys: \(data.keys)")
            // Clear the invalid data
            UserDefaults.standard.removeObject(forKey: "pendingParkingLocation")
            return 
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let sourceString = data["source"] as? String ?? "caraudio"
        let source = ParkingSource(rawValue: sourceString) ?? .carDisconnect
        
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

//
//  SF_Parking_AppApp.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    print("🔥 Firebase configured successfully")
    
    // Test analytics event
    Analytics.logEvent("app_open_test", parameters: [
      "debug": "true" as NSObject
    ])
    print("📊 Test event logged")

    return true
  }
}

@main
struct SF_Parking_AppApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

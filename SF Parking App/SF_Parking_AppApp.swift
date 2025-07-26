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

    return true
  }
  
  func applicationWillResignActive(_ application: UIApplication) {
    // Help prevent Metal crashes during app transitions
    NotificationCenter.default.post(name: NSNotification.Name("AppWillResignActive"), object: nil)
  }
  
  func applicationDidBecomeActive(_ application: UIApplication) {
    // App became active again
    NotificationCenter.default.post(name: NSNotification.Name("AppDidBecomeActive"), object: nil)
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

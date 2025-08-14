//
//  ContentView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var parkingDetectionHandler: ParkingDetectionHandler
    @StateObject private var smartParkManager = SmartParkManager.shared

    var body: some View {
        let shouldShowParking = parkingDetectionHandler.shouldShowParkingConfirmation
        let pendingLocation = parkingDetectionHandler.pendingParkingLocation
        let pendingAddress = parkingDetectionHandler.pendingParkingAddress
        let pendingSource = parkingDetectionHandler.pendingParkingSource
        
        print("🎯 ContentView body re-evaluated - shouldShowParking: \(shouldShowParking)")
        print("🎯 ContentView - isSmartParkUpdate: \(parkingDetectionHandler.isSmartParkUpdate)")
        print("🎯 ContentView - pendingLocation: \(pendingLocation?.latitude ?? 0), \(pendingLocation?.longitude ?? 0)")
        print("🎯 ContentView - pendingAddress: \(pendingAddress ?? "nil")")
        print("🎯 ContentView - pendingSource: \(pendingSource?.rawValue ?? "nil")")
        
        if shouldShowParking && !parkingDetectionHandler.isSmartParkUpdate {
            print("🎯 ContentView - Passing auto parking data to VehicleParkingView")
        } else if shouldShowParking && parkingDetectionHandler.isSmartParkUpdate {
            print("🚗 ContentView - Smart Park confirmation detected, not passing through auto-detected flow")
        }
        
        return VehicleParkingView(
            autoDetectedLocation: (shouldShowParking && !parkingDetectionHandler.isSmartParkUpdate) ? pendingLocation : nil,
            autoDetectedAddress: (shouldShowParking && !parkingDetectionHandler.isSmartParkUpdate) ? pendingAddress : nil,
            autoDetectedSource: (shouldShowParking && !parkingDetectionHandler.isSmartParkUpdate) ? pendingSource : nil,
            onAutoParkingHandled: {
                parkingDetectionHandler.clearPendingParking()
            }
        )
        .onAppear {
            print("🎯 ContentView.onAppear - shouldShowParkingConfirmation: \(parkingDetectionHandler.shouldShowParkingConfirmation)")
        }
        .onChange(of: parkingDetectionHandler.shouldShowParkingConfirmation) { oldValue, newValue in
            print("🎯 ContentView - shouldShowParkingConfirmation changed from \(oldValue) to \(newValue)")
            if newValue {
                print("🎯 ContentView - Auto parking data available: location=\(parkingDetectionHandler.pendingParkingLocation != nil), address=\(parkingDetectionHandler.pendingParkingAddress ?? "nil")")
            }
        }
        .sheet(isPresented: $smartParkManager.showSetup) {
            SmartParkSettingsView()
        }
    }
}

#Preview("Light Mode") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .preferredColorScheme(.dark)
}

//
//  ContentView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @State private var showingOnboarding = !OnboardingManager.hasCompletedOnboarding
    @EnvironmentObject var parkingDetectionHandler: ParkingDetectionHandler

    var body: some View {
        let shouldShowParking = parkingDetectionHandler.shouldShowParkingConfirmation
        let pendingLocation = parkingDetectionHandler.pendingParkingLocation
        let pendingAddress = parkingDetectionHandler.pendingParkingAddress
        let pendingSource = parkingDetectionHandler.pendingParkingSource
        
        print("🎯 ContentView body re-evaluated - shouldShowParking: \(shouldShowParking)")
        print("🎯 ContentView - pendingLocation: \(pendingLocation?.latitude ?? 0), \(pendingLocation?.longitude ?? 0)")
        print("🎯 ContentView - pendingAddress: \(pendingAddress ?? "nil")")
        print("🎯 ContentView - pendingSource: \(pendingSource?.rawValue ?? "nil")")
        
        if shouldShowParking {
            print("🎯 ContentView - Passing auto parking data to VehicleParkingView")
        }
        
        return ZStack {
            // Main app with beautiful slide-up transition
            VehicleParkingView(
                autoDetectedLocation: shouldShowParking ? pendingLocation : nil,
                autoDetectedAddress: shouldShowParking ? pendingAddress : nil,
                autoDetectedSource: shouldShowParking ? pendingSource : nil,
                onAutoParkingHandled: {
                    parkingDetectionHandler.clearPendingParking()
                }
            )
                .opacity(showingOnboarding ? 0 : 1)
                .scaleEffect(showingOnboarding ? 0.95 : 1.0)
                .offset(y: showingOnboarding ? 50 : 0)
                .animation(.spring(response: 1.0, dampingFraction: 0.8, blendDuration: 0.2), value: showingOnboarding)
            
            if showingOnboarding {
                OnboardingView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .onDisappear {
                        showingOnboarding = false
                    }
            }
        }
        .onAppear {
            // Check if onboarding should be shown
            showingOnboarding = !OnboardingManager.hasCompletedOnboarding
            print("🎯 ContentView.onAppear - shouldShowParkingConfirmation: \(parkingDetectionHandler.shouldShowParkingConfirmation)")
        }
        .onChange(of: parkingDetectionHandler.shouldShowParkingConfirmation) { oldValue, newValue in
            print("🎯 ContentView - shouldShowParkingConfirmation changed from \(oldValue) to \(newValue)")
            if newValue {
                print("🎯 ContentView - Auto parking data available: location=\(parkingDetectionHandler.pendingParkingLocation != nil), address=\(parkingDetectionHandler.pendingParkingAddress ?? "nil")")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OnboardingCompleted"))) { _ in
            // Hide onboarding when completed with a beautiful transition
            withAnimation(.easeInOut(duration: 1.0)) {
                showingOnboarding = false
            }
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

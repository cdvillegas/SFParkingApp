//
//  ContentView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var showingOnboarding = !OnboardingManager.hasCompletedOnboarding

    var body: some View {
        ZStack {
            // Main app with beautiful slide-up transition
            ParkingLocationView()
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OnboardingCompleted"))) { _ in
            // Hide onboarding when completed with a beautiful transition
            withAnimation(.easeInOut(duration: 1.0)) {
                showingOnboarding = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}

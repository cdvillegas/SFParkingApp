//
//  ParkingHistorySheet.swift
//  SF Parking App
//
//  Created by Assistant on 1/8/25.
//

import SwiftUI
import CoreLocation

struct ParkingHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var historyManager = ParkingHistoryManager.shared
    @ObservedObject var vehicleManager: VehicleManager
    
    let onSelectLocation: (ParkingLocation) -> Void
    
    @State private var showingClearConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Fixed header (exactly like RemindersSheet)
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .padding(.bottom, 24)
                
                // Always show the section title (like "MY REMINDERS")
                VStack(spacing: 0) {
                    HStack {
                        Text("RECENT LOCATIONS")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    
                    // Content based on history state (like notifications enabled/disabled)
                    if historyManager.parkingHistory.isEmpty {
                        // Empty state - floating (like notifications disabled)
                        Spacer()
                            .frame(maxHeight: 100)
                        EmptyHistoryView()
                        Spacer()
                    } else {
                        // History enabled - scrollable content with background
                        ScrollView {
                            VStack(spacing: 0) {
                                // Has history (like "Has reminders")
                                VStack(spacing: 0) {
                                    ForEach(historyManager.parkingHistory) { item in
                                        ParkingHistoryRowView(
                                            historyItem: item,
                                            onSetLocation: {
                                                let location = ParkingLocation(
                                                    coordinate: item.coordinate,
                                                    address: item.address,
                                                    timestamp: Date()
                                                )
                                                onSelectLocation(location)
                                                dismiss()
                                            },
                                            onDelete: {
                                                withAnimation {
                                                    historyManager.removeHistoryItem(item)
                                                }
                                            }
                                        )
                                        
                                        if item.id != historyManager.parkingHistory.last?.id {
                                            Divider()
                                                .background(Color.secondary.opacity(0.2))
                                                .padding(.leading, 72)
                                        }
                                    }
                                }
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                )
                                .padding(.horizontal, 20)
                            }
                            .padding(.top, 4)
                            .padding(.bottom, 20)
                        }
                        .mask(
                            VStack(spacing: 0) {
                                // Top fade - from transparent to opaque
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.clear, Color.black]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 8)
                                
                                // Middle is fully visible
                                Color.black
                                
                                // Bottom fade - from opaque to transparent
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black, Color.clear]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 40)
                            }
                        )
                        .padding(.bottom, 96)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .navigationBarHidden(true)
            .overlay(alignment: .bottom) {
                // Fixed bottom button (exactly like RemindersSheet)
                VStack(spacing: 0) {
                    actionButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .background(Color.clear)
            }
        }
        .alert("Clear History", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                withAnimation {
                    historyManager.clearHistory()
                }
            }
        } message: {
            Text("This will remove all parking history. This action cannot be undone.")
        }
        .presentationBackground(.thinMaterial)
        .presentationBackgroundInteraction(.enabled)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Parking History")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Clear button (like Add button in RemindersSheet)
                if !historyManager.parkingHistory.isEmpty {
                    Button(action: {
                        showingClearConfirmation = true
                    }) {
                        Text("Clear")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    private var actionButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            dismiss()
        }) {
            HStack {
                Text("Looks Good")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.blue)
            .cornerRadius(16)
        }
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Parking History")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Your recent parking locations will appear here after you park your vehicle.")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    ParkingHistorySheet(
        vehicleManager: VehicleManager(),
        onSelectLocation: { _ in }
    )
}

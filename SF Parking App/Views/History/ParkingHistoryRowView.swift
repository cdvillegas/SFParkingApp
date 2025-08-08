//
//  ParkingHistoryRowView.swift
//  SF Parking App
//
//  Created by Assistant on 1/8/25.
//

import SwiftUI
import CoreLocation
import MapKit

struct ParkingHistoryRowView: View {
    let historyItem: ParkingHistory
    let onSetLocation: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Location icon (similar to toggle in ReminderRowView)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue,
                                Color.blue.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Text content (matching ReminderRowView structure)
            VStack(alignment: .leading, spacing: 2) {
                Text(historyItem.shortAddress)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                
                Text(historyItem.timeAgoString)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 3-dot menu (matching ReminderRowView)
            Menu {
                Button(action: onSetLocation) {
                    Label("Park Here", systemImage: "car.fill")
                }
                
                Button(action: {
                    openInMaps()
                }) {
                    Label("View in Maps", systemImage: "map")
                }
                
                Button(role: .destructive, action: onDelete) {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.clear)
                    .contentShape(Rectangle())
            }
            .onLongPressGesture(minimumDuration: 0) {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onSetLocation()
        }
    }
    
    private func openInMaps() {
        let coordinate = historyItem.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = historyItem.shortAddress
        mapItem.openInMaps(launchOptions: [:])
    }
}
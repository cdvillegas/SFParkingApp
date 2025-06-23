//
//  ParkingLocationSection.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI

struct ParkingLocationSection: View {
    let parkingLocation: ParkingLocation?
    let onLocationTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Parking Location")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {}) {
                    Text("View History")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
            }
            
            if let location = parkingLocation {
                Button(action: { onLocationTap(location.address) }) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.body)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.address)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                            
                            Text(formatParkingTime(location))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("No parking location set")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 40)
    }
    
    private func formatParkingTime(_ location: ParkingLocation) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mm a"
        let timeString = formatter.string(from: location.timestamp)
        let methodString = location.isManuallySet ? "Manually Set" : "Auto-detected"
        return "Parked \(timeString) • \(methodString)"
    }
}

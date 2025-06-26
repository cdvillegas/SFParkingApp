//
//  UpcomingRemindersSection.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI

struct UpcomingRemindersSection: View {
    @ObservedObject var streetDataManager: StreetDataManager
    let parkingLocation: ParkingLocation?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // Content based on street data state
                if streetDataManager.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading street data...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let nextSchedule = streetDataManager.nextUpcomingSchedule {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Street Cleaning Alert")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text(nextSchedule.relativeTimeString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if streetDataManager.hasError {
                    Button(action: {
                        if let location = parkingLocation {
                            streetDataManager.fetchSchedules(for: location.coordinate)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                            Text("Tap to retry")
                                .font(.subheadline)
                        }
                        .foregroundColor(.orange)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("No upcoming restrictions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}


#Preview {
    VehicleParkingView()
}

#Preview("Light Mode") {
    VehicleParkingView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VehicleParkingView()
        .preferredColorScheme(.dark)
}

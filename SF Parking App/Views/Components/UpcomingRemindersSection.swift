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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Reminders")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {}) {
                    Text("View All")
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
            
            // Content based on street data state
            Group {
                if streetDataManager.isLoading {
                    LoadingReminderView()
                } else if let nextSchedule = streetDataManager.nextUpcomingSchedule {
                    ActiveReminderView(schedule: nextSchedule)
                } else if streetDataManager.hasError {
                    ErrorReminderView {
                        if let location = parkingLocation {
                            streetDataManager.fetchSchedules(for: location.coordinate)
                        }
                    }
                } else {
                    NoRemindersView()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
}

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
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}


#Preview {
    ParkingLocationView()
}

#Preview("Light Mode") {
    ParkingLocationView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ParkingLocationView()
        .preferredColorScheme(.dark)
}

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
        VStack(spacing: 0) {
            if streetDataManager.isLoading {
                loadingState
            } else if let nextSchedule = streetDataManager.nextUpcomingSchedule {
                upcomingAlert(for: nextSchedule)
            } else if streetDataManager.hasError {
                errorState
            } else {
                noRestrictionsState
            }
        }
    }
    
    // MARK: - Loading State
    private var loadingState: some View {
        HStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.0)
                .tint(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Checking schedule...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Looking for street cleaning times")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Upcoming Alert
    private func upcomingAlert(for schedule: UpcomingSchedule) -> some View {
        let timeUntil = formatPreciseTimeUntil(schedule.date)
        let urgencyLevel = getUrgencyLevel(for: schedule.date)
        let urgencyColor = getUrgencyColor(urgencyLevel)
        
        return HStack(spacing: 16) {
            Circle()
                .fill(urgencyColor)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Street cleaning \(timeUntil)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(formatDateAndTime(schedule.date, startTime: schedule.startTime, endTime: schedule.endTime))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Error State
    private var errorState: some View {
        Button(action: {
            if let location = parkingLocation {
                streetDataManager.fetchSchedules(for: location.coordinate)
            }
        }) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check failed • Tap to retry")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Unable to load schedule")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - No Restrictions State
    private var noRestrictionsState: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("No restrictions")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Clear to park")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Helper Functions
extension UpcomingRemindersSection {
    
    enum UrgencyLevel {
        case critical  // < 2 hours
        case warning   // < 24 hours  
        case info      // > 24 hours
    }
    
    private func getUrgencyLevel(for date: Date) -> UrgencyLevel {
        let timeInterval = date.timeIntervalSinceNow
        let hours = timeInterval / 3600
        
        if hours < 24 {
            return .critical
        } else if hours < 24 * 7 {
            return .warning
        } else {
            return .info
        }
    }
    
    private func getUrgencyColor(_ level: UrgencyLevel) -> Color {
        switch level {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
    
    private func formatPreciseTimeUntil(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSinceNow
        let totalSeconds = Int(timeInterval)
        
        if totalSeconds <= 0 {
            return "now"
        }
        
        let minutes = totalSeconds / 60
        let hours = minutes / 60  
        let days = hours / 24
        
        if minutes < 60 {
            let min = minutes == 1 ? "minute" : "minutes"
            return "in \(minutes) \(min)"
        } else if hours < 24 {
            let hr = hours == 1 ? "hour" : "hours"
            return "in \(hours) \(hr)"
        } else if days < 7 {
            let day = days == 1 ? "day" : "days"
            return "in \(days) \(day)"
        } else {
            let weeks = days / 7
            let week = weeks == 1 ? "week" : "weeks"
            return "in \(weeks) \(week)"
        }
    }
    
    private func formatDateAndTime(_ date: Date, startTime: String, endTime: String) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        let isToday = calendar.isDateInToday(date)
        let isTomorrow = calendar.isDateInTomorrow(date)
        
        if isToday {
            return "Today, \(startTime) - \(endTime)"
        } else if isTomorrow {
            return "Tomorrow, \(startTime) - \(endTime)"
        } else {
            formatter.dateFormat = "EEEE, MMMM d"
            let dateString = formatter.string(from: date)
            return "\(dateString), \(startTime) - \(endTime)"
        }
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

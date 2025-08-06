//
//  UpcomingSchedule.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import SwiftUI

struct UpcomingSchedule {
    let streetName: String
    let date: Date
    let endDate: Date
    let dayOfWeek: String
    let startTime: String
    let endTime: String
    let avgSweeperTime: Double?  // Average citation time in hours (e.g. 9.5 for 9:30 AM)
    let medianSweeperTime: Double?  // Median citation time in hours
    
    var relativeTimeString: String {
        let timeInterval = date.timeIntervalSinceNow
        
        // If the date is in the past, show "Street Sweeping Started" or similar
        if timeInterval < 0 {
            return "Street Sweeping in Progress"
        }
        
        let seconds = Int(timeInterval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        
        if weeks > 0 {
            return "\(weeks) \(weeks == 1 ? "Week" : "Weeks") Until Street Sweeping"
        } else if days > 0 {
            return "\(days) \(days == 1 ? "Day" : "Days") Until Street Sweeping"
        } else if hours > 0 {
            return "\(hours) \(hours == 1 ? "Hour" : "Hours") Until Street Sweeping"
        } else if minutes > 0 {
            return "\(minutes) \(minutes == 1 ? "Minute" : "Minutes") Until Street Sweeping"
        } else {
            return "Street Sweeping Starting Soon"
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, h:mm a"
        return "\(formatter.string(from: date)) - \(timeFormatter.string(from: endDate))"
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    var isUrgent: Bool {
        return date.timeIntervalSinceNow < 24 * 60 * 60
    }
    
    var estimatedSweeperTime: String? {
        guard let medianTime = medianSweeperTime else { return nil }
        
        let hour = Int(medianTime)
        let exactMinute = Int((medianTime - Double(hour)) * 60)
        
        // Round down to nearest 5-minute interval
        let minute = (exactMinute / 5) * 5
        
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        
        if minute == 0 {
            return "\(displayHour) \(period)"
        } else {
            return "\(displayHour):\(String(format: "%02d", minute)) \(period)"
        }
    }
    
    // MARK: - Shared UI Logic
    
    var urgencyColor: Color {
        let hoursUntil = date.timeIntervalSinceNow / 3600
        
        if hoursUntil < 24 {
            return .red
        } else {
            return .green
        }
    }
    
    func formatTimeUntil() -> String {
        let timeInterval = date.timeIntervalSinceNow
        let totalSeconds = Int(timeInterval)
        
        // Handle past/current times
        if totalSeconds <= 0 {
            return "happening now"
        }
        
        // Handle very soon (under 2 minutes)
        if totalSeconds < 120 {
            if totalSeconds < 60 {
                return "in under 1 minute"
            } else {
                return "in 1 minute"
            }
        }
        
        let minutes = totalSeconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let remainingHours = hours % 24
        let remainingMinutes = minutes % 60
        
        // Under 1 hour - show minutes
        if hours < 1 {
            return "in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        
        // Under 12 hours - show hours and be precise
        if hours < 12 {
            if remainingMinutes < 10 {
                return "in \(hours) hour\(hours == 1 ? "" : "s")"
            } else if remainingMinutes < 40 {
                return "in \(hours)½ hours"
            } else {
                return "in \(hours + 1) hours"
            }
        }
        
        // 12-36 hours - special handling for "tomorrow"
        if hours >= 12 && hours < 36 {
            // Check if it's actually tomorrow
            let calendar = Calendar.current
            if calendar.isDateInTomorrow(date) {
                return "tomorrow"
            } else if hours < 24 {
                return "in \(hours) hours"
            }
        }
        
        // 1.5 - 2.5 days - be more precise
        if hours >= 36 && hours < 60 {
            // Round to nearest half day
            if remainingHours < 6 {
                return "in \(days) day\(days == 1 ? "" : "s")"
            } else if remainingHours < 18 {
                return "in \(days)½ days"
            } else {
                return "in \(days + 1) days"
            }
        }
        
        // 2.5 - 6.5 days - round to nearest day
        if days >= 2 && days < 7 {
            if remainingHours < 12 {
                return "in \(days) days"
            } else {
                return "in \(days + 1) days"
            }
        }
        
        // 1+ weeks
        let weeks = days / 7
        if weeks >= 1 && weeks < 4 {
            let remainingDays = days % 7
            if weeks == 1 && remainingDays <= 1 {
                return "in 1 week"
            } else if remainingDays <= 3 {
                return "in \(weeks) week\(weeks == 1 ? "" : "s")"
            } else {
                return "in \(weeks + 1) weeks"
            }
        }
        
        // Default for longer periods
        return "in \(days) days"
    }
    
    func formatDateAndTime() -> String {
        let calendar = Calendar.current
        
        // Helper to clean up time strings
        let cleanTime = { (time: String) -> String in
            return time.replacingOccurrences(of: ":00", with: "")
        }
        
        let cleanStartTime = cleanTime(startTime)
        let cleanEndTime = cleanTime(endTime)
        
        if calendar.isDateInToday(date) {
            return "Today, \(cleanStartTime) - \(cleanEndTime)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow, \(cleanStartTime) - \(cleanEndTime)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"  // Abbreviated month
            let dateString = formatter.string(from: date)
            return "\(dateString), \(cleanStartTime) - \(cleanEndTime)"
        }
    }
}

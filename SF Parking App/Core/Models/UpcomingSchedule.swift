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
        
        // Under 1 hour - show minutes only
        if hours < 1 {
            return "in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        
        // Under 24 hours - show hours only
        if hours < 24 {
            return "in \(hours) hour\(hours == 1 ? "" : "s")"
        }
        
        // 1 day
        if days == 1 {
            return "in 1 day"
        }
        
        // 2 days
        if days == 2 {
            return "in 2 days"
        }
        
        // 3-6 days - show day count
        if days >= 3 && days <= 6 {
            return "in \(days) days"
        }
        
        // 7-10 days - roughly 1 week
        if days >= 7 && days <= 10 {
            return "in 1 week"
        }
        
        // 11-17 days - roughly 2 weeks
        if days >= 11 && days <= 17 {
            return "in 2 weeks"
        }
        
        // 18-24 days - roughly 3 weeks
        if days >= 18 && days <= 24 {
            return "in 3 weeks"
        }
        
        // 25-31 days - roughly 4 weeks
        if days >= 25 && days <= 31 {
            return "in 4 weeks"
        }
        
        // Over a month
        let weeks = (days + 3) / 7  // Rough rounding
        return "in \(weeks) weeks"
    }
    
    func formatDateAndTime() -> String {
        let calendar = Calendar.current
        
        // Helper to clean up time strings and make AM/PM lowercase
        let cleanTime = { (time: String) -> String in
            return time
                .replacingOccurrences(of: ":00", with: "")
                .replacingOccurrences(of: "AM", with: "am")
                .replacingOccurrences(of: "PM", with: "pm")
        }
        
        let cleanStartTime = cleanTime(startTime)
        let cleanEndTime = cleanTime(endTime)
        
        if calendar.isDateInToday(date) {
            return "Today, \(cleanStartTime) - \(cleanEndTime)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow, \(cleanStartTime) - \(cleanEndTime)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"  // Abbreviated day and month (e.g., "Mon, Jan 20")
            let dateString = formatter.string(from: date)
            return "\(dateString), \(cleanStartTime) - \(cleanEndTime)"
        }
    }
}

//
//  UpcomingSchedule.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation

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
}

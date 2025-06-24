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
}

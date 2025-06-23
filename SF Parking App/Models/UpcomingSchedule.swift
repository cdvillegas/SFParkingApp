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

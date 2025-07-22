//
//  CustomReminder.swift
//  SF Parking App
//
//  Created by Claude on 7/16/25.
//

import Foundation

// MARK: - Custom Reminder Data Model

struct CustomReminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var message: String?
    var timing: ReminderTiming
    var isActive: Bool
    var type: ReminderType
    var createdAt: Date
    var lastTriggered: Date?
    
    init(
        title: String,
        message: String? = nil,
        timing: ReminderTiming,
        isActive: Bool = true,
        type: ReminderType = .custom
    ) {
        self.title = title
        self.message = message
        self.timing = timing
        self.isActive = isActive
        self.type = type
        self.createdAt = Date()
    }
}

// MARK: - Reminder Timing

enum ReminderTiming: Codable, Equatable {
    case preset(PresetTiming)
    case custom(CustomTiming)
    
    var displayText: String {
        switch self {
        case .preset(let preset):
            return preset.displayText
        case .custom(let custom):
            return custom.displayText
        }
    }
    
    func notificationDate(from cleaningStart: Date) -> Date? {
        switch self {
        case .preset(let preset):
            return preset.calculateNotificationDate(from: cleaningStart)
        case .custom(let custom):
            return custom.calculateNotificationDate(from: cleaningStart)
        }
    }
}

// MARK: - Preset Timing Options

enum PresetTiming: String, Codable, CaseIterable {
    case weekBefore = "week_before"
    case threeDaysBefore = "three_days_before"
    case dayBefore = "day_before"
    case morningOf = "morning_of"
    case twoHoursBefore = "two_hours_before"
    case oneHourBefore = "one_hour_before"
    case thirtyMinutes = "thirty_minutes"
    case fifteenMinutes = "fifteen_minutes"
    case fiveMinutes = "five_minutes"
    case atCleaningTime = "at_cleaning_time"
    case afterCleaning = "after_cleaning"
    
    var displayText: String {
        switch self {
        case .weekBefore: return "1 Week Before"
        case .threeDaysBefore: return "3 Days Before"
        case .dayBefore: return "1 Day Before"
        case .morningOf: return "Day Of"
        case .twoHoursBefore: return "2 Hours Before"
        case .oneHourBefore: return "1 Hour Before"
        case .thirtyMinutes: return "30 Minutes Before"
        case .fifteenMinutes: return "15 Minutes Before"
        case .fiveMinutes: return "5 Minutes Before"
        case .atCleaningTime: return "When Cleaning Starts"
        case .afterCleaning: return "After Cleaning Ends"
        }
    }
    
    var icon: String {
        switch self {
        case .weekBefore, .threeDaysBefore: return "calendar"
        case .dayBefore: return "moon.stars"
        case .morningOf: return "sun.and.horizon"
        case .twoHoursBefore, .oneHourBefore: return "clock"
        case .thirtyMinutes, .fifteenMinutes, .fiveMinutes: return "clock.badge.exclamationmark"
        case .atCleaningTime: return "exclamationmark.triangle"
        case .afterCleaning: return "checkmark.circle"
        }
    }
    
    func calculateNotificationDate(from cleaningStart: Date = Date()) -> Date? {
        let calendar = Calendar.current
        
        switch self {
        case .weekBefore:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: cleaningStart)
        case .threeDaysBefore:
            return calendar.date(byAdding: .day, value: -3, to: cleaningStart)
        case .dayBefore:
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: cleaningStart) else { return nil }
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: dayBefore)
        case .morningOf:
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: cleaningStart)
        case .twoHoursBefore:
            return calendar.date(byAdding: .hour, value: -2, to: cleaningStart)
        case .oneHourBefore:
            return calendar.date(byAdding: .hour, value: -1, to: cleaningStart)
        case .thirtyMinutes:
            return calendar.date(byAdding: .minute, value: -30, to: cleaningStart)
        case .fifteenMinutes:
            return calendar.date(byAdding: .minute, value: -15, to: cleaningStart)
        case .fiveMinutes:
            return calendar.date(byAdding: .minute, value: -5, to: cleaningStart)
        case .atCleaningTime:
            return cleaningStart
        case .afterCleaning:
            return calendar.date(byAdding: .hour, value: 2, to: cleaningStart) // Assume 2-hour cleaning
        }
    }
}

// MARK: - Custom Timing

struct CustomTiming: Codable, Equatable {
    let amount: Int
    let unit: TimeUnit
    let relativeTo: RelativeToTime
    let specificTime: TimeOfDay? // For day-based timing
    
    var displayText: String {
        switch relativeTo {
        case .beforeCleaning:
            // Special case for 0 days before
            if unit == .days && amount == 0 {
                return "On The Day"
            }
            let timeText = amount == 1 ? "1 \(unit.singularName.capitalized)" : "\(amount) \(unit.pluralName.capitalized)"
            return "\(timeText) Before"
        case .afterCleaning:
            let timeText = amount == 1 ? "1 \(unit.singularName.capitalized)" : "\(amount) \(unit.pluralName.capitalized)"
            return "\(timeText) After"
        }
    }
    
    func calculateNotificationDate(from cleaningStart: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var baseDate: Date
        
        // Calculate base date relative to cleaning time
        switch relativeTo {
        case .beforeCleaning:
            switch unit {
            case .minutes:
                baseDate = calendar.date(byAdding: .minute, value: -amount, to: cleaningStart) ?? cleaningStart
            case .hours:
                baseDate = calendar.date(byAdding: .hour, value: -amount, to: cleaningStart) ?? cleaningStart
            case .days:
                baseDate = calendar.date(byAdding: .day, value: -amount, to: cleaningStart) ?? cleaningStart
            case .weeks:
                baseDate = calendar.date(byAdding: .weekOfYear, value: -amount, to: cleaningStart) ?? cleaningStart
            }
        case .afterCleaning:
            let cleaningEnd = calendar.date(byAdding: .hour, value: 2, to: cleaningStart) ?? cleaningStart
            switch unit {
            case .minutes:
                baseDate = calendar.date(byAdding: .minute, value: amount, to: cleaningEnd) ?? cleaningEnd
            case .hours:
                baseDate = calendar.date(byAdding: .hour, value: amount, to: cleaningEnd) ?? cleaningEnd
            case .days:
                baseDate = calendar.date(byAdding: .day, value: amount, to: cleaningEnd) ?? cleaningEnd
            case .weeks:
                baseDate = calendar.date(byAdding: .weekOfYear, value: amount, to: cleaningEnd) ?? cleaningEnd
            }
        }
        
        // Apply specific time if set
        if let specificTime = specificTime {
            return calendar.date(bySettingHour: specificTime.hour, minute: specificTime.minute, second: 0, of: baseDate)
        }
        
        return baseDate
    }
}

enum TimeUnit: String, Codable, CaseIterable {
    case minutes, hours, days, weeks
    
    var singularName: String {
        switch self {
        case .minutes: return "minute"
        case .hours: return "hour"
        case .days: return "day"
        case .weeks: return "week"
        }
    }
    
    var pluralName: String {
        return rawValue
    }
}

enum RelativeToTime: String, Codable, CaseIterable {
    case beforeCleaning = "before"
    case afterCleaning = "after"
    
    var displayText: String {
        switch self {
        case .beforeCleaning: return "before cleaning"
        case .afterCleaning: return "after cleaning"
        }
    }
}

struct TimeOfDay: Codable, Equatable {
    let hour: Int // 0-23
    let minute: Int // 0-59
    
    var displayText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Reminder Type

enum ReminderType: String, Codable {
    case custom = "custom"
}


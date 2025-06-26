//
//  NotificationManager.swift
//  SF Parking App
//
//  Street Cleaning Notification System
//

import Foundation
import UserNotifications
import CoreLocation

// MARK: - Notification Manager
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var scheduledNotifications: [ScheduledNotification] = []
    
    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current
    
    private override init() {
        super.init()
        center.delegate = self
        
        // Setup notification categories
        setupNotificationCategories()
        
        // Check permission status on init
        checkPermissionStatus()
    }

    // MARK: - Enhanced Permission Management

    func checkPermissionStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("Current notification permission status: \(settings.authorizationStatus.rawValue)")
                self.notificationPermissionStatus = settings.authorizationStatus
            }
        }
    }

    func requestNotificationPermission() {
        print("Requesting notification permission...")
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error requesting notification permission: \(error)")
                    self.notificationPermissionStatus = .denied
                    return
                }
                
                if granted {
                    print("Notification permission granted")
                    self.notificationPermissionStatus = .authorized
                } else {
                    print("Notification permission denied")
                    self.notificationPermissionStatus = .denied
                }
                
                // Update the permission status immediately
                self.checkPermissionStatus()
            }
        }
    }

    private func setupNotificationCategories() {
        // CRITICAL FIX: Better action buttons with snooze functionality
        let moveCarAction = UNNotificationAction(
            identifier: "MOVE_CAR",
            title: "Mark as Moved",
            options: [.foreground]
        )
        
        let openMapsAction = UNNotificationAction(
            identifier: "OPEN_MAPS",
            title: "Find Parking",
            options: [.foreground]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_15",
            title: "Remind in 15 min",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "STREET_CLEANING",
            actions: [moveCarAction, openMapsAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        center.setNotificationCategories([category])
    }
    
    // MARK: - Street Cleaning Notifications
    
    func scheduleStreetCleaningNotifications(for location: ParkingLocation, schedules: [StreetCleaningSchedule]) {
        // Cancel existing notifications for this location
        cancelNotifications(for: location)
        
        guard notificationPermissionStatus == .authorized else {
            print("Notification permission not granted")
            return
        }
        
        var newNotifications: [ScheduledNotification] = []
        
        for schedule in schedules {
            let notifications = createNotificationsForSchedule(schedule, location: location)
            newNotifications.append(contentsOf: notifications)
        }
        
        // Schedule all notifications
        for notification in newNotifications {
            scheduleNotification(notification)
        }
        
        // Update our tracking
        scheduledNotifications.append(contentsOf: newNotifications)
        
        print("Scheduled \(newNotifications.count) street cleaning notifications")
    }
    
    private func createNotificationsForSchedule(_ schedule: StreetCleaningSchedule, location: ParkingLocation) -> [ScheduledNotification] {
        var notifications: [ScheduledNotification] = []
        
        // Get next occurrences of this schedule (next 4 weeks)
        let nextOccurrences = getNextOccurrences(for: schedule, weeksAhead: 4)
        
        for occurrence in nextOccurrences {
            // Create multiple notifications with different timing
            let notificationTimes = getNotificationTimes(for: occurrence, schedule: schedule)
            
            for (timing, notificationDate) in notificationTimes {
                let notification = ScheduledNotification(
                    id: generateNotificationId(location: location, schedule: schedule, date: occurrence, timing: timing),
                    locationId: location.id,
                    scheduleId: schedule.id,
                    scheduledDate: notificationDate,
                    cleaningDate: occurrence,
                    timing: timing,
                    schedule: schedule,
                    location: location
                )
                notifications.append(notification)
            }
        }
        
        return notifications
    }
    
    private func getNextOccurrences(for schedule: StreetCleaningSchedule, weeksAhead: Int) -> [Date] {
        var occurrences: [Date] = []
        let now = Date()
        let endDate = calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: now) ?? now
        
        // Parse the schedule to determine days and times
        let cleaningDays = parseCleaningDays(from: schedule.description)
        let cleaningTime = parseCleaningTime(from: schedule.description)
        
        var currentDate = now
        while currentDate < endDate {
            let weekday = calendar.component(.weekday, from: currentDate)
            
            if cleaningDays.contains(weekday) {
                // Create the cleaning start time for this day
                var components = calendar.dateComponents([.year, .month, .day], from: currentDate)
                components.hour = cleaningTime.hour
                components.minute = cleaningTime.minute
                
                if let cleaningDateTime = calendar.date(from: components),
                   cleaningDateTime > now {
                    occurrences.append(cleaningDateTime)
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return occurrences
    }
    
    private func getNotificationTimes(for cleaningDate: Date, schedule: StreetCleaningSchedule) -> [(NotificationTiming, Date)] {
        var times: [(NotificationTiming, Date)] = []
        let now = Date()
        let timeUntilCleaning = cleaningDate.timeIntervalSince(now)
        
        // CRITICAL FIX: Smart notification timing based on how much time is left
        
        // Only add night before if cleaning is more than 12 hours away
        if timeUntilCleaning > 12 * 3600 { // 12 hours
            if let nightBefore = calendar.date(byAdding: .day, value: -1, to: cleaningDate) {
                var components = calendar.dateComponents([.year, .month, .day], from: nightBefore)
                components.hour = 20
                components.minute = 0
                
                if let notificationDate = calendar.date(from: components),
                   notificationDate > now {
                    times.append((.nightBefore, notificationDate))
                }
            }
        }
        
        // 1 hour before (only if more than 1 hour away)
        if timeUntilCleaning > 3600 { // 1 hour
            if let oneHourBefore = calendar.date(byAdding: .hour, value: -1, to: cleaningDate),
               oneHourBefore > now {
                times.append((.oneHourBefore, oneHourBefore))
            }
        }
        
        // 30 minutes before (only if more than 30 minutes away)
        if timeUntilCleaning > 1800 { // 30 minutes
            if let thirtyMinBefore = calendar.date(byAdding: .minute, value: -30, to: cleaningDate),
               thirtyMinBefore > now {
                times.append((.thirtyMinutesBefore, thirtyMinBefore))
            }
        }
        
        // EDGE CASE FIX: If cleaning is very soon, add immediate notification
        if timeUntilCleaning <= 1800 && timeUntilCleaning > 600 { // Between 10-30 minutes
            let immediateNotification = calendar.date(byAdding: .minute, value: 2, to: now) ?? now
            times.append((.thirtyMinutesBefore, immediateNotification))
        }
        
        return times
    }
    
    private func scheduleNotification(_ notification: ScheduledNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.timing.title
        content.body = notification.timing.body(for: notification.location.address, schedule: notification.schedule)
        content.sound = .default
        content.categoryIdentifier = "STREET_CLEANING"
        
        // Add custom data
        content.userInfo = [
            "type": "street_cleaning",
            "locationId": notification.locationId.uuidString,
            "scheduleId": notification.scheduleId,
            "cleaningDate": notification.cleaningDate.timeIntervalSince1970,
            "timing": notification.timing.rawValue
        ]
        
        let triggerDate = notification.scheduledDate
        // CRITICAL FIX: Add explicit timezone handling
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        components.timeZone = TimeZone.current
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )
        
        center.add(request) { [weak self] error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
                // CRITICAL FIX: Retry mechanism
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.center.add(request) { retryError in
                        if let retryError = retryError {
                            print("Retry failed for notification: \(retryError)")
                        } else {
                            self?.persistScheduledNotification(notification)
                        }
                    }
                }
            } else {
                // CRITICAL FIX: Persist successful notifications
                self?.persistScheduledNotification(notification)
            }
        }
    }
    
    // MARK: - Notification Persistence (CRITICAL FIX)
    
    private func persistScheduledNotification(_ notification: ScheduledNotification) {
        var persistedNotifications = getPersistedNotifications()
        persistedNotifications[notification.id] = notification
        
        if let data = try? JSONEncoder().encode(persistedNotifications) {
            UserDefaults.standard.set(data, forKey: "ScheduledNotifications")
        }
    }
    
    private func getPersistedNotifications() -> [String: ScheduledNotification] {
        guard let data = UserDefaults.standard.data(forKey: "ScheduledNotifications"),
              let notifications = try? JSONDecoder().decode([String: ScheduledNotification].self, from: data) else {
            return [:]
        }
        return notifications
    }
    
    private func removePersistedNotification(_ notificationId: String) {
        var persistedNotifications = getPersistedNotifications()
        persistedNotifications.removeValue(forKey: notificationId)
        
        if let data = try? JSONEncoder().encode(persistedNotifications) {
            UserDefaults.standard.set(data, forKey: "ScheduledNotifications")
        }
    }
    
    func validateAndRecoverNotifications() {
        let persistedNotifications = getPersistedNotifications()
        let currentTime = Date()
        
        // Remove expired notifications
        let validNotifications = persistedNotifications.filter { _, notification in
            notification.scheduledDate > currentTime
        }
        
        // Re-schedule any missing notifications
        center.getPendingNotificationRequests { [weak self] requests in
            let existingIds = Set(requests.map { $0.identifier })
            
            for (id, notification) in validNotifications {
                if !existingIds.contains(id) {
                    print("Re-scheduling missing notification: \(id)")
                    self?.scheduleNotification(notification)
                }
            }
        }
    }
    
    // MARK: - Notification Management
    
    func cancelNotifications(for location: ParkingLocation) {
        let identifiers = scheduledNotifications
            .filter { $0.locationId == location.id }
            .map { $0.id }
        
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        scheduledNotifications.removeAll { $0.locationId == location.id }
        
        // CRITICAL FIX: Remove from persistence
        for identifier in identifiers {
            removePersistedNotification(identifier)
        }
        
        print("Cancelled \(identifiers.count) notifications for location")
    }
    
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        scheduledNotifications.removeAll()
        print("Cancelled all notifications")
    }
    
    func getPendingNotifications() {
        center.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                print("Pending notifications: \(requests.count)")
                for request in requests {
                    if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                        print("- \(request.identifier): \(trigger.nextTriggerDate()?.description ?? "Unknown")")
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateNotificationId(location: ParkingLocation, schedule: StreetCleaningSchedule, date: Date, timing: NotificationTiming) -> String {
        let dateString = ISO8601DateFormatter().string(from: date)
        return "\(location.id.uuidString)_\(schedule.id)_\(dateString)_\(timing.rawValue)"
    }
    
    private func parseCleaningDays(from description: String) -> [Int] {
        // Parse days from schedule description (e.g., "MON 8AM-10AM" -> [2])
        // Sunday = 1, Monday = 2, etc.
        var days: [Int] = []
        
        let dayMap = [
            "SUN": 1, "SUNDAY": 1,
            "MON": 2, "MONDAY": 2,
            "TUE": 3, "TUESDAY": 3,
            "WED": 4, "WEDNESDAY": 4,
            "THU": 5, "THURSDAY": 5,
            "FRI": 6, "FRIDAY": 6,
            "SAT": 7, "SATURDAY": 7
        ]
        
        let upperDescription = description.uppercased()
        for (dayString, dayNumber) in dayMap {
            if upperDescription.contains(dayString) {
                days.append(dayNumber)
            }
        }
        
        return days.isEmpty ? [2] : days // Default to Monday if parsing fails
    }
    
    private func parseCleaningTime(from description: String) -> (hour: Int, minute: Int) {
        // Parse time from schedule description (e.g., "8AM-10AM" -> 8:00)
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(AM|PM)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        
        if let match = regex?.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)) {
            let hourString = String(description[Range(match.range(at: 1), in: description)!])
            let minuteString = match.range(at: 2).location != NSNotFound ?
                String(description[Range(match.range(at: 2), in: description)!]) : "0"
            let ampm = String(description[Range(match.range(at: 3), in: description)!])
            
            var hour = Int(hourString) ?? 8
            let minute = Int(minuteString) ?? 0
            
            if ampm.uppercased() == "PM" && hour != 12 {
                hour += 12
            } else if ampm.uppercased() == "AM" && hour == 12 {
                hour = 0
            }
            
            return (hour: hour, minute: minute)
        }
        
        return (hour: 8, minute: 0) // Default to 8 AM
    }
    
    
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let type = userInfo["type"] as? String, type == "street_cleaning" {
            // Handle street cleaning notification tap
            handleStreetCleaningNotificationTap(userInfo: userInfo)
        }
        
        completionHandler()
    }
    
    private func handleStreetCleaningNotificationTap(userInfo: [AnyHashable: Any]) {
        // You can post a notification to update your UI or take other actions
        NotificationCenter.default.post(
            name: .streetCleaningNotificationTapped,
            object: nil,
            userInfo: userInfo
        )
    }
}

// MARK: - Data Models

struct ScheduledNotification: Identifiable, Codable {
    let id: String
    let locationId: UUID
    let scheduleId: String
    let scheduledDate: Date
    let cleaningDate: Date
    let timing: NotificationTiming
    let schedule: StreetCleaningSchedule
    let location: ParkingLocation
}

enum NotificationTiming: String, CaseIterable, Codable {
    case nightBefore = "night_before"
    case oneHourBefore = "one_hour_before"
    case thirtyMinutesBefore = "thirty_minutes_before"
    
    var title: String {
        switch self {
        case .nightBefore:
            return "🚗 Parking Reminder"
        case .oneHourBefore:
            return "⚠️ MOVE CAR - 1 HOUR"
        case .thirtyMinutesBefore:
            return "🚨 URGENT: MOVE NOW"
        }
    }
    
    func body(for address: String, schedule: StreetCleaningSchedule) -> String {
        // Extract just the street name for brevity
        let streetName = address.components(separatedBy: ",").first ?? address
        let cleaningTime = schedule.description
        
        switch self {
        case .nightBefore:
            return "Tomorrow \(cleaningTime) on \(streetName). Move by then to avoid $80+ ticket"
        case .oneHourBefore:
            return "Cleaning starts in 1 HOUR on \(streetName). Move now or get ticketed!"
        case .thirtyMinutesBefore:
            return "30 MINUTES LEFT! Move car from \(streetName) immediately to avoid ticket"
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let streetCleaningNotificationTapped = Notification.Name("streetCleaningNotificationTapped")
}

// MARK: - Placeholder Models (assuming these exist in your app)

struct StreetCleaningSchedule: Codable {
    let id: String
    let description: String
    let dayOfWeek: Int
    let startTime: String
    let endTime: String
}


//
//  NotificationManager.swift
//  SF Parking App
//
//  Street Cleaning Notification System
//

import Foundation
import UserNotifications
import CoreLocation
import UIKit

// MARK: - Notification Manager
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var scheduledNotifications: [ScheduledNotification] = []
    
    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current
    
    // Dependencies for accessing current app state
    private var vehicleManager: VehicleManager?
    private var streetDataManager: StreetDataManager?
    private weak var parkingDetectionHandler: ParkingDetectionHandler?
    
    private override init() {
        super.init()
        center.delegate = self
        
        // Setup notification categories
        setupNotificationCategories()
        
        // Check permission status on init
        checkPermissionStatus()
        
        // Load existing reminders and create defaults if needed
        loadCustomReminders()
        createDefaultRemindersIfNeeded()
    }
    
    // MARK: - Dependency Injection
    
    func configure(vehicleManager: VehicleManager, streetDataManager: StreetDataManager) {
        self.vehicleManager = vehicleManager
        self.streetDataManager = streetDataManager
    }
    
    func setParkingDetectionHandler(_ handler: ParkingDetectionHandler) {
        self.parkingDetectionHandler = handler
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
        
        let streetCleaningCategory = UNNotificationCategory(
            identifier: "STREET_CLEANING",
            actions: [moveCarAction, openMapsAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Parking confirmation category
        let confirmParkingAction = UNNotificationAction(
            identifier: "CONFIRM_PARKING",
            title: "Confirm Location",
            options: [.foreground]
        )
        
        let dismissParkingAction = UNNotificationAction(
            identifier: "DISMISS_PARKING",
            title: "Not Parked",
            options: [.destructive]
        )
        
        let parkingConfirmationCategory = UNNotificationCategory(
            identifier: "PARKING_CONFIRMATION",
            actions: [confirmParkingAction, dismissParkingAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        center.setNotificationCategories([streetCleaningCategory, parkingConfirmationCategory])
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
                components.hour = 17
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
    
    // MARK: - Custom Reminders Management
    
    @Published var customReminders: [CustomReminder] = []
    let maxCustomReminders = 25
    
    func loadCustomReminders() {
        if let data = UserDefaults.standard.data(forKey: "customReminders"),
           let reminders = try? JSONDecoder().decode([CustomReminder].self, from: data) {
            self.customReminders = reminders
        } else {
            // No custom reminders yet - start with empty list
            self.customReminders = []
        }
    }
    
    func saveCustomReminders() {
        if let encoded = try? JSONEncoder().encode(customReminders) {
            UserDefaults.standard.set(encoded, forKey: "customReminders")
        }
    }
    
    private func createDefaultRemindersIfNeeded() {
        // Check if we've already created default reminders
        let hasCreatedDefaults = UserDefaults.standard.bool(forKey: "hasCreatedDefaultReminders")
        
        if !hasCreatedDefaults && customReminders.isEmpty {
            // Create default reminders
            let defaultReminders = [
                // Evening before at 5 PM
                CustomReminder(
                    title: "Evening Before",
                    timing: .custom(CustomTiming(
                        amount: 1,
                        unit: .days,
                        relativeTo: .beforeCleaning,
                        specificTime: TimeOfDay(hour: 17, minute: 0)
                    )),
                    isActive: true
                ),
                // Morning of at 8 AM
                CustomReminder(
                    title: "Morning Of",
                    timing: .custom(CustomTiming(
                        amount: 0,
                        unit: .days,
                        relativeTo: .beforeCleaning,
                        specificTime: TimeOfDay(hour: 8, minute: 0)
                    )),
                    isActive: true
                ),
                // 30 minutes before
                CustomReminder(
                    title: "30 Minutes Before",
                    timing: .custom(CustomTiming(
                        amount: 30,
                        unit: .minutes,
                        relativeTo: .beforeCleaning,
                        specificTime: nil
                    )),
                    isActive: true
                )
            ]
            
            customReminders = defaultReminders
            saveCustomReminders()
            
            // Mark that we've created default reminders
            UserDefaults.standard.set(true, forKey: "hasCreatedDefaultReminders")
            
            print("Created default reminders: \(defaultReminders.count) reminders")
        }
    }
    
    enum AddReminderResult {
        case success
        case duplicate
        case maxReached
    }
    
    func checkForDuplicateReminder(_ reminder: CustomReminder) -> CustomReminder? {
        return customReminders.first { existing in
            // Check if timing is the same
            switch (existing.timing, reminder.timing) {
            case (.preset(let existing), .preset(let new)):
                return existing == new
            case (.custom(let existing), .custom(let new)):
                return existing.amount == new.amount &&
                       existing.unit == new.unit &&
                       existing.relativeTo == new.relativeTo &&
                       existing.specificTime?.hour == new.specificTime?.hour &&
                       existing.specificTime?.minute == new.specificTime?.minute
            default:
                return false
            }
        }
    }
    
    func addCustomReminder(_ reminder: CustomReminder) -> AddReminderResult {
        guard customReminders.count < maxCustomReminders else {
            print("Maximum number of custom reminders reached (\(maxCustomReminders))")
            return .maxReached
        }
        
        if let _ = checkForDuplicateReminder(reminder) {
            return .duplicate
        }
        
        customReminders.append(reminder)
        saveCustomReminders()
        
        // Log analytics
        let timingText = reminder.timing.displayText
        let reminderType = AnalyticsManager.shared.getReminderType(from: reminder.timing)
        AnalyticsManager.shared.logReminderCreated(reminderType: reminderType, timing: timingText)
        
        return .success
    }
    
    func addCustomReminderForced(_ reminder: CustomReminder) -> Bool {
        guard customReminders.count < maxCustomReminders else {
            print("Maximum number of custom reminders reached (\(maxCustomReminders))")
            return false
        }
        
        customReminders.append(reminder)
        saveCustomReminders()
        
        // Log analytics
        let timingText = reminder.timing.displayText
        let reminderType = AnalyticsManager.shared.getReminderType(from: reminder.timing)
        AnalyticsManager.shared.logReminderCreated(reminderType: reminderType, timing: timingText)
        
        return true
    }
    
    func removeCustomReminder(withId id: UUID) {
        customReminders.removeAll { $0.id == id }
        saveCustomReminders()
        
        AnalyticsManager.shared.logReminderDeleted(reminderId: id.uuidString)
        
        // Cancel any scheduled notifications for this reminder
        cancelCustomReminder(withId: id)
    }
    
    func toggleReminderActive(withId id: UUID) {
        if let index = customReminders.firstIndex(where: { $0.id == id }) {
            customReminders[index].isActive.toggle()
            let isEnabled = customReminders[index].isActive
            saveCustomReminders()
            
            AnalyticsManager.shared.logReminderToggled(enabled: isEnabled)
            
            // Reschedule notifications if needed
            if let location = getCurrentParkingLocation() {
                scheduleCustomReminders(for: location)
            }
        }
    }
    
    func updateCustomReminder(_ reminder: CustomReminder) {
        if let index = customReminders.firstIndex(where: { $0.id == reminder.id }) {
            customReminders[index] = reminder
            saveCustomReminders()
            
            AnalyticsManager.shared.logReminderEdited(reminderId: reminder.id.uuidString)
            
            // Reschedule notifications if needed
            if let location = getCurrentParkingLocation() {
                scheduleCustomReminders(for: location)
            }
        }
    }
    
    func toggleCustomReminder(withId id: UUID, isActive: Bool) {
        if let index = customReminders.firstIndex(where: { $0.id == id }) {
            customReminders[index].isActive = isActive
            saveCustomReminders()
            
            // Always reschedule all notifications to ensure proper state
            if let location = getCurrentParkingLocation() {
                scheduleCustomReminders(for: location)
            }
        }
    }
    
    // MARK: - Custom Reminder Scheduling
    
    func scheduleCustomReminders(for location: ParkingLocation, cleaningDate: Date? = nil) {
        guard notificationPermissionStatus == .authorized else {
            print("Notification permission not granted")
            return
        }
        
        // Cancel existing custom reminder notifications
        cancelCustomReminders()
        
        let activeReminders = customReminders.filter { $0.isActive }
        guard !activeReminders.isEmpty else { return }
        
        // Use provided cleaning date or find next cleaning date
        let targetCleaningDate = cleaningDate ?? getNextCleaningDate(for: location) ?? Date().addingTimeInterval(86400) // Default to tomorrow
        
        for reminder in activeReminders {
            scheduleCustomReminder(reminder, for: location, cleaningDate: targetCleaningDate)
        }
        
    }
    
    private func scheduleCustomReminder(_ reminder: CustomReminder, for location: ParkingLocation, cleaningDate: Date) {
        let notificationDate: Date?
        
        // Calculate notification date based on reminder timing and cleaning date
        switch reminder.timing {
        case .preset(let preset):
            notificationDate = preset.calculateNotificationDate(from: cleaningDate)
        case .custom(let custom):
            notificationDate = custom.calculateNotificationDate(from: cleaningDate)
        }
        
        guard let finalNotificationDate = notificationDate else {
            print("Could not calculate notification date for reminder: \(reminder.title)")
            return
        }
        
        // Don't schedule notifications in the past
        guard finalNotificationDate > Date() else {
            print("Skipping past notification date for reminder: \(reminder.title)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.message ?? getDefaultMessageForTiming(reminder.timing)
        content.sound = .default
        content.categoryIdentifier = "STREET_CLEANING"
        
        // Add user info for handling
        content.userInfo = [
            "type": "custom_reminder",
            "reminderId": reminder.id.uuidString,
            "locationId": location.id.uuidString,
            "cleaningDate": ISO8601DateFormatter().string(from: cleaningDate)
        ]
        
        // Create trigger
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: finalNotificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        // Create request
        let identifier = "custom_reminder_\(reminder.id.uuidString)_\(location.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Schedule notification
        center.add(request) { error in
            if let error = error {
                print("Error scheduling custom reminder notification: \(error)")
            } else {
                print("Scheduled custom reminder: \(reminder.title) for \(finalNotificationDate)")
            }
        }
    }
    
    private func getDefaultMessageForTiming(_ timing: ReminderTiming) -> String {
        switch timing {
        case .preset(let preset):
            switch preset {
            case .weekBefore, .threeDaysBefore, .dayBefore:
                return "Don't forget - street cleaning is coming up!"
            case .morningOf:
                return "Street cleaning today - move your car!"
            case .twoHoursBefore, .oneHourBefore:
                return "Street cleaning starts soon - time to move your car!"
            case .thirtyMinutes, .fifteenMinutes, .fiveMinutes:
                return "Move your car now - street cleaning starts soon!"
            case .atCleaningTime:
                return "Street cleaning is starting now!"
            case .afterCleaning:
                return "Street cleaning is done - you can park again!"
            }
        case .custom:
            return "Parking reminder - check your street cleaning schedule!"
        }
    }
    
    private func cancelCustomReminders() {
        center.getPendingNotificationRequests { requests in
            let customReminderIdentifiers = requests
                .filter { $0.identifier.starts(with: "custom_reminder_") }
                .map { $0.identifier }
            
            self.center.removePendingNotificationRequests(withIdentifiers: customReminderIdentifiers)
            print("Cancelled \(customReminderIdentifiers.count) custom reminder notifications")
        }
    }
    
    private func cancelCustomReminder(withId id: UUID) {
        let identifierPrefix = "custom_reminder_\(id.uuidString)"
        center.getPendingNotificationRequests { requests in
            let matchingIdentifiers = requests
                .filter { $0.identifier.starts(with: identifierPrefix) }
                .map { $0.identifier }
            
            self.center.removePendingNotificationRequests(withIdentifiers: matchingIdentifiers)
            print("Cancelled notifications for custom reminder: \(id)")
        }
    }
    
    private func getCurrentParkingLocation() -> ParkingLocation? {
        // Use injected VehicleManager to get the current vehicle's parking location
        return vehicleManager?.currentVehicle?.parkingLocation
    }
    
    private func getNextCleaningDate(for location: ParkingLocation) -> Date? {
        // Use injected StreetDataManager to get the next cleaning date
        return streetDataManager?.nextUpcomingSchedule?.date ?? 
               Calendar.current.date(byAdding: .day, value: 1, to: Date()) // Fallback to tomorrow
    }
    
    // MARK: - Recurring Reminder Logic
    
    func handleReminderTriggered(_ reminderId: UUID) {
        // Update last triggered date
        if let index = customReminders.firstIndex(where: { $0.id == reminderId }) {
            customReminders[index].lastTriggered = Date()
            saveCustomReminders()
        }
        
        // Schedule next occurrence if user is still parked in the same location
        scheduleNextRecurringReminder(reminderId)
    }
    
    private func scheduleNextRecurringReminder(_ reminderId: UUID) {
        guard let reminder = customReminders.first(where: { $0.id == reminderId }),
              reminder.isActive,
              let location = getCurrentParkingLocation() else { return }
        
        // Find next cleaning date (this would integrate with your schedule detection)
        if let nextCleaningDate = getNextCleaningDate(for: location) {
            scheduleCustomReminder(reminder, for: location, cleaningDate: nextCleaningDate)
        }
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
        print("📱 Notification tapped - App state: \(UIApplication.shared.applicationState.rawValue)")
        
        if let type = userInfo["type"] as? String {
            switch type {
            case "street_cleaning":
                handleStreetCleaningNotificationTap(userInfo: userInfo)
            case "parking_detection":
                print("📱 Handling parking detection notification tap")
                // Store data for app launch handling - this works for both closed and open app states
                storeParkingDataForAppLaunch(userInfo: userInfo)
                
                // Only handle immediately if app is already running (foreground/background)
                if UIApplication.shared.applicationState != .inactive {
                    print("📱 App is active/background - handling immediately")
                    handleParkingDetectionNotificationTap(userInfo: userInfo)
                } else {
                    print("📱 App is launching - data stored for launch handling")
                }
            default:
                break
            }
        }
        
        completionHandler()
    }
    
    private func storeParkingDataForAppLaunch(userInfo: [AnyHashable: Any]) {
        // Store the parking data so it can be retrieved when app launches
        guard let latitude = userInfo["latitude"] as? Double,
              let longitude = userInfo["longitude"] as? Double,
              let address = userInfo["address"] as? String else { return }
        
        let pendingData: [String: Any] = [
            "coordinate": ["latitude": latitude, "longitude": longitude],
            "address": address,
            "source": "car_disconnect",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        UserDefaults.standard.set(pendingData, forKey: "pendingParkingLocation")
        print("📱 Stored parking data for app launch: \(address)")
    }
    
    private func handleStreetCleaningNotificationTap(userInfo: [AnyHashable: Any]) {
        // You can post a notification to update your UI or take other actions
        NotificationCenter.default.post(
            name: .streetCleaningNotificationTapped,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func handleParkingDetectionNotificationTap(userInfo: [AnyHashable: Any]) {
        // Extract parking location data from notification
        guard let latitude = userInfo["latitude"] as? Double,
              let longitude = userInfo["longitude"] as? Double,
              let address = userInfo["address"] as? String,
              let sourceString = userInfo["source"] as? String else {
            print("Invalid parking detection notification data")
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let source: ParkingSource = ParkingSource(rawValue: sourceString) ?? .carDisconnect
        
        // Pass to the parking detection handler
        DispatchQueue.main.async {
            self.parkingDetectionHandler?.handleParkingDetection(
                coordinate: coordinate,
                address: address,
                source: source
            )
        }
        
        // Don't clear stored data here - let the app launch flow handle it
        print("📱 Parking detection handled for immediate processing")
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
    static let parkingDetected = Notification.Name("parkingDetected")
}

// MARK: - Placeholder Models (assuming these exist in your app)

struct StreetCleaningSchedule: Codable {
    let id: String
    let description: String
    let dayOfWeek: Int
    let startTime: String
    let endTime: String
}


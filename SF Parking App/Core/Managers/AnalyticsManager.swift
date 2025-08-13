//
//  AnalyticsManager.swift
//  SF Parking App
//
//  Created by Claude on 7/26/25.
//

import Foundation
import FirebaseAnalytics

class AnalyticsManager {
    static let shared = AnalyticsManager()
    
    private init() {}
    
    // Throttling for high-frequency events
    private var lastMapCenterTime: Date?
    private let mapEventThrottleInterval: TimeInterval = 5.0 // 5 seconds
    
    // MARK: - App Lifecycle Events
    
    func logAppOpened() {
        Analytics.logEvent("app_opened", parameters: nil)
    }
    
    func logAppBackgrounded() {
        Analytics.logEvent("app_backgrounded", parameters: nil)
    }
    
    // MARK: - Onboarding Events
    
    func logOnboardingStarted() {
        Analytics.logEvent("onboarding_started", parameters: nil)
    }
    
    func logOnboardingStepCompleted(stepName: String) {
        Analytics.logEvent("onboarding_step_completed", parameters: [
            "step_name": stepName as NSObject
        ])
    }
    
    func logOnboardingCompleted() {
        Analytics.logEvent("onboarding_completed", parameters: nil)
    }
    
    func logOnboardingSkipped() {
        Analytics.logEvent("onboarding_skipped", parameters: nil)
    }
    
    func logPermissionGranted(permissionType: String) {
        Analytics.logEvent("permission_granted", parameters: [
            "permission_type": permissionType as NSObject
        ])
    }
    
    func logPermissionDenied(permissionType: String) {
        Analytics.logEvent("permission_denied", parameters: [
            "permission_type": permissionType as NSObject
        ])
    }
    
    // MARK: - Vehicle Management Events
    
    func logVehicleAdded(vehicleType: String, color: String) {
        Analytics.logEvent("vehicle_added", parameters: [
            "vehicle_type": vehicleType as NSObject,
            "color": color as NSObject
        ])
    }
    
    func logVehicleEdited(vehicleId: String) {
        Analytics.logEvent("vehicle_edited", parameters: [
            "vehicle_id": vehicleId as NSObject
        ])
    }
    
    func logVehicleDeleted(vehicleId: String) {
        Analytics.logEvent("vehicle_deleted", parameters: [
            "vehicle_id": vehicleId as NSObject
        ])
    }
    
    func logVehicleSelected(vehicleId: String) {
        Analytics.logEvent("vehicle_selected", parameters: [
            "vehicle_id": vehicleId as NSObject
        ])
    }
    
    // MARK: - Parking Events
    
    func logParkingLocationSet(method: String) {
        Analytics.logEvent("parking_location_set", parameters: [
            "method": method as NSObject
        ])
    }
    
    func logParkingLocationCleared() {
        Analytics.logEvent("parking_location_cleared", parameters: nil)
    }
    
    func logParkingScheduleSelected(scheduleType: String, duration: String) {
        Analytics.logEvent("parking_schedule_selected", parameters: [
            "schedule_type": scheduleType as NSObject,
            "duration": duration as NSObject
        ])
    }
    
    func logParkingConfirmed(vehicleId: String, hasSchedule: Bool) {
        Analytics.logEvent("parking_confirmed", parameters: [
            "vehicle_id": vehicleId as NSObject,
            "has_schedule": hasSchedule as NSObject
        ])
    }
    
    func logFindMyCarTapped() {
        Analytics.logEvent("find_my_car_tapped", parameters: nil)
    }
    
    func logParkingLocationShared(method: String) {
        Analytics.logEvent("parking_location_shared", parameters: [
            "method": method as NSObject
        ])
    }
    
    // MARK: - Map Interaction Events (Throttled)
    
    func logMapCenteredOnUser() {
        guard shouldLogMapEvent() else { return }
        Analytics.logEvent("map_centered_on_user", parameters: nil)
    }
    
    func logMapCenteredOnVehicle() {
        guard shouldLogMapEvent() else { return }
        Analytics.logEvent("map_centered_on_vehicle", parameters: nil)
    }
    
    func logStreetCleaningInfoViewed() {
        Analytics.logEvent("street_cleaning_info_viewed", parameters: nil)
    }
    
    // Helper method for throttling map events
    private func shouldLogMapEvent() -> Bool {
        let now = Date()
        if let lastTime = lastMapCenterTime {
            let timeSinceLastEvent = now.timeIntervalSince(lastTime)
            if timeSinceLastEvent < mapEventThrottleInterval {
                return false
            }
        }
        lastMapCenterTime = now
        return true
    }
    
    // MARK: - Smart Park Events
    
    func logSmartParkTabClicked() {
        Analytics.logEvent("smart_park_tab_clicked", parameters: nil)
    }
    
    func logSmartParkSetupStarted() {
        Analytics.logEvent("smart_park_setup_started", parameters: nil)
    }
    
    func logSmartParkSetupCompleted() {
        Analytics.logEvent("smart_park_setup_completed", parameters: nil)
    }
    
    func logSmartParkEnabled() {
        Analytics.logEvent("smart_park_enabled", parameters: nil)
    }
    
    func logSmartParkDisabled() {
        Analytics.logEvent("smart_park_disabled", parameters: nil)
    }
    
    func logSmartParkModeChanged(mode: String) {
        Analytics.logEvent("smart_park_mode_changed", parameters: [
            "mode": mode as NSObject // "manual" or "confirmation"
        ])
    }
    
    func logSmartParkConfirmClicked() {
        Analytics.logEvent("smart_park_confirm_clicked", parameters: nil)
    }
    
    // MARK: - Navigation Events
    
    func logHistoryTabClicked() {
        Analytics.logEvent("history_tab_clicked", parameters: nil)
    }
    
    func logHistoryItemClicked() {
        Analytics.logEvent("history_item_clicked", parameters: nil)
    }
    
    func logRemindersTabClicked() {
        Analytics.logEvent("reminders_tab_clicked", parameters: nil)
    }
    
    // MARK: - Location Movement Events
    
    func logLocationMovedViaCarIcon() {
        Analytics.logEvent("location_moved_via_car_icon", parameters: nil)
    }
    
    func logLocationMovedViaUserButton() {
        Analytics.logEvent("location_moved_via_user_button", parameters: nil)
    }
    
    // MARK: - Reminder Events
    
    func logReminderCreated(reminderType: String, timing: String) {
        Analytics.logEvent("reminder_created", parameters: [
            "reminder_type": reminderType as NSObject,
            "timing": timing as NSObject
        ])
    }
    
    // Helper function to determine reminder type from ReminderTiming
    func getReminderType(from timing: ReminderTiming) -> String {
        switch timing {
        case .preset(let preset):
            switch preset {
            case .dayBefore:
                return "Evening Before"
            case .morningOf:
                return "Morning Of"
            case .thirtyMinutes:
                return "30 Minutes Before"
            default:
                return "Custom"
            }
        case .custom:
            return "Custom"
        }
    }
    
    func logReminderEdited(reminderId: String) {
        Analytics.logEvent("reminder_edited", parameters: [
            "reminder_id": reminderId as NSObject
        ])
    }
    
    func logReminderDeleted(reminderId: String) {
        Analytics.logEvent("reminder_deleted", parameters: [
            "reminder_id": reminderId as NSObject
        ])
    }
    
    func logReminderToggled(enabled: Bool) {
        Analytics.logEvent("reminder_toggled", parameters: [
            "enabled": enabled as NSObject
        ])
    }
    
    func logRemindersSheetOpened() {
        Analytics.logEvent("reminders_sheet_opened", parameters: nil)
    }
    
    func logRemindersSheetClosed() {
        Analytics.logEvent("reminders_sheet_closed", parameters: nil)
    }
    
    func logNotificationSent(reminderType: String) {
        Analytics.logEvent("notification_sent", parameters: [
            "reminder_type": reminderType as NSObject
        ])
    }
    
    func logNotificationTapped() {
        Analytics.logEvent("notification_tapped", parameters: nil)
    }
    
    // MARK: - Data Events (Only essential ones)
    
    func logStreetDataLoaded(loadTime: Double, dataSize: Int) {
        Analytics.logEvent("street_data_loaded", parameters: [
            "load_time": loadTime as NSObject,
            "data_size": dataSize as NSObject
        ])
    }
    
    func logLocationSearchPerformed() {
        Analytics.logEvent("location_search_performed", parameters: nil)
    }
    
    func logErrorOccurred(errorType: String, screenName: String) {
        Analytics.logEvent("error_occurred", parameters: [
            "error_type": errorType as NSObject,
            "screen_name": screenName as NSObject
        ])
    }
}
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
    
    func logVehicleActivated() {
        Analytics.logEvent("vehicle_activated", parameters: nil)
    }
    
    func logVehicleDeactivated() {
        Analytics.logEvent("vehicle_deactivated", parameters: nil)
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
    
    // MARK: - Map Interaction Events
    
    func logMapCenteredOnUser() {
        Analytics.logEvent("map_centered_on_user", parameters: nil)
    }
    
    func logMapCenteredOnVehicle() {
        Analytics.logEvent("map_centered_on_vehicle", parameters: nil)
    }
    
    func logMapZoomed(zoomLevel: Double) {
        Analytics.logEvent("map_zoomed", parameters: [
            "zoom_level": zoomLevel as NSObject
        ])
    }
    
    func logMapPanned() {
        Analytics.logEvent("map_panned", parameters: nil)
    }
    
    func logStreetCleaningInfoViewed() {
        Analytics.logEvent("street_cleaning_info_viewed", parameters: nil)
    }
    
    // MARK: - Reminder Events
    
    func logReminderCreated(reminderType: String, timing: String) {
        Analytics.logEvent("reminder_created", parameters: [
            "reminder_type": reminderType as NSObject,
            "timing": timing as NSObject
        ])
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
    
    // MARK: - Navigation/UI Events
    
    func logTabSwitched(tabName: String) {
        Analytics.logEvent("tab_switched", parameters: [
            "tab_name": tabName as NSObject
        ])
    }
    
    func logSettingsOpened() {
        Analytics.logEvent("settings_opened", parameters: nil)
    }
    
    func logHelpTapped() {
        Analytics.logEvent("help_tapped", parameters: nil)
    }
    
    func logErrorOccurred(errorType: String, screenName: String) {
        Analytics.logEvent("error_occurred", parameters: [
            "error_type": errorType as NSObject,
            "screen_name": screenName as NSObject
        ])
    }
    
    // MARK: - Data Events
    
    func logStreetDataLoaded(loadTime: Double, dataSize: Int) {
        Analytics.logEvent("street_data_loaded", parameters: [
            "load_time": loadTime as NSObject,
            "data_size": dataSize as NSObject
        ])
    }
    
    func logGeocodingPerformed(success: Bool) {
        Analytics.logEvent("geocoding_performed", parameters: [
            "success": success as NSObject
        ])
    }
    
    func logLocationSearchPerformed() {
        Analytics.logEvent("location_search_performed", parameters: nil)
    }
}
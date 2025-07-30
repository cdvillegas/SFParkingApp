//
//  StreetDataManager.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import Combine
import CoreLocation

class StreetDataManager: ObservableObject {
    @Published var schedule: SweepSchedule?
    @Published var isLoading = false
    @Published var hasError = false
    @Published var nextUpcomingSchedule: UpcomingSchedule?
    
    // For area visualization in two-step location setting
    @Published var areaSchedules: [SweepSchedule] = []
    @Published var isLoadingAreaSchedules = false
    @Published var selectedSchedule: SweepSchedule?
    
    // Add debouncing to prevent repeated API calls
    private var lastFetchedCoordinate: CLLocationCoordinate2D?
    private var lastFetchTime: Date?
    private let minimumFetchInterval: TimeInterval = 5.0 // 5 seconds
    private let coordinateThreshold: Double = 0.0001 // ~10 meters
    
    func fetchSchedules(for coordinate: CLLocationCoordinate2D) {
        // Check if we should skip this fetch due to debouncing
        if shouldSkipFetch(for: coordinate) {
            return
        }
        
        performFetch(for: coordinate)
    }
    
    // Force a fresh fetch, bypassing debouncing
    func forceFetchSchedules(for coordinate: CLLocationCoordinate2D) {
        performFetch(for: coordinate)
    }
    
    private func performFetch(for coordinate: CLLocationCoordinate2D) {
        // Update tracking variables
        lastFetchedCoordinate = coordinate
        lastFetchTime = Date()
        
        isLoading = true
        hasError = false
        nextUpcomingSchedule = nil
        
        let startTime = Date()
        
        StreetDataService.shared.getClosestSchedule(for: coordinate) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                let loadTime = Date().timeIntervalSince(startTime)
                
                switch result {
                case .success(let schedule):
                    if let schedule = schedule {
                        self?.schedule = schedule
                        self?.processNextSchedule(for: schedule)
                        self?.hasError = false
                        
                        // Log successful data load
                        AnalyticsManager.shared.logStreetDataLoaded(
                            loadTime: loadTime,
                            dataSize: 1 // Single schedule
                        )
                    } else {
                        self?.hasError = false
                        self?.schedule = nil
                        self?.nextUpcomingSchedule = nil
                    }
                case .failure(let error):
                    print("❌ Error fetching schedule: \(error)")
                    self?.hasError = true
                    self?.schedule = nil
                    self?.nextUpcomingSchedule = nil
                    
                    // Log error
                    AnalyticsManager.shared.logErrorOccurred(
                        errorType: "street_data_fetch_failed",
                        screenName: "parking_location"
                    )
                }
            }
        }
    }
    
    // Helper to determine if we should skip the fetch
    private func shouldSkipFetch(for coordinate: CLLocationCoordinate2D) -> Bool {
        // Check if we have a recent fetch
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
            return true
        }
        
        // Check if the coordinate is too close to the last one
        if let lastCoordinate = lastFetchedCoordinate {
            let latDiff = abs(coordinate.latitude - lastCoordinate.latitude)
            let lonDiff = abs(coordinate.longitude - lastCoordinate.longitude)
            
            if latDiff < coordinateThreshold && lonDiff < coordinateThreshold {
                return true
            }
        }
        
        return false
    }
    
    // Separate geocoding for debug to avoid conflicts
    private func reverseGeocodeForDebug(coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                let address = self.formatAddress(from: placemark)
                print("🔍 Fetching schedules for address: \(address)")
            } else {
                print("🔍 Fetching schedules for coordinate: \(coordinate) (address lookup failed)")
            }
        }
    }

    // Helper function to format address
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var addressComponents: [String] = []
        
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            addressComponents.append("\(streetNumber) \(streetName)")
        } else if let streetName = placemark.thoroughfare {
            addressComponents.append(streetName)
        }
        
        if let city = placemark.locality {
            addressComponents.append(city)
        }
        
        if let state = placemark.administrativeArea {
            addressComponents.append(state)
        }
        
        if !addressComponents.isEmpty {
            return addressComponents.joined(separator: ", ")
        }
        
        if let name = placemark.name {
            return name
        }
        
        return "Unknown Location"
    }
    
    func processNextSchedule(for schedule: SweepSchedule) {
        // Check if we should use the new aggregated approach
        if StreetDataService.shared.useNewDataset {
            processNextScheduleAggregated(for: schedule)
        } else {
            // Move heavy calculations off main thread
            Task {
                await processNextScheduleAsync(for: schedule)
            }
        }
    }
    
    private func processNextScheduleAggregated(for schedule: SweepSchedule) {
        Task {
            // Get the aggregated schedule from the service
            StreetDataService.shared.getClosestAggregatedSchedule(for: CLLocationCoordinate2D(
                latitude: schedule.line?.coordinates.first?[1] ?? 0,
                longitude: schedule.line?.coordinates.first?[0] ?? 0
            )) { [weak self] result in
                switch result {
                case .success(let aggregatedSchedule):
                    if let aggregated = aggregatedSchedule {
                        // Get all schedule days from the aggregated data
                        let allDays = StreetDataService.shared.getAllScheduleDays(from: aggregated)
                        
                        Task {
                            await self?.processMultipleDaysAsync(schedules: allDays, streetName: schedule.streetName)
                        }
                    }
                case .failure:
                    // Fall back to single schedule processing
                    Task {
                        await self?.processNextScheduleAsync(for: schedule)
                    }
                }
            }
        }
    }
    
    private func processMultipleDaysAsync(schedules: [SweepSchedule], streetName: String) async {
        let now = Date()
        var allUpcomingSchedules: [UpcomingSchedule] = []
        
        // Process each day's schedule
        for schedule in schedules {
            guard let weekday = schedule.weekday,
                  let fromHour = schedule.fromhour,
                  let toHour = schedule.tohour else { continue }
            
            let weekdayNum = dayStringToWeekday(weekday)
            guard weekdayNum > 0 else { continue }
            
            guard let startHour = Int(fromHour),
                  let endHour = Int(toHour) else { continue }
            
            // Find next occurrences for this specific day
            let nextOccurrences = findNextOccurrences(weekday: weekdayNum, schedule: schedule, from: now)
            
            for nextDate in nextOccurrences {
                if let nextDateTime = createDateTime(date: nextDate, hour: startHour),
                   let endDateTime = createDateTime(date: nextDate, hour: endHour),
                   nextDateTime > now {
                    
                    let upcomingSchedule = UpcomingSchedule(
                        streetName: streetName,
                        date: nextDateTime,
                        endDate: endDateTime,
                        dayOfWeek: weekday,
                        startTime: schedule.startTime,
                        endTime: schedule.endTime
                    )
                    
                    allUpcomingSchedules.append(upcomingSchedule)
                }
            }
        }
        
        // Find the next upcoming schedule across all days
        let result = allUpcomingSchedules.sorted { $0.date < $1.date }.first
        
        // Update UI on main thread
        await MainActor.run {
            nextUpcomingSchedule = result
        }
        
        if let next = result {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            print("✅ Next occurrence (aggregated): \(formatter.string(from: next.date))")
        } else {
            print("❌ No upcoming schedules found in aggregated data")
        }
    }
    
    /// Calculate next schedule immediately (synchronous) for instant UI updates
    func calculateNextScheduleImmediate(for schedule: SweepSchedule) -> UpcomingSchedule? {
        // For new dataset, we already have the summary which might be sufficient for immediate display
        if StreetDataService.shared.useNewDataset && schedule.fullname != nil {
            // Return a placeholder with the summary for immediate display
            // The async method will calculate the exact next time
            return UpcomingSchedule(
                streetName: schedule.streetName,
                date: Date(), // Placeholder, will be updated by async method
                endDate: Date(),
                dayOfWeek: "", 
                startTime: "",
                endTime: schedule.fullname ?? "Multiple schedules" // Use the summary
            )
        }
        
        let now = Date()
        
        guard let weekday = schedule.weekday,
              let fromHour = schedule.fromhour,
              let toHour = schedule.tohour else { 
            return nil
        }
        
        let weekdayNum = dayStringToWeekday(weekday)
        guard weekdayNum > 0 else { return nil }
        
        guard let startHour = Int(fromHour),
              let endHour = Int(toHour) else { 
            return nil
        }
        
        // Quick calculation for immediate UI update - just get next occurrence
        let nextOccurrences = findNextOccurrences(weekday: weekdayNum, schedule: schedule, from: now)
        
        for nextDate in nextOccurrences {
            if let nextDateTime = createDateTime(date: nextDate, hour: startHour),
               let endDateTime = createDateTime(date: nextDate, hour: endHour),
               nextDateTime > now {
                
                return UpcomingSchedule(
                    streetName: schedule.streetName,
                    date: nextDateTime,
                    endDate: endDateTime,
                    dayOfWeek: weekday,
                    startTime: schedule.startTime,
                    endTime: schedule.endTime
                )
            }
        }
        
        return nil
    }
    
    private func processNextScheduleAsync(for schedule: SweepSchedule) async {
        let now = Date()
        
        guard let weekday = schedule.weekday,
              let fromHour = schedule.fromhour,
              let toHour = schedule.tohour else { 
            print("❌ Missing schedule data: weekday=\(schedule.weekday ?? "nil"), fromHour=\(schedule.fromhour ?? "nil"), toHour=\(schedule.tohour ?? "nil")")
            return 
        }
        
        let weekdayNum = dayStringToWeekday(weekday)
        guard weekdayNum > 0 else { 
            print("❌ Invalid weekday: \(weekday)")
            return 
        }
        
        guard let startHour = Int(fromHour),
              let endHour = Int(toHour) else { 
            print("❌ Invalid hours: fromHour=\(fromHour), toHour=\(toHour)")
            return 
        }
        
        print("🔍 Processing schedule for \(schedule.streetName): \(weekday) \(schedule.startTime)-\(schedule.endTime)")
        
        // Perform heavy calculations on background thread
        let nextOccurrences = findNextOccurrences(weekday: weekdayNum, schedule: schedule, from: now)
        
        var upcomingSchedules: [UpcomingSchedule] = []
        
        for nextDate in nextOccurrences {
            if let nextDateTime = createDateTime(date: nextDate, hour: startHour),
               let endDateTime = createDateTime(date: nextDate, hour: endHour),
               nextDateTime > now {
                
                let upcomingSchedule = UpcomingSchedule(
                    streetName: schedule.streetName,
                    date: nextDateTime,
                    endDate: endDateTime,
                    dayOfWeek: weekday,
                    startTime: schedule.startTime,
                    endTime: schedule.endTime
                )
                
                upcomingSchedules.append(upcomingSchedule)
            }
        }
        
        let result = upcomingSchedules.sorted { $0.date < $1.date }.first
        
        // Update UI on main thread
        await MainActor.run {
            nextUpcomingSchedule = result
        }
        
        if let next = nextUpcomingSchedule {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            print("✅ Next occurrence: \(formatter.string(from: next.date))")
        } else {
            print("❌ No upcoming schedules found")
        }
    }
    
    private func findNextOccurrences(weekday: Int, schedule: SweepSchedule, from date: Date) -> [Date] {
        let calendar = Calendar.current
        var occurrences: [Date] = []
        
        // Look ahead for up to 3 months to find valid occurrences (optimization: reduced from 6 months)
        for monthOffset in 0..<3 {
            guard let futureMonth = calendar.date(byAdding: .month, value: monthOffset, to: date) else { continue }
            
            // Get all occurrences of the target weekday in this month
            let monthOccurrences = getAllWeekdayOccurrencesInMonth(weekday: weekday, month: futureMonth, calendar: calendar)
            
            for (weekNumber, weekdayDate) in monthOccurrences.enumerated() {
                let weekPos = weekNumber + 1
                let applies = doesScheduleApplyToWeek(weekNumber: weekPos, schedule: schedule)
                
                if applies {
                    // Create the actual start time for this occurrence
                    guard let startHour = schedule.fromhour, let hour = Int(startHour) else { continue }
                    guard let scheduleDateTime = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: weekdayDate) else { continue }
                    
                    // Debug logging
                    let debugFormatter = DateFormatter()
                    debugFormatter.dateFormat = "EEE MMM d, yyyy h:mm a"
                    print("  🔍 Checking occurrence: \(debugFormatter.string(from: scheduleDateTime)) (week \(weekPos))")
                    
                    // Only include if the schedule time is in the future
                    if scheduleDateTime > date {
                        print("    ✅ Added to occurrences")
                        occurrences.append(weekdayDate)
                        
                        // Early exit optimization: stop after finding 3 occurrences
                        if occurrences.count >= 3 {
                            return occurrences.sorted()
                        }
                    } else {
                        print("    ❌ Skipped (in the past)")
                    }
                } else {
                    print("  ❌ Schedule doesn't apply to week \(weekPos)")
                }
            }
        }
        
        return occurrences.sorted()
    }
    
    // Get all occurrences of a specific weekday in a given month
    private func getAllWeekdayOccurrencesInMonth(weekday: Int, month: Date, calendar: Calendar) -> [Date] {
        var occurrences: [Date] = []
        
        // Get the first day of the month
        let monthComponents = calendar.dateComponents([.year, .month], from: month)
        guard let firstDayOfMonth = calendar.date(from: monthComponents) else { return [] }
        
        // Find the first occurrence of the target weekday in this month
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        var daysToAdd = weekday - firstWeekday
        if daysToAdd < 0 {
            daysToAdd += 7
        }
        
        guard let firstOccurrence = calendar.date(byAdding: .day, value: daysToAdd, to: firstDayOfMonth) else { return [] }
        
        // Add all occurrences of this weekday in the month (typically 4-5 times)
        var currentDate = firstOccurrence
        while calendar.component(.month, from: currentDate) == calendar.component(.month, from: month) {
            occurrences.append(currentDate)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) else { break }
            currentDate = nextWeek
        }
        
        return occurrences
    }
    
    // Check if the schedule applies to a specific week number (1st, 2nd, 3rd, 4th, 5th)
    private func doesScheduleApplyToWeek(weekNumber: Int, schedule: SweepSchedule) -> Bool {
        switch weekNumber {
        case 1: return schedule.week1 == "1"
        case 2: return schedule.week2 == "1"
        case 3: return schedule.week3 == "1"
        case 4: return schedule.week4 == "1"
        case 5: return schedule.week5 == "1"
        default: return false
        }
    }
    
    private func dayStringToWeekday(_ dayString: String) -> Int {
        let normalizedDay = dayString.lowercased().trimmingCharacters(in: .whitespaces)
        
        switch normalizedDay {
        case "sun", "sunday": return 1
        case "mon", "monday": return 2
        case "tue", "tues", "tuesday": return 3
        case "wed", "wednesday": return 4
        case "thu", "thur", "thursday": return 5
        case "fri", "friday": return 6
        case "sat", "saturday": return 7
        default: return 0
        }
    }
    
    private func nextOccurrence(of weekday: Int, from date: Date, allowSameDay: Bool = false) -> Date {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        
        var daysToAdd = weekday - currentWeekday
        
        // If it's the same day and we allow same day, use 0 days
        // Otherwise, if it's today or in the past this week, move to next week
        if daysToAdd < 0 || (daysToAdd == 0 && !allowSameDay) {
            daysToAdd += 7
        }
        
        return calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
    }
    
    private func createDateTime(date: Date, hour: Int) -> Date? {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
    }
    
    /// Fetch all street sweeping schedules in an area for visualization
    func fetchAreaSchedules(for coordinate: CLLocationCoordinate2D) {
        isLoadingAreaSchedules = true
        selectedSchedule = nil
        
        StreetDataService.shared.getSchedulesInArea(for: coordinate) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingAreaSchedules = false
                
                switch result {
                case .success(let schedules):
                    self?.areaSchedules = schedules
                    print("✅ Loaded \(schedules.count) schedules for area visualization")
                case .failure(let error):
                    print("❌ Failed to load area schedules: \(error)")
                    self?.areaSchedules = []
                }
            }
        }
    }
    
    /// Select a specific schedule from the area schedules
    func selectSchedule(_ schedule: SweepSchedule) {
        selectedSchedule = schedule
        self.schedule = schedule
        processNextSchedule(for: schedule)
    }
    
    /// Clear area visualization data
    func clearAreaData() {
        areaSchedules = []
        selectedSchedule = nil
        isLoadingAreaSchedules = false
    }
    
    // Clean up method to reset state when needed
    func reset() {
        lastFetchedCoordinate = nil
        lastFetchTime = nil
        schedule = nil
        nextUpcomingSchedule = nil
        isLoading = false
        hasError = false
        
        // Clear area data
        clearAreaData()
    }
}

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
    
    func fetchSchedules(for coordinate: CLLocationCoordinate2D) {
        // Debug: Convert coordinate to address
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    let address = self.formatAddress(from: placemark)
                    print("Fetching schedules for address: \(address)")
                } else {
                    print("Fetching schedules for coordinate: \(coordinate) (address lookup failed)")
                }
            }
        }
        
        isLoading = true
        hasError = false
        nextUpcomingSchedule = nil
        
        StreetDataService.shared.getClosestSchedule(for: coordinate) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success(let schedule):
                    if let schedule = schedule {
                        self?.schedule = schedule
                        self?.processNextSchedule(for: schedule)
                        self?.hasError = false
                        print("✅ Successfully found schedule for street: \(schedule.streetName)")
                    } else {
                        self?.hasError = false
                        self?.schedule = nil
                        self?.nextUpcomingSchedule = nil
                        print("⚠️ No schedule found for this location")
                    }
                case .failure(let error):
                    print("❌ Error fetching schedule: \(error)")
                    self?.hasError = true
                    self?.schedule = nil
                    self?.nextUpcomingSchedule = nil
                }
            }
        }
    }

    // Helper function to format address (add this to your StreetDataManager)
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
    
    private func processNextSchedule(for schedule: SweepSchedule) {
        let now = Date()
        
        guard let weekday = schedule.weekday,
              let fromHour = schedule.fromhour,
              let toHour = schedule.tohour else { return }
        
        let weekdayNum = dayStringToWeekday(weekday)
        guard weekdayNum > 0 else { return }
        
        guard let startHour = Int(fromHour),
              let endHour = Int(toHour) else { return }
        
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
        
        nextUpcomingSchedule = upcomingSchedules.sorted { $0.date < $1.date }.first
    }
    
    private func findNextOccurrences(weekday: Int, schedule: SweepSchedule, from date: Date) -> [Date] {
        let calendar = Calendar.current
        var occurrences: [Date] = []
        
        // Look ahead for up to 8 weeks to find valid occurrences
        for weekOffset in 0..<8 {
            guard let futureDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: date) else { continue }
            
            // Find the next occurrence of the target weekday in this week
            let targetDate = nextOccurrence(of: weekday, from: futureDate, allowSameDay: weekOffset == 0)
            let weekOfMonth = calendar.component(.weekOfMonth, from: targetDate)
            
            let appliesThisWeek: Bool
            switch weekOfMonth {
            case 1: appliesThisWeek = schedule.week1 == "1"
            case 2: appliesThisWeek = schedule.week2 == "1"
            case 3: appliesThisWeek = schedule.week3 == "1"
            case 4: appliesThisWeek = schedule.week4 == "1"
            case 5: appliesThisWeek = schedule.week5 == "1"
            default: appliesThisWeek = false
            }
            
            if appliesThisWeek {
                occurrences.append(targetDate)
            }
        }
        
        return occurrences
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
}

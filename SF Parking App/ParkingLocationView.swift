//
//  ParkingLocationView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import MapKit
import CoreLocation

struct ParkingLocationView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var streetDataManager = StreetDataManager()
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.783759, longitude: -122.442232),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    
    var body: some View {
        VStack(spacing: 0) {
            // Map Section
            ZStack {
                Map(position: $mapPosition) {
                    // Show user location if available
                    if let userLocation = locationManager.userLocation {
                        Annotation("Your Location", coordinate: userLocation.coordinate) {
                            ZStack {
                                // Blue circular background for current location
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 20, height: 20)
                                
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                            }
                            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        }
                    }
                    
                    Annotation("Parked Car", coordinate: ParkingLocation.sample.coordinate) {
                        ZStack {
                            // Red circular background
                            Circle()
                                .fill(Color.red)
                                .frame(width: 28, height: 28)
                            
                            // White location pin icon
                            Image(systemName: "location.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                .mapStyle(.standard)
                .onReceive(locationManager.$userLocation) { location in
                    if let location = location {
                        withAnimation(.easeInOut(duration: 1.0)) {
                            mapPosition = .region(MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                            ))
                        }
                    }
                }
                
                // Center on User Location Button
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        // Go to Parked Car Button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                mapPosition = .region(MKCoordinateRegion(
                                    center: ParkingLocation.sample.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                                ))
                            }
                        }) {
                            Image(systemName: "car.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 44, height: 44)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .padding(.trailing, 12)
                        
                        // Center on User Location Button
                        Button(action: {
                            if let location = locationManager.userLocation {
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    mapPosition = .region(MKCoordinateRegion(
                                        center: location.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                                    ))
                                }
                            } else {
                                locationManager.requestLocation()
                            }
                        }) {
                            Image(systemName: "location.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 44, height: 44)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .padding(.trailing, 20)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            
            // Bottom UI Section
            VStack(spacing: 0) {
                // Last Parking Location Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Last Parking Location")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Text("View History")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.1))
                                )
                        }
                    }
                    
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.body)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1530 Broderick Street, San Francisco, California, 94115")
                                .font(.callout)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                            
                            Text("Parked Jun 21 at 12:12 PM  •  Manually Set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                // Divider
                Divider()
                    .padding(.horizontal, 20)
                
                // Upcoming Reminders Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Upcoming Reminders")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Text("View All")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.1))
                                )
                        }
                    }
                    
                    // Dynamic content based on street data
                    if streetDataManager.isLoading {
                        HStack(alignment: .center, spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Loading street sweeping data...")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if let nextSchedule = streetDataManager.nextUpcomingSchedule {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(nextSchedule.isUrgent ? .red : .orange)
                                .font(.body)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Street Sweeping - \(nextSchedule.streetName)")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text(nextSchedule.formattedDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("Auto-detected from location")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if streetDataManager.hasError {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.body)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Unable to load street data")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                
                                Button("Retry") {
                                    streetDataManager.fetchSchedules(for: ParkingLocation.sample.coordinate)
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.body)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No upcoming street sweeping")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("You're all clear for now!")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // Update Button
                Button(action: {
                    // Refresh street data when parking location is updated
                    streetDataManager.fetchSchedules(for: ParkingLocation.sample.coordinate)
                }) {
                    Text("Update Parking Location")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(25)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                
                // This spacer will push content up but allow background to extend
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            // Add a small delay to ensure the view is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                locationManager.requestLocationPermission()
                // Fetch street data for the parking location
                streetDataManager.fetchSchedules(for: ParkingLocation.sample.coordinate)
            }
        }
    }
}

// MARK: - Street Data Manager
class StreetDataManager: ObservableObject {
    @Published var schedules: [SweepSchedule] = []
    @Published var isLoading = false
    @Published var hasError = false
    @Published var nextUpcomingSchedule: UpcomingSchedule?
    
    func fetchSchedules(for coordinate: CLLocationCoordinate2D) {
        isLoading = true
        hasError = false
        
        StreetDataService.shared.getSchedule(for: coordinate) { [weak self] schedules in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let schedules = schedules {
                    self?.schedules = schedules
                    self?.processNextSchedule()
                    self?.hasError = false
                } else {
                    self?.hasError = true
                    self?.schedules = []
                    self?.nextUpcomingSchedule = nil
                }
            }
        }
    }
    
    private func processNextSchedule() {
        let now = Date()
        let calendar = Calendar.current
        
        // Find the next upcoming schedule
        var upcomingSchedules: [UpcomingSchedule] = []
        
        for schedule in schedules {
            // Use the raw API fields, not the computed properties
            guard let weekday = schedule.weekday,
                  let fromHour = schedule.fromhour,
                  let toHour = schedule.tohour else { continue }
            
            // Convert day string to weekday number
            let weekdayNum = dayStringToWeekday(weekday)
            guard weekdayNum > 0 else { continue }
            
            // Convert hour strings to integers
            guard let startHour = Int(fromHour),
                  let endHour = Int(toHour) else { continue }
            
            // Find all possible next occurrences for this schedule
            let nextOccurrences = findNextOccurrences(weekday: weekdayNum, schedule: schedule, from: now)
            
            for nextDate in nextOccurrences {
                // Create full date with time
                if let nextDateTime = createDateTime(date: nextDate, hour: startHour),
                   let endDateTime = createDateTime(date: nextDate, hour: endHour),
                   nextDateTime > now { // Only include future dates
                    
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
        }
        
        // Sort by date and take the earliest one
        nextUpcomingSchedule = upcomingSchedules.sorted { $0.date < $1.date }.first
    }
    
    private func findNextOccurrences(weekday: Int, schedule: SweepSchedule, from date: Date) -> [Date] {
        let calendar = Calendar.current
        var occurrences: [Date] = []
        
        // Look ahead 8 weeks to find all possible next occurrences
        for weekOffset in 0..<8 {
            let futureDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: date) ?? date
            let weekOfMonth = calendar.component(.weekOfMonth, from: futureDate)
            
            // Check if this schedule applies to this week of the month
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
                let nextOccurrence = nextOccurrence(of: weekday, from: futureDate)
                
                // Make sure this occurrence is in the correct week of the month
                let occurrenceWeekOfMonth = calendar.component(.weekOfMonth, from: nextOccurrence)
                if occurrenceWeekOfMonth == weekOfMonth {
                    occurrences.append(nextOccurrence)
                }
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
    
    private func nextOccurrence(of weekday: Int, from date: Date) -> Date {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        
        var daysToAdd = weekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7
        }
        
        return calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
    }
    
    private func createDateTime(date: Date, hour: Int) -> Date? {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
    }
}

// MARK: - Supporting Models
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
        // Consider it urgent if it's within 24 hours
        return date.timeIntervalSinceNow < 24 * 60 * 60
    }
}

// Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Only update if user moves 10 meters
        
        // Get the current authorization status
        authorizationStatus = locationManager.authorizationStatus
        print("LocationManager initialized with status: \(authorizationStatus.rawValue)")
    }
    
    func requestLocationPermission() {
        print("Requesting location permission. Current status: \(authorizationStatus.rawValue)")
        
        // Check if location services are enabled on the device
        guard CLLocationManager.locationServicesEnabled() else {
            print("Location services are disabled on this device")
            return
        }
        
        // Only request permission if not determined
        if authorizationStatus == .notDetermined {
            print("Status not determined, requesting permission...")
            locationManager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            print("Already authorized, starting location updates")
            startLocationUpdates()
        } else {
            print("Location access denied or restricted")
        }
    }
    
    func requestLocation() {
        print("Manual location request triggered")
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Not authorized, cannot get location")
            return
        }
        
        print("Getting one-time location")
        locationManager.requestLocation()
    }
    
    private func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("Cannot start location updates - not authorized")
            return
        }
        
        print("Starting continuous location updates")
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        DispatchQueue.main.async {
            self.userLocation = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        
        // If it's a location error, try requesting permission again
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("Location access denied by user")
            case .locationUnknown:
                print("Location service unable to determine location")
            case .network:
                print("Network error while getting location")
            default:
                print("Other location error: \(clError.localizedDescription)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Authorization status changed to: \(status.rawValue)")
        
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            switch status {
            case .notDetermined:
                print("Location permission not determined")
            case .denied, .restricted:
                print("Location permission denied or restricted")
            case .authorizedWhenInUse, .authorizedAlways:
                print("Location permission granted, starting updates")
                self.startLocationUpdates()
            @unknown default:
                print("Unknown authorization status")
            }
        }
    }
}

// Supporting Models
struct ParkingLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let address: String
    let timestamp: Date
    
    static let sample = ParkingLocation(
        coordinate: CLLocationCoordinate2D(latitude: 37.784009, longitude: -122.442300), // Coordinates with known street sweeping data
        address: "1530 Broderick Street, San Francisco, California, 94115",
        timestamp: Date()
    )
}

// Preview
struct ParkingLocationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ParkingLocationView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            ParkingLocationView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}

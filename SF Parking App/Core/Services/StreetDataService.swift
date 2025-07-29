//
//  StreetDataService.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import CoreLocation
import Darwin

enum ParkingError: LocalizedError {
    case networkError(Error)
    case invalidURL
    case noData
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        }
    }
    
    var userFriendlyMessage: String {
        switch self {
        case .networkError, .noData:
            return "Unable to check street sweeping schedules right now. Please try again later."
        case .invalidURL, .decodingError:
            return "There was a problem with the parking data. Please try again."
        }
    }
}

struct LineGeometry: Decodable {
    let type: String
    let coordinates: [[Double]]
}

struct SweepSchedule: Decodable {
    let cnn: String?
    let corridor: String?
    let limits: String?
    let blockside: String?
    let fullname: String?
    let weekday: String?
    let fromhour: String?
    let tohour: String?
    let week1: String?
    let week2: String?
    let week3: String?
    let week4: String?
    let week5: String?
    let holidays: String?
    let line: LineGeometry?
    
    // Computed properties for easier access
    var streetName: String {
        return corridor ?? "Unknown Street"
    }
    
    var sweepDay: String {
        return weekday ?? "Unknown"
    }
    
    var startTime: String {
        guard let hour = fromhour, let hourInt = Int(hour) else { return "Unknown" }
        let period = hourInt < 12 ? "AM" : "PM"
        let displayHour = hourInt == 0 ? 12 : (hourInt > 12 ? hourInt - 12 : hourInt)
        return "\(displayHour):00 \(period)"
    }
    
    var endTime: String {
        guard let hour = tohour, let hourInt = Int(hour) else { return "Unknown" }
        let period = hourInt < 12 ? "AM" : "PM"
        let displayHour = hourInt == 0 ? 12 : (hourInt > 12 ? hourInt - 12 : hourInt)
        return "\(displayHour):00 \(period)"
    }
}

// Helper struct for line segment operations
struct LineSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    
    // Find the closest point on this line segment to a given point
    func closestPoint(to point: CLLocationCoordinate2D) -> (point: CLLocationCoordinate2D, distance: Double) {
        let A = point
        let B = start
        let C = end
        
        // Vector from B to C
        let BCx = C.longitude - B.longitude
        let BCy = C.latitude - B.latitude
        
        // Vector from B to A
        let BAx = A.longitude - B.longitude
        let BAy = A.latitude - B.latitude
        
        // Project BA onto BC
        let dotProduct = BAx * BCx + BAy * BCy
        let lengthSquared = BCx * BCx + BCy * BCy
        
        if lengthSquared == 0 {
            // B and C are the same point
            let distance = CLLocation(latitude: B.latitude, longitude: B.longitude)
                .distance(from: CLLocation(latitude: A.latitude, longitude: A.longitude))
            return (B, distance)
        }
        
        let t = max(0, min(1, dotProduct / lengthSquared))
        
        let closestPoint = CLLocationCoordinate2D(
            latitude: B.latitude + t * (C.latitude - B.latitude),
            longitude: B.longitude + t * (C.longitude - B.longitude)
        )
        
        let distance = CLLocation(latitude: closestPoint.latitude, longitude: closestPoint.longitude)
            .distance(from: CLLocation(latitude: A.latitude, longitude: A.longitude))
        
        return (closestPoint, distance)
    }
}

// MARK: - Models
struct SweepScheduleWithSide {
    let schedule: SweepSchedule
    let offsetCoordinate: CLLocationCoordinate2D // Coordinate offset to the side of the street
    let side: String // "North", "South", "East", "West" or blockside description
    let distance: Double // Distance from user's selected point
    
    // For consolidated schedules, store the individual schedules for processing
    let individualSchedules: [SweepSchedule]? // nil for non-consolidated schedules
    
    // Computed property to get the schedule to use for processing (handles both consolidated and individual)
    var scheduleForProcessing: SweepSchedule {
        // For consolidated schedules, find the next upcoming individual schedule
        if let individuals = individualSchedules, individuals.count > 1 {
            // This is a consolidated schedule, need to find the next upcoming one
            // For now, just return the first one - we'll improve this later
            return individuals.first ?? schedule
        } else {
            // This is an individual schedule, use as-is
            return schedule
        }
    }
}

struct LocalSweepSchedule {
    let cnn: String
    let corridor: String
    let limits: String
    let blockSide: String
    let fullName: String
    let weekday: String
    let fromHour: Int
    let toHour: Int
    let week1: Int
    let week2: Int
    let week3: Int
    let week4: Int
    let week5: Int
    let holidays: Int
    let scheduleID: Int // Changed from blockSweepID to match new dataset
    let lineCoordinates: [[Double]] // Parsed from Line column
    
    // New fields from pipeline dataset (for future use)
    let citationCount: Int
    let avgCitationTime: Double?
    let minCitationTime: Double?
    let maxCitationTime: Double?
    
    // Backward compatibility
    var blockSweepID: Int { return scheduleID }
    
    // Computed properties for compatibility with existing code
    var streetName: String { return corridor }
    var sweepDay: String { return weekday }
    
    var startTime: String {
        let period = fromHour < 12 ? "AM" : "PM"
        let displayHour = fromHour == 0 ? 12 : (fromHour > 12 ? fromHour - 12 : fromHour)
        return "\(displayHour):00 \(period)"
    }
    
    var endTime: String {
        let period = toHour < 12 ? "AM" : "PM"
        let displayHour = toHour == 0 ? 12 : (toHour > 12 ? toHour - 12 : toHour)
        return "\(displayHour):00 \(period)"
    }
}

// MARK: - Spatial Grid for Fast Lookups
class SpatialGrid {
    private let cellSize: Double = 0.001 // roughly 100 meters in SF
    private var grid: [String: [LocalSweepSchedule]] = [:]
    
    private func getCellKey(for coordinate: CLLocationCoordinate2D) -> String {
        let x = Int(coordinate.longitude / cellSize)
        let y = Int(coordinate.latitude / cellSize)
        return "\(x),\(y)"
    }
    
    func addSchedule(_ schedule: LocalSweepSchedule) {
        // Add schedule to all grid cells it intersects
        for coord in schedule.lineCoordinates {
            let location = CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
            let key = getCellKey(for: location)
            
            if grid[key] == nil {
                grid[key] = []
            }
            
            // Avoid duplicates
            if !grid[key]!.contains(where: { $0.scheduleID == schedule.scheduleID }) {
                grid[key]!.append(schedule)
            }
        }
    }
    
    func getSchedulesNear(_ coordinate: CLLocationCoordinate2D, radius: Int = 2) -> [LocalSweepSchedule] {
        var schedules: [LocalSweepSchedule] = []
        let _ = getCellKey(for: coordinate)
        let centerX = Int(coordinate.longitude / cellSize)
        let centerY = Int(coordinate.latitude / cellSize)
        
        // Check surrounding cells
        for dx in -radius...radius {
            for dy in -radius...radius {
                let key = "\(centerX + dx),\(centerY + dy)"
                if let cellSchedules = grid[key] {
                    schedules.append(contentsOf: cellSchedules)
                }
            }
        }
        
        // Remove duplicates
        let uniqueSchedules = Array(Set(schedules.map { $0.scheduleID }))
            .compactMap { id in schedules.first { $0.scheduleID == id } }
        
        return uniqueSchedules
    }
}

// MARK: - Main Service
final class StreetDataService {
    static let shared = StreetDataService()
    
    private var schedules: [LocalSweepSchedule] = []
    private var spatialGrid = SpatialGrid()
    private let maxDistance = 50.0 // 50 feet
    private var isLoaded = false
    
    private init() {
        // Test Python dict parsing with known good data
        if let testCoords = parseLineCoordinatesFromDict("\"{'type': 'LineString', 'coordinates': [[-122.395007841381, 37.787717615642], [-122.394481273193, 37.787298215216]]}\"") {
            print("🧪 Python dict parsing test successful: \(testCoords.count) coordinates")
        } else {
            print("❌ Python dict parsing test failed")
        }
        
        print("🧪 Testing next occurrence logic...")
        let testSchedule = LocalSweepSchedule(
            cnn: "test",
            corridor: "Test St",
            limits: "Test Limits",
            blockSide: "Test",
            fullName: "Monday",
            weekday: "Monday", 
            fromHour: 8,
            toHour: 10,
            week1: 1, week2: 0, week3: 1, week4: 0, week5: 0,
            holidays: 0,
            scheduleID: 999999,
            lineCoordinates: [[0.0, 0.0]],
            citationCount: 0,
            avgCitationTime: nil,
            minCitationTime: nil,
            maxCitationTime: nil
        )
        
        if let nextDate = getNextValidOccurrence(for: testSchedule, after: Date()) {
            print("🧪 Next occurrence test: \(nextDate)")
        }
        
        // Test side detection logic
        let testSegment = LineSegment(
            start: CLLocationCoordinate2D(latitude: 37.787717615642, longitude: -122.395007841381),
            end: CLLocationCoordinate2D(latitude: 37.787298215216, longitude: -122.394481273193)
        )
        
        // Test point slightly east of the segment
        let testPointEast = CLLocationCoordinate2D(latitude: 37.787500, longitude: -122.394700)
        let sideEast = determineStreetSide(point: testPointEast, segment: testSegment)
        print("🧪 Side detection test (East): \(sideEast)")
        
        // Test point slightly west of the segment  
        let testPointWest = CLLocationCoordinate2D(latitude: 37.787500, longitude: -122.394800)
        let sideWest = determineStreetSide(point: testPointWest, segment: testSegment)
        print("🧪 Side detection test (West): \(sideWest)")
        
        loadSchedulesFromCSV()
    }
    
    // MARK: - CSV Loading
    private func loadSchedulesFromCSV() {
        print("Loading street sweeping schedules from CSV...")
        
        guard let csvPath = Bundle.main.path(forResource: "final_analysis_20250728_220918_schedules_20250729_000531", ofType: "csv") else {
            print("❌ CSV file not found in bundle")
            return
        }
        
        guard let csvContent = try? String(contentsOfFile: csvPath, encoding: .utf8) else {
            print("❌ Failed to read CSV file")
            return
        }
        
        let lines = csvContent.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            print("❌ CSV file appears empty")
            return
        }
        
        // Skip header row
        let dataLines = Array(lines.dropFirst())
        var loadedCount = 0
        
        for (index, line) in dataLines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            
            if let schedule = parseCSVLine(line, lineIndex: index) {
                schedules.append(schedule)
                spatialGrid.addSchedule(schedule)
                loadedCount += 1
            } else if index < 10 {
                print("❌ Failed to parse line \(index): \(line.prefix(100))")
            }
        }
        
        isLoaded = true
        print("✅ Loaded \(loadedCount) street sweeping schedules from \(dataLines.count) total lines")
    }
    
    private func parseCSVLine(_ line: String, lineIndex: Int) -> LocalSweepSchedule? {
        let columns = parseCSVRow(line)
        
        guard columns.count >= 19 else {
            return nil
        }
        
        // Parse the Line column (Python dict format)
        guard let lineCoordinates = parseLineCoordinatesFromDict(columns[14]) else {
            if lineIndex < 5 {
                print("❌ Failed to parse coordinates for line \(lineIndex): \(columns[14].prefix(100))")
            }
            return nil
        }
        
        if lineIndex < 5 {
            print("✅ Parsed \(lineCoordinates.count) coordinates for \(columns[2])")
        }
        
        // Map new dataset columns to LocalSweepSchedule
        return LocalSweepSchedule(
            cnn: columns[1],                          // cnn
            corridor: columns[2],                     // corridor
            limits: columns[3],                       // limits
            blockSide: columns[5],                    // block_side
            fullName: columns[6],                     // weekday (use as fullName for now)
            weekday: columns[6],                      // weekday
            fromHour: Int(columns[7]) ?? 0,          // scheduled_from_hour
            toHour: Int(columns[8]) ?? 0,            // scheduled_to_hour
            week1: Int(columns[9]) ?? 0,             // week1
            week2: Int(columns[10]) ?? 0,            // week2
            week3: Int(columns[11]) ?? 0,            // week3
            week4: Int(columns[12]) ?? 0,            // week4
            week5: Int(columns[13]) ?? 0,            // week5
            holidays: 0,                              // Not in new dataset, default to 0
            scheduleID: Int(columns[0]) ?? 0,        // schedule_id
            lineCoordinates: lineCoordinates,
            citationCount: Int(columns[15]) ?? 0,    // citation_count
            avgCitationTime: Double(columns[16]),    // avg_citation_time (can be empty)
            minCitationTime: Double(columns[17]),    // min_citation_time (can be empty)
            maxCitationTime: Double(columns[18])     // max_citation_time (can be empty)
        )
    }
    
    // Simple CSV parser that handles quoted fields
    private func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = row.startIndex
        
        while i < row.endIndex {
            let char = row[i]
            
            if char == "\"" {
                if inQuotes && i < row.index(before: row.endIndex) && row[row.index(after: i)] == "\"" {
                    // Escaped quote
                    currentField.append("\"")
                    i = row.index(after: i)
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
            
            i = row.index(after: i)
        }
        
        // Add the last field
        fields.append(currentField.trimmingCharacters(in: .whitespaces))
        
        return fields
    }
    
    // Parse the Line column which contains WKT LINESTRING format
    private func parseLineCoordinates(_ lineString: String) -> [[Double]]? {
        // The Line column contains WKT format like: "LINESTRING (-122.416291701103 37.777493843394, -122.416317106137 37.777410028361)"
        let trimmed = lineString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove quotes if present
        let unquoted = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") 
            ? String(trimmed.dropFirst().dropLast()) 
            : trimmed
        
        // Check if it starts with LINESTRING
        guard unquoted.hasPrefix("LINESTRING") else {
            return nil
        }
        
        // Extract coordinates from LINESTRING (lon lat, lon lat, ...)
        let coordinatesStart = unquoted.firstIndex(of: "(")
        let coordinatesEnd = unquoted.lastIndex(of: ")")
        
        guard let start = coordinatesStart, let end = coordinatesEnd else {
            return nil
        }
        
        let coordinatesString = String(unquoted[unquoted.index(after: start)..<end])
        let coordinatePairs = coordinatesString.components(separatedBy: ",")
        
        var coordinates: [[Double]] = []
        
        for pair in coordinatePairs {
            let trimmedPair = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            let components = trimmedPair.components(separatedBy: " ")
            
            if components.count == 2,
               let lon = Double(components[0]),
               let lat = Double(components[1]) {
                coordinates.append([lon, lat])
            }
        }
        
        return coordinates.isEmpty ? nil : coordinates
    }
    
    // Parse the Line column which contains Python dict format
    private func parseLineCoordinatesFromDict(_ dictString: String) -> [[Double]]? {
        // The Line column contains Python dict format like: "{'type': 'LineString', 'coordinates': [[-122.395007841381, 37.787717615642], [-122.394481273193, 37.787298215216]]}"
        let trimmed = dictString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove outer quotes if present
        let unquoted = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") 
            ? String(trimmed.dropFirst().dropLast()) 
            : trimmed
        
        // Find the coordinates array within the dict
        guard let coordinatesStart = unquoted.range(of: "'coordinates': ["),
              let coordinatesEnd = unquoted.range(of: "]}", options: .backwards) else {
            return nil
        }
        
        // Extract just the coordinates array content
        let startIndex = coordinatesStart.upperBound
        let endIndex = coordinatesEnd.lowerBound
        let coordinatesContent = String(unquoted[startIndex..<endIndex])
        
        // Parse coordinate pairs: [[-122.395007841381, 37.787717615642], [-122.394481273193, 37.787298215216]]
        var coordinates: [[Double]] = []
        
        // Split by "], [" to get individual coordinate pairs
        let pairStrings = coordinatesContent.components(separatedBy: "], [")
        
        for (index, pairString) in pairStrings.enumerated() {
            var cleanPair = pairString
            
            // Clean up the first and last pairs
            if index == 0 {
                cleanPair = cleanPair.replacingOccurrences(of: "[", with: "")
            }
            if index == pairStrings.count - 1 {
                cleanPair = cleanPair.replacingOccurrences(of: "]", with: "")
            }
            
            // Parse lon, lat
            let components = cleanPair.components(separatedBy: ", ")
            if components.count == 2,
               let lon = Double(components[0]),
               let lat = Double(components[1]) {
                coordinates.append([lon, lat])
            }
        }
        
        return coordinates.isEmpty ? nil : coordinates
    }
    
    // MARK: - Public API (matches your existing interface)
    func getClosestSchedule(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<SweepSchedule?, ParkingError>) -> Void) {
        guard isLoaded else {
            print("❌ StreetDataService not loaded yet")
            completion(.failure(.noData))
            return
        }
        
        print("🔍 Total schedules loaded: \(schedules.count)")
        
        // Get candidates from spatial grid
        let candidates = spatialGrid.getSchedulesNear(coordinate)
        print("🔍 Found \(candidates.count) candidate schedules near \(coordinate)")
        
        // Find the closest one
        let closestSchedule = findClosestSchedule(from: coordinate, schedules: candidates)
        
        if let schedule = closestSchedule {
            print("✅ Found closest schedule: \(schedule.corridor) at distance within 50 feet")
        } else {
            print("❌ No schedules found within 50 feet of \(coordinate)")
        }
        
        // Convert to your existing SweepSchedule format
        if let local = closestSchedule {
            let apiSchedule = convertToAPIFormat(local)
            completion(.success(apiSchedule))
        } else {
            completion(.success(nil))
        }
    }
    
    // New method to get nearby schedules for side-of-street selection
    func getNearbySchedulesForSelection(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<[SweepScheduleWithSide], ParkingError>) -> Void) {
        guard isLoaded else {
            completion(.failure(.noData))
            return
        }
        
        // Get candidates from spatial grid
        let candidates = spatialGrid.getSchedulesNear(coordinate)
        
        // Find all schedules within range and calculate their side positions
        let schedulesWithSides = findSchedulesWithSides(from: coordinate, schedules: candidates)
        
        // Consolidate schedules that share the same block/side/time
        let consolidatedSchedules = consolidateSchedulesByGroup(schedulesWithSides)
        
        print("🔍 Found \(schedulesWithSides.count) raw schedules, consolidated to \(consolidatedSchedules.count) grouped schedules")
        
        completion(.success(consolidatedSchedules))
    }
    
    private func consolidateSchedulesByGroup(_ schedulesWithSides: [SweepScheduleWithSide]) -> [SweepScheduleWithSide] {
        // Group schedules by block + side + time
        var groups: [String: [SweepScheduleWithSide]] = [:]
        
        for scheduleWithSide in schedulesWithSides {
            let schedule = scheduleWithSide.schedule
            
            // Create grouping key: corridor + limits + blockside + fromhour + tohour
            let groupKey = "\(schedule.corridor ?? "")|\(schedule.limits ?? "")|\(schedule.blockside ?? "")|\(schedule.fromhour ?? "")|\(schedule.tohour ?? "")"
            
            if groups[groupKey] == nil {
                groups[groupKey] = []
            }
            groups[groupKey]!.append(scheduleWithSide)
        }
        
        // Convert groups back to consolidated schedules
        var consolidatedSchedules: [SweepScheduleWithSide] = []
        
        for (_, groupSchedules) in groups {
            if let consolidatedSchedule = createConsolidatedSchedule(from: groupSchedules) {
                consolidatedSchedules.append(consolidatedSchedule)
            }
        }
        
        // Sort by distance, closest first
        return consolidatedSchedules.sorted { $0.distance < $1.distance }
    }
    
    private func createConsolidatedSchedule(from schedules: [SweepScheduleWithSide]) -> SweepScheduleWithSide? {
        guard let firstSchedule = schedules.first else { return nil }
        
        // If only one schedule, return as-is
        if schedules.count == 1 {
            return firstSchedule
        }
        
        // Collect all the weekdays from the schedules
        var weekdays: [String] = []
        var weekdaySet: Set<String> = []
        
        for scheduleWithSide in schedules {
            if let weekday = scheduleWithSide.schedule.weekday, !weekdaySet.contains(weekday) {
                weekdays.append(weekday)
                weekdaySet.insert(weekday)
            }
        }
        
        // Sort weekdays in logical order
        let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        weekdays.sort { dayOrder.firstIndex(of: $0) ?? 99 < dayOrder.firstIndex(of: $1) ?? 99 }
        
        // Create consolidated weekday string with short names and "Daily" for all 7 days
        let consolidatedWeekday = formatConsolidatedWeekdays(weekdays)
        
        // Merge week patterns - if any schedule is active for a week, the consolidated one should be too
        var mergedWeek1 = "0", mergedWeek2 = "0", mergedWeek3 = "0", mergedWeek4 = "0", mergedWeek5 = "0"
        
        for scheduleWithSide in schedules {
            let schedule = scheduleWithSide.schedule
            if schedule.week1 == "1" { mergedWeek1 = "1" }
            if schedule.week2 == "1" { mergedWeek2 = "1" }
            if schedule.week3 == "1" { mergedWeek3 = "1" }
            if schedule.week4 == "1" { mergedWeek4 = "1" }
            if schedule.week5 == "1" { mergedWeek5 = "1" }
        }
        
        // Create consolidated schedule using the first schedule as template
        let consolidatedSweepSchedule = SweepSchedule(
            cnn: firstSchedule.schedule.cnn,
            corridor: firstSchedule.schedule.corridor,
            limits: firstSchedule.schedule.limits,
            blockside: firstSchedule.schedule.blockside,
            fullname: consolidatedWeekday, // Use consolidated weekdays as fullname
            weekday: consolidatedWeekday,  // Use consolidated weekdays
            fromhour: firstSchedule.schedule.fromhour,
            tohour: firstSchedule.schedule.tohour,
            week1: mergedWeek1,
            week2: mergedWeek2,
            week3: mergedWeek3,
            week4: mergedWeek4,
            week5: mergedWeek5,
            holidays: firstSchedule.schedule.holidays,
            line: firstSchedule.schedule.line
        )
        
        return SweepScheduleWithSide(
            schedule: consolidatedSweepSchedule,
            offsetCoordinate: firstSchedule.offsetCoordinate,
            side: firstSchedule.side,
            distance: firstSchedule.distance,
            individualSchedules: schedules.map { $0.schedule } // Store all individual schedules
        )
    }
    
    private func formatConsolidatedWeekdays(_ weekdays: [String]) -> String {
        // If all 7 days, return "Daily"
        if weekdays.count == 7 {
            return "Daily"
        }
        
        // Convert to short names
        let shortNames = weekdays.compactMap { longName -> String? in
            switch longName {
            case "Monday": return "Mon"
            case "Tuesday": return "Tue"
            case "Wednesday": return "Wed"
            case "Thursday": return "Thu"
            case "Friday": return "Fri"
            case "Saturday": return "Sat"
            case "Sunday": return "Sun"
            default: return nil
            }
        }
        
        // Check for common patterns to make them more readable
        if shortNames == ["Mon", "Tue", "Wed", "Thu", "Fri"] {
            return "Weekdays"
        } else if shortNames == ["Sat", "Sun"] {
            return "Weekends"
        } else if shortNames == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] {
            return "Mon-Sat"
        } else if shortNames == ["Tue", "Wed", "Thu", "Fri", "Sat"] {
            return "Tue-Sat"
        } else if shortNames == ["Mon", "Tue", "Wed", "Thu"] {
            return "Mon-Thu"
        } else if shortNames == ["Tue", "Wed", "Thu", "Fri"] {
            return "Tue-Fri"
        } else {
            // For other patterns, just join with commas
            return shortNames.joined(separator: ", ")
        }
    }
    
    func getSchedulesInArea(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<[SweepSchedule], ParkingError>) -> Void) {
        guard isLoaded else {
            completion(.failure(.noData))
            return
        }
        
        let candidates = spatialGrid.getSchedulesNear(coordinate, radius: 10) // Even larger radius for better coverage
        let apiSchedules = candidates.map { convertToAPIFormat($0) }
        
        completion(.success(apiSchedules))
    }
    
    // MARK: - Helper Methods
    private func findClosestSchedule(from point: CLLocationCoordinate2D, schedules: [LocalSweepSchedule]) -> LocalSweepSchedule? {
        // Step 1: Find the street segment the user is closest to
        guard let closestSegmentInfo = findClosestStreetSegment(from: point, schedules: schedules) else {
            return nil
        }
        
        // Step 2: Determine which side of the street the user is on
        let userSide = determineStreetSide(point: point, segment: closestSegmentInfo.segment)
        
        // Step 3: Filter schedules to only those that match the user's side and street segment
        let sideMatchingSchedules = schedules.filter { schedule in
            // Must be same street segment (using corridor + limits as identifier)
            let sameStreet = schedule.corridor == closestSegmentInfo.schedule.corridor && 
                           schedule.limits == closestSegmentInfo.schedule.limits
            
            // Must match the user's side of the street
            let sameSide = doesScheduleMatchSide(schedule: schedule, userSide: userSide, segment: closestSegmentInfo.segment)
            
            return sameStreet && sameSide
        }
        
        print("🎯 Found \(sideMatchingSchedules.count) schedules matching user's side (\(userSide)) on \(closestSegmentInfo.schedule.corridor)")
        
        // Step 4: Find the schedule with the next soonest valid occurrence
        let nextSchedule = findNextUpcomingSchedule(from: sideMatchingSchedules)
        
        if let schedule = nextSchedule {
            print("🎯 Selected next upcoming schedule: \(schedule.corridor) (\(schedule.blockSide)) on \(schedule.weekday) at \(schedule.startTime)")
        }
        
        return nextSchedule
    }
    
    private func findClosestStreetSegment(from point: CLLocationCoordinate2D, schedules: [LocalSweepSchedule]) -> (schedule: LocalSweepSchedule, segment: LineSegment, distance: Double)? {
        var closestInfo: (schedule: LocalSweepSchedule, segment: LineSegment, distance: Double)?
        var minDistance = Double.infinity
        
        for schedule in schedules {
            // Check distance to each line segment for this schedule
            for i in 0..<(schedule.lineCoordinates.count - 1) {
                let segment = LineSegment(
                    start: CLLocationCoordinate2D(latitude: schedule.lineCoordinates[i][1], longitude: schedule.lineCoordinates[i][0]),
                    end: CLLocationCoordinate2D(latitude: schedule.lineCoordinates[i+1][1], longitude: schedule.lineCoordinates[i+1][0])
                )
                
                let (_, distance) = segment.closestPoint(to: point)
                let distanceInFeet = distance * 3.28084
                
                if distanceInFeet <= maxDistance && distance < minDistance {
                    minDistance = distance
                    closestInfo = (schedule: schedule, segment: segment, distance: distance)
                }
            }
        }
        
        return closestInfo
    }
    
    private func determineStreetSide(point: CLLocationCoordinate2D, segment: LineSegment) -> String {
        // Calculate which side of the street segment the point is on
        let streetVector = (
            longitude: segment.end.longitude - segment.start.longitude,
            latitude: segment.end.latitude - segment.start.latitude
        )
        
        let pointVector = (
            longitude: point.longitude - segment.start.longitude,
            latitude: point.latitude - segment.start.latitude
        )
        
        // Cross product to determine which side
        let crossProduct = streetVector.longitude * pointVector.latitude - streetVector.latitude * pointVector.longitude
        
        // Determine cardinal direction based on street orientation
        let streetAngle = atan2(streetVector.latitude, streetVector.longitude)
        let streetAngleDegrees = streetAngle * 180 / .pi
        
        // Normalize angle to 0-360
        let normalizedAngle = streetAngleDegrees < 0 ? streetAngleDegrees + 360 : streetAngleDegrees
        
        // Determine if street runs more north-south or east-west
        let isNorthSouth = (normalizedAngle > 45 && normalizedAngle <= 135) || (normalizedAngle > 225 && normalizedAngle <= 315)
        
        if isNorthSouth {
            // Street runs north-south, sides are East/West
            return crossProduct > 0 ? "East" : "West"
        } else {
            // Street runs east-west, sides are North/South  
            return crossProduct > 0 ? "North" : "South"
        }
    }
    
    private func doesScheduleMatchSide(schedule: LocalSweepSchedule, userSide: String, segment: LineSegment) -> Bool {
        let blockSide = schedule.blockSide.lowercased()
        let userSideLower = userSide.lowercased()
        
        // Direct matches
        if blockSide.contains(userSideLower) {
            return true
        }
        
        // Handle compound directions (NorthEast, SouthWest, etc.)
        switch userSideLower {
        case "north":
            return blockSide.contains("north")
        case "south":
            return blockSide.contains("south")  
        case "east":
            return blockSide.contains("east")
        case "west":
            return blockSide.contains("west")
        default:
            return false
        }
    }
    
    private func findNextUpcomingSchedule(from schedules: [LocalSweepSchedule]) -> LocalSweepSchedule? {
        let now = Date()
        var nearestSchedule: LocalSweepSchedule?
        var nearestDate: Date?
        
        for schedule in schedules {
            if let nextDate = getNextValidOccurrence(for: schedule, after: now) {
                print("📅 Schedule for \(schedule.weekday): next occurrence at \(nextDate)")
                if nearestDate == nil || nextDate < nearestDate! {
                    nearestDate = nextDate
                    nearestSchedule = schedule
                }
            }
        }
        
        return nearestSchedule
    }
    
    private func getNextValidOccurrence(for schedule: LocalSweepSchedule, after date: Date) -> Date? {
        let calendar = Calendar.current
        
        // Get the target weekday (1 = Sunday, 2 = Monday, etc.)
        let targetWeekday = getWeekdayNumber(from: schedule.weekday)
        guard targetWeekday != -1 else { 
            print("⚠️ Unknown weekday: \(schedule.weekday)")
            return nil 
        }
        
        // Check if any weeks are valid for this schedule
        let hasValidWeeks = schedule.week1 == 1 || schedule.week2 == 1 || schedule.week3 == 1 || schedule.week4 == 1 || schedule.week5 == 1
        guard hasValidWeeks else {
            print("⚠️ No valid weeks found for schedule")
            return nil
        }
        
        // Check next 8 weeks to find a valid occurrence
        for weeksAhead in 0...8 {
            let checkDate = calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: date)!
            
            // Find the next occurrence of the target weekday
            if let nextWeekdayDate = getNextOccurrence(of: targetWeekday, after: weeksAhead == 0 ? date : checkDate, calendar: calendar) {
                let weekOfMonth = getWeekOfMonth(for: nextWeekdayDate)
                
                // Check if this week is valid for the schedule
                if isWeekValid(weekOfMonth, for: schedule) {
                    // Check if the time hasn't passed today
                    if calendar.isDate(nextWeekdayDate, inSameDayAs: date) {
                        // If it's today, check if the time has passed
                        if let scheduleTime = calendar.date(bySettingHour: schedule.fromHour, minute: 0, second: 0, of: nextWeekdayDate) {
                            if scheduleTime > date {
                                return scheduleTime
                            }
                        }
                    } else if nextWeekdayDate > date {
                        // If it's a future date, return the schedule time
                        return calendar.date(bySettingHour: schedule.fromHour, minute: 0, second: 0, of: nextWeekdayDate)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func getWeekdayNumber(from weekdayString: String) -> Int {
        let lowercased = weekdayString.lowercased()
        switch lowercased {
        case "sunday": return 1
        case "monday": return 2
        case "tuesday": return 3
        case "wednesday": return 4
        case "thursday": return 5
        case "friday": return 6
        case "saturday": return 7
        default: return -1
        }
    }
    
    private func getWeekOfMonth(for date: Date) -> Int {
        let calendar = Calendar.current
        let weekOfMonth = calendar.component(.weekOfMonth, from: date)
        return weekOfMonth
    }
    
    private func getNextOccurrence(of weekday: Int, after date: Date, calendar: Calendar) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: date)
        
        if currentWeekday == weekday {
            // Today is the target day, return today
            return calendar.startOfDay(for: date)
        } else {
            // Calculate days until target weekday
            let daysUntilTarget = (weekday - currentWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: daysUntilTarget, to: date)
        }
    }
    
    private func isWeekValid(_ weekOfMonth: Int, for schedule: LocalSweepSchedule) -> Bool {
        switch weekOfMonth {
        case 1: return schedule.week1 == 1
        case 2: return schedule.week2 == 1
        case 3: return schedule.week3 == 1
        case 4: return schedule.week4 == 1
        case 5: return schedule.week5 == 1
        default: return false
        }
    }
    
    private func findSchedulesWithSides(from point: CLLocationCoordinate2D, schedules: [LocalSweepSchedule]) -> [SweepScheduleWithSide] {
        var schedulesWithSides: [SweepScheduleWithSide] = []
        
        for schedule in schedules {
            var closestDistance = Double.infinity
            var closestSegment: LineSegment?
            
            // Find the closest line segment for this schedule
            for i in 0..<(schedule.lineCoordinates.count - 1) {
                let segment = LineSegment(
                    start: CLLocationCoordinate2D(latitude: schedule.lineCoordinates[i][1], longitude: schedule.lineCoordinates[i][0]),
                    end: CLLocationCoordinate2D(latitude: schedule.lineCoordinates[i+1][1], longitude: schedule.lineCoordinates[i+1][0])
                )
                
                let (_, distance) = segment.closestPoint(to: point)
                if distance < closestDistance {
                    closestDistance = distance
                    closestSegment = segment
                }
            }
            
            guard let segment = closestSegment else { continue }
            
            let distanceInFeet = closestDistance * 3.28084
            if distanceInFeet <= maxDistance {
                // Calculate the offset coordinate to represent the side of the street
                let offsetCoordinate = calculateSideOffset(point: point, segment: segment, blockSide: schedule.blockSide)
                
                let scheduleWithSide = SweepScheduleWithSide(
                    schedule: convertToAPIFormat(schedule),
                    offsetCoordinate: offsetCoordinate,
                    side: schedule.blockSide,
                    distance: distanceInFeet,
                    individualSchedules: nil // Non-consolidated individual schedule
                )
                
                schedulesWithSides.append(scheduleWithSide)
            }
        }
        
        // Sort by distance, closest first
        return schedulesWithSides.sorted { $0.distance < $1.distance }
    }
    
    private func calculateSideOffset(point: CLLocationCoordinate2D, segment: LineSegment, blockSide: String) -> CLLocationCoordinate2D {
        // Calculate the direction vector of the street segment
        let streetVector = (
            longitude: segment.end.longitude - segment.start.longitude,
            latitude: segment.end.latitude - segment.start.latitude
        )
        
        // Calculate perpendicular vector (rotate 90 degrees)
        let perpVector = (
            longitude: -streetVector.latitude,
            latitude: streetVector.longitude
        )
        
        // Normalize the perpendicular vector
        let perpLength = sqrt(perpVector.longitude * perpVector.longitude + perpVector.latitude * perpVector.latitude)
        guard perpLength > 0 else { return point }
        
        let normalizedPerp = (
            longitude: perpVector.longitude / perpLength,
            latitude: perpVector.latitude / perpLength
        )
        
        // Determine offset direction based on block side
        let offsetDirection = getOffsetDirection(blockSide: blockSide, streetVector: streetVector)
        
        // Apply offset (about 15 feet / 5 meters converted to coordinate degrees)
        let offsetDistance = 0.00004 // roughly 15 feet in coordinate degrees
        
        return CLLocationCoordinate2D(
            latitude: point.latitude + (normalizedPerp.latitude * offsetDistance * offsetDirection),
            longitude: point.longitude + (normalizedPerp.longitude * offsetDistance * offsetDirection)
        )
    }
    
    private func getOffsetDirection(blockSide: String, streetVector: (longitude: Double, latitude: Double)) -> Double {
        // Determine which side of the street based on block side description
        let side = blockSide.lowercased()
        
        // For north/south streets, east side gets positive offset, west side gets negative
        // For east/west streets, north side gets positive offset, south side gets negative
        
        if side.contains("north") || side.contains("northeast") || side.contains("northwest") {
            return 1.0
        } else if side.contains("south") || side.contains("southeast") || side.contains("southwest") {
            return -1.0
        } else if side.contains("east") {
            return streetVector.latitude > 0 ? 1.0 : -1.0 // Adjust based on street direction
        } else if side.contains("west") {
            return streetVector.latitude > 0 ? -1.0 : 1.0 // Adjust based on street direction
        } else {
            // Default: use the closest point with slight offset
            return 1.0
        }
    }
    
    private func convertToAPIFormat(_ local: LocalSweepSchedule) -> SweepSchedule {
        let lineGeometry = LineGeometry(
            type: "LineString",
            coordinates: local.lineCoordinates
        )
        
        return SweepSchedule(
            cnn: local.cnn,
            corridor: local.corridor,
            limits: local.limits,
            blockside: local.blockSide,
            fullname: local.fullName,
            weekday: local.weekday,
            fromhour: String(local.fromHour),
            tohour: String(local.toHour),
            week1: String(local.week1),
            week2: String(local.week2),
            week3: String(local.week3),
            week4: String(local.week4),
            week5: String(local.week5),
            holidays: String(local.holidays),
            line: lineGeometry
        )
    }
    
    func getParkingStatusMessage(for coordinate: CLLocationCoordinate2D, completion: @escaping (String) -> Void) {
        getClosestSchedule(for: coordinate) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let schedule):
                    if let schedule = schedule {
                        completion("Street sweeping: \(schedule.sweepDay) from \(schedule.startTime) - \(schedule.endTime) on \(schedule.streetName)")
                    } else {
                        completion("You're all set! No street sweeping restrictions in this area.")
                    }
                case .failure(let error):
                    completion(error.userFriendlyMessage)
                }
            }
        }
    }
    
    // Convert persisted schedule back to SweepSchedule for processing
    func convertToSweepSchedule(from persisted: PersistedSweepSchedule) -> SweepSchedule {
        return SweepSchedule(
            cnn: nil,
            corridor: persisted.streetName,
            limits: nil,
            blockside: persisted.blockSide,
            fullname: nil,
            weekday: persisted.weekday,
            fromhour: extractHourFromTime(persisted.startTime),
            tohour: extractHourFromTime(persisted.endTime),
            week1: persisted.week1,
            week2: persisted.week2,
            week3: persisted.week3,
            week4: persisted.week4,
            week5: persisted.week5,
            holidays: nil,
            line: nil
        )
    }
    
    private func extractHourFromTime(_ timeString: String) -> String? {
        // Convert "8:00 AM" back to "8"
        let components = timeString.components(separatedBy: ":")
        guard let firstComponent = components.first else { return nil }
        
        if timeString.contains("PM") && firstComponent != "12" {
            if let hour = Int(firstComponent) {
                return String(hour + 12)
            }
        } else if timeString.contains("AM") && firstComponent == "12" {
            return "0"
        }
        
        return firstComponent
    }
}



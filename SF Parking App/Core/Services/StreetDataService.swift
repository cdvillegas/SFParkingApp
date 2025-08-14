//
//  StreetDataService.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import CoreLocation

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
    let avgSweeperTime: Double?
    let medianSweeperTime: Double?
    
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
    let blockSweepID: Int
    let lineCoordinates: [[Double]] // Parsed from Line column
    
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

// New structure for aggregated schedule data
struct AggregatedSweepSchedule {
    let cleanId: String
    let cnn: String
    let corridor: String
    let limits: String
    let cnnRightLeft: String
    let blockSide: String
    let mondayHours: [Int]
    let tuesdayHours: [Int]
    let wednesdayHours: [Int]
    let thursdayHours: [Int]
    let fridayHours: [Int]
    let saturdayHours: [Int]
    let sundayHours: [Int]
    let scheduleSummary: String
    let totalWeeklyHours: Int
    let hasMultipleWindows: Bool
    let week1: Int
    let week2: Int
    let week3: Int
    let week4: Int
    let week5: Int
    let citationCount: Int
    let avgCitationTime: Double?
    let medianCitationTime: Double?
    let lineCoordinates: [[Double]] // Parsed from GeoJSON
    
    // Helper to get hours for a specific day
    func hours(for dayOfWeek: Int) -> [Int] {
        switch dayOfWeek {
        case 1: return sundayHours
        case 2: return mondayHours
        case 3: return tuesdayHours
        case 4: return wednesdayHours
        case 5: return thursdayHours
        case 6: return fridayHours
        case 7: return saturdayHours
        default: return []
        }
    }
    
    // Convert to LocalSweepSchedule for a specific day (for compatibility)
    func toLocalSchedule(for weekday: String, hours: [Int]) -> LocalSweepSchedule? {
        guard !hours.isEmpty else { return nil }
        
        let fromHour = hours.min() ?? 0
        let toHour = (hours.max() ?? 0) + 1 // Add 1 because toHour is exclusive
        
        return LocalSweepSchedule(
            cnn: cnn,
            corridor: corridor,
            limits: limits,
            blockSide: blockSide,
            fullName: scheduleSummary,
            weekday: weekday,
            fromHour: fromHour,
            toHour: toHour,
            week1: week1,
            week2: week2,
            week3: week3,
            week4: week4,
            week5: week5,
            holidays: 0,
            blockSweepID: cleanId.hashValue,
            lineCoordinates: lineCoordinates
        )
    }
}

// MARK: - Spatial Grid for Fast Lookups
class SpatialGrid {
    private let cellSize: Double = 0.001 // roughly 100 meters in SF
    private var grid: [String: [LocalSweepSchedule]] = [:]
    private var aggregatedGrid: [String: [AggregatedSweepSchedule]] = [:]
    
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
            if !grid[key]!.contains(where: { $0.blockSweepID == schedule.blockSweepID }) {
                grid[key]!.append(schedule)
            }
        }
    }
    
    func addAggregatedSchedule(_ schedule: AggregatedSweepSchedule) {
        // Add schedule to all grid cells it intersects
        for coord in schedule.lineCoordinates {
            let location = CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
            let key = getCellKey(for: location)
            
            if aggregatedGrid[key] == nil {
                aggregatedGrid[key] = []
            }
            
            // Avoid duplicates
            if !aggregatedGrid[key]!.contains(where: { $0.cleanId == schedule.cleanId }) {
                aggregatedGrid[key]!.append(schedule)
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
        let uniqueSchedules = Array(Set(schedules.map { $0.blockSweepID }))
            .compactMap { id in schedules.first { $0.blockSweepID == id } }
        
        return uniqueSchedules
    }
    
    func getAggregatedSchedulesNear(_ coordinate: CLLocationCoordinate2D, radius: Int = 2) -> [AggregatedSweepSchedule] {
        var schedules: [AggregatedSweepSchedule] = []
        let centerX = Int(coordinate.longitude / cellSize)
        let centerY = Int(coordinate.latitude / cellSize)
        
        
        // Check surrounding cells
        for dx in -radius...radius {
            for dy in -radius...radius {
                let key = "\(centerX + dx),\(centerY + dy)"
                if let cellSchedules = aggregatedGrid[key] {
                    schedules.append(contentsOf: cellSchedules)
                }
            }
        }
        
        // Remove duplicates
        var seen = Set<String>()
        let uniqueSchedules = schedules.filter { seen.insert($0.cleanId).inserted }
        
        return uniqueSchedules
    }
}

// MARK: - Main Service
final class StreetDataService {
    static let shared = StreetDataService()
    
    private var schedules: [LocalSweepSchedule] = []
    private var aggregatedSchedules: [AggregatedSweepSchedule] = []
    private var spatialGrid = SpatialGrid()
    private let maxDistance = 50.0 // 50 feet
    private var isLoaded = false
    var useNewDataset = true // Flag to control which dataset to use (made public for StreetDataManager)
    
    private init() {
        // Check if we should force old dataset (for testing)
        if UserDefaults.standard.bool(forKey: "ForceOldDataset") {
            useNewDataset = false
            print("📊 Forcing old dataset based on UserDefaults")
        }
        
        if useNewDataset {
            loadAggregatedSchedulesFromCSV()
        } else {
            // Test WKT parsing with known good data
            if let testCoords = parseLineCoordinates("\"LINESTRING (-122.416291701103 37.777493843394, -122.416317106137 37.777410028361)\"") {
                print("🧪 WKT parsing test successful: \(testCoords.count) coordinates")
            } else {
                print("❌ WKT parsing test failed")
            }
            
            loadSchedulesFromCSV()
        }
    }
    
    // MARK: - CSV Loading
    private func loadAggregatedSchedulesFromCSV() {
        print("Loading aggregated street sweeping schedules from new CSV...")
        
        guard let csvPath = Bundle.main.path(forResource: "app_ready_aggregated_20250729_221947", ofType: "csv") else {
            print("❌ Aggregated CSV file not found in bundle")
            // Fall back to old dataset
            useNewDataset = false
            loadSchedulesFromCSV()
            return
        }
        
        guard let csvContent = try? String(contentsOfFile: csvPath, encoding: .utf8) else {
            print("❌ Failed to read aggregated CSV file")
            // Fall back to old dataset
            useNewDataset = false
            loadSchedulesFromCSV()
            return
        }
        
        let lines = csvContent.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            print("❌ Aggregated CSV file appears empty")
            return
        }
        
        // Skip header row
        let dataLines = Array(lines.dropFirst())
        var loadedCount = 0
        
        for (index, line) in dataLines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            
            if let schedule = parseAggregatedCSVLine(line, lineIndex: index) {
                aggregatedSchedules.append(schedule)
                spatialGrid.addAggregatedSchedule(schedule)
                loadedCount += 1
            } else if index < 10 {
                print("❌ Failed to parse aggregated line \(index): \(line.prefix(100))")
            }
        }
        
        isLoaded = true
        print("✅ Loaded \(loadedCount) aggregated street sweeping schedules from \(dataLines.count) total lines")
        
    }
    
    private func loadSchedulesFromCSV() {
        print("Loading street sweeping schedules from CSV...")
        
        guard let csvPath = Bundle.main.path(forResource: "Street_Sweeping_Schedule_20250709", ofType: "csv") else {
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
        
        guard columns.count >= 17 else {
            return nil
        }
        
        // Parse the Line column (WKT LINESTRING format)
        guard let lineCoordinates = parseLineCoordinates(columns[16]) else {
            if lineIndex < 5 {
                print("❌ Failed to parse coordinates for line \(lineIndex): \(columns[16].prefix(100))")
            }
            return nil
        }
        
        if lineIndex < 5 {
            print("✅ Parsed \(lineCoordinates.count) coordinates for \(columns[1])")
        }
        
        return LocalSweepSchedule(
            cnn: columns[0],
            corridor: columns[1],
            limits: columns[2],
            blockSide: columns[4],
            fullName: columns[5],
            weekday: columns[6],
            fromHour: Int(columns[7]) ?? 0,
            toHour: Int(columns[8]) ?? 0,
            week1: Int(columns[9]) ?? 0,
            week2: Int(columns[10]) ?? 0,
            week3: Int(columns[11]) ?? 0,
            week4: Int(columns[12]) ?? 0,
            week5: Int(columns[13]) ?? 0,
            holidays: Int(columns[14]) ?? 0,
            blockSweepID: Int(columns[15]) ?? 0,
            lineCoordinates: lineCoordinates
        )
    }
    
    // Enhanced CSV parser that handles quoted fields and nested structures
    private func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var inCurlyBraces = false
        var braceCount = 0
        var i = row.startIndex
        
        while i < row.endIndex {
            let char = row[i]
            
            if char == "\"" && !inCurlyBraces {
                if inQuotes && i < row.index(before: row.endIndex) && row[row.index(after: i)] == "\"" {
                    // Escaped quote
                    currentField.append("\"")
                    i = row.index(after: i)
                } else {
                    inQuotes.toggle()
                }
            } else if char == "{" && !inQuotes {
                inCurlyBraces = true
                braceCount = 1
                currentField.append(char)
            } else if char == "}" && inCurlyBraces && !inQuotes {
                braceCount -= 1
                currentField.append(char)
                if braceCount == 0 {
                    inCurlyBraces = false
                }
            } else if char == "{" && inCurlyBraces && !inQuotes {
                braceCount += 1
                currentField.append(char)
            } else if char == "," && !inQuotes && !inCurlyBraces {
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
    
    private func parseAggregatedCSVLine(_ line: String, lineIndex: Int) -> AggregatedSweepSchedule? {
        let columns = parseCSVRow(line)
        
        // Expected columns based on the new format
        guard columns.count >= 25 else {
            if lineIndex < 5 {
                print("❌ Not enough columns for line \(lineIndex): got \(columns.count), expected 25")
                print("❌ Columns: \(columns)")
            }
            return nil
        }
        
        // Parse hour arrays
        let parseHours: (String) -> [Int] = { hourString in
            guard !hourString.isEmpty else { return [] }
            return hourString.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        
        // Parse GeoJSON line
        guard let lineCoordinates = parseGeoJSONLine(columns[24]) else {
            if lineIndex < 5 {
                print("❌ Failed to parse GeoJSON for line \(lineIndex): \(columns[24])")
            }
            return nil
        }
        
        
        return AggregatedSweepSchedule(
            cleanId: columns[0],
            cnn: columns[1],
            corridor: columns[2],
            limits: columns[3],
            cnnRightLeft: columns[4],
            blockSide: columns[5],
            mondayHours: parseHours(columns[6]),
            tuesdayHours: parseHours(columns[7]),
            wednesdayHours: parseHours(columns[8]),
            thursdayHours: parseHours(columns[9]),
            fridayHours: parseHours(columns[10]),
            saturdayHours: parseHours(columns[11]),
            sundayHours: parseHours(columns[12]),
            scheduleSummary: columns[13],
            totalWeeklyHours: Int(columns[14]) ?? 0,
            hasMultipleWindows: columns[15].lowercased() == "true",
            week1: Int(columns[16]) ?? 0,
            week2: Int(columns[17]) ?? 0,
            week3: Int(columns[18]) ?? 0,
            week4: Int(columns[19]) ?? 0,
            week5: Int(columns[20]) ?? 0,
            citationCount: Int(columns[21]) ?? 0,
            avgCitationTime: columns[22].isEmpty ? nil : Double(columns[22]),
            medianCitationTime: columns[23].isEmpty ? nil : Double(columns[23]),
            lineCoordinates: lineCoordinates
        )
    }
    
    // Parse GeoJSON LineString format
    private func parseGeoJSONLine(_ geoJSON: String) -> [[Double]]? {
        // Remove surrounding quotes if present
        let trimmed = geoJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") 
            ? String(trimmed.dropFirst().dropLast()) 
            : trimmed
        
        // Parse the GeoJSON structure
        // Format: {'type': 'LineString', 'coordinates': [[-122.399148598539, 37.791016649255], [-122.398589511053, 37.790571225457]]}
        
        // Find coordinates array - try both single and double quotes
        var coordStart: String.Index?
        if let start = unquoted.range(of: "'coordinates': [")?.upperBound {
            coordStart = start
        } else if let start = unquoted.range(of: "\"coordinates\": [")?.upperBound {
            coordStart = start
        } else if let start = unquoted.range(of: "coordinates\": [")?.upperBound {
            coordStart = start
        }
        
        guard let start = coordStart else {
            print("❌ Could not find coordinates in GeoJSON: \(unquoted.prefix(100))")
            return nil
        }
        
        let coordSubstring = String(unquoted[start...])
        
        // Find the matching closing bracket for the coordinates array
        // We need to find ]] (end of coordinate pairs array, then end of coordinates array)
        var bracketCount = 1 // We already passed the opening [
        var coordEnd: String.Index?
        
        for (index, char) in coordSubstring.enumerated() {
            if char == "[" {
                bracketCount += 1
            } else if char == "]" {
                bracketCount -= 1
                if bracketCount == 0 {
                    coordEnd = coordSubstring.index(coordSubstring.startIndex, offsetBy: index)
                    break
                }
            }
        }
        
        guard let end = coordEnd else {
            print("❌ Could not find end of coordinates array")
            return nil
        }
        
        let coordinatesString = String(coordSubstring[..<end])
        
        // Parse coordinate pairs
        var coordinates: [[Double]] = []
        
        // Split by "], [" to get individual coordinate pairs
        let pairs = coordinatesString.components(separatedBy: "], [")
        
        for pair in pairs {
            let cleanPair = pair.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            let components = cleanPair.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            if components.count == 2,
               let lon = Double(components[0]),
               let lat = Double(components[1]) {
                coordinates.append([lon, lat])
            }
        }
        
        return coordinates.isEmpty ? nil : coordinates
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
    
    // New method to get the closest aggregated schedule (for next sweep calculation)
    func getClosestAggregatedSchedule(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<AggregatedSweepSchedule?, ParkingError>) -> Void) {
        guard isLoaded else {
            print("❌ StreetDataService not loaded yet")
            completion(.failure(.noData))
            return
        }
        
        guard useNewDataset else {
            completion(.success(nil))
            return
        }
        
        // Get candidates from spatial grid
        let candidates = spatialGrid.getAggregatedSchedulesNear(coordinate)
        
        // Find the closest one
        let closestSchedule = findClosestAggregatedSchedule(from: coordinate, schedules: candidates)
        
        completion(.success(closestSchedule))
    }
    
    // MARK: - Public API (matches your existing interface)
    // New method for Smart Park geometric side detection
    func getClosestScheduleWithGeometry(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<([AggregatedSweepSchedule], SweepSchedule)?, ParkingError>) -> Void) {
        guard isLoaded else {
            completion(.failure(.noData))
            return
        }
        
        guard useNewDataset else {
            completion(.success(nil))
            return
        }
        
        // Get candidates from spatial grid
        let candidates = spatialGrid.getAggregatedSchedulesNear(coordinate)
        
        // Find closest schedule and return both raw data and converted schedule
        if let closest = findClosestAggregatedSchedule(from: coordinate, schedules: candidates),
           let convertedSchedule = convertAggregatedToAPIFormat(closest) {
            
            // Get all schedules for the same street for side comparison
            let streetSchedules = candidates.filter { $0.corridor == closest.corridor }
            
            print("📐 [StreetDataService] Found \(streetSchedules.count) schedules for \(closest.corridor) with geometry data")
            
            completion(.success((streetSchedules, convertedSchedule)))
        } else {
            completion(.success(nil))
        }
    }

    func getClosestSchedule(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<SweepSchedule?, ParkingError>) -> Void) {
        guard isLoaded else {
            print("❌ StreetDataService not loaded yet")
            completion(.failure(.noData))
            return
        }
        
        if useNewDataset {
            // Use aggregated schedules
            print("🔍 Total aggregated schedules loaded: \(aggregatedSchedules.count)")
            
            // Get candidates from spatial grid
            let candidates = spatialGrid.getAggregatedSchedulesNear(coordinate)
            print("🔍 Found \(candidates.count) candidate aggregated schedules near \(coordinate)")
            
            // Find the closest one
            let closestSchedule = findClosestAggregatedSchedule(from: coordinate, schedules: candidates)
            
            if let schedule = closestSchedule {
                print("✅ Found closest aggregated schedule: \(schedule.corridor) at distance within 50 feet")
                // Convert to API format - for now, return the first available day's schedule
                if let apiSchedule = convertAggregatedToAPIFormat(schedule) {
                    completion(.success(apiSchedule))
                } else {
                    completion(.success(nil))
                }
            } else {
                print("❌ No aggregated schedules found within 50 feet of \(coordinate)")
                completion(.success(nil))
            }
        } else {
            // Use old format
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
    }
    
    // New method to get nearby schedules for side-of-street selection
    func getNearbySchedulesForSelection(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<[SweepScheduleWithSide], ParkingError>) -> Void) {
        guard isLoaded else {
            completion(.failure(.noData))
            return
        }
        
        if useNewDataset {
            // Get candidates from spatial grid
            let candidates = spatialGrid.getAggregatedSchedulesNear(coordinate)
            
            // Find all schedules within range and calculate their side positions
            let schedulesWithSides = findAggregatedSchedulesWithSides(from: coordinate, schedules: candidates)
            
            print("🔍 Found \(schedulesWithSides.count) aggregated schedules with side information for selection")
            
            completion(.success(schedulesWithSides))
        } else {
            // Get candidates from spatial grid
            let candidates = spatialGrid.getSchedulesNear(coordinate)
            
            // Find all schedules within range and calculate their side positions
            let schedulesWithSides = findSchedulesWithSides(from: coordinate, schedules: candidates)
            
            print("🔍 Found \(schedulesWithSides.count) schedules with side information for selection")
            
            completion(.success(schedulesWithSides))
        }
    }
    
    func getSchedulesInArea(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<[SweepSchedule], ParkingError>) -> Void) {
        guard isLoaded else {
            completion(.failure(.noData))
            return
        }
        
        if useNewDataset {
            let candidates = spatialGrid.getAggregatedSchedulesNear(coordinate, radius: 10) // Even larger radius for better coverage
            let apiSchedules = candidates.compactMap { convertAggregatedToAPIFormat($0) }
            completion(.success(apiSchedules))
        } else {
            let candidates = spatialGrid.getSchedulesNear(coordinate, radius: 10) // Even larger radius for better coverage
            let apiSchedules = candidates.map { convertToAPIFormat($0) }
            completion(.success(apiSchedules))
        }
    }
    
    // MARK: - Helper Methods
    private func findClosestAggregatedSchedule(from point: CLLocationCoordinate2D, schedules: [AggregatedSweepSchedule]) -> AggregatedSweepSchedule? {
        var closestSchedule: AggregatedSweepSchedule?
        var minDistance = Double.infinity
        
        print("🔍 Finding closest from \(schedules.count) aggregated candidates")
        print("🔍 Point: \(point)")
        print("🔍 Max distance: \(maxDistance) feet")
        
        for (index, schedule) in schedules.enumerated() {
            var scheduleMinDistance = Double.infinity
            
            // Check distance to each line segment
            for i in 0..<(schedule.lineCoordinates.count - 1) {
                let startCoord = schedule.lineCoordinates[i]
                let endCoord = schedule.lineCoordinates[i+1]
                
                // Validate coordinates
                guard startCoord.count >= 2 && endCoord.count >= 2,
                      startCoord[0].isFinite && startCoord[1].isFinite,
                      endCoord[0].isFinite && endCoord[1].isFinite else {
                    if index < 5 {
                        print("🔍 Invalid coordinates for schedule \(index): \(startCoord) -> \(endCoord)")
                    }
                    continue
                }
                
                let segment = LineSegment(
                    start: CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0]),
                    end: CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0])
                )
                
                let (_, distance) = segment.closestPoint(to: point)
                
                // Validate distance
                guard distance.isFinite else {
                    if index < 5 {
                        print("🔍 Invalid distance for schedule \(index): \(distance)")
                    }
                    continue
                }
                
                scheduleMinDistance = min(scheduleMinDistance, distance)
            }
            
            let distanceInFeet = scheduleMinDistance * 3.28084
            
            if index < 5 { // Log first 5 for debugging
                if distanceInFeet.isFinite {
                    print("🔍 Schedule \(index): \(schedule.corridor) - Distance: \(Int(distanceInFeet)) feet")
                } else {
                    print("🔍 Schedule \(index): \(schedule.corridor) - Distance: INVALID")
                }
            }
            
            if distanceInFeet.isFinite && distanceInFeet <= maxDistance && scheduleMinDistance < minDistance {
                minDistance = scheduleMinDistance
                closestSchedule = schedule
                print("🔍 New closest: \(schedule.corridor) at \(Int(distanceInFeet)) feet")
            }
        }
        
        if let closest = closestSchedule {
            print("🔍 Final closest: \(closest.corridor) at \(Int(minDistance * 3.28084)) feet")
        } else {
            print("🔍 No schedules within \(maxDistance) feet")
        }
        
        return closestSchedule
    }
    
    private func convertAggregatedToAPIFormat(_ aggregated: AggregatedSweepSchedule) -> SweepSchedule? {
        // Find the first day with hours and convert
        let days = [
            ("Monday", aggregated.mondayHours),
            ("Tuesday", aggregated.tuesdayHours),
            ("Wednesday", aggregated.wednesdayHours),
            ("Thursday", aggregated.thursdayHours),
            ("Friday", aggregated.fridayHours),
            ("Saturday", aggregated.saturdayHours),
            ("Sunday", aggregated.sundayHours)
        ]
        
        for (dayName, hours) in days {
            if !hours.isEmpty {
                let fromHour = hours.min() ?? 0
                let toHour = (hours.max() ?? 0) + 1
                
                let lineGeometry = LineGeometry(
                    type: "LineString",
                    coordinates: aggregated.lineCoordinates
                )
                
                return SweepSchedule(
                    cnn: aggregated.cnn,
                    corridor: aggregated.corridor,
                    limits: aggregated.limits,
                    blockside: aggregated.blockSide,
                    fullname: aggregated.scheduleSummary,
                    weekday: dayName.prefix(3).description, // Convert to abbreviated form
                    fromhour: String(fromHour),
                    tohour: String(toHour),
                    week1: String(aggregated.week1),
                    week2: String(aggregated.week2),
                    week3: String(aggregated.week3),
                    week4: String(aggregated.week4),
                    week5: String(aggregated.week5),
                    holidays: "0",
                    line: lineGeometry,
                    avgSweeperTime: aggregated.avgCitationTime,
                    medianSweeperTime: aggregated.medianCitationTime
                )
            }
        }
        
        return nil
    }
    
    // New method to get all schedule days for next sweep calculation
    func getAllScheduleDays(from aggregated: AggregatedSweepSchedule) -> [SweepSchedule] {
        var schedules: [SweepSchedule] = []
        let days = [
            ("Mon", "Monday", aggregated.mondayHours),
            ("Tue", "Tuesday", aggregated.tuesdayHours),
            ("Wed", "Wednesday", aggregated.wednesdayHours),
            ("Thu", "Thursday", aggregated.thursdayHours),
            ("Fri", "Friday", aggregated.fridayHours),
            ("Sat", "Saturday", aggregated.saturdayHours),
            ("Sun", "Sunday", aggregated.sundayHours)
        ]
        
        let lineGeometry = LineGeometry(
            type: "LineString",
            coordinates: aggregated.lineCoordinates
        )
        
        for (abbrev, _, hours) in days {
            if !hours.isEmpty {
                let fromHour = hours.min() ?? 0
                let toHour = (hours.max() ?? 0) + 1
                
                let schedule = SweepSchedule(
                    cnn: aggregated.cnn,
                    corridor: aggregated.corridor,
                    limits: aggregated.limits,
                    blockside: aggregated.blockSide,
                    fullname: aggregated.scheduleSummary,
                    weekday: abbrev,
                    fromhour: String(fromHour),
                    tohour: String(toHour),
                    week1: String(aggregated.week1),
                    week2: String(aggregated.week2),
                    week3: String(aggregated.week3),
                    week4: String(aggregated.week4),
                    week5: String(aggregated.week5),
                    holidays: "0",
                    line: lineGeometry,
                    avgSweeperTime: aggregated.avgCitationTime,
                    medianSweeperTime: aggregated.medianCitationTime
                )
                schedules.append(schedule)
            }
        }
        
        return schedules
    }
    
    private func findClosestSchedule(from point: CLLocationCoordinate2D, schedules: [LocalSweepSchedule]) -> LocalSweepSchedule? {
        var closestSchedule: LocalSweepSchedule?
        var minDistance = Double.infinity
        
        for schedule in schedules {
            var scheduleMinDistance = Double.infinity
            
            // Check distance to each line segment
            for i in 0..<(schedule.lineCoordinates.count - 1) {
                let segment = LineSegment(
                    start: CLLocationCoordinate2D(latitude: schedule.lineCoordinates[i][1], longitude: schedule.lineCoordinates[i][0]),
                    end: CLLocationCoordinate2D(latitude: schedule.lineCoordinates[i+1][1], longitude: schedule.lineCoordinates[i+1][0])
                )
                
                let (_, distance) = segment.closestPoint(to: point)
                scheduleMinDistance = min(scheduleMinDistance, distance)
            }
            
            let distanceInFeet = scheduleMinDistance * 3.28084
            
            if distanceInFeet <= maxDistance && scheduleMinDistance < minDistance {
                minDistance = scheduleMinDistance
                closestSchedule = schedule
            }
        }
        
        return closestSchedule
    }
    
    private func findAggregatedSchedulesWithSides(from point: CLLocationCoordinate2D, schedules: [AggregatedSweepSchedule]) -> [SweepScheduleWithSide] {
        var schedulesWithSides: [SweepScheduleWithSide] = []
        
        print("🔍 Finding aggregated schedules with sides from \(schedules.count) candidates")
        
        for (index, schedule) in schedules.enumerated() {
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
            
            guard let segment = closestSegment else { 
                if index < 5 {
                    print("🔍 Schedule \(index) (\(schedule.corridor)): No valid segment - has \(schedule.lineCoordinates.count) coordinates")
                    if !schedule.lineCoordinates.isEmpty {
                        print("🔍 First coordinate: \(schedule.lineCoordinates.first!)")
                    }
                }
                continue 
            }
            
            let distanceInFeet = closestDistance * 3.28084
            
            if index < 5 { // Log first 5
                print("🔍 Schedule \(index) (\(schedule.corridor)): \(Int(distanceInFeet)) feet")
            }
            
            if distanceInFeet <= maxDistance {
                // Convert to API format
                if let apiSchedule = convertAggregatedToAPIFormat(schedule) {
                    // Calculate the offset coordinate to represent the side of the street
                    let offsetCoordinate = calculateSideOffset(point: point, segment: segment, blockSide: schedule.blockSide)
                    
                    let scheduleWithSide = SweepScheduleWithSide(
                        schedule: apiSchedule,
                        offsetCoordinate: offsetCoordinate,
                        side: schedule.blockSide,
                        distance: distanceInFeet
                    )
                    
                    schedulesWithSides.append(scheduleWithSide)
                    
                    if index < 5 {
                        print("🔍 Added schedule: \(schedule.corridor) (\(schedule.scheduleSummary))")
                    }
                } else {
                    print("🔍 Failed to convert schedule \(index) (\(schedule.corridor)) to API format")
                }
            }
        }
        
        print("🔍 Final result: \(schedulesWithSides.count) schedules with sides")
        
        // Sort by distance, closest first
        return schedulesWithSides.sorted { $0.distance < $1.distance }
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
                    distance: distanceInFeet
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
            line: lineGeometry,
            avgSweeperTime: nil,
            medianSweeperTime: nil
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
            line: nil,
            avgSweeperTime: persisted.avgSweeperTime,
            medianSweeperTime: persisted.medianSweeperTime
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



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

final class StreetDataService {
    static let shared = StreetDataService()
    private let session = URLSession.shared
    private let baseURL = "https://data.sfgov.org/resource/yhqp-riqs.json"
    private let maxDistance = 50.0 // 50 feet maximum distance

    private init() {}

    func getClosestSchedule(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<SweepSchedule?, ParkingError>) -> Void) {
        // Try multiple approaches
        print("Searching for schedules near: \(coordinate.latitude), \(coordinate.longitude)")
        
        // First try the spatial query approach
        getSchedulesWithinRadius(for: coordinate) { [weak self] schedules in
            if let schedules = schedules, !schedules.isEmpty {
                print("Spatial query found \(schedules.count) schedules")
                let closestSchedule = self?.findClosestSchedule(from: coordinate, schedules: schedules)
                if let schedule = closestSchedule {
                    completion(.success(schedule))
                } else {
                    completion(.success(nil)) // No schedules within range, but data was retrieved
                }
                return
            }
            
            print("Spatial query returned no results, trying fallback approach...")
            
            // Fallback: Get a larger sample and filter client-side
            self?.getSchedulesFallback(for: coordinate, completion: completion)
        }
    }
    
    private func getSchedulesWithinRadius(for coordinate: CLLocationCoordinate2D, completion: @escaping ([SweepSchedule]?) -> Void) {
        // More accurate degree calculation for San Francisco latitude
        let latInRadians = coordinate.latitude * .pi / 180
        let feetPerDegreeLat = 364000.0 // roughly constant
        let feetPerDegreeLng = 364000.0 * cos(latInRadians) // varies by latitude
        
        let radiusInFeet = 200.0 // Start with larger radius for testing
        let deltaLat = radiusInFeet / feetPerDegreeLat
        let deltaLng = radiusInFeet / feetPerDegreeLng
        
        let minLat = coordinate.latitude - deltaLat
        let maxLat = coordinate.latitude + deltaLat
        let minLng = coordinate.longitude - deltaLng
        let maxLng = coordinate.longitude + deltaLng
        
        print("Search bounds: lat[\(minLat), \(maxLat)] lng[\(minLng), \(maxLng)]")
        
        // Try different spatial query formats
        let queries = [
            // Standard intersects with polygon
            "intersects(line, 'POLYGON((\(minLng) \(maxLat), \(maxLng) \(maxLat), \(maxLng) \(minLat), \(minLng) \(minLat), \(minLng) \(maxLat)))')",
            
            // Alternative: Use within_circle if supported
            "within_circle(line, \(coordinate.latitude), \(coordinate.longitude), \(radiusInFeet * 0.3048))", // Convert feet to meters
            
            // Simple bounding box on coordinates (if line has point representation)
            "latitude between \(minLat) and \(maxLat) and longitude between \(minLng) and \(maxLng)"
        ]
        
        tryQueriesSequentially(queries: queries, completion: completion)
    }
    
    private func tryQueriesSequentially(queries: [String], completion: @escaping ([SweepSchedule]?) -> Void) {
        guard !queries.isEmpty else {
            completion(nil)
            return
        }
        
        let whereClause = queries[0]
        let remainingQueries = Array(queries.dropFirst())
        
        guard let query = "\(baseURL)?$where=\(whereClause)&$limit=1000"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: query) else {
            print("Failed to create URL for query: \(whereClause)")
            tryQueriesSequentially(queries: remainingQueries, completion: completion)
            return
        }
        
        print("Trying query: \(whereClause)")
        print("Full URL: \(query)")
        
        let request = URLRequest(url: url)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Network error for query '\(whereClause)': \(error)")
                self?.tryQueriesSequentially(queries: remainingQueries, completion: completion)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("No data received for query: \(whereClause)")
                self?.tryQueriesSequentially(queries: remainingQueries, completion: completion)
                return
            }
            
            // Print raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Raw response length: \(responseString.count)")
                if responseString.count < 1000 {
                    print("Raw response: \(responseString)")
                }
            }
            
            do {
                let schedules = try JSONDecoder().decode([SweepSchedule].self, from: data)
                print("Query '\(whereClause)' found \(schedules.count) schedules")
                
                if schedules.isEmpty && !remainingQueries.isEmpty {
                    // Try next query
                    self?.tryQueriesSequentially(queries: remainingQueries, completion: completion)
                } else {
                    completion(schedules)
                }
            } catch {
                print("Decoding error for query '\(whereClause)': \(error)")
                self?.tryQueriesSequentially(queries: remainingQueries, completion: completion)
            }
        }.resume()
    }
    
    private func getSchedulesFallback(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<SweepSchedule?, ParkingError>) -> Void) {
        // Get a sample of all data and filter client-side
        let fallbackURL = "\(baseURL)?$limit=5000"
        
        guard let url = URL(string: fallbackURL) else {
            completion(.failure(.invalidURL))
            return
        }
        
        print("Trying fallback: getting sample data to filter client-side")
        
        let request = URLRequest(url: url)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Fallback network error: \(error)")
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let data = data else {
                print("No fallback data received")
                completion(.failure(.noData))
                return
            }
            
            do {
                let allSchedules = try JSONDecoder().decode([SweepSchedule].self, from: data)
                print("Fallback: Got \(allSchedules.count) total schedules to filter")
                
                // Filter client-side
                let closestSchedule = self?.findClosestSchedule(from: coordinate, schedules: allSchedules)
                completion(.success(closestSchedule))
            } catch {
                print("Fallback decoding error: \(error)")
                completion(.failure(.decodingError(error)))
            }
        }.resume()
    }
    
    private func findClosestSchedule(from point: CLLocationCoordinate2D, schedules: [SweepSchedule]) -> SweepSchedule? {
        var closestSchedule: SweepSchedule?
        var minDistance = Double.infinity
        
        print("Checking \(schedules.count) schedules for closest match...")
        
        for schedule in schedules {
            guard let line = schedule.line else {
                print("Schedule missing line geometry: \(schedule.streetName)")
                continue
            }
            
            // Find the closest distance to this schedule's line
            let coordinates = line.coordinates
            guard coordinates.count >= 2 else {
                print("Schedule has insufficient coordinates: \(schedule.streetName)")
                continue
            }
            
            var scheduleMinDistance = Double.infinity
            
            // Check distance to each line segment
            for i in 0..<(coordinates.count - 1) {
                let segment = LineSegment(
                    start: CLLocationCoordinate2D(latitude: coordinates[i][1], longitude: coordinates[i][0]),
                    end: CLLocationCoordinate2D(latitude: coordinates[i+1][1], longitude: coordinates[i+1][0])
                )
                
                let (_, distance) = segment.closestPoint(to: point)
                scheduleMinDistance = min(scheduleMinDistance, distance)
            }
            
            // Convert meters to feet for comparison
            let distanceInFeet = scheduleMinDistance * 3.28084
            
            print("Schedule '\(schedule.streetName)' distance: \(distanceInFeet) feet")
            
            // Only consider schedules within max distance and keep the closest one
            if distanceInFeet <= maxDistance && scheduleMinDistance < minDistance {
                minDistance = scheduleMinDistance
                closestSchedule = schedule
                print("New closest: \(schedule.streetName) at \(distanceInFeet) feet")
            }
        }
        
        if let closest = closestSchedule {
            let distanceInFeet = minDistance * 3.28084
            print("Final closest schedule: \(closest.streetName) at \(distanceInFeet) feet")
        } else {
            print("No schedules found within \(maxDistance) feet - area appears to be street sweeping free!")
        }
        
        return closestSchedule
    }
    
    // Helper method to get user-friendly status message
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
}

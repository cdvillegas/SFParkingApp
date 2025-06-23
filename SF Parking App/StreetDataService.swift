//
//  StreetDataService.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import CoreLocation

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

    func getClosestSchedule(for coordinate: CLLocationCoordinate2D, completion: @escaping (SweepSchedule?) -> Void) {
        // Step 1: Get all schedules within 50 foot radius
        getSchedulesWithinRadius(for: coordinate) { [weak self] schedules in
            guard let self = self, let schedules = schedules, !schedules.isEmpty else {
                completion(nil)
                return
            }
            
            // Step 2: Find the closest one
            let closestSchedule = self.findClosestSchedule(from: coordinate, schedules: schedules)
            completion(closestSchedule)
        }
    }
    
    private func getSchedulesWithinRadius(for coordinate: CLLocationCoordinate2D, completion: @escaping ([SweepSchedule]?) -> Void) {
        // Convert 50 feet to degrees (approximate)
        // 1 degree ≈ 364,000 feet, so 50 feet ≈ 0.000137 degrees
        let radiusInDegrees = 50.0 / 364000.0
        
        let minLat = coordinate.latitude - radiusInDegrees
        let maxLat = coordinate.latitude + radiusInDegrees
        let minLng = coordinate.longitude - radiusInDegrees
        let maxLng = coordinate.longitude + radiusInDegrees
        
        let polygon = String(format: "POLYGON ((%.6f %.6f, %.6f %.6f, %.6f %.6f, %.6f %.6f, %.6f %.6f))",
                            minLng, maxLat,
                            maxLng, maxLat,
                            maxLng, minLat,
                            minLng, minLat,
                            minLng, maxLat)
        let whereClause = "intersects(line, '\(polygon)')"
        
        guard let query = "\(baseURL)?$where=\(whereClause)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: query) else {
            completion(nil)
            return
        }
        
        print("Query URL: \(query)")
        
        let request = URLRequest(url: url)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Network error: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                let schedules = try JSONDecoder().decode([SweepSchedule].self, from: data)
                print("Found \(schedules.count) schedules within radius")
                completion(schedules)
            } catch {
                print("Decoding error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    private func findClosestSchedule(from point: CLLocationCoordinate2D, schedules: [SweepSchedule]) -> SweepSchedule? {
        var closestSchedule: SweepSchedule?
        var minDistance = Double.infinity
        
        for schedule in schedules {
            guard let line = schedule.line else { continue }
            
            // Find the closest distance to this schedule's line
            let coordinates = line.coordinates
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
            
            // Only consider schedules within 50 feet and keep the closest one
            if scheduleMinDistance <= maxDistance && scheduleMinDistance < minDistance {
                minDistance = scheduleMinDistance
                closestSchedule = schedule
            }
        }
        
        if let closest = closestSchedule {
            print("Closest schedule: \(closest.streetName) at \(minDistance) feet")
        }
        
        return closestSchedule
    }
}

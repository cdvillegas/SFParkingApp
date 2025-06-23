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

final class StreetDataService {
    static let shared = StreetDataService()
    private let session = URLSession.shared
    private let baseURL = "https://data.sfgov.org/resource/yhqp-riqs.json"
    private let radiusFeet = 20 // 20 foot radius

    private init() {}

    func getSchedule(for coordinate: CLLocationCoordinate2D, completion: @escaping ([SweepSchedule]?) -> Void) {
        print("Fetching schedules for \(coordinate.latitude), \(coordinate.longitude)")
        
        // Use a larger radius - the working example uses about 0.000061 degrees
        // Let's use 0.000061 for consistency with the working example
        let degreesOffset = 0.000061
        
        let minLat = coordinate.latitude - degreesOffset
        let maxLat = coordinate.latitude + degreesOffset
        let minLng = coordinate.longitude - degreesOffset
        let maxLng = coordinate.longitude + degreesOffset
        
        // Create polygon query (make sure coordinates are properly formatted)
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
            print("Failed to create URL")
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
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("No data received")
                completion(nil)
                return
            }
            
            // Print raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw response: \(jsonString.prefix(500))...")
            }
            
            do {
                let schedules = try JSONDecoder().decode([SweepSchedule].self, from: data)
                print("Found \(schedules.count) schedules")
                completion(schedules)
            } catch {
                print("Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("Decoding error details: \(decodingError)")
                }
                completion(nil)
            }
        }.resume()
    }
}

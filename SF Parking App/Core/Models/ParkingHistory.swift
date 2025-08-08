//
//  ParkingHistory.swift
//  SF Parking App
//
//  Created by Assistant on 1/8/25.
//

import Foundation
import CoreLocation

struct ParkingHistory: Identifiable, Codable {
    let id: UUID
    let address: String
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let vehicleId: UUID?
    
    init(
        id: UUID = UUID(),
        address: String,
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        vehicleId: UUID? = nil
    ) {
        self.id = id
        self.address = address
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.vehicleId = vehicleId
    }
    
    var timeAgoString: String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(timestamp)
        let seconds = Int(timeInterval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        
        if seconds < 60 {
            return "Just now"
        } else if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if days == 1 {
            return "Yesterday"
        } else if days < 7 {
            return "\(days) days ago"
        } else if weeks == 1 {
            return "1 week ago"
        } else if weeks < 4 {
            return "\(weeks) weeks ago"
        } else {
            let months = weeks / 4
            if months == 1 {
                return "1 month ago"
            } else {
                return "\(months) months ago"
            }
        }
    }
    
    var shortAddress: String {
        // Return first two components of address (street and city)
        let components = address.components(separatedBy: ",").prefix(2)
        return components.joined(separator: ",").trimmingCharacters(in: .whitespaces)
    }
}

// Custom encoding/decoding for CLLocationCoordinate2D
extension ParkingHistory {
    enum CodingKeys: String, CodingKey {
        case id, address, latitude, longitude, timestamp, vehicleId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        address = try container.decode(String.self, forKey: .address)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        vehicleId = try container.decodeIfPresent(UUID.self, forKey: .vehicleId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(address, forKey: .address)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(vehicleId, forKey: .vehicleId)
    }
}
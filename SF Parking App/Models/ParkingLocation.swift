//
//  ParkingLocation.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//
import Foundation
import CoreLocation

enum ParkingSource: String, Codable {
    case manual = "manual"
    case motionActivity = "motion_activity"
    case carDisconnect = "car_disconnect"
    
    var displayName: String {
        switch self {
        case .manual:
            return "Manually Set"
        case .motionActivity:
            return "Auto-detected via Motion"
        case .carDisconnect:
            return "Set when Car Disconnected"
        }
    }
}

struct ParkingLocation: Identifiable, Codable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let address: String
    let timestamp: Date
    let source: ParkingSource
    
    init(coordinate: CLLocationCoordinate2D, address: String, timestamp: Date = Date(), source: ParkingSource = .manual) {
        self.coordinate = coordinate
        self.address = address
        self.timestamp = timestamp
        self.source = source
    }
    
    static let sample = ParkingLocation(
        coordinate: CLLocationCoordinate2D(latitude: 37.784790, longitude: -122.441556),
        address: "1530 Broderick Street",
        source: .manual
    )
    
    // Custom encoding/decoding for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case coordinate, address, timestamp, source
    }
    
    enum CoordinateKeys: String, CodingKey {
        case latitude, longitude
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coordinateContainer = try container.nestedContainer(keyedBy: CoordinateKeys.self, forKey: .coordinate)
        
        let latitude = try coordinateContainer.decode(Double.self, forKey: .latitude)
        let longitude = try coordinateContainer.decode(Double.self, forKey: .longitude)
        
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.address = try container.decode(String.self, forKey: .address)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Handle migration from old isManuallySet to new source
        if let isManuallySet = try? container.decode(Bool.self, forKey: .isManuallySet) {
            self.source = isManuallySet ? .manual : .motionActivity
        } else {
            self.source = try container.decode(ParkingSource.self, forKey: .source)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var coordinateContainer = container.nestedContainer(keyedBy: CoordinateKeys.self, forKey: .coordinate)
        
        try coordinateContainer.encode(coordinate.latitude, forKey: .latitude)
        try coordinateContainer.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(address, forKey: .address)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
    }
}

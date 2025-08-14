//
//  ParkingLocation.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//
import Foundation
import CoreLocation
import SwiftUI

// Simplified schedule data for persistence (avoids complex line geometry)
struct PersistedSweepSchedule: Codable, Equatable {
    let streetName: String
    let blockSide: String
    let weekday: String
    let startTime: String
    let endTime: String
    let week1: String
    let week2: String
    let week3: String
    let week4: String
    let week5: String
    let avgSweeperTime: Double?
    let medianSweeperTime: Double?
    
    init(from schedule: SweepSchedule, side: String) {
        self.streetName = schedule.streetName
        self.blockSide = side
        self.weekday = schedule.weekday ?? ""
        self.startTime = schedule.startTime
        self.endTime = schedule.endTime
        self.week1 = schedule.week1 ?? ""
        self.week2 = schedule.week2 ?? ""
        self.week3 = schedule.week3 ?? ""
        self.week4 = schedule.week4 ?? ""
        self.week5 = schedule.week5 ?? ""
        self.avgSweeperTime = schedule.avgSweeperTime
        self.medianSweeperTime = schedule.medianSweeperTime
    }
}

enum ParkingSource: String, Codable {
    case manual = "manual"
    case bluetooth = "bluetooth"
    case carplay = "carplay"
    case carDisconnect = "car_disconnect"
    case smartPark = "smart_park"
    
    var displayName: String {
        switch self {
        case .manual:
            return "Manually Set"
        case .bluetooth:
            return "Auto-detected via Bluetooth"
        case .carplay:
            return "Auto-detected via CarPlay"
        case .carDisconnect:
            return "Set when Car Disconnected"
        case .smartPark:
            return "Smart Park"
        }
    }
}

enum ParkingLocationColor: String, CaseIterable, Codable {
    case blue = "blue"
    case red = "red"
    case green = "green"
    case orange = "orange"
    case purple = "purple"
    case pink = "pink"
    case yellow = "yellow"
    case indigo = "indigo"
    case teal = "teal"
    case mint = "mint"
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .red: return .red
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .yellow: return .yellow
        case .indigo: return .indigo
        case .teal: return .teal
        case .mint: return .mint
        }
    }
    
    var displayName: String {
        switch self {
        case .blue: return "Ocean Blue"
        case .red: return "Cherry Red"
        case .green: return "Forest Green"
        case .orange: return "Sunset Orange"
        case .purple: return "Royal Purple"
        case .pink: return "Blossom Pink"
        case .yellow: return "Sunshine Yellow"
        case .indigo: return "Deep Indigo"
        case .teal: return "Tropical Teal"
        case .mint: return "Fresh Mint"
        }
    }
}

struct ParkingLocation: Identifiable, Codable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let address: String
    let timestamp: Date
    let source: ParkingSource
    let name: String?
    let color: ParkingLocationColor
    let isActive: Bool
    
    // Store user's selected schedule to persist their side-of-street choice
    let selectedSchedule: PersistedSweepSchedule?
    
    init(coordinate: CLLocationCoordinate2D, address: String, timestamp: Date = Date(), source: ParkingSource = .manual, name: String? = nil, color: ParkingLocationColor = .blue, isActive: Bool = true, selectedSchedule: PersistedSweepSchedule? = nil) {
        self.id = UUID()
        self.coordinate = coordinate
        self.address = address
        self.timestamp = timestamp
        self.source = source
        self.name = name
        self.color = color
        self.isActive = isActive
        self.selectedSchedule = selectedSchedule
    }
    
    var displayName: String {
        return name ?? generateDefaultName()
    }
    
    private func generateDefaultName() -> String {
        let components = address.components(separatedBy: ",")
        if let streetName = components.first?.trimmingCharacters(in: .whitespaces) {
            return streetName
        }
        return "Parking Location"
    }
    
    // Equatable conformance
    static func == (lhs: ParkingLocation, rhs: ParkingLocation) -> Bool {
        return lhs.id == rhs.id
    }
    
    static let sample = ParkingLocation(
        coordinate: CLLocationCoordinate2D(latitude: 37.784790, longitude: -122.441556),
        address: "1530 Broderick Street, San Francisco, CA",
        source: .manual,
        name: "Home",
        color: .blue
    )
    
    // Custom encoding/decoding for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, coordinate, address, timestamp, source, name, color, isActive, selectedSchedule
    }
    
    enum LegacyCodingKeys: String, CodingKey {
        case isManuallySet
    }
    
    enum CoordinateKeys: String, CodingKey {
        case latitude, longitude
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coordinateContainer = try container.nestedContainer(keyedBy: CoordinateKeys.self, forKey: .coordinate)
        
        let latitude = try coordinateContainer.decode(Double.self, forKey: .latitude)
        let longitude = try coordinateContainer.decode(Double.self, forKey: .longitude)
        
        // Decode the id 
        self.id = try container.decode(UUID.self, forKey: .id)
        
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.address = try container.decode(String.self, forKey: .address)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Handle new properties with defaults for backward compatibility
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.color = try container.decodeIfPresent(ParkingLocationColor.self, forKey: .color) ?? .blue
        self.isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        self.selectedSchedule = try container.decodeIfPresent(PersistedSweepSchedule.self, forKey: .selectedSchedule)
        
        // Handle migration from old isManuallySet to new source
        if let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self),
           let isManuallySet = try? legacyContainer.decode(Bool.self, forKey: .isManuallySet) {
            self.source = isManuallySet ? .manual : .carDisconnect
        } else {
            self.source = try container.decode(ParkingSource.self, forKey: .source)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var coordinateContainer = container.nestedContainer(keyedBy: CoordinateKeys.self, forKey: .coordinate)
        
        try container.encode(id, forKey: .id)
        try coordinateContainer.encode(coordinate.latitude, forKey: .latitude)
        try coordinateContainer.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(address, forKey: .address)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(selectedSchedule, forKey: .selectedSchedule)
    }
}

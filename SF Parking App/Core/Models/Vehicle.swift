//
//  Vehicle.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/26/25.
//

import Foundation
import SwiftUI

enum VehicleType: String, CaseIterable, Codable {
    case car = "car"
    case motorcycle = "motorcycle"
    case truck = "truck"
    case van = "van"
    
    var displayName: String {
        switch self {
        case .car:
            return "Car"
        case .motorcycle:
            return "Motorcycle"
        case .truck:
            return "Truck"
        case .van:
            return "Van"
        }
    }
    
    var iconName: String {
        switch self {
        case .car:
            return "car.fill"
        case .motorcycle:
            return "motorcycle"
        case .truck:
            return "truck.box.fill"
        case .van:
            return "bus.fill"
        }
    }
}

enum VehicleColor: String, CaseIterable, Codable {
    // Standard colors
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
    
    // Car-specific colors
    case black = "black"
    case white = "white"
    case silver = "silver"
    case gray = "gray"
    case darkGray = "darkGray"
    case brown = "brown"
    case gold = "gold"
    case maroon = "maroon"
    
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
        case .black: return .black
        case .white: return Color(.systemGray6)
        case .silver: return Color(.systemGray4)
        case .gray: return .gray
        case .darkGray: return Color(.systemGray2)
        case .brown: return .brown
        case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .maroon: return Color(red: 0.5, green: 0.0, blue: 0.0)
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
        case .black: return "Jet Black"
        case .white: return "Pearl White"
        case .silver: return "Metallic Silver"
        case .gray: return "Storm Gray"
        case .darkGray: return "Charcoal Gray"
        case .brown: return "Chestnut Brown"
        case .gold: return "Golden Yellow"
        case .maroon: return "Deep Maroon"
        }
    }
}

struct Vehicle: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String?
    var type: VehicleType
    var color: VehicleColor
    let createdAt: Date
    var parkingLocation: ParkingLocation?
    var isActive: Bool
    
    init(name: String? = nil, type: VehicleType = .car, color: VehicleColor = .blue, parkingLocation: ParkingLocation? = nil, isActive: Bool = true) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.color = color
        self.createdAt = Date()
        self.parkingLocation = parkingLocation
        self.isActive = isActive
    }
    
    var displayName: String {
        return name ?? generateDefaultName()
    }
    
    private func generateDefaultName() -> String {
        return "My \(type.displayName)"
    }
    
    // Equatable conformance
    static func == (lhs: Vehicle, rhs: Vehicle) -> Bool {
        return lhs.id == rhs.id
    }
    
    static let sample = Vehicle(
        name: "My Car",
        type: .car,
        color: .blue
    )
}

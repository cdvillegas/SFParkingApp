//
//  ParkingHistoryManager.swift
//  SF Parking App
//
//  Created by Assistant on 1/8/25.
//

import Foundation
import CoreLocation
import SwiftUI

class ParkingHistoryManager: ObservableObject {
    @Published var parkingHistory: [ParkingHistory] = []
    
    private let userDefaults = UserDefaults.standard
    private let historyKey = "ParkingHistoryData"
    private let maxHistoryItems = 10
    
    static let shared = ParkingHistoryManager()
    
    init() {
        loadHistory()
    }
    
    func addParkingLocation(_ location: ParkingLocation, vehicleId: UUID? = nil) {
        let historyItem = ParkingHistory(
            address: location.address,
            coordinate: location.coordinate,
            vehicleId: vehicleId
        )
        
        // Remove any duplicate locations (same coordinate within ~50 meters)
        parkingHistory.removeAll { existingItem in
            let distance = calculateDistance(from: existingItem.coordinate, to: location.coordinate)
            return distance < 50 // 50 meters threshold
        }
        
        // Add new item at the beginning
        parkingHistory.insert(historyItem, at: 0)
        
        // Keep only the last N items
        if parkingHistory.count > maxHistoryItems {
            parkingHistory = Array(parkingHistory.prefix(maxHistoryItems))
        }
        
        saveHistory()
    }
    
    func clearHistory() {
        parkingHistory.removeAll()
        saveHistory()
    }
    
    func removeHistoryItem(_ item: ParkingHistory) {
        parkingHistory.removeAll { $0.id == item.id }
        saveHistory()
    }
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(parkingHistory) {
            userDefaults.set(encoded, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        guard let data = userDefaults.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([ParkingHistory].self, from: data) else {
            return
        }
        parkingHistory = decoded
    }
}
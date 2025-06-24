//
//  ParkingLocationManager.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import CoreLocation
import Combine

class ParkingLocationManager: ObservableObject {
    @Published var currentLocation: ParkingLocation?
    @Published var locationHistory: [ParkingLocation] = []
    
    private let userDefaults = UserDefaults.standard
    private let currentLocationKey = "CurrentParkingLocation"
    private let historyKey = "ParkingLocationHistory"
    
    init() {
        loadCurrentLocation()
        loadLocationHistory()
    }
    
    func updateParkingLocation(_ location: ParkingLocation) {
        // Add current location to history if it exists
        if let current = currentLocation {
            addToHistory(current)
        }
        
        // Set new current location
        currentLocation = location
        saveCurrentLocation()
        
        print("Parking location updated: \(location.address)")
    }
    
    func setCurrentLocationAsParking(coordinate: CLLocationCoordinate2D, address: String) {
        let location = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .motionActivity
        )
        updateParkingLocation(location)
    }
    
    func setManualParkingLocation(coordinate: CLLocationCoordinate2D, address: String) {
        let location = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .manual
        )
        updateParkingLocation(location)
    }
    
    func setMotionDetectedParking(coordinate: CLLocationCoordinate2D, address: String) {
        let location = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .motionActivity
        )
        updateParkingLocation(location)
    }
    
    func setCarDisconnectParking(coordinate: CLLocationCoordinate2D, address: String) {
        let location = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .carDisconnect
        )
        updateParkingLocation(location)
    }
    
    private func addToHistory(_ location: ParkingLocation) {
        locationHistory.insert(location, at: 0)
        
        // Keep only the last 50 locations
        if locationHistory.count > 50 {
            locationHistory = Array(locationHistory.prefix(50))
        }
        
        saveLocationHistory()
    }
    
    private func saveCurrentLocation() {
        if let location = currentLocation,
           let data = try? JSONEncoder().encode(location) {
            userDefaults.set(data, forKey: currentLocationKey)
        }
    }
    
    private func loadCurrentLocation() {
        if let data = userDefaults.data(forKey: currentLocationKey),
           let location = try? JSONDecoder().decode(ParkingLocation.self, from: data) {
            currentLocation = location
        }
    }
    
    private func saveLocationHistory() {
        if let data = try? JSONEncoder().encode(locationHistory) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
    
    private func loadLocationHistory() {
        if let data = userDefaults.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([ParkingLocation].self, from: data) {
            locationHistory = history
        }
    }
}

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
    @Published var parkingLocations: [ParkingLocation] = []
    @Published var selectedLocation: ParkingLocation?
    
    private let userDefaults = UserDefaults.standard
    private let locationsKey = "ParkingLocations"
    private let selectedLocationKey = "SelectedParkingLocation"
    
    init() {
        loadParkingLocations()
        loadSelectedLocation()
    }
    
    // MARK: - Computed Properties
    
    var activeLocations: [ParkingLocation] {
        return parkingLocations.filter { $0.isActive }
    }
    
    var currentLocation: ParkingLocation? {
        return selectedLocation
    }
    
    var hasMultipleLocations: Bool {
        return activeLocations.count > 1
    }
    
    // MARK: - Location Management
    
    func addParkingLocation(_ location: ParkingLocation, setAsSelected: Bool = true) {
        // Remove any existing location at the same coordinates (within 10 meters)
        parkingLocations.removeAll { existingLocation in
            let distance = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                .distance(from: CLLocation(latitude: existingLocation.coordinate.latitude, longitude: existingLocation.coordinate.longitude))
            return distance < 10
        }
        
        parkingLocations.append(location)
        
        if setAsSelected || selectedLocation == nil {
            selectedLocation = location
            saveSelectedLocation()
        }
        
        saveParkingLocations()
        print("Added parking location: \(location.displayName)")
    }
    
    func updateParkingLocation(_ location: ParkingLocation) {
        if let index = parkingLocations.firstIndex(where: { $0.id == location.id }) {
            parkingLocations[index] = location
            
            if selectedLocation?.id == location.id {
                selectedLocation = location
                saveSelectedLocation()
            }
            
            saveParkingLocations()
        }
    }
    
    func removeParkingLocation(_ location: ParkingLocation) {
        parkingLocations.removeAll { $0.id == location.id }
        
        if selectedLocation?.id == location.id {
            selectedLocation = activeLocations.first
            saveSelectedLocation()
        }
        
        saveParkingLocations()
    }
    
    func selectLocation(_ location: ParkingLocation) {
        selectedLocation = location
        saveSelectedLocation()
    }
    
    func deactivateLocation(_ location: ParkingLocation) {
        let updatedLocation = ParkingLocation(
            coordinate: location.coordinate,
            address: location.address,
            timestamp: location.timestamp,
            source: location.source,
            name: location.name,
            color: location.color,
            isActive: false
        )
        updateParkingLocation(updatedLocation)
    }
    
    // MARK: - Convenience Methods
    
    func setCurrentLocationAsParking(coordinate: CLLocationCoordinate2D, address: String) {
        let location = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .motionActivity,
            color: getNextAvailableColor()
        )
        addParkingLocation(location)
    }
    
    func setManualParkingLocation(coordinate: CLLocationCoordinate2D, address: String, name: String? = nil, color: ParkingLocationColor? = nil) {
        let location = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .manual,
            name: name,
            color: color ?? getNextAvailableColor()
        )
        addParkingLocation(location)
    }
    
    func setCarDisconnectLocation(coordinate: CLLocationCoordinate2D, address: String) {
        let location = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .carDisconnect,
            color: getNextAvailableColor()
        )
        addParkingLocation(location)
    }
    
    private func getNextAvailableColor() -> ParkingLocationColor {
        let usedColors = Set(activeLocations.map { $0.color })
        let availableColors = ParkingLocationColor.allCases.filter { !usedColors.contains($0) }
        return availableColors.first ?? ParkingLocationColor.allCases.randomElement() ?? .blue
    }
    
    // MARK: - Persistence
    
    private func saveParkingLocations() {
        if let data = try? JSONEncoder().encode(parkingLocations) {
            userDefaults.set(data, forKey: locationsKey)
        }
    }
    
    private func loadParkingLocations() {
        if let data = userDefaults.data(forKey: locationsKey),
           let locations = try? JSONDecoder().decode([ParkingLocation].self, from: data) {
            parkingLocations = locations
        }
        
        // Migration from old single location system
        migrateOldCurrentLocation()
    }
    
    private func saveSelectedLocation() {
        if let location = selectedLocation,
           let data = try? JSONEncoder().encode(location.id) {
            userDefaults.set(data, forKey: selectedLocationKey)
        } else {
            userDefaults.removeObject(forKey: selectedLocationKey)
        }
    }
    
    private func loadSelectedLocation() {
        if let data = userDefaults.data(forKey: selectedLocationKey),
           let locationId = try? JSONDecoder().decode(UUID.self, from: data) {
            selectedLocation = parkingLocations.first { $0.id == locationId }
        }
        
        // If no selected location or it doesn't exist, select the first active one
        if selectedLocation == nil {
            selectedLocation = activeLocations.first
        }
    }
    
    private func migrateOldCurrentLocation() {
        // Check for old single location data and migrate it
        if parkingLocations.isEmpty,
           let data = userDefaults.data(forKey: "CurrentParkingLocation"),
           let oldLocation = try? JSONDecoder().decode(ParkingLocation.self, from: data) {
            
            // Create new location with updated structure
            let migratedLocation = ParkingLocation(
                coordinate: oldLocation.coordinate,
                address: oldLocation.address,
                timestamp: oldLocation.timestamp,
                source: oldLocation.source,
                name: nil,
                color: .blue,
                isActive: true
            )
            
            parkingLocations = [migratedLocation]
            selectedLocation = migratedLocation
            
            saveParkingLocations()
            saveSelectedLocation()
            
            // Clean up old data
            userDefaults.removeObject(forKey: "CurrentParkingLocation")
            userDefaults.removeObject(forKey: "ParkingLocationHistory")
        }
    }
}

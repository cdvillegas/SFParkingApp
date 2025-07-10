//
//  VehicleManager.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/26/25.
//

import Foundation
import CoreLocation
import Combine

class VehicleManager: ObservableObject {
    @Published var vehicles: [Vehicle] = []
    @Published var selectedVehicle: Vehicle?
    
    private let userDefaults = UserDefaults.standard
    private let vehiclesKey = "SavedVehicles"
    private let selectedVehicleKey = "SelectedVehicle"
    
    init() {
        loadVehicles()
        loadSelectedVehicle()
        
        // Ensure we always have exactly one vehicle (single-vehicle mode)
        ensureSingleVehicleExists()
    }
    
    // MARK: - Vehicle Management
    
    var activeVehicles: [Vehicle] {
        return vehicles.filter { $0.isActive }
    }
    
    /// Returns the single vehicle (single-vehicle mode)
    var currentVehicle: Vehicle? {
        return activeVehicles.first
    }
    
    /// Ensures exactly one vehicle exists (single-vehicle mode)
    private func ensureSingleVehicleExists() {
        if activeVehicles.isEmpty {
            let defaultVehicle = Vehicle(
                name: nil, // Will use generated name
                type: .car,
                color: .blue
            )
            addVehicle(defaultVehicle, setAsSelected: true)
        } else if activeVehicles.count > 1 {
            // If we have multiple vehicles, keep only the first one
            let vehicleToKeep = activeVehicles.first!
            vehicles = [vehicleToKeep]
            selectedVehicle = vehicleToKeep
            saveVehicles()
            saveSelectedVehicle()
        }
    }
    
    func addVehicle(_ vehicle: Vehicle, setAsSelected: Bool = true) {
        // Single-vehicle mode: replace the existing vehicle
        vehicles = [vehicle]
        selectedVehicle = vehicle
        
        saveVehicles()
        saveSelectedVehicle()
        
        print("✅ Added vehicle: \(vehicle.displayName)")
    }
    
    func updateVehicle(_ vehicle: Vehicle) {
        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
            
            // Update selected vehicle if it's the one being updated
            if selectedVehicle?.id == vehicle.id {
                selectedVehicle = vehicle
            }
            
            saveVehicles()
            saveSelectedVehicle()
            
            print("✅ Updated vehicle: \(vehicle.displayName)")
        }
    }
    
    func removeVehicle(_ vehicle: Vehicle) {
        // Single-vehicle mode: don't allow removing the only vehicle
        // Instead, reset it to default
        let defaultVehicle = Vehicle(
            name: nil, // Will use generated name
            type: .car,
            color: .blue
        )
        vehicles = [defaultVehicle]
        selectedVehicle = defaultVehicle
        
        saveVehicles()
        saveSelectedVehicle()
        
        print("✅ Removed vehicle: \(vehicle.displayName)")
    }
    
    func selectVehicle(_ vehicle: Vehicle) {
        selectedVehicle = vehicle
        saveSelectedVehicle()
        
        print("✅ Selected vehicle: \(vehicle.displayName)")
    }
    
    // MARK: - Parking Location Management
    
    func setParkingLocation(for vehicle: Vehicle, location: ParkingLocation) {
        var updatedVehicle = vehicle
        updatedVehicle.parkingLocation = location
        updateVehicle(updatedVehicle)
        
        print("🚗 Set parking location for \(vehicle.displayName): \(location.address)")
    }
    
    func clearParkingLocation(for vehicle: Vehicle) {
        var updatedVehicle = vehicle
        updatedVehicle.parkingLocation = nil
        updateVehicle(updatedVehicle)
        
        print("🚗 Cleared parking location for \(vehicle.displayName)")
    }
    
    func setManualParkingLocation(for vehicle: Vehicle, coordinate: CLLocationCoordinate2D, address: String, selectedSchedule: PersistedSweepSchedule? = nil) {
        let parkingLocation = ParkingLocation(
            coordinate: coordinate,
            address: address,
            source: .manual,
            name: "\(vehicle.displayName) Parking",
            color: .blue, // We can match vehicle color later if needed
            selectedSchedule: selectedSchedule
        )
        
        setParkingLocation(for: vehicle, location: parkingLocation)
    }
    
    // MARK: - Auto-Generated Names
    
    func generateVehicleName(for type: VehicleType) -> String {
        let existingVehiclesOfType = vehicles.filter { $0.type == type }
        let count = existingVehiclesOfType.count + 1
        return "\(type.displayName) \(count)"
    }
    
    // MARK: - Persistence
    
    private func saveVehicles() {
        if let data = try? JSONEncoder().encode(vehicles) {
            userDefaults.set(data, forKey: vehiclesKey)
        }
    }
    
    private func loadVehicles() {
        guard let data = userDefaults.data(forKey: vehiclesKey),
              let savedVehicles = try? JSONDecoder().decode([Vehicle].self, from: data) else {
            return
        }
        
        vehicles = savedVehicles
    }
    
    private func saveSelectedVehicle() {
        if let selectedVehicle = selectedVehicle,
           let data = try? JSONEncoder().encode(selectedVehicle) {
            userDefaults.set(data, forKey: selectedVehicleKey)
        } else {
            userDefaults.removeObject(forKey: selectedVehicleKey)
        }
    }
    
    private func loadSelectedVehicle() {
        guard let data = userDefaults.data(forKey: selectedVehicleKey),
              let savedVehicle = try? JSONDecoder().decode(Vehicle.self, from: data) else {
            return
        }
        
        // Make sure the selected vehicle still exists in our vehicles array
        if vehicles.contains(where: { $0.id == savedVehicle.id }) {
            selectedVehicle = savedVehicle
        }
    }
}
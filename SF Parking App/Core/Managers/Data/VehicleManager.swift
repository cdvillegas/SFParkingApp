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
    // Singleton for background operations (Smart Park)
    static let shared = VehicleManager()
    
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
        
    }
    
    func selectVehicle(_ vehicle: Vehicle) {
        selectedVehicle = vehicle
        saveSelectedVehicle()
        AnalyticsManager.shared.logVehicleSelected(vehicleId: vehicle.id.uuidString)
    }
    
    // MARK: - Parking Location Management
    
    func setParkingLocation(for vehicle: Vehicle, location: ParkingLocation) {
        var updatedVehicle = vehicle
        updatedVehicle.parkingLocation = location
        updateVehicle(updatedVehicle)
        
        // Add to parking history (only if not already added by setManualParkingLocation)
        if location.source != .manual {
            ParkingHistoryManager.shared.addParkingLocation(location, vehicleId: vehicle.id)
        }
        
        AnalyticsManager.shared.logParkingLocationSet(method: "manual")
    }
    
    func clearParkingLocation(for vehicle: Vehicle) {
        var updatedVehicle = vehicle
        updatedVehicle.parkingLocation = nil
        updateVehicle(updatedVehicle)
        AnalyticsManager.shared.logParkingLocationCleared()
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
        
        // Add to parking history
        ParkingHistoryManager.shared.addParkingLocation(parkingLocation, vehicleId: vehicle.id)
        
        // Log additional analytics for schedule selection
        if let schedule = selectedSchedule {
            AnalyticsManager.shared.logParkingScheduleSelected(
                scheduleType: "street_cleaning",
                duration: "\(schedule.weekday) \(schedule.startTime)-\(schedule.endTime)"
            )
        }
        
        AnalyticsManager.shared.logParkingConfirmed(
            vehicleId: vehicle.id.uuidString,
            hasSchedule: selectedSchedule != nil
        )
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
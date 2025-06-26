//
//  BluetoothManager.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import Foundation
import CoreBluetooth
import CoreLocation
import Combine

class BluetoothManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private let geocoder = CLGeocoder()
    
    @Published var isConnectedToCar = false
    @Published var connectedCarDevices: [CBPeripheral] = []
    
    private var wasConnectedToCar = false
    private var lastCarDisconnectLocation: CLLocation?
    
    weak var parkingLocationManager: ParkingLocationManager?
    weak var locationManager: LocationManager?
    
    // Known car device identifiers (you'll need to customize these)
    private let carDeviceNames = ["Car", "Honda", "Toyota", "BMW", "Mercedes", "Audi", "Ford", "Chevrolet"]
    private let carDeviceIdentifiers: Set<String> = []
    
    override init() {
        super.init()
        // Don't auto-start Bluetooth - wait for explicit permission request
    }
    
    func requestBluetoothPermission() {
        setupBluetoothManager()
    }
    
    private func setupBluetoothManager() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        
        // Scan for all devices to detect car connections/disconnections
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    private func isCarDevice(_ peripheral: CBPeripheral) -> Bool {
        guard let name = peripheral.name else { return false }
        
        // Check if device name contains car-related keywords
        for carName in carDeviceNames {
            if name.localizedCaseInsensitiveContains(carName) {
                return true
            }
        }
        
        // Check if device identifier is in known car identifiers
        return carDeviceIdentifiers.contains(peripheral.identifier.uuidString)
    }
    
    private func handleCarConnection(_ peripheral: CBPeripheral) {
        print("Car connected: \(peripheral.name ?? "Unknown")")
        
        if !connectedCarDevices.contains(peripheral) {
            connectedCarDevices.append(peripheral)
        }
        
        isConnectedToCar = !connectedCarDevices.isEmpty
        wasConnectedToCar = true
        
        // Store current location as potential parking location
        storeCurrentLocationForPotentialDisconnect()
    }
    
    private func handleCarDisconnection(_ peripheral: CBPeripheral) {
        print("Car disconnected: \(peripheral.name ?? "Unknown")")
        
        connectedCarDevices.removeAll { $0.identifier == peripheral.identifier }
        isConnectedToCar = !connectedCarDevices.isEmpty
        
        // Only handle disconnect if we were previously connected to a car
        if wasConnectedToCar && connectedCarDevices.isEmpty {
            handleCarDisconnectEvent()
        }
    }
    
    private func storeCurrentLocationForPotentialDisconnect() {
        guard let location = locationManager?.userLocation else { return }
        lastCarDisconnectLocation = location
    }
    
    private func handleCarDisconnectEvent() {
        // Wait a bit to ensure this isn't a temporary disconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.confirmCarDisconnect()
        }
    }
    
    private func confirmCarDisconnect() {
        // Check if we're still disconnected
        guard connectedCarDevices.isEmpty else {
            print("Car reconnected - ignoring disconnect")
            return
        }
        
        // Make sure we have a recent location
        guard let disconnectLocation = lastCarDisconnectLocation else {
            print("No location available for car disconnect")
            return
        }
        
        // Check if location is recent enough (within last 2 minutes)
        let locationAge = Date().timeIntervalSince(disconnectLocation.timestamp)
        guard locationAge < 120 else {
            print("Disconnect location too old: \(locationAge) seconds")
            return
        }
        
        // Reverse geocode and set parking location
        reverseGeocodeAndSetParkingLocation(disconnectLocation)
    }
    
    private func reverseGeocodeAndSetParkingLocation(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    self.setParkingLocationWithFallbackAddress(location)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    self.setParkingLocationWithFallbackAddress(location)
                    return
                }
                
                let address = self.formatAddress(from: placemark)
                self.setParkingLocation(coordinate: location.coordinate, address: address)
            }
        }
    }
    
    private func setParkingLocationWithFallbackAddress(_ location: CLLocation) {
        let address = "Parking Location (\(location.coordinate.latitude), \(location.coordinate.longitude))"
        setParkingLocation(coordinate: location.coordinate, address: address)
    }
    
    private func setParkingLocation(coordinate: CLLocationCoordinate2D, address: String) {
        print("Auto-setting parking location via car disconnect: \(address)")
        parkingLocationManager?.setCarDisconnectLocation(coordinate: coordinate, address: address)
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        if let streetNumber = placemark.subThoroughfare,
           let streetName = placemark.thoroughfare {
            return "\(streetNumber) \(streetName)"
        } else if let streetName = placemark.thoroughfare {
            return streetName
        } else if let name = placemark.name {
            return name
        } else {
            return "Unknown Location"
        }
    }
    
    func addKnownCarDevice(_ identifier: String) {
        // Allow users to manually add car device identifiers
        // This would typically be done through a settings screen
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            startScanning()
        case .poweredOff:
            print("Bluetooth is powered off")
            connectedCarDevices.removeAll()
            isConnectedToCar = false
        case .resetting:
            print("Bluetooth is resetting")
        case .unauthorized:
            print("Bluetooth is unauthorized")
        case .unsupported:
            print("Bluetooth is unsupported")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if this is a car device
        if isCarDevice(peripheral) {
            // Try to connect to track connection/disconnection
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if isCarDevice(peripheral) {
            handleCarConnection(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if isCarDevice(peripheral) {
            handleCarDisconnection(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
    }
}

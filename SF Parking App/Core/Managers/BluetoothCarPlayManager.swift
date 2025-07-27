//
//  BluetoothCarPlayManager.swift
//  SF Parking App
//
//  Handles Bluetooth and CarPlay connection detection for auto-parking
//

import Foundation
import CoreBluetooth
import CoreLocation
import UserNotifications
import UIKit

class BluetoothCarPlayManager: NSObject, ObservableObject {
    static let shared = BluetoothCarPlayManager()
    
    @Published var isBluetoothEnabled = false
    @Published var isCarPlayConnected = false
    @Published var connectedDevices: [String] = []
    @Published var pairedDevices: [String] = []
    @Published var isAutoParkingEnabled = false
    
    private var bluetoothManager: CBCentralManager?
    private var connectedPeripherals: Set<String> = []
    private var lastDisconnectionTime: Date?
    private var lastKnownLocation: CLLocation?
    
    private let locationManager = LocationManager()
    
    override init() {
        super.init()
        loadSettings()
        setupNotificationObservers()
        loadPairedDevices()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        isAutoParkingEnabled = UserDefaults.standard.bool(forKey: "bluetoothAutoParkingEnabled")
    }
    
    func saveSettings() {
        UserDefaults.standard.set(isAutoParkingEnabled, forKey: "bluetoothAutoParkingEnabled")
    }
    
    func enableAutoParkingDetection() {
        guard !isAutoParkingEnabled else { return }
        
        isAutoParkingEnabled = true
        saveSettings()
        startMonitoring()
    }
    
    func disableAutoParkingDetection() {
        guard isAutoParkingEnabled else { return }
        
        isAutoParkingEnabled = false
        saveSettings()
        stopMonitoring()
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        guard isAutoParkingEnabled else { return }
        
        print("🔵 Starting Bluetooth/CarPlay monitoring...")
        
        // Initialize Bluetooth manager
        bluetoothManager = CBCentralManager(delegate: self, queue: nil)
        
        // Start location updates to capture parking location
        locationManager.startLocationUpdates()
        
        print("🔵 Bluetooth/CarPlay monitoring started")
    }
    
    func stopMonitoring() {
        print("🔵 Stopping Bluetooth/CarPlay monitoring...")
        
        bluetoothManager?.stopScan()
        bluetoothManager = nil
        
        print("🔵 Bluetooth/CarPlay monitoring stopped")
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // CarPlay connection notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(carPlayDidConnect),
            name: NSNotification.Name("CarPlayDidConnect"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(carPlayDidDisconnect),
            name: NSNotification.Name("CarPlayDidDisconnect"),
            object: nil
        )
        
        // App lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func carPlayDidConnect() {
        print("🔵 🚗 CarPlay connected")
        DispatchQueue.main.async {
            self.isCarPlayConnected = true
        }
        
        // Store current location as potential parking spot
        storeCurrentLocation()
    }
    
    @objc private func carPlayDidDisconnect() {
        print("🔵 🚗 CarPlay disconnected - potential parking detected")
        DispatchQueue.main.async {
            self.isCarPlayConnected = false
        }
        
        handlePotentialParking(source: "carplay")
    }
    
    @objc private func appDidEnterBackground() {
        // Continue monitoring in background if enabled
        if isAutoParkingEnabled {
            print("🔵 Continuing monitoring in background")
        }
    }
    
    @objc private func appWillEnterForeground() {
        // Resume monitoring when app becomes active
        if isAutoParkingEnabled {
            print("🔵 Resuming monitoring in foreground")
            startMonitoring()
        }
    }
    
    // MARK: - Parking Detection
    
    private func storeCurrentLocation() {
        guard let location = locationManager.userLocation else { return }
        lastKnownLocation = location
        print("🔵 📍 Stored location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
    
    private func handlePotentialParking(source: String) {
        guard isAutoParkingEnabled else { return }
        
        lastDisconnectionTime = Date()
        
        // Wait 10 seconds to confirm parking (avoid false positives from temporary disconnections)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.confirmParkingDetection(source: source)
        }
    }
    
    private func confirmParkingDetection(source: String) {
        // Check if we haven't reconnected (which would indicate it was just a temporary disconnection)
        guard let disconnectionTime = lastDisconnectionTime,
              Date().timeIntervalSince(disconnectionTime) >= 10 else {
            print("🔵 ❌ Parking detection cancelled - reconnected too quickly")
            return
        }
        
        // Get current or last known location
        let parkingLocation = locationManager.userLocation ?? lastKnownLocation
        
        guard let location = parkingLocation else {
            print("🔵 ❌ No location available for parking detection")
            return
        }
        
        print("🔵 ✅ Parking confirmed via \(source)")
        
        // Reverse geocode and send notification
        reverseGeocodeAndNotify(location: location, source: source)
    }
    
    private func reverseGeocodeAndNotify(location: CLLocation, source: String) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                let address = self?.formatAddress(from: placemarks?.first) ?? 
                             "Parking Location (\(location.coordinate.latitude), \(location.coordinate.longitude))"
                
                self?.sendParkingNotification(
                    coordinate: location.coordinate,
                    address: address,
                    source: source
                )
            }
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark?) -> String {
        guard let placemark = placemark else { return "Unknown Location" }
        
        var components: [String] = []
        
        if let streetNumber = placemark.subThoroughfare {
            components.append(streetNumber)
        }
        
        if let streetName = placemark.thoroughfare {
            components.append(streetName)
        }
        
        if components.isEmpty, let name = placemark.name {
            components.append(name)
        }
        
        return components.joined(separator: " ")
    }
    
    private func sendParkingNotification(coordinate: CLLocationCoordinate2D, address: String, source: String) {
        let content = UNMutableNotificationContent()
        content.title = "🚗 Parking Detected"
        content.body = "Confirm your parking location at \(address)"
        content.sound = .default
        content.categoryIdentifier = "PARKING_CONFIRMATION"
        
        // Add location data to notification
        content.userInfo = [
            "type": "parking_detection",
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "address": address,
            "source": source.lowercased().replacingOccurrences(of: " ", with: "_")
        ]
        
        // Schedule immediate notification
        let request = UNNotificationRequest(
            identifier: "parking_detection_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔵 ❌ Failed to send parking notification: \(error)")
            } else {
                print("🔵 ✅ Parking notification sent successfully!")
            }
        }
        
        // Store pending parking data for app launch handling
        storePendingParkingData(coordinate: coordinate, address: address, source: source)
    }
    
    private func storePendingParkingData(coordinate: CLLocationCoordinate2D, address: String, source: String) {
        let pendingData: [String: Any] = [
            "coordinate": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
            "address": address,
            "source": source.lowercased().replacingOccurrences(of: " ", with: "_"),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        UserDefaults.standard.set(pendingData, forKey: "pendingParkingLocation")
        print("🔵 💾 Stored pending parking data for app launch")
    }
    
    // MARK: - Permission Management
    
    func requestBluetoothPermission() -> Bool {
        print("🔵 🔐 Requesting Bluetooth permission...")
        
        // Initialize Bluetooth manager if not already done - this triggers permission prompt
        if bluetoothManager == nil {
            bluetoothManager = CBCentralManager(delegate: self, queue: nil)
        }
        
        // Return true if we successfully initiated the request
        return true
    }
    
    var bluetoothAuthorizationStatus: CBManagerAuthorization {
        return bluetoothManager?.authorization ?? .notDetermined
    }
    
    // MARK: - Paired Devices Management
    
    private func loadPairedDevices() {
        // Load previously saved paired devices
        if let saved = UserDefaults.standard.array(forKey: "pairedBluetoothDevices") as? [String] {
            pairedDevices = saved
        } else {
            // Start with empty list - users will add their devices
            pairedDevices = []
        }
    }
    
    func addPairedDevice(_ deviceName: String) {
        if !pairedDevices.contains(deviceName) {
            pairedDevices.append(deviceName)
            savePairedDevices()
        }
    }
    
    func removePairedDevice(_ deviceName: String) {
        pairedDevices.removeAll { $0 == deviceName }
        savePairedDevices()
    }
    
    private func savePairedDevices() {
        UserDefaults.standard.set(pairedDevices, forKey: "pairedBluetoothDevices")
    }
    
    func getAllAvailableDevices() -> [String] {
        // Combine connected and paired devices, removing duplicates
        let allDevices = Set(connectedDevices + pairedDevices)
        return Array(allDevices).sorted()
    }
    
    // Manually add a device (for when users want to add their car manually)
    func addCustomDevice(_ deviceName: String) {
        addPairedDevice(deviceName)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMonitoring()
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothCarPlayManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            switch central.state {
            case .poweredOn:
                self.isBluetoothEnabled = true
                print("🔵 ✅ Bluetooth powered on")
                
                if self.isAutoParkingEnabled {
                    self.startScanning()
                }
                
            case .poweredOff:
                self.isBluetoothEnabled = false
                print("🔵 ❌ Bluetooth powered off")
                
            case .unauthorized:
                self.isBluetoothEnabled = false
                print("🔵 ❌ Bluetooth unauthorized")
                
            case .unsupported:
                self.isBluetoothEnabled = false
                print("🔵 ❌ Bluetooth unsupported")
                
            default:
                print("🔵 ⚠️ Bluetooth state: \(central.state.rawValue)")
            }
        }
    }
    
    private func startScanning() {
        guard let manager = bluetoothManager, manager.state == .poweredOn else { return }
        
        print("🔵 🔍 Starting Bluetooth scan...")
        manager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name else { return }
        
        // Filter for car-related devices (you can customize this list)
        let carKeywords = ["car", "auto", "bmw", "mercedes", "audi", "toyota", "honda", "ford", "tesla", "lexus", "infiniti", "acura", "cadillac", "buick", "chevrolet", "gmc", "jeep", "dodge", "chrysler", "ram", "lincoln", "volvo", "jaguar", "land rover", "porsche", "maserati", "ferrari", "lamborghini", "bentley", "rolls-royce", "subaru", "mazda", "nissan", "hyundai", "kia", "genesis", "polestar", "rivian", "lucid"]
        
        let isCarDevice = carKeywords.contains { name.lowercased().contains($0) }
        
        if isCarDevice {
            print("🔵 🚗 Discovered car device: \(name)")
            
            // Connect to track connection/disconnection
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let name = peripheral.name else { return }
        
        print("🔵 ✅ Connected to: \(name)")
        
        DispatchQueue.main.async {
            self.connectedPeripherals.insert(peripheral.identifier.uuidString)
            self.connectedDevices = Array(self.connectedPeripherals)
            
            // Auto-add discovered car devices to paired list
            self.addPairedDevice(name)
        }
        
        // Store location when connecting (potential departure point)
        storeCurrentLocation()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let name = peripheral.name else { return }
        
        print("🔵 ❌ Disconnected from: \(name)")
        
        DispatchQueue.main.async {
            self.connectedPeripherals.remove(peripheral.identifier.uuidString)
            self.connectedDevices = Array(self.connectedPeripherals)
        }
        
        // Handle potential parking
        handlePotentialParking(source: "bluetooth")
    }
}
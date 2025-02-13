import CoreBluetooth
import os
import UIKit
import UserNotifications

class BluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var wasManuallyStopped = false
    @Published var discoveredPeripherals: [(peripheral: CBPeripheral, rssi: Int, lastUpdate: Date, systemId: String?)] = []
    @Published var selectedPeripheral: CBPeripheral?
    @Published var rssi: Int = 0
    @Published var state: CBManagerState = .unknown
    @Published var favoriteDevices: [FavoriteDevice] = []
    @Published var systemId: String?
    @Published var error: String?
    @Published var timeoutInterval: TimeInterval = 4.0 // Default 4 seconds
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "NotificationsEnabled")
        }
    }
    
    private var centralManager: CBCentralManager!
    private let favoritesKey = "FavoriteDevices"
    private let deviceInfoServiceUUID = CBUUID(string: "180A")
    private let systemIdCharacteristicUUID = CBUUID(string: "2A23")
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")
    
    // Constants for distance calculation
    private let measuredPower: Double = -59.0  // Calibrated RSSI value at 1 meter
    private let environmentalFactor: Double = 2.0  // Path loss exponent (2.0 for free space)
    
    private var lastAllDevicesActiveState: Bool?
    private var lastNotificationState: Bool?
    
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Keep track of peripherals we're connecting to for System ID
    private var connectingPeripherals: Set<CBPeripheral> = []
    
    override init() {
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: "NotificationsEnabled")
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadFavorites()
        requestNotificationPermission()
        setupBackgroundHandling()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func showDevicesStatusNotification(totalDevices: Int, activeDevices: Int) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Bluetooth Devices Status"
        content.body = "Active devices: \(activeDevices) of \(totalDevices)"
        content.sound = nil
        
        let request = UNNotificationRequest(
            identifier: "DevicesStatus",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
    
    private func setupBackgroundHandling() {
        // Register for background notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundTransition),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForegroundTransition),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleBackgroundTransition() {
        // Start background task when app enters background
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        // Ensure scanning continues in background if it was active
        if isScanning {
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true,
                    CBCentralManagerOptionShowPowerAlertKey: true
                ]
            )
        }
    }
    
    @objc private func handleForegroundTransition() {
        // End background task when app returns to foreground
        endBackgroundTask()
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            error = "Bluetooth is not powered on"
            return
        }
        
        isScanning = true
        wasManuallyStopped = false
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }
    
    func stopScanning() {
        isScanning = false
        wasManuallyStopped = true
        centralManager.stopScan()
    }
    
    func connect(to peripheral: CBPeripheral) {
        selectedPeripheral = peripheral
        selectedPeripheral?.delegate = self
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }
    
    func disconnect() {
        if let peripheral = selectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            selectedPeripheral = nil
            systemId = nil
        }
    }
    
    // MARK: - Favorites Management
    func toggleFavorite(for peripheral: CBPeripheral) {
        if isFavorite(peripheral) {
            removeFavorite(peripheral)
        } else {
            addFavorite(peripheral)
        }
    }
    
    func isFavorite(_ peripheral: CBPeripheral) -> Bool {
        favoriteDevices.contains { $0.id == peripheral.identifier.uuidString }
    }
    
    private func addFavorite(_ peripheral: CBPeripheral) {
        let favorite = FavoriteDevice(peripheral: peripheral)
        favoriteDevices.append(favorite)
        saveFavorites()
    }
    
    private func removeFavorite(_ peripheral: CBPeripheral) {
        favoriteDevices.removeAll { $0.id == peripheral.identifier.uuidString }
        saveFavorites()
    }
    
    func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favoriteDevices) {
            UserDefaults.standard.set(encoded, forKey: favoritesKey)
        }
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([FavoriteDevice].self, from: data) {
            favoriteDevices = decoded
        }
    }
    
    func calculateDistance(rssi: Int) -> Double {
        // Distance = 10 ^ ((|RSSI| - |Measured Power|) / (10 * Environmental Factor))
        let ratio = (abs(Double(rssi)) - abs(measuredPower)) / (10 * environmentalFactor)
        return pow(10.0, ratio)
    }
    
    func updateDeviceName(id: String, newName: String) {
        if let index = favoriteDevices.firstIndex(where: { $0.id == id }) {
            var device = favoriteDevices[index]
            device.customName = newName
            favoriteDevices[index] = device
            saveFavorites()
        }
    }
    
    func checkFavoritesStatus() {
        let currentAllActive = !favoriteDevices.isEmpty && favoriteDevices.allSatisfy { favorite in
            if let discovered = discoveredPeripherals.first(where: { $0.peripheral.identifier.uuidString == favorite.id }) {
                return Date().timeIntervalSince(discovered.lastUpdate) <= timeoutInterval
            }
            return false
        }
        
        // Only vibrate if the state has changed
        if currentAllActive != lastAllDevicesActiveState {
            if currentAllActive {
                // All devices are in range - vibrate once
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Show notification if enabled
                showDevicesStatusNotification(
                    totalDevices: favoriteDevices.count,
                    activeDevices: favoriteDevices.count
                )
            } else if lastAllDevicesActiveState == true {
                // Devices were all active but now some are not - vibrate twice
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    generator.impactOccurred()
                }
                
                // Show notification if enabled
                let activeCount = favoriteDevices.filter { favorite in
                    if let discovered = discoveredPeripherals.first(where: { $0.peripheral.identifier.uuidString == favorite.id }) {
                        return Date().timeIntervalSince(discovered.lastUpdate) <= timeoutInterval
                    }
                    return false
                }.count
                
                showDevicesStatusNotification(
                    totalDevices: favoriteDevices.count,
                    activeDevices: activeCount
                )
            }
            lastAllDevicesActiveState = currentAllActive
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == deviceInfoServiceUUID {
                peripheral.discoverCharacteristics([systemIdCharacteristicUUID], for: service)
            } else if service.uuid == batteryServiceUUID {
                peripheral.discoverCharacteristics(
                    [batteryLevelCharacteristicUUID],
                    for: service
                )
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == systemIdCharacteristicUUID {
                peripheral.readValue(for: characteristic)
            } else if characteristic.uuid == batteryLevelCharacteristicUUID {
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == systemIdCharacteristicUUID, let data = characteristic.value {
            // Reverse the bytes and format as MAC
            let systemIdString = data.reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
            os_log("Got System ID for %@: %@", peripheral.name ?? "Unknown", systemIdString)
            DispatchQueue.main.async {
                if let index = self.discoveredPeripherals.firstIndex(where: { $0.peripheral == peripheral }) {
                    self.discoveredPeripherals[index].systemId = systemIdString
                    // Disconnect after getting System ID if not selected
                    if peripheral != self.selectedPeripheral {
                        self.centralManager.cancelPeripheralConnection(peripheral)
                    }
                }
            }
        } else if characteristic.uuid == batteryLevelCharacteristicUUID, let data = characteristic.value {
            let batteryLevel = Int(data[0])
            DispatchQueue.main.async {
                if let index = self.favoriteDevices.firstIndex(where: { $0.id == peripheral.identifier.uuidString }) {
                    var device = self.favoriteDevices[index]
                    device.batteryLevel = batteryLevel
                    self.favoriteDevices[index] = device
                }
            }
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            if isScanning {
                startScanning()
            }
        case .poweredOff:
            print("Bluetooth is powered off - please enable Bluetooth")
        case .unsupported:
            print("Bluetooth is unsupported on this device")
            #if targetEnvironment(simulator)
            print("Note: Running in simulator - Bluetooth support is limited")
            #endif
        case .unauthorized:
            print("Bluetooth permission denied - please check Settings")
        case .resetting:
            print("Bluetooth is resetting - please wait")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state occurred")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let index = discoveredPeripherals.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
            // Update existing peripheral
            discoveredPeripherals[index].rssi = RSSI.intValue
            discoveredPeripherals[index].lastUpdate = Date()
        } else {
            // Add new peripheral
            discoveredPeripherals.append((peripheral: peripheral, rssi: RSSI.intValue, lastUpdate: Date(), systemId: nil))
            // Connect to get System ID if we haven't tried yet
            if !connectingPeripherals.contains(peripheral) {
                connectingPeripherals.insert(peripheral)
                peripheral.delegate = self
                centralManager.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
                ])
            }
        }
        
        if peripheral == selectedPeripheral {
            self.rssi = RSSI.intValue
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Connected to peripheral: %@", peripheral.name ?? "Unknown")
        peripheral.delegate = self
        peripheral.discoverServices([deviceInfoServiceUUID, batteryServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            os_log("Disconnected from peripheral with error: %@", error.localizedDescription)
        } else {
            os_log("Disconnected from peripheral")
        }
        
        connectingPeripherals.remove(peripheral)
        
        if peripheral == selectedPeripheral {
            selectedPeripheral = nil
        }
    }
} 
import CoreBluetooth
import os

class BluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var discoveredPeripherals: [(peripheral: CBPeripheral, rssi: Int)] = []
    @Published var selectedPeripheral: CBPeripheral?
    @Published var rssi: Int = 0
    @Published var state: CBManagerState = .unknown
    @Published var favoriteDevices: [FavoriteDevice] = []
    
    private var centralManager: CBCentralManager!
    private let favoritesKey = "FavoriteDevices"
    
    // Constants for distance calculation
    private let measuredPower: Double = -59.0  // Calibrated RSSI value at 1 meter
    private let environmentalFactor: Double = 2.0  // Path loss exponent (2.0 for free space)
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadFavorites()
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        
        isScanning = true
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }
    
    func connect(to peripheral: CBPeripheral) {
        selectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = selectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            selectedPeripheral = nil
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
        if let existingIndex = discoveredPeripherals.firstIndex(where: { $0.peripheral == peripheral }) {
            // Update RSSI for existing peripheral
            discoveredPeripherals[existingIndex].rssi = RSSI.intValue
        } else {
            // Add new peripheral with RSSI
            discoveredPeripherals.append((peripheral: peripheral, rssi: RSSI.intValue))
        }
        
        if peripheral == selectedPeripheral {
            self.rssi = RSSI.intValue
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Connected to peripheral: %@", peripheral.name ?? "Unknown")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            os_log("Disconnected from peripheral with error: %@", error.localizedDescription)
        } else {
            os_log("Disconnected from peripheral")
        }
        
        if peripheral == selectedPeripheral {
            selectedPeripheral = nil
        }
    }
} 
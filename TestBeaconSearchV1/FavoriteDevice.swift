import Foundation
import CoreBluetooth

struct FavoriteDevice: Identifiable, Codable {
    let id: String // UUID string
    let originalName: String
    var customName: String?
    let dateAdded: Date
    
    // These properties won't be stored, just used for display
    var isConnected: Bool = false
    var rssi: Int = 0
    var batteryLevel: Int = -1 // -1 indicates unknown/unavailable
    
    var displayName: String {
        customName ?? originalName
    }
    
    enum CodingKeys: String, CodingKey {
        case id, originalName, dateAdded
    }
    
    init(peripheral: CBPeripheral) {
        self.id = peripheral.identifier.uuidString
        self.originalName = peripheral.name ?? "Unknown Device"
        self.dateAdded = Date()
    }
    
    func calculateDistance(measuredPower: Int, environmentalFactor: Double = 2.0) -> Double {
        let power = Double(measuredPower - rssi) / (10.0 * environmentalFactor)
        return pow(10.0, power)
    }
} 
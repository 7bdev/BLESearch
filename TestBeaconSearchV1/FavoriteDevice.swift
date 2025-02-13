import Foundation
import CoreBluetooth

struct FavoriteDevice: Identifiable, Codable {
    let id: String // UUID string
    let name: String
    let dateAdded: Date
    
    // These properties won't be stored, just used for display
    var isConnected: Bool = false
    var rssi: Int = 0
    
    enum CodingKeys: String, CodingKey {
        case id, name, dateAdded
    }
    
    init(peripheral: CBPeripheral) {
        self.id = peripheral.identifier.uuidString
        self.name = peripheral.name ?? "Unknown Device"
        self.dateAdded = Date()
    }
} 
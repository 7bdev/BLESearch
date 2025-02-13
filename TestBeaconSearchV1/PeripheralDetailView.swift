import SwiftUI
import CoreBluetooth

struct PeripheralDetailView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let peripheral: CBPeripheral
    
    var body: some View {
        List {
            Section("Device Info") {
                LabeledContent("Name", value: peripheral.name ?? "Unknown")
                LabeledContent("Identifier", value: peripheral.identifier.uuidString)
                LabeledContent("State", value: stateString)
                if let rssi = bluetoothManager.discoveredPeripherals.first(where: { $0.peripheral == peripheral })?.rssi {
                    LabeledContent("Signal Strength") {
                        HStack {
                            Text("\(rssi) dBm")
                            Text("•")
                            Text(String(format: "%.1fm", bluetoothManager.calculateDistance(rssi: rssi)))
                        }
                    }
                }
            }
            
            ForEach(bluetoothManager.discoveredServices, id: \.uuid) { service in
                Section {
                    if let characteristics = bluetoothManager.discoveredCharacteristics[service.uuid] {
                        ForEach(characteristics, id: \.uuid) { characteristic in
                            CharacteristicRow(
                                bluetoothManager: bluetoothManager,
                                peripheral: peripheral,
                                characteristic: characteristic
                            )
                        }
                    }
                } header: {
                    Text(service.uuid.uuidString)
                } footer: {
                    if let name = getServiceName(service.uuid) {
                        Text(name)
                    }
                }
            }
        }
        .navigationTitle("Device Details")
        .toolbar {
            Button(peripheral == bluetoothManager.selectedPeripheral ? "Disconnect" : "Connect") {
                if peripheral == bluetoothManager.selectedPeripheral {
                    bluetoothManager.disconnect()
                } else {
                    bluetoothManager.connect(to: peripheral)
                }
            }
        }
    }
    
    private var stateString: String {
        switch peripheral.state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting..."
        @unknown default: return "Unknown"
        }
    }
    
    private func getServiceName(_ uuid: CBUUID) -> String? {
        // Common BLE service names
        let services: [CBUUID: String] = [
            CBUUID(string: "180A"): "Device Information",
            CBUUID(string: "180F"): "Battery Service",
            CBUUID(string: "1800"): "Generic Access",
            CBUUID(string: "1801"): "Generic Attribute",
            // Add more as needed
        ]
        return services[uuid]
    }
}

struct CharacteristicRow: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let peripheral: CBPeripheral
    let characteristic: CBCharacteristic
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(characteristic.uuid.uuidString)
                .font(.subheadline)
            
            if let value = bluetoothManager.characteristicValues[characteristic.uuid] {
                Text("Value: \(formatCharacteristicValue(value))")
                    .font(.caption)
            }
            
            HStack {
                if characteristic.properties.contains(.read) {
                    Image(systemName: "book")
                }
                if characteristic.properties.contains(.write) {
                    Image(systemName: "pencil")
                }
                if characteristic.properties.contains(.notify) {
                    Image(systemName: "bell")
                }
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private func formatCharacteristicValue(_ data: Data) -> String {
        // Try to interpret the data in different formats
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        // Fallback to hex representation
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
} 
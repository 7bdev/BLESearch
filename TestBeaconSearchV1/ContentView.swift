//
//  ContentView.swift
//  TestBeaconSearchV1
//
//  Created by Primož Šilec on 12. 2. 25.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        NavigationView {
            VStack {
                // Status and controls
                HStack {
                    // Bluetooth status with icon
                    HStack {
                        Image(systemName: bluetoothStatusIcon)
                            .foregroundColor(bluetoothStatusColor)
                        
                        Text(stateText)
                            .foregroundColor(bluetoothStatusColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(bluetoothStatusColor.opacity(0.1))
                    .cornerRadius(15)
                    
                    Spacer()
                    
                    // Clear list button (only shows while scanning)
                    if bluetoothManager.isScanning {
                        Button {
                            bluetoothManager.discoveredPeripherals.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 8)
                    }
                    
                    Button {
                        if bluetoothManager.isScanning {
                            bluetoothManager.stopScanning()
                        } else {
                            bluetoothManager.startScanning()
                        }
                    } label: {
                        HStack {
                            Image(systemName: bluetoothManager.isScanning ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(bluetoothManager.isScanning ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                    }
                    .disabled(bluetoothManager.state != .poweredOn)
                    .opacity(bluetoothManager.state != .poweredOn ? 0.5 : 1.0)
                }
                .padding()
                
                // Error message
                if let error = bluetoothManager.error {
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                // Device list
                List {
                    // Favorites section
                    Section(header: Text("Favorites")) {
                        ForEach(bluetoothManager.discoveredPeripherals.filter { bluetoothManager.isFavorite($0.peripheral) },
                               id: \.peripheral.identifier) { discovered in
                            deviceRow(for: (peripheral: discovered.peripheral, rssi: discovered.rssi))
                        }
                    }
                    
                    // Other devices section
                    Section(header: Text("Other Devices")) {
                        ForEach(bluetoothManager.discoveredPeripherals.filter { !bluetoothManager.isFavorite($0.peripheral) },
                               id: \.peripheral.identifier) { discovered in
                            deviceRow(for: (peripheral: discovered.peripheral, rssi: discovered.rssi))
                        }
                    }
                }
                
                // Selected device info
                if let peripheral = bluetoothManager.selectedPeripheral {
                    VStack(spacing: 10) {
                        Text("Tracking: \(peripheral.name ?? "Unknown Device")")
                            .font(.headline)
                        
                        SignalStrengthView(rssi: bluetoothManager.rssi)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)
                    .padding()
                }
            }
            .navigationTitle("BLE Scanner")
            .toolbar {
                HStack {
                    NavigationLink(destination: FavoritesView(bluetoothManager: bluetoothManager)) {
                        Image(systemName: "star.fill")
                    }
                    
                    NavigationLink(destination: BatteryUsageView()) {
                        Image(systemName: "battery.100")
                    }
                }
            }
            .onAppear {
                if bluetoothManager.state == .poweredOn && !bluetoothManager.wasManuallyStopped {
                    bluetoothManager.startScanning()
                }
            }
            .onChange(of: bluetoothManager.state) { newState in
                if newState == .poweredOn {
                    bluetoothManager.error = nil
                    bluetoothManager.startScanning()
                }
            }
        }
    }
    
    private var stateText: String {
        switch bluetoothManager.state {
        case .poweredOn:
            return "Bluetooth is ready"
        case .poweredOff:
            return "Bluetooth is turned off"
        case .unauthorized:
            return "Bluetooth permission denied"
        case .unsupported:
            return "Bluetooth is not supported"
        default:
            return "Bluetooth is not available"
        }
    }
    
    private var bluetoothStatusIcon: String {
        switch bluetoothManager.state {
        case .poweredOn:
            return "bluetooth"
        case .poweredOff:
            return "bluetooth.slash"
        case .unauthorized:
            return "lock.shield"
        case .unsupported:
            return "xmark.circle"
        case .resetting:
            return "arrow.clockwise"
        default:
            return "questionmark.circle"
        }
    }
    
    private var bluetoothStatusColor: Color {
        switch bluetoothManager.state {
        case .poweredOn:
            return .blue
        case .poweredOff:
            return .red
        case .unauthorized:
            return .orange
        case .unsupported:
            return .red
        case .resetting:
            return .yellow
        default:
            return .gray
        }
    }
    
    // Helper function to create consistent device rows
    private func deviceRow(for discovered: (peripheral: CBPeripheral, rssi: Int)) -> some View {
        PeripheralRow(
            peripheral: discovered.peripheral,
            rssi: discovered.rssi,
            isSelected: discovered.peripheral == bluetoothManager.selectedPeripheral,
            isFavorite: bluetoothManager.isFavorite(discovered.peripheral),
            onFavoriteToggle: { bluetoothManager.toggleFavorite(for: discovered.peripheral) },
            bluetoothManager: bluetoothManager
        )
        .onTapGesture {
            if discovered.peripheral == bluetoothManager.selectedPeripheral {
                bluetoothManager.disconnect()
            } else {
                bluetoothManager.connect(to: discovered.peripheral)
            }
        }
    }
}

struct PeripheralRow: View {
    let peripheral: CBPeripheral
    let rssi: Int
    let isSelected: Bool
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(peripheral.name ?? "Unknown Device")
                    .font(.headline)
                HStack {
                    if isAppleDevice(peripheral) {
                        Image(systemName: "apple.logo")
                            .foregroundColor(.gray)
                    }
                    Text(peripheral.identifier.uuidString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let discovered = bluetoothManager.discoveredPeripherals.first(where: { $0.peripheral == peripheral }),
                   let systemId = discovered.systemId {
                    Text("MAC: \(systemId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("\(rssi) dBm")
                    Text("•")
                    Image(systemName: "ruler")
                    Text(String(format: "%.1fm", bluetoothManager.calculateDistance(rssi: rssi)))
                    if let favorite = bluetoothManager.favoriteDevices.first(where: { $0.id == peripheral.identifier.uuidString }),
                       favorite.batteryLevel >= 0 {
                        Text("•")
                        Image(systemName: batteryIcon(level: favorite.batteryLevel))
                        Text("\(favorite.batteryLevel)%")
                            .foregroundColor(batteryColor(level: favorite.batteryLevel))
                    }
                }
                .font(.caption)
                .foregroundColor(signalColor)
            }
            
            Spacer()
            
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
            }
            .buttonStyle(BorderlessButtonStyle())
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }
    
    private var signalColor: Color {
        let strength = abs(rssi)
        switch strength {
        case 0...50:  // Excellent signal
            return .green
        case 51...70:  // Good signal
            return .blue
        case 71...90:  // Fair signal
            return .orange
        default:      // Poor signal
            return .red
        }
    }
    
    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0...20: return "battery.0"
        case 21...40: return "battery.25"
        case 41...60: return "battery.50"
        case 61...80: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func batteryColor(level: Int) -> Color {
        switch level {
        case 0...20: return .red
        case 21...40: return .orange
        default: return .green
        }
    }
    
    private func isAppleDevice(_ peripheral: CBPeripheral) -> Bool {
        // Check if the name starts with common Apple device prefixes
        let appleDevicePrefixes = ["iPhone", "iPad", "iPod", "Watch", "MacBook", "iMac", "Mac"]
        if let name = peripheral.name {
            return appleDevicePrefixes.contains { name.starts(with: $0) }
        }
        return false
    }
}

struct SignalStrengthView: View {
    let rssi: Int
    
    var body: some View {
        HStack {
            Text("Signal Strength:")
            
            // RSSI bars
            HStack(spacing: 2) {
                ForEach(0..<4) { index in
                    Rectangle()
                        .fill(barColor(for: index))
                        .frame(width: 20, height: CGFloat(index + 1) * 10)
                }
            }
            
            Text("\(rssi) dBm")
                .font(.caption)
        }
    }
    
    private func barColor(for index: Int) -> Color {
        let strength = abs(rssi)
        let threshold = 60 + (index * 10)
        return strength < threshold ? .blue : .gray.opacity(0.3)
    }
}

#Preview {
    ContentView()
}

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
                    
                    Button {
                        if bluetoothManager.isScanning {
                            bluetoothManager.stopScanning()
                        } else {
                            bluetoothManager.startScanning()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text(bluetoothManager.isScanning ? "Stop Scanning" : "Start Scanning")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(bluetoothManager.isScanning ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                    }
                    .disabled(bluetoothManager.state != .poweredOn)
                    .opacity(bluetoothManager.state != .poweredOn ? 0.5 : 1.0)
                }
                .padding()
                
                // Device list
                List {
                    // Favorites section
                    Section(header: Text("Favorites")) {
                        ForEach(bluetoothManager.discoveredPeripherals.filter { bluetoothManager.isFavorite($0.peripheral) },
                               id: \.peripheral.identifier) { discovered in
                            deviceRow(for: discovered)
                        }
                    }
                    
                    // Other devices section
                    Section(header: Text("Other Devices")) {
                        ForEach(bluetoothManager.discoveredPeripherals.filter { !bluetoothManager.isFavorite($0.peripheral) },
                               id: \.peripheral.identifier) { discovered in
                            deviceRow(for: discovered)
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
                NavigationLink(destination: FavoritesView(bluetoothManager: bluetoothManager)) {
                    Image(systemName: "star.fill")
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
                Text(peripheral.identifier.uuidString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("\(rssi) dBm")
                    Text("•")
                    Image(systemName: "ruler")
                    Text(String(format: "%.1fm", bluetoothManager.calculateDistance(rssi: rssi)))
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

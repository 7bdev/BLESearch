import SwiftUI
import CoreBluetooth

struct FavoritesView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var sortOption: SortOption = .name
    @State private var showingSortSheet = false
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateAdded = "Date Added"
        case signalStrength = "Signal Strength"
        case distance = "Distance"
        case connectionStatus = "Connection Status"
        
        var icon: String {
            switch self {
            case .name: return "textformat"
            case .dateAdded: return "calendar"
            case .signalStrength: return "antenna.radiowaves.left.and.right"
            case .distance: return "ruler"
            case .connectionStatus: return "dot.radiowaves.left.and.right"
            }
        }
    }
    
    var body: some View {
        List {
            Section {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Label(option.rawValue, systemImage: option.icon)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Sort Options")
            }
            
            Section {
                ForEach(sortedDevices) { favorite in
                    FavoriteDeviceRow(
                        favorite: favorite,
                        isConnected: isDeviceConnected(favorite),
                        rssi: getRSSI(favorite),
                        bluetoothManager: bluetoothManager
                    )
                }
                .onDelete(perform: deleteFavorites)
            } header: {
                Text("Favorite Devices")
            }
        }
        .navigationTitle("Favorites")
        .toolbar {
            EditButton()
        }
    }
    
    private var sortedDevices: [FavoriteDevice] {
        bluetoothManager.favoriteDevices.sorted { first, second in
            switch sortOption {
            case .name:
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                
            case .dateAdded:
                return first.dateAdded > second.dateAdded
                
            case .signalStrength:
                let firstRSSI = getRSSI(first)
                let secondRSSI = getRSSI(second)
                return firstRSSI > secondRSSI
                
            case .distance:
                let firstRSSI = getRSSI(first)
                let secondRSSI = getRSSI(second)
                let firstDistance = bluetoothManager.calculateDistance(rssi: firstRSSI)
                let secondDistance = bluetoothManager.calculateDistance(rssi: secondRSSI)
                return firstDistance < secondDistance
                
            case .connectionStatus:
                let firstConnected = isDeviceConnected(first)
                let secondConnected = isDeviceConnected(second)
                if firstConnected == secondConnected {
                    // If connection status is the same, sort by name
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
                return firstConnected && !secondConnected
            }
        }
    }
    
    private func isDeviceConnected(_ favorite: FavoriteDevice) -> Bool {
        bluetoothManager.selectedPeripheral?.identifier.uuidString == favorite.id
    }
    
    private func getRSSI(_ favorite: FavoriteDevice) -> Int {
        if let discovered = bluetoothManager.discoveredPeripherals.first(where: { $0.peripheral.identifier.uuidString == favorite.id }) {
            return discovered.rssi
        }
        return 0
    }
    
    private func deleteFavorites(at offsets: IndexSet) {
        bluetoothManager.favoriteDevices.remove(atOffsets: offsets)
        bluetoothManager.saveFavorites()
    }
}

struct FavoriteDeviceRow: View {
    let favorite: FavoriteDevice
    let isConnected: Bool
    let rssi: Int
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(favorite.name)
                    .font(.headline)
                Text(favorite.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Added: \(favorite.dateAdded.formatted())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Connection status
                HStack {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(isConnected ? .green : .red)
                }
                
                // Signal strength
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("\(rssi) dBm")
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                // Distance
                HStack(spacing: 4) {
                    Image(systemName: "ruler")
                    Text(String(format: "%.1fm", bluetoothManager.calculateDistance(rssi: rssi)))
                }
                .font(.caption)
                .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
} 
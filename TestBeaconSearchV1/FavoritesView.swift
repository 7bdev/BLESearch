import SwiftUI
import CoreBluetooth

struct FavoritesView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var sortOption: SortOption = .nameAsc
    @State private var showingSortSheet = false
    @State private var showingTimeoutSettings = false
    
    enum SortOption: String, CaseIterable {
        case nameAsc = "Name (A to Z)"
        case nameDesc = "Name (Z to A)"
        case distance = "Distance"
    }
    
    var body: some View {
        ZStack {
            // Background color
            if allDevicesActive {
                Color.green.opacity(0.3).ignoresSafeArea()
            }
            
            List {
                Section {
                    // Device counts
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Favorites: \(bluetoothManager.favoriteDevices.count)")
                            .font(.system(size: 14))
                        Text("Active Devices: \(activeDevicesCount)")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                    
                    Picker("Sort by", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue)
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
                            rssi: getRSSI(favorite),
                            bluetoothManager: bluetoothManager
                        )
                    }
                    .onDelete(perform: deleteFavorites)
                } header: {
                    Text("Favorite Devices")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Favorites")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    if bluetoothManager.isScanning {
                        bluetoothManager.stopScanning()
                    } else {
                        bluetoothManager.startScanning()
                    }
                } label: {
                    Image(systemName: bluetoothManager.isScanning ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(bluetoothManager.isScanning ? .red : .green)
                }
                .disabled(bluetoothManager.state != .poweredOn)
                
                Button {
                    showingTimeoutSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                
                EditButton()
            }
        }
        .sheet(isPresented: $showingTimeoutSettings) {
            TimeoutSettingsView(timeoutInterval: $bluetoothManager.timeoutInterval, bluetoothManager: bluetoothManager)
        }
        .onAppear {
            // Start checking status when view appears
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                bluetoothManager.checkFavoritesStatus()
            }
        }
    }
    
    private var sortedDevices: [FavoriteDevice] {
        bluetoothManager.favoriteDevices.sorted { first, second in
            switch sortOption {
            case .nameAsc:
                return first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
            case .nameDesc:
                return first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedDescending
            case .distance:
                let firstRSSI = getRSSI(first)
                let secondRSSI = getRSSI(second)
                let firstDistance = bluetoothManager.calculateDistance(rssi: firstRSSI)
                let secondDistance = bluetoothManager.calculateDistance(rssi: secondRSSI)
                return firstDistance < secondDistance
            }
        }
    }
    
    private func isDeviceConnected(_ favorite: FavoriteDevice) -> Bool {
        bluetoothManager.selectedPeripheral?.identifier.uuidString == favorite.id
    }
    
    private func getRSSI(_ favorite: FavoriteDevice) -> Int {
        // Return 0 if not scanning
        guard bluetoothManager.isScanning else { return 0 }
        
        if let discovered = bluetoothManager.discoveredPeripherals.first(where: { 
            $0.peripheral.identifier.uuidString == favorite.id &&
            Date().timeIntervalSince($0.lastUpdate) <= bluetoothManager.timeoutInterval
        }) {
            return discovered.rssi
        }
        return 0
    }
    
    private func deleteFavorites(at offsets: IndexSet) {
        bluetoothManager.favoriteDevices.remove(atOffsets: offsets)
        bluetoothManager.saveFavorites()
    }
    
    // Helper computed property to count active devices (connected or in range)
    private var activeDevicesCount: Int {
        // If not scanning, return 0
        if !bluetoothManager.isScanning {
            return 0
        }
        
        return bluetoothManager.favoriteDevices.filter { favorite in
            // If not scanning, no devices are active
            if let discovered = bluetoothManager.discoveredPeripherals.first(where: { $0.peripheral.identifier.uuidString == favorite.id }) {
                // Device is either connected or has recent RSSI updates
                return isDeviceConnected(favorite) || 
                       Date().timeIntervalSince(discovered.lastUpdate) <= bluetoothManager.timeoutInterval
            }
            return false
        }.count
    }
    
    private var allDevicesActive: Bool {
        if !bluetoothManager.isScanning {
            return false
        }
        return !bluetoothManager.favoriteDevices.isEmpty && 
               activeDevicesCount == bluetoothManager.favoriteDevices.count
    }
}

struct FavoriteDeviceRow: View {
    let favorite: FavoriteDevice
    let rssi: Int
    @ObservedObject var bluetoothManager: BluetoothManager
    @State private var isEditingName = false
    @State private var customName = ""
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if isEditingName {
                    TextField("Device name", text: $customName)
                        .font(.headline)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveCustomName()
                        }
                } else {
                    Text(favorite.displayName)
                        .font(.headline)
                        .onTapGesture(count: 2) {
                            customName = favorite.customName ?? favorite.originalName
                            isEditingName = true
                        }
                }
                HStack {
                    if isAppleDevice(favorite.originalName) {
                        Image(systemName: "apple.logo")
                            .foregroundColor(.gray)
                    }
                    Text(favorite.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if favorite.customName != nil {
                    Text("Original: \(favorite.originalName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("Added: \(favorite.dateAdded.formatted())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if isEditingName {
                    Button(action: saveCustomName) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                // Connection status
                HStack {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                    Text(status.text)
                        .font(.caption)
                        .foregroundColor(status.color)
                }
                
                // Signal strength
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("\(rssi) dBm")
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                // Battery level
                if favorite.batteryLevel >= 0 {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon)
                        Text("\(favorite.batteryLevel)%")
                    }
                    .font(.caption)
                    .foregroundColor(batteryColor)
                }
                
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
    
    private var status: (text: String, color: Color) {
        // Always show Disconn when not scanning
        guard bluetoothManager.isScanning else {
            return ("Disconn", .red)
        }
        
        if isDeviceConnected {
            return ("Connected", .green)
        } else if let discovered = bluetoothManager.discoveredPeripherals.first(where: { $0.peripheral.identifier.uuidString == favorite.id }) {
            // Check if the last update was within the timeout period
            let timeSinceLastUpdate = Date().timeIntervalSince(discovered.lastUpdate)
            if timeSinceLastUpdate <= bluetoothManager.timeoutInterval {
                return ("In Range", .blue)
            } else {
                return ("Disconn", .red)
            }
        } else {
            return ("Disconn", .red)
        }
    }
    
    private var isDeviceConnected: Bool {
        bluetoothManager.selectedPeripheral?.identifier.uuidString == favorite.id
    }
    
    private func saveCustomName() {
        if !customName.isEmpty && customName != favorite.originalName {
            bluetoothManager.updateDeviceName(id: favorite.id, newName: customName)
        }
        isEditingName = false
    }
    
    private var batteryIcon: String {
        switch favorite.batteryLevel {
        case 0...20: return "battery.0"
        case 21...40: return "battery.25"
        case 41...60: return "battery.50"
        case 61...80: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private var batteryColor: Color {
        switch favorite.batteryLevel {
        case 0...20: return .red
        case 21...40: return .orange
        default: return .green
        }
    }
    
    private func isAppleDevice(_ name: String) -> Bool {
        let appleDevicePrefixes = ["iPhone", "iPad", "iPod", "Watch", "MacBook", "iMac", "Mac"]
        return appleDevicePrefixes.contains { name.starts(with: $0) }
    }
}

struct TimeoutSettingsView: View {
    @Binding var timeoutInterval: TimeInterval
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Status Change Interval")) {
                    Slider(
                        value: $timeoutInterval,
                        in: 1...60,
                        step: 1
                    ) {
                        Text("Status Change Interval")
                    } minimumValueLabel: {
                        Text("1s")
                    } maximumValueLabel: {
                        Text("60s")
                    }
                    
                    Text("Current interval: \(Int(timeoutInterval)) seconds")
                }
                
                Section(header: Text("Notifications")) {
                    Toggle("Background Notifications", isOn: $bluetoothManager.notificationsEnabled)
                    Text("Show notifications when device status changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Status Change Settings")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
} 
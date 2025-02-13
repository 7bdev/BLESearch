import Foundation
import UIKit

struct BatteryUsageEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let usagePercentage: Double
    let duration: TimeInterval
    
    init(usagePercentage: Double, duration: TimeInterval) {
        self.id = UUID()
        self.date = Date()
        self.usagePercentage = usagePercentage
        self.duration = duration
    }
}

class BatteryUsageManager: ObservableObject {
    @Published var usageHistory: [BatteryUsageEntry] = []
    private let storageKey = "BatteryUsageHistory"
    private var startTime: Date?
    private var startLevel: Float?
    
    init() {
        loadHistory()
        startTracking()
    }
    
    private func startTracking() {
        startTime = Date()
        startLevel = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    func recordCurrentUsage() {
        guard let startTime = startTime,
              let startLevel = startLevel else { return }
        
        let currentLevel = UIDevice.current.batteryLevel
        let duration = Date().timeIntervalSince(startTime)
        let usagePercentage = Double(startLevel - currentLevel) * 100
        
        if usagePercentage > 0 {
            let entry = BatteryUsageEntry(usagePercentage: usagePercentage, duration: duration)
            usageHistory.append(entry)
            saveHistory()
        }
        
        // Reset tracking
        self.startTime = Date()
        self.startLevel = currentLevel
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(usageHistory) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BatteryUsageEntry].self, from: data) {
            usageHistory = decoded
        }
    }
    
    func clearHistory() {
        usageHistory.removeAll()
        saveHistory()
    }
} 
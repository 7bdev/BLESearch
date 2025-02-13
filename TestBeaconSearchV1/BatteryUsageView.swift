//
//  BatteryUsageView.swift
//  TestBeaconSearchV1
//
//  Created by Primož Šilec on 13. 2. 25.
//

import SwiftUI
import Charts

struct BatteryUsageView: View {
    @StateObject private var batteryManager = BatteryUsageManager()
    @State private var timeRange: TimeRange = .week
    
    enum TimeRange {
        case day, week, month, all
        
        var text: String {
            switch self {
            case .day: return "24 Hours"
            case .week: return "Week"
            case .month: return "Month"
            case .all: return "All Time"
            }
        }
        
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .all: return 365
            }
        }
    }
    
    var body: some View {
        List {
            Section {
                Picker("Time Range", selection: $timeRange) {
                    Text("24 Hours").tag(TimeRange.day)
                    Text("Week").tag(TimeRange.week)
                    Text("Month").tag(TimeRange.month)
                    Text("All Time").tag(TimeRange.all)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Chart(filteredUsage) { entry in
                        BarMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Usage", entry.usagePercentage)
                        )
                        .foregroundStyle(Color.blue.gradient)
                    }
                    .frame(height: 200)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day())
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Average Usage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", averageUsage))
                                .font(.title2)
                                .bold()
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Total Time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(totalTimeFormatted)
                                .font(.title2)
                                .bold()
                        }
                    }
                    .padding(.top)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Battery Usage")
            }
        }
        .navigationTitle("Battery Usage")
        .toolbar {
            Button("Clear", role: .destructive) {
                batteryManager.clearHistory()
            }
        }
        .onAppear {
            batteryManager.recordCurrentUsage()
        }
        .onDisappear {
            batteryManager.recordCurrentUsage()
        }
    }
    
    private var filteredUsage: [BatteryUsageEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date()) ?? Date()
        return batteryManager.usageHistory.filter { $0.date >= cutoff }
    }
    
    private var averageUsage: Double {
        guard !filteredUsage.isEmpty else { return 0 }
        let total = filteredUsage.reduce(0) { $0 + $1.usagePercentage }
        return total / Double(filteredUsage.count)
    }
    
    private var totalTimeFormatted: String {
        let total = filteredUsage.reduce(0) { $0 + $1.duration }
        let hours = Int(total / 3600)
        let minutes = Int((total.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}

#Preview {
    NavigationView {
        BatteryUsageView()
    }
}

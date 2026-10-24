import Foundation
import SwiftUI
import Combine

@MainActor
class CalibrationManager: ObservableObject {
    static let shared = CalibrationManager()
    
    // Offset in seconds.
    // Positive means notes are hit late (after the hit line).
    // Negative means notes are hit early (before the hit line).
    @Published var visualOffset: TimeInterval = 0.0
    @Published private(set) var sampleCount: Int = 0
    
    // Store multiple hit offsets to calculate a rolling average during calibration routine
    private var hitOffsets: [TimeInterval] = []
    private let defaultsKey = "visualOffset"
    
    private init() {
        self.visualOffset = UserDefaults.standard.double(forKey: defaultsKey)
    }
    
    func saveOffset(_ offset: TimeInterval) {
        let clamped = max(-0.2, min(0.2, offset))
        self.visualOffset = clamped
        UserDefaults.standard.set(clamped, forKey: defaultsKey)
    }
    
    func recordCalibrationHit(targetTime: TimeInterval, actualTime: TimeInterval) {
        recordCalibrationOffset(actualTime - targetTime)
    }
    
    func recordCalibrationOffset(_ offset: TimeInterval) {
        // Ignore extreme outliers (> 250ms) when auto-calibrating
        guard abs(offset) <= 0.25 else { return }
        
        hitOffsets.append(offset)
        if hitOffsets.count > 10 {
            hitOffsets.removeFirst()
        }
        sampleCount = hitOffsets.count
        
        let average = hitOffsets.reduce(0, +) / Double(hitOffsets.count)
        saveOffset(average)
    }
    
    func clearHistory() {
        hitOffsets.removeAll()
        sampleCount = 0
    }
}

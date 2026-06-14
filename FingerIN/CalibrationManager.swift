import Foundation
import SwiftUI
import Combine

class CalibrationManager: ObservableObject {
    static let shared = CalibrationManager()
    
    // Offset in seconds. 
    // Positive means notes appear to be hitting late (user is hitting after the line).
    // Negative means notes appear to be hitting early.
    @Published var visualOffset: TimeInterval = 0.0
    
    // Store multiple hit offsets to calculate average during calibration routine
    private var hitOffsets: [TimeInterval] = []
    
    private init() {
        // Load saved calibration from UserDefaults if needed
        self.visualOffset = UserDefaults.standard.double(forKey: "visualOffset")
    }
    
    func saveOffset(_ offset: TimeInterval) {
        self.visualOffset = offset
        UserDefaults.standard.set(offset, forKey: "visualOffset")
    }
    
    func recordCalibrationHit(targetTime: TimeInterval, actualTime: TimeInterval) {
        let offset = actualTime - targetTime
        hitOffsets.append(offset)
        
        // Keep only last 10 hits for average
        if hitOffsets.count > 10 {
            hitOffsets.removeFirst()
        }
        
        // Update recommended offset based on average
        let average = hitOffsets.reduce(0, +) / Double(hitOffsets.count)
        self.visualOffset = average
    }
    
    func clearHistory() {
        hitOffsets.removeAll()
    }
}

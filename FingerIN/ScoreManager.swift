import Foundation
import SwiftUI
import Combine

enum HitAccuracy: String {
    case perfect = "PERFECT"
    case good = "GOOD"
    case miss = "MISS"
    
    var points: Int {
        switch self {
        case .perfect: return 100
        case .good: return 50
        case .miss: return 0
        }
    }
    
    var color: Color {
        switch self {
        case .perfect: return .cyan
        case .good: return .green
        case .miss: return .red
        }
    }
}

@MainActor
class ScoreManager: ObservableObject {
    static let shared = ScoreManager()
    
    @Published var score: Int = 0
    @Published var streak: Int = 0
    @Published var maxStreak: Int = 0
    @Published var perfectCount: Int = 0
    @Published var goodCount: Int = 0
    @Published var missCount: Int = 0
    @Published var lastAccuracy: HitAccuracy?
    /// Signed timing offset in milliseconds (negative = EARLY, positive = LATE)
    @Published var lastTimingOffsetMs: Int?
    
    var totalJudgedNotes: Int {
        perfectCount + goodCount + missCount
    }
    
    var multiplier: Int {
        switch streak {
        case 0..<10: return 1
        case 10..<25: return 2
        case 25..<50: return 3
        default: return 4
        }
    }
    
    var accuracyPercentage: Double {
        guard totalJudgedNotes > 0 else { return 100.0 }
        let weighted = (Double(perfectCount) * 1.0) + (Double(goodCount) * 0.65)
        return (weighted / Double(totalJudgedNotes)) * 100.0
    }
    
    private init() {}
    
    func registerHit(accuracy: HitAccuracy, timingOffsetMs: Int? = nil) {
        self.lastAccuracy = accuracy
        self.lastTimingOffsetMs = timingOffsetMs
        
        switch accuracy {
        case .perfect:
            self.perfectCount += 1
            self.streak += 1
            self.maxStreak = max(self.maxStreak, self.streak)
            self.score += accuracy.points * self.multiplier
        case .good:
            self.goodCount += 1
            self.streak += 1
            self.maxStreak = max(self.maxStreak, self.streak)
            self.score += accuracy.points * self.multiplier
        case .miss:
            self.missCount += 1
            self.streak = 0
        }
    }
    
    func reset() {
        self.score = 0
        self.streak = 0
        self.maxStreak = 0
        self.perfectCount = 0
        self.goodCount = 0
        self.missCount = 0
        self.lastAccuracy = nil
        self.lastTimingOffsetMs = nil
    }
}

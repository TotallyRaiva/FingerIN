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

class ScoreManager: ObservableObject {
    static let shared = ScoreManager()
    
    @Published var score: Int = 0
    @Published var streak: Int = 0
    @Published var lastAccuracy: HitAccuracy?
    
    private init() {}
    
    func registerHit(accuracy: HitAccuracy) {
        DispatchQueue.main.async {
            self.lastAccuracy = accuracy
            if accuracy == .miss {
                self.streak = 0
            } else {
                self.streak += 1
                self.score += accuracy.points
            }
        }
    }
    
    func reset() {
        DispatchQueue.main.async {
            self.score = 0
            self.streak = 0
            self.lastAccuracy = nil
        }
    }
}

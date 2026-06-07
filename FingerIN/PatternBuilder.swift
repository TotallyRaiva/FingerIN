import Foundation

/// Represents a single note hit in the game
struct TrackNote: Identifiable {
    let id = UUID()
    let padIndex: UInt8
    let timeSeconds: TimeInterval
}

/// Utility to convert 16-step patterns into time-indexed TrackNotes
struct PatternBuilder {
    
    /// Builds a list of TrackNotes from 16-step sequences
    /// - Parameters:
    ///   - bpm: Beats per minute
    ///   - kick: 16-step array for Kick (Note 12)
    ///   - snare: 16-step array for Snare (Note 13)
    ///   - hatC: 16-step array for Closed Hat (Note 14)
    ///   - hatO: 16-step array for Open Hat (Note 15)
    static func build(bpm: Double, kick: [Int], snare: [Int], hatC: [Int], hatO: [Int]) -> [TrackNote] {
        let secondsPerBeat = 60.0 / bpm
        let sixteenthNoteDuration = secondsPerBeat / 4.0 // 16 steps per 4 beats (1 bar)
        
        var allNotes: [TrackNote] = []
        
        let patterns: [UInt8: [Int]] = [
            12: kick,
            13: snare,
            14: hatC,
            15: hatO
        ]
        
        for (pad, steps) in patterns {
            for (index, hit) in steps.enumerated() {
                if hit == 1 {
                    let time = Double(index) * sixteenthNoteDuration
                    allNotes.append(TrackNote(padIndex: pad, timeSeconds: time))
                }
            }
        }
        
        // Return sorted by time
        return allNotes.sorted { $0.timeSeconds < $1.timeSeconds }
    }
}

/// Provides pre-defined drum patterns for the game
struct LevelProvider {
    
    static var rockPattern: [TrackNote] {
        return PatternBuilder.build(
            bpm: 120,
            kick:  [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
            snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
            hatC:  [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
            hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
        )
    }
    
    static var housePattern: [TrackNote] {
        return PatternBuilder.build(
            bpm: 128,
            kick:  [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
            snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
            hatC:  [1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1],
            hatO:  [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0]
        )
    }
    
    static var boomBapPattern: [TrackNote] {
        return PatternBuilder.build(
            bpm: 90,
            kick:  [1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0],
            snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0],
            hatC:  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
        )
    }
}

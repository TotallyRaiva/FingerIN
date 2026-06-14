import Foundation

/// Represents a single note hit in the game
struct TrackNote: Identifiable {
    let id = UUID()
    let padIndex: UInt8
    let timeSeconds: TimeInterval
}

/// Utility to convert 16-step patterns into time-indexed TrackNotes
struct PatternBuilder {
    
    /// Builds a list of TrackNotes from 16-step sequences with filtering
    static func build(
        bpm: Double,
        activePads: Set<UInt8>,
        kick: [Int],
        snare: [Int],
        hatC: [Int],
        hatO: [Int]
    ) -> (notes: [TrackNote], barDuration: TimeInterval) {
        let secondsPerBeat = 60.0 / bpm
        let barDuration = secondsPerBeat * 4.0
        let sixteenthNoteDuration = secondsPerBeat / 4.0
        
        var allNotes: [TrackNote] = []
        
        let patterns: [UInt8: [Int]] = [
            12: kick,
            13: snare,
            14: hatC,
            15: hatO
        ]
        
        for (pad, steps) in patterns {
            // Complexity Mode: Only add notes if the pad is active
            if activePads.contains(pad) {
                for (index, hit) in steps.enumerated() {
                    if hit == 1 {
                        let time = Double(index) * sixteenthNoteDuration
                        allNotes.append(TrackNote(padIndex: pad, timeSeconds: time))
                    }
                }
            }
        }
        
        let sortedNotes = allNotes.sorted { $0.timeSeconds < $1.timeSeconds }
        return (notes: sortedNotes, barDuration: barDuration)
    }
}

/// Provides pre-defined drum patterns for the game
struct LevelProvider {
    
    struct PatternTemplate: Equatable {
        let bpm: Double
        let kick: [Int]
        let snare: [Int]
        let hatC: [Int]
        let hatO: [Int]
    }
    
    static let rock = PatternTemplate(
        bpm: 120,
        kick:  [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
        snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
        hatC:  [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    )
    
    static let house = PatternTemplate(
        bpm: 128,
        kick:  [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
        snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
        hatC:  [1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1],
        hatO:  [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0]
    )
    
    static let boomBap = PatternTemplate(
        bpm: 90,
        kick:  [1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0],
        hatC:  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
    )
    
    static let calibration = PatternTemplate(
        bpm: 100,
        kick:  [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
        snare: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        hatC:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    )
}

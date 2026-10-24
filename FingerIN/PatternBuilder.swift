import Foundation

/// Represents a single note hit in the game
struct TrackNote: Identifiable, Equatable {
    let id = UUID()
    let padIndex: UInt8
    let stepIndex: Int
    let timeSeconds: TimeInterval
    let velocity: UInt8
    
    init(padIndex: UInt8, stepIndex: Int = 0, timeSeconds: TimeInterval, velocity: UInt8 = 100) {
        self.padIndex = padIndex
        self.stepIndex = stepIndex
        self.timeSeconds = timeSeconds
        self.velocity = velocity
    }
}

/// Utility to convert 16-step (or multi-bar) patterns into time-indexed TrackNotes
struct PatternBuilder {
    
    /// Maps step values (1 = standard, 2 = ghost note, 3 = accent) to MIDI velocity
    static func velocity(forStepValue value: Int) -> UInt8? {
        switch value {
        case 1: return 100
        case 2: return 55   // Ghost note
        case 3: return 122  // Accent
        default: return nil
        }
    }
    
    /// Builds a list of TrackNotes from step sequences with active pad filtering
    static func build(
        bpm: Double,
        activePads: Set<UInt8>,
        kick: [Int],
        snare: [Int],
        hatC: [Int],
        hatO: [Int]
    ) -> (notes: [TrackNote], barDuration: TimeInterval) {
        let safeBPM = max(30.0, bpm)
        let secondsPerBeat = 60.0 / safeBPM
        let stepCount = max(16, max(kick.count, max(snare.count, max(hatC.count, hatO.count))))
        let sixteenthNoteDuration = secondsPerBeat / 4.0
        let barDuration = Double(stepCount) * sixteenthNoteDuration
        
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
                for (index, hitValue) in steps.enumerated() {
                    if let velocity = velocity(forStepValue: hitValue) {
                        let time = Double(index) * sixteenthNoteDuration
                        allNotes.append(
                            TrackNote(
                                padIndex: pad,
                                stepIndex: index,
                                timeSeconds: time,
                                velocity: velocity
                            )
                        )
                    }
                }
            }
        }
        
        let sortedNotes = allNotes.sorted {
            if $0.timeSeconds == $1.timeSeconds {
                return $0.padIndex < $1.padIndex
            }
            return $0.timeSeconds < $1.timeSeconds
        }
        return (notes: sortedNotes, barDuration: barDuration)
    }
}

/// Provides pre-defined drum patterns for the game
struct LevelProvider {
    
    struct PatternTemplate: Equatable, Identifiable {
        var id: String { name }
        let name: String
        let bpm: Double
        let kick: [Int]
        let snare: [Int]
        let hatC: [Int]
        let hatO: [Int]
        var isCalibration: Bool = false
    }
    
    static let rock = PatternTemplate(
        name: "ROCK",
        bpm: 120,
        kick:  [3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0],
        hatC:  [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    )
    
    static let house = PatternTemplate(
        name: "HOUSE",
        bpm: 128,
        kick:  [3, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0],
        hatC:  [1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2],
        hatO:  [0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0]
    )
    
    static let boomBap = PatternTemplate(
        name: "BOOM BAP",
        bpm: 90,
        kick:  [3, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 1, 3, 0, 0, 2],
        hatC:  [1, 2, 1, 2, 1, 2, 1, 0, 1, 2, 1, 2, 1, 2, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
    )
    
    static let funk = PatternTemplate(
        name: "FUNK",
        bpm: 105,
        kick:  [3, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 2, 2],
        hatC:  [3, 2, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 2, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
    )
    
    static let calibration = PatternTemplate(
        name: "CALIB",
        bpm: 100,
        kick:  [3, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
        snare: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        hatC:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        isCalibration: true
    )
    
    static let allTemplates: [PatternTemplate] = [
        rock,
        house,
        boomBap,
        funk,
        calibration
    ]
}

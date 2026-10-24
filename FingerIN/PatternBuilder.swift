import Foundation

/// Available studio & electronic drum kits
enum DrumKit: String, CaseIterable, Identifiable, Equatable {
    case studioAcoustic = "STUDIO"
    case mpcLoFi = "MPC LO-FI"
    case club909 = "CLUB 909"
    case trap808 = "808 TRAP"
    case funkBreak = "FUNK BREAK"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
}

/// Represents a single drum note hit in the timeline
struct TrackNote: Identifiable, Equatable {
    let id = UUID()
    let padIndex: UInt8
    let stepIndex: Int
    /// Fractional 16th-note swing offset (0.0 for straight steps, 0.0...0.35 for swung off-beats)
    let stepOffsetRatio: Double
    let timeSeconds: TimeInterval
    let velocity: UInt8
    
    init(
        padIndex: UInt8,
        stepIndex: Int = 0,
        stepOffsetRatio: Double = 0.0,
        timeSeconds: TimeInterval,
        velocity: UInt8 = 100
    ) {
        self.padIndex = padIndex
        self.stepIndex = stepIndex
        self.stepOffsetRatio = stepOffsetRatio
        self.timeSeconds = timeSeconds
        self.velocity = velocity
    }
}

/// Represents a musical accompaniment event (bass note and/or chord voices) on a 16th-note step
struct BackingStepEvent: Equatable {
    let stepIndex: Int
    /// Bass MIDI note (e.g., 36 = C2) and duration in 16th steps
    let bassMIDINote: UInt8?
    let bassDurationSteps: Double
    /// Chord MIDI notes (e.g., Rhodes / Synth pad voicing) and duration in 16th steps
    let chordMIDINotes: [UInt8]
    let chordDurationSteps: Double
}

/// Utility to convert 16-step or 32-step (2-bar) patterns into time-indexed TrackNotes with swing
struct PatternBuilder {
    
    /// Maps step values (1 = standard, 2 = ghost note, 3 = accent) to MIDI velocity
    static func velocity(forStepValue value: Int) -> UInt8? {
        switch value {
        case 1: return 98
        case 2: return 52   // Expressive ghost note
        case 3: return 124  // Rimshot / heavy accent
        default: return nil
        }
    }
    
    /// Builds a list of TrackNotes from step sequences with active pad filtering and swing
    static func build(
        bpm: Double,
        activePads: Set<UInt8>,
        kick: [Int],
        snare: [Int],
        hatC: [Int],
        hatO: [Int],
        swing: Double = 0.0
    ) -> (notes: [TrackNote], barDuration: TimeInterval, totalSteps: Int) {
        let safeBPM = max(30.0, bpm)
        let secondsPerBeat = 60.0 / safeBPM
        let totalSteps = max(16, max(kick.count, max(snare.count, max(hatC.count, hatO.count))))
        let sixteenthNoteDuration = secondsPerBeat / 4.0
        // Single 4/4 bar duration (4 beats = 16 sixteenth notes)
        let singleBarDuration = secondsPerBeat * 4.0
        let clampedSwing = max(0.0, min(0.38, swing))
        
        var allNotes: [TrackNote] = []
        
        let patterns: [UInt8: [Int]] = [
            12: kick,
            13: snare,
            14: hatC,
            15: hatO
        ]
        
        for (pad, steps) in patterns {
            if activePads.contains(pad) {
                for (index, hitValue) in steps.enumerated() {
                    if let velocity = velocity(forStepValue: hitValue) {
                        // Apply MPC-style 16th-note swing to odd-numbered steps
                        let swingRatio = (index % 2 == 1) ? clampedSwing : 0.0
                        let time = (Double(index) + swingRatio) * sixteenthNoteDuration
                        allNotes.append(
                            TrackNote(
                                padIndex: pad,
                                stepIndex: index,
                                stepOffsetRatio: swingRatio,
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
        return (notes: sortedNotes, barDuration: singleBarDuration, totalSteps: totalSteps)
    }
}

/// Provides rich 2-bar musical grooves with turnaround fills, swing, drum kits, and backing bass/chords
struct LevelProvider {
    
    struct PatternTemplate: Equatable, Identifiable {
        var id: String { name }
        let name: String
        let subtitle: String
        let bpm: Double
        let swing: Double
        let recommendedKit: DrumKit
        let kick: [Int]
        let snare: [Int]
        let hatC: [Int]
        let hatO: [Int]
        let backingEvents: [BackingStepEvent]
        var isCalibration: Bool = false
        
        var totalSteps: Int {
            max(16, max(kick.count, max(snare.count, max(hatC.count, hatO.count))))
        }
    }
    
    // MARK: - 1. NEO BOOM BAP (2 Bars / 32 Steps, MPC Swing, Jazzy Rhodes + Sub Bass)
    static let boomBap = PatternTemplate(
        name: "BOOM BAP",
        subtitle: "90s MPC Swing · 2-Bar Groove + Fill",
        bpm: 92,
        swing: 0.24,
        recommendedKit: .mpcLoFi,
        //      Bar 1 (Steps 0..15)                               | Bar 2 (Steps 16..31) with turnaround pickup
        kick:  [3, 0, 0, 1, 0, 0, 1, 0, 0, 1, 3, 0, 0, 0, 1, 0,   3, 0, 0, 0, 0, 1, 0, 0, 3, 0, 1, 0, 0, 1, 0, 1],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 2, 1, 3],
        hatC:  [3, 2, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 2, 1, 0,   3, 2, 1, 2, 1, 2, 1, 2, 3, 2, 1, 2, 1, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0],
        backingEvents: [
            // Bar 1: Cm9 -> Fm9
            BackingStepEvent(stepIndex: 0,  bassMIDINote: 36, bassDurationSteps: 3.0, chordMIDINotes: [60, 63, 67, 70, 74], chordDurationSteps: 7.5),
            BackingStepEvent(stepIndex: 3,  bassMIDINote: 39, bassDurationSteps: 2.5, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 6,  bassMIDINote: 43, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 8,  bassMIDINote: 41, bassDurationSteps: 2.0, chordMIDINotes: [60, 65, 68, 72, 75], chordDurationSteps: 7.5),
            BackingStepEvent(stepIndex: 10, bassMIDINote: 41, bassDurationSteps: 4.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 14, bassMIDINote: 43, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            // Bar 2: Abmaj7 -> G7alt turnaround
            BackingStepEvent(stepIndex: 16, bassMIDINote: 44, bassDurationSteps: 5.0, chordMIDINotes: [63, 68, 72, 75], chordDurationSteps: 7.5),
            BackingStepEvent(stepIndex: 21, bassMIDINote: 46, bassDurationSteps: 3.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 24, bassMIDINote: 43, bassDurationSteps: 2.0, chordMIDINotes: [59, 65, 68, 71, 75], chordDurationSteps: 7.5),
            BackingStepEvent(stepIndex: 26, bassMIDINote: 43, bassDurationSteps: 3.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 29, bassMIDINote: 38, bassDurationSteps: 3.0, chordMIDINotes: [], chordDurationSteps: 0)
        ]
    )
    
    // MARK: - 2. FUNK POCKET (2 Bars / 32 Steps, Funk Break Kit, Syncopated Ghost Chatter)
    static let funk = PatternTemplate(
        name: "FUNK",
        subtitle: "Tight Breakbeat · Ghost Notes & Bark",
        bpm: 104,
        swing: 0.18,
        recommendedKit: .funkBreak,
        //      Bar 1                                              | Bar 2 with syncopated snare & hat bark
        kick:  [3, 0, 0, 1, 0, 0, 3, 0, 0, 0, 1, 0, 0, 1, 0, 0,   3, 0, 1, 0, 0, 0, 3, 0, 0, 1, 0, 0, 0, 1, 0, 1],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 2, 3, 0, 2, 2,   0, 2, 0, 0, 3, 0, 0, 2, 0, 2, 3, 0, 3, 2, 3, 0],
        hatC:  [3, 2, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 2, 0, 0,   3, 2, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 0, 1, 2],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 3, 0, 0],
        backingEvents: [
            // Dorian Funk in E minor (Em9 -> A13)
            BackingStepEvent(stepIndex: 0,  bassMIDINote: 40, bassDurationSteps: 2.5, chordMIDINotes: [64, 67, 71, 74, 78], chordDurationSteps: 3.5),
            BackingStepEvent(stepIndex: 3,  bassMIDINote: 43, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 6,  bassMIDINote: 45, bassDurationSteps: 3.5, chordMIDINotes: [64, 67, 71, 74], chordDurationSteps: 3.0),
            BackingStepEvent(stepIndex: 10, bassMIDINote: 47, bassDurationSteps: 2.5, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 13, bassMIDINote: 38, bassDurationSteps: 2.5, chordMIDINotes: [62, 66, 69, 73], chordDurationSteps: 2.5),
            BackingStepEvent(stepIndex: 16, bassMIDINote: 40, bassDurationSteps: 2.0, chordMIDINotes: [64, 67, 71, 74, 78], chordDurationSteps: 5.0),
            BackingStepEvent(stepIndex: 18, bassMIDINote: 40, bassDurationSteps: 3.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 22, bassMIDINote: 45, bassDurationSteps: 3.0, chordMIDINotes: [64, 69, 73, 76, 78], chordDurationSteps: 6.0),
            BackingStepEvent(stepIndex: 25, bassMIDINote: 45, bassDurationSteps: 3.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 29, bassMIDINote: 47, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 31, bassMIDINote: 38, bassDurationSteps: 1.0, chordMIDINotes: [], chordDurationSteps: 0)
        ]
    )
    
    // MARK: - 3. DEEP HOUSE (2 Bars / 32 Steps, Club 909 Kit, Offbeat Chords & Sub Groove)
    static let house = PatternTemplate(
        name: "HOUSE",
        subtitle: "Club 909 · Offbeat Hats & Jackin' Groove",
        bpm: 124,
        swing: 0.14,
        recommendedKit: .club909,
        //      Bar 1                                              | Bar 2 with syncopated bass/kick pickup
        kick:  [3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 1,   3, 0, 0, 0, 3, 0, 0, 1, 3, 0, 0, 0, 3, 0, 1, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 2, 3, 0, 0, 0,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 2, 3],
        hatC:  [1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2,   1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 0, 0, 0],
        hatO:  [0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0,   0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 3, 3, 0],
        backingEvents: [
            // Deep House chords: Am9 -> Fmaj9 -> Dm9 -> E7#9
            BackingStepEvent(stepIndex: 0,  bassMIDINote: 33, bassDurationSteps: 2.0, chordMIDINotes: [60, 64, 67, 71], chordDurationSteps: 2.5),
            BackingStepEvent(stepIndex: 2,  bassMIDINote: 45, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 6,  bassMIDINote: 43, bassDurationSteps: 2.0, chordMIDINotes: [60, 64, 67, 71], chordDurationSteps: 4.5),
            BackingStepEvent(stepIndex: 10, bassMIDINote: 41, bassDurationSteps: 3.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 14, bassMIDINote: 40, bassDurationSteps: 2.0, chordMIDINotes: [57, 60, 64, 69], chordDurationSteps: 2.0),
            BackingStepEvent(stepIndex: 16, bassMIDINote: 38, bassDurationSteps: 2.0, chordMIDINotes: [60, 65, 69, 72], chordDurationSteps: 4.5),
            BackingStepEvent(stepIndex: 18, bassMIDINote: 50, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 22, bassMIDINote: 38, bassDurationSteps: 2.0, chordMIDINotes: [60, 65, 69, 72], chordDurationSteps: 3.0),
            BackingStepEvent(stepIndex: 24, bassMIDINote: 40, bassDurationSteps: 3.5, chordMIDINotes: [59, 64, 68, 71, 75], chordDurationSteps: 6.0),
            BackingStepEvent(stepIndex: 30, bassMIDINote: 36, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0)
        ]
    )
    
    // MARK: - 4. 808 TRAP (2 Bars / 32 Steps, 808 Sub Bounce & Rapid Hi-Hat Rolls)
    static let trap808 = PatternTemplate(
        name: "808 TRAP",
        subtitle: "Sub-Bass 808 · Half-Time Snare & Hat Rolls",
        bpm: 134,
        swing: 0.08,
        recommendedKit: .trap808,
        //      Bar 1                                              | Bar 2 with 808 bounce & snare roll
        kick:  [3, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 3, 0,   3, 0, 0, 1, 0, 0, 3, 0, 0, 0, 0, 1, 0, 0, 3, 0],
        snare: [0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 2,   0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 2, 0, 1, 2, 3],
        hatC:  [3, 0, 1, 0, 1, 2, 1, 2, 3, 0, 1, 0, 1, 2, 0, 0,   3, 2, 1, 2, 1, 0, 1, 0, 3, 0, 1, 2, 3, 2, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3],
        backingEvents: [
            // Dark F minor trap progression (Fm -> Db -> C7)
            BackingStepEvent(stepIndex: 0,  bassMIDINote: 29, bassDurationSteps: 6.0, chordMIDINotes: [60, 65, 68, 72], chordDurationSteps: 8.0),
            BackingStepEvent(stepIndex: 6,  bassMIDINote: 29, bassDurationSteps: 4.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 10, bassMIDINote: 32, bassDurationSteps: 4.0, chordMIDINotes: [60, 63, 68], chordDurationSteps: 6.0),
            BackingStepEvent(stepIndex: 14, bassMIDINote: 34, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 16, bassMIDINote: 37, bassDurationSteps: 6.0, chordMIDINotes: [61, 65, 68, 73], chordDurationSteps: 8.0),
            BackingStepEvent(stepIndex: 22, bassMIDINote: 37, bassDurationSteps: 5.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 27, bassMIDINote: 36, bassDurationSteps: 3.0, chordMIDINotes: [60, 64, 67, 70], chordDurationSteps: 5.0),
            BackingStepEvent(stepIndex: 30, bassMIDINote: 36, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0)
        ]
    )
    
    // MARK: - 5. STUDIO ROCK / INDIE GROOVE (2 Bars / 32 Steps, Studio Acoustic Kit)
    static let rock = PatternTemplate(
        name: "ROCK",
        subtitle: "Studio Kit · Syncopated Groove & Bar-2 Fill",
        bpm: 116,
        swing: 0.0,
        recommendedKit: .studioAcoustic,
        //      Bar 1                                              | Bar 2 with 16th-note turnaround drum fill
        kick:  [3, 0, 0, 0, 0, 0, 1, 0, 3, 0, 1, 0, 0, 0, 0, 0,   3, 0, 0, 1, 0, 0, 1, 0, 3, 0, 0, 0, 1, 0, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 0,   0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 3, 2, 0, 3, 1, 3],
        hatC:  [3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 0, 0,   3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 0, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0],
        backingEvents: [
            // Driving Indie/Alt Rock progression: Am -> F -> C -> G
            BackingStepEvent(stepIndex: 0,  bassMIDINote: 33, bassDurationSteps: 6.0, chordMIDINotes: [57, 64, 69, 72], chordDurationSteps: 8.0),
            BackingStepEvent(stepIndex: 6,  bassMIDINote: 33, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 8,  bassMIDINote: 29, bassDurationSteps: 2.0, chordMIDINotes: [53, 60, 65, 69], chordDurationSteps: 8.0),
            BackingStepEvent(stepIndex: 10, bassMIDINote: 29, bassDurationSteps: 6.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 16, bassMIDINote: 36, bassDurationSteps: 3.0, chordMIDINotes: [60, 64, 67, 72], chordDurationSteps: 8.0),
            BackingStepEvent(stepIndex: 19, bassMIDINote: 36, bassDurationSteps: 3.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 22, bassMIDINote: 38, bassDurationSteps: 2.0, chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 24, bassMIDINote: 31, bassDurationSteps: 4.0, chordMIDINotes: [55, 59, 62, 67], chordDurationSteps: 8.0),
            BackingStepEvent(stepIndex: 28, bassMIDINote: 35, bassDurationSteps: 4.0, chordMIDINotes: [], chordDurationSteps: 0)
        ]
    )
    
    // MARK: - 6. LIQUID D&B (2 Bars / 32 Steps, Two-Step Amen / Liquid Breakbeat)
    static let liquidDnB = PatternTemplate(
        name: "LIQUID D&B",
        subtitle: "164 BPM Two-Step Breakbeat & Reese Bass",
        bpm: 164,
        swing: 0.0,
        recommendedKit: .funkBreak,
        //      Bar 1 (Classic Two-Step + Ghost Shuffle)           | Bar 2 (Amen Variation)
        kick:  [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0,   3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 2, 3],
        hatC:  [3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 0, 0,   3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        backingEvents: [
            // Lush Liquid D&B progression: Dm9 -> Bbmaj7 -> Gm9 -> A7sus4
            BackingStepEvent(stepIndex: 0,  bassMIDINote: 38, bassDurationSteps: 10.0, chordMIDINotes: [62, 65, 69, 72, 76], chordDurationSteps: 16.0),
            BackingStepEvent(stepIndex: 10, bassMIDINote: 36, bassDurationSteps: 6.0,  chordMIDINotes: [], chordDurationSteps: 0),
            BackingStepEvent(stepIndex: 16, bassMIDINote: 34, bassDurationSteps: 10.0, chordMIDINotes: [58, 62, 65, 69, 72], chordDurationSteps: 10.0),
            BackingStepEvent(stepIndex: 26, bassMIDINote: 33, bassDurationSteps: 6.0,  chordMIDINotes: [57, 62, 64, 69], chordDurationSteps: 6.0)
        ]
    )
    
    // MARK: - 7. CALIBRATION (1 Bar / 16 Steps, Reference 4-on-the-floor)
    static let calibration = PatternTemplate(
        name: "CALIB",
        subtitle: "Latency Calibration Reference",
        bpm: 100,
        swing: 0.0,
        recommendedKit: .studioAcoustic,
        kick:  [3, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
        snare: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        hatC:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        backingEvents: [],
        isCalibration: true
    )
    
    static let allTemplates: [PatternTemplate] = [
        boomBap,
        funk,
        house,
        trap808,
        rock,
        liquidDnB,
        calibration
    ]
}

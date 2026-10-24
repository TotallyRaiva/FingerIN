import Foundation

/// Available studio & electronic drum kits
nonisolated enum DrumKit: String, CaseIterable, Identifiable, Equatable, Sendable {
    case studioAcoustic = "STUDIO"
    case mpcLoFi = "MPC LO-FI"
    case club909 = "CLUB 909"
    case trap808 = "808 TRAP"
    case funkBreak = "FUNK BREAK"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
}

/// Sample attack / low-latency trim options to eliminate perceived sample onset lag
nonisolated enum SampleLatencyMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case tight = "TIGHT (2ms)"
    case instant = "ZERO-LAG (5ms)"
    case natural = "RAW (0ms)"
    
    var id: String { rawValue }
    
    /// Number of milliseconds of pre-peak onset trimmed from raw samples
    var trimMilliseconds: Double {
        switch self {
        case .natural: return 0.0
        case .tight: return 2.2
        case .instant: return 4.5
        }
    }
    
    var shortLabel: String {
        switch self {
        case .natural: return "RAW"
        case .tight: return "TIGHT"
        case .instant: return "ULTRA"
        }
    }
}

/// Music genre categories, each offering multiple progressively richer beat variations
enum MusicStyle: String, CaseIterable, Identifiable, Equatable {
    case boomBap = "BOOM BAP"
    case funk = "FUNK"
    case house = "HOUSE"
    case trap808 = "808 TRAP"
    case rock = "ROCK"
    case liquidDnB = "LIQUID D&B"
    case calibration = "CALIB"
    
    var id: String { rawValue }
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
    let bassMIDINote: UInt8?
    let bassDurationSteps: Double
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

/// Provides rich 2-bar musical grooves with multiple variations per style, turnaround fills, swing, drum kits, and backing bass/chords
struct LevelProvider {
    
    struct PatternTemplate: Equatable, Identifiable {
        var id: String { "\(style.rawValue)_\(variationIndex)" }
        let style: MusicStyle
        let variationIndex: Int // 1, 2, 3
        let variationName: String
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
    
    // MARK: - Shared Musical Progression Helpers
    
    private static let boomBapBacking: [BackingStepEvent] = [
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
    
    private static let funkBacking: [BackingStepEvent] = [
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
    
    private static let houseBacking: [BackingStepEvent] = [
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
    
    private static let trapBacking: [BackingStepEvent] = [
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
    
    private static let rockBacking: [BackingStepEvent] = [
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
    
    private static let dnbBacking: [BackingStepEvent] = [
        // Lush Liquid D&B progression: Dm9 -> Bbmaj7 -> Gm9 -> A7sus4
        BackingStepEvent(stepIndex: 0,  bassMIDINote: 38, bassDurationSteps: 10.0, chordMIDINotes: [62, 65, 69, 72, 76], chordDurationSteps: 16.0),
        BackingStepEvent(stepIndex: 10, bassMIDINote: 36, bassDurationSteps: 6.0,  chordMIDINotes: [], chordDurationSteps: 0),
        BackingStepEvent(stepIndex: 16, bassMIDINote: 34, bassDurationSteps: 10.0, chordMIDINotes: [58, 62, 65, 69, 72], chordDurationSteps: 10.0),
        BackingStepEvent(stepIndex: 26, bassMIDINote: 33, bassDurationSteps: 6.0,  chordMIDINotes: [57, 62, 64, 69], chordDurationSteps: 6.0)
    ]
    
    // MARK: - 1. BOOM BAP (3 Variations)
    
    static let boomBap = PatternTemplate(
        style: .boomBap,
        variationIndex: 1,
        variationName: "V1 · 90s East Coast",
        name: "BOOM BAP",
        subtitle: "Boom Bap V1 · 90s East Coast Pocket",
        bpm: 90,
        swing: 0.22,
        recommendedKit: .mpcLoFi,
        kick:  [3, 0, 0, 0, 0, 0, 1, 0, 0, 1, 3, 0, 0, 0, 1, 0,   3, 0, 0, 0, 0, 0, 1, 0, 3, 0, 1, 0, 0, 1, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 2, 3],
        hatC:  [3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 0, 0,   3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0],
        backingEvents: boomBapBacking
    )
    
    static let boomBapV2 = PatternTemplate(
        style: .boomBap,
        variationIndex: 2,
        variationName: "V2 · Dilla Neo-Soul",
        name: "BOOM BAP V2",
        subtitle: "Boom Bap V2 · Heavy Dilla Swing & Ghost Snares",
        bpm: 88,
        swing: 0.28,
        recommendedKit: .mpcLoFi,
        kick:  [3, 0, 0, 1, 0, 0, 1, 0, 0, 1, 3, 0, 0, 0, 1, 0,   3, 0, 0, 0, 0, 1, 0, 0, 3, 0, 1, 0, 0, 1, 0, 1],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 2, 1, 3],
        hatC:  [3, 2, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 2, 1, 0,   3, 2, 1, 2, 1, 2, 1, 2, 3, 2, 1, 2, 1, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0],
        backingEvents: boomBapBacking
    )
    
    static let boomBapV3 = PatternTemplate(
        style: .boomBap,
        variationIndex: 3,
        variationName: "V3 · Jazz Bap Chop",
        name: "BOOM BAP V3",
        subtitle: "Boom Bap V3 · Syncopated Jazz Chop & Fill",
        bpm: 94,
        swing: 0.24,
        recommendedKit: .mpcLoFi,
        kick:  [3, 0, 1, 0, 0, 1, 0, 0, 0, 1, 3, 0, 0, 1, 0, 0,   3, 0, 0, 1, 0, 0, 3, 0, 0, 1, 0, 1, 0, 0, 1, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 2, 3, 0, 2, 0,   0, 2, 0, 0, 3, 0, 0, 2, 0, 2, 3, 2, 3, 2, 3, 3],
        hatC:  [3, 2, 1, 0, 1, 2, 1, 2, 3, 2, 0, 2, 1, 2, 1, 0,   3, 2, 1, 2, 1, 0, 1, 2, 3, 2, 1, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1,   0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0],
        backingEvents: boomBapBacking
    )
    
    // MARK: - 2. FUNK (3 Variations)
    
    static let funk = PatternTemplate(
        style: .funk,
        variationIndex: 1,
        variationName: "V1 · Clyde Pocket",
        name: "FUNK",
        subtitle: "Funk V1 · Classic Breakbeat & Open-Hat Bark",
        bpm: 102,
        swing: 0.16,
        recommendedKit: .funkBreak,
        kick:  [3, 0, 1, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 1, 0, 0,   3, 0, 1, 0, 0, 0, 1, 0, 0, 1, 3, 0, 0, 1, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 2, 3, 0, 2, 3],
        hatC:  [3, 2, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 2, 0, 0,   3, 2, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 0, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 3, 0, 0],
        backingEvents: funkBacking
    )
    
    static let funkV2 = PatternTemplate(
        style: .funk,
        variationIndex: 2,
        variationName: "V2 · Oakland Linear",
        name: "FUNK V2",
        subtitle: "Funk V2 · Syncopated Linear Kick & Snare",
        bpm: 106,
        swing: 0.18,
        recommendedKit: .funkBreak,
        kick:  [3, 0, 0, 1, 0, 0, 3, 0, 0, 0, 1, 0, 0, 1, 0, 0,   3, 0, 1, 0, 0, 0, 3, 0, 0, 1, 0, 0, 0, 1, 0, 1],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 2, 3, 0, 2, 2,   0, 2, 0, 0, 3, 0, 0, 2, 0, 2, 3, 0, 3, 2, 3, 0],
        hatC:  [3, 2, 1, 0, 1, 2, 0, 0, 3, 2, 1, 0, 1, 0, 0, 0,   3, 0, 1, 2, 1, 2, 0, 0, 3, 0, 0, 2, 1, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 3, 0, 0],
        backingEvents: funkBacking
    )
    
    static let funkV3 = PatternTemplate(
        style: .funk,
        variationIndex: 3,
        variationName: "V3 · Ghost Chatter",
        name: "FUNK V3",
        subtitle: "Funk V3 · Rapid Ghost Notes & Showtime Fill",
        bpm: 108,
        swing: 0.20,
        recommendedKit: .funkBreak,
        kick:  [3, 0, 0, 1, 0, 1, 0, 0, 3, 0, 0, 1, 0, 0, 3, 0,   3, 0, 0, 1, 0, 1, 0, 0, 3, 0, 1, 0, 0, 1, 0, 0],
        snare: [0, 2, 2, 0, 3, 0, 2, 2, 0, 2, 3, 0, 3, 2, 0, 2,   0, 2, 2, 0, 3, 0, 2, 2, 0, 2, 0, 3, 2, 0, 3, 3],
        hatC:  [3, 0, 1, 2, 1, 2, 1, 0, 3, 2, 1, 2, 1, 0, 1, 0,   3, 0, 1, 2, 1, 2, 1, 0, 3, 2, 1, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 3, 0, 0,   0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 3, 0, 0, 0],
        backingEvents: funkBacking
    )
    
    // MARK: - 3. HOUSE (3 Variations)
    
    static let house = PatternTemplate(
        style: .house,
        variationIndex: 1,
        variationName: "V1 · Deep Club",
        name: "HOUSE",
        subtitle: "House V1 · Classic 909 Four-on-the-Floor",
        bpm: 122,
        swing: 0.12,
        recommendedKit: .club909,
        kick:  [3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0,   3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 1, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0,   0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 2],
        hatC:  [1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2,   1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 0],
        hatO:  [0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0,   0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0],
        backingEvents: houseBacking
    )
    
    static let houseV2 = PatternTemplate(
        style: .house,
        variationIndex: 2,
        variationName: "V2 · Jackin' Garage",
        name: "HOUSE V2",
        subtitle: "House V2 · UK Garage Shuffled Ghost Snares",
        bpm: 126,
        swing: 0.22,
        recommendedKit: .club909,
        kick:  [3, 0, 0, 0, 3, 0, 0, 1, 3, 0, 0, 0, 3, 0, 1, 0,   3, 0, 0, 1, 0, 0, 3, 0, 3, 0, 0, 0, 3, 0, 1, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 2, 3, 0, 2, 3],
        hatC:  [1, 0, 0, 2, 1, 0, 0, 2, 1, 0, 0, 2, 1, 0, 0, 2,   1, 2, 0, 2, 1, 0, 0, 2, 1, 2, 0, 2, 1, 0, 0, 0],
        hatO:  [0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0,   0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 3, 3, 0],
        backingEvents: houseBacking
    )
    
    static let houseV3 = PatternTemplate(
        style: .house,
        variationIndex: 3,
        variationName: "V3 · Tech Roller",
        name: "HOUSE V3",
        subtitle: "House V3 · Driving 16th-Hat Roller & Clap Fill",
        bpm: 128,
        swing: 0.10,
        recommendedKit: .club909,
        kick:  [3, 0, 0, 1, 3, 0, 0, 0, 3, 0, 0, 1, 3, 0, 1, 0,   3, 0, 0, 1, 3, 0, 0, 0, 3, 0, 1, 0, 3, 1, 0, 1],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 0, 2, 3, 0, 0, 2,   0, 2, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 2, 3, 3],
        hatC:  [1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2,   1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 0, 0, 0, 0],
        hatO:  [0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0,   0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3, 0, 3, 0, 0, 0],
        backingEvents: houseBacking
    )
    
    // MARK: - 4. 808 TRAP (3 Variations)
    
    static let trap808 = PatternTemplate(
        style: .trap808,
        variationIndex: 1,
        variationName: "V1 · Atlanta Bounce",
        name: "808 TRAP",
        subtitle: "808 Trap V1 · Half-Time Snare & Sub Bounce",
        bpm: 134,
        swing: 0.08,
        recommendedKit: .trap808,
        kick:  [3, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 3, 0,   3, 0, 0, 1, 0, 0, 3, 0, 0, 0, 0, 1, 0, 0, 3, 0],
        snare: [0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 2,   0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 2, 0, 1, 2, 3],
        hatC:  [3, 0, 1, 0, 1, 2, 1, 2, 3, 0, 1, 0, 1, 2, 0, 0,   3, 2, 1, 2, 1, 0, 1, 0, 3, 0, 1, 2, 3, 2, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3],
        backingEvents: trapBacking
    )
    
    static let trap808V2 = PatternTemplate(
        style: .trap808,
        variationIndex: 2,
        variationName: "V2 · Dark Drill Glide",
        name: "808 TRAP V2",
        subtitle: "808 Trap V2 · Tresillo Drill Hats & Offset Snare",
        bpm: 140,
        swing: 0.06,
        recommendedKit: .trap808,
        kick:  [3, 0, 0, 0, 0, 0, 3, 0, 0, 3, 0, 0, 0, 0, 0, 1,   3, 0, 0, 1, 0, 0, 3, 0, 0, 0, 3, 0, 0, 1, 3, 0],
        snare: [0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 3, 0, 2, 3],
        hatC:  [3, 0, 0, 1, 0, 0, 3, 0, 0, 1, 0, 2, 3, 0, 1, 2,   3, 0, 0, 1, 2, 2, 3, 0, 0, 1, 0, 2, 3, 2, 1, 0],
        hatO:  [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0],
        backingEvents: trapBacking
    )
    
    static let trap808V3 = PatternTemplate(
        style: .trap808,
        variationIndex: 3,
        variationName: "V3 · Stutter Roll",
        name: "808 TRAP V3",
        subtitle: "808 Trap V3 · Rapid 16th Hat Stutters & Build",
        bpm: 144,
        swing: 0.05,
        recommendedKit: .trap808,
        kick:  [3, 0, 1, 0, 0, 0, 3, 0, 0, 1, 0, 0, 0, 1, 3, 0,   3, 0, 1, 0, 0, 1, 3, 0, 0, 0, 3, 0, 3, 0, 3, 0],
        snare: [0, 0, 0, 0, 0, 0, 0, 2, 3, 0, 0, 2, 0, 0, 0, 2,   0, 0, 0, 2, 0, 0, 0, 0, 3, 0, 2, 2, 3, 2, 3, 3],
        hatC:  [3, 2, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 0, 0,   3, 2, 1, 2, 3, 2, 1, 0, 3, 2, 1, 2, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 3, 0, 0, 0],
        backingEvents: trapBacking
    )
    
    // MARK: - 5. ROCK (3 Variations)
    
    static let rock = PatternTemplate(
        style: .rock,
        variationIndex: 1,
        variationName: "V1 · Studio Drive",
        name: "ROCK",
        subtitle: "Rock V1 · Driving Indie Groove & Bar-2 Fill",
        bpm: 116,
        swing: 0.0,
        recommendedKit: .studioAcoustic,
        kick:  [3, 0, 0, 0, 0, 0, 1, 0, 3, 0, 1, 0, 0, 0, 0, 0,   3, 0, 0, 1, 0, 0, 1, 0, 3, 0, 0, 0, 1, 0, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 0,   0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 3, 2, 0, 3, 1, 3],
        hatC:  [3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 0, 0,   3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 0, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0],
        backingEvents: rockBacking
    )
    
    static let rockV2 = PatternTemplate(
        style: .rock,
        variationIndex: 2,
        variationName: "V2 · Half-Time Heavy",
        name: "ROCK V2",
        subtitle: "Rock V2 · Heavy Arena Half-Time & Open Hats",
        bpm: 110,
        swing: 0.0,
        recommendedKit: .studioAcoustic,
        kick:  [3, 0, 0, 1, 0, 0, 3, 0, 0, 0, 0, 1, 0, 1, 0, 0,   3, 0, 0, 1, 0, 0, 3, 0, 0, 1, 0, 0, 3, 0, 1, 0],
        snare: [0, 0, 0, 0, 0, 0, 0, 2, 3, 0, 0, 0, 0, 0, 2, 2,   0, 0, 0, 0, 0, 0, 0, 2, 3, 0, 2, 0, 0, 3, 2, 3],
        hatC:  [3, 0, 1, 0, 3, 0, 1, 0, 3, 0, 1, 0, 3, 0, 0, 0,   3, 0, 1, 0, 3, 0, 1, 0, 3, 0, 1, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0],
        backingEvents: rockBacking
    )
    
    static let rockV3 = PatternTemplate(
        style: .rock,
        variationIndex: 3,
        variationName: "V3 · Garage Disco",
        name: "ROCK V3",
        subtitle: "Rock V3 · Fast 16th-Hat Post-Punk / Disco Beat",
        bpm: 128,
        swing: 0.0,
        recommendedKit: .studioAcoustic,
        kick:  [3, 0, 0, 0, 1, 0, 0, 1, 3, 0, 0, 0, 1, 0, 1, 0,   3, 0, 0, 0, 1, 0, 0, 1, 3, 0, 1, 0, 0, 1, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 3, 3, 0, 3, 3],
        hatC:  [3, 2, 1, 2, 1, 2, 0, 2, 3, 2, 1, 2, 1, 2, 0, 2,   3, 2, 1, 2, 1, 2, 0, 2, 3, 2, 1, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3, 0, 0],
        backingEvents: rockBacking
    )
    
    // MARK: - 6. LIQUID D&B (3 Variations)
    
    static let liquidDnB = PatternTemplate(
        style: .liquidDnB,
        variationIndex: 1,
        variationName: "V1 · Liquid Two-Step",
        name: "LIQUID D&B",
        subtitle: "D&B V1 · Smooth Two-Step & Reese Sub",
        bpm: 164,
        swing: 0.0,
        recommendedKit: .funkBreak,
        kick:  [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0,   3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 2, 3],
        hatC:  [3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 0, 0,   3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 1, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0,   0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        backingEvents: dnbBacking
    )
    
    static let liquidDnBV2 = PatternTemplate(
        style: .liquidDnB,
        variationIndex: 2,
        variationName: "V2 · Amen Jungle Chop",
        name: "LIQUID D&B V2",
        subtitle: "D&B V2 · Classic Syncopated Amen Break Chop",
        bpm: 168,
        swing: 0.0,
        recommendedKit: .funkBreak,
        kick:  [3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 1, 0, 0, 0, 0,   3, 0, 0, 0, 0, 0, 3, 0, 0, 1, 0, 0, 0, 0, 1, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 2, 0, 0, 3, 0, 0, 2,   0, 2, 0, 0, 3, 0, 0, 2, 0, 0, 3, 0, 0, 2, 3, 2],
        hatC:  [3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0, 1, 0, 1, 0,   3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 0, 0, 1, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 3, 0, 0],
        backingEvents: dnbBacking
    )
    
    static let liquidDnBV3 = PatternTemplate(
        style: .liquidDnB,
        variationIndex: 3,
        variationName: "V3 · Neuro Steppa",
        name: "LIQUID D&B V3",
        subtitle: "D&B V3 · Tight Techy Steppa & Double-Snare Switch",
        bpm: 172,
        swing: 0.0,
        recommendedKit: .funkBreak,
        kick:  [3, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1, 0,   3, 0, 0, 1, 0, 0, 0, 0, 0, 3, 0, 0, 3, 0, 0, 0],
        snare: [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3, 0, 0, 2, 2,   0, 0, 0, 0, 3, 0, 2, 0, 0, 0, 0, 3, 0, 2, 3, 3],
        hatC:  [3, 2, 1, 2, 3, 0, 1, 2, 3, 0, 1, 0, 3, 2, 1, 0,   3, 2, 1, 0, 3, 2, 1, 2, 3, 0, 1, 0, 0, 0, 0, 0],
        hatO:  [0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0],
        backingEvents: dnbBacking
    )
    
    // MARK: - 7. CALIBRATION
    
    static let calibration = PatternTemplate(
        style: .calibration,
        variationIndex: 1,
        variationName: "Quarter Reference",
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
    
    static func variations(for style: MusicStyle) -> [PatternTemplate] {
        switch style {
        case .boomBap: return [boomBap, boomBapV2, boomBapV3]
        case .funk: return [funk, funkV2, funkV3]
        case .house: return [house, houseV2, houseV3]
        case .trap808: return [trap808, trap808V2, trap808V3]
        case .rock: return [rock, rockV2, rockV3]
        case .liquidDnB: return [liquidDnB, liquidDnBV2, liquidDnBV3]
        case .calibration: return [calibration]
        }
    }
    
    static let allTemplates: [PatternTemplate] = [
        boomBap, boomBapV2, boomBapV3,
        funk, funkV2, funkV3,
        house, houseV2, houseV3,
        trap808, trap808V2, trap808V3,
        rock, rockV2, rockV3,
        liquidDnB, liquidDnBV2, liquidDnBV3,
        calibration
    ]
}

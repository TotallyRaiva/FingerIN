import Foundation
import SwiftData
import SwiftUI
import Combine
import os

/// Shared Comix × Retro Akai MPC 2000XL design system tokens matching the web showcase
enum MPCTheme {
    static let mpcCream = Color(red: 0.965, green: 0.945, blue: 0.898)      // #F6F1E5
    static let mpcBeige = Color(red: 0.918, green: 0.875, blue: 0.796)      // #EADFCB
    static let mpcBeigeDark = Color(red: 0.847, green: 0.788, blue: 0.682)  // #D8C9AE
    static let mpcChassis = Color(red: 0.129, green: 0.141, blue: 0.169)    // #21242B
    static let mpcPanel = Color(red: 0.078, green: 0.086, blue: 0.106)      // #14161B
    static let mpcSlate = Color(red: 0.180, green: 0.200, blue: 0.239)      // #2E333D
    static let mpcPadBed = Color(red: 0.231, green: 0.259, blue: 0.298)     // #3B424C
    static let ink = Color(red: 0.067, green: 0.071, blue: 0.086)           // #111216
    static let lcdBackground = Color(red: 0.051, green: 0.149, blue: 0.122) // #0D261F
    static let lcdGlow = Color(red: 0.220, green: 0.973, blue: 0.698)       // #38F8B2
    static let lcdDim = Color(red: 0.114, green: 0.420, blue: 0.318)        // #1D6B51
    static let kick = Color(red: 1.000, green: 0.302, blue: 0.161)          // #FF4D29
    static let snare = Color(red: 1.000, green: 0.722, blue: 0.000)         // #FFB800
    static let closedHat = Color(red: 0.000, green: 0.839, blue: 0.498)     // #00D67F
    static let openHat = Color(red: 0.000, green: 0.706, blue: 1.000)       // #00B4FF
    static let purple = Color(red: 0.608, green: 0.420, blue: 1.000)        // #9B6BFF
}

/// Canonical definition for each of the 4 finger-drumming voices/lanes
struct DrumVoiceConfig: Identifiable, Equatable {
    let laneIndex: Int          // 0 (bottom) to 3 (top)
    let canonicalNote: UInt8    // Internal canonical ID: 12, 13, 14, 15
    let gmNote: UInt8           // Standard General MIDI drum note (36, 38, 42, 46)
    let padCode: String         // e.g. "PAD A01"
    let shortName: String       // e.g. "KICK"
    let matrixLabel: String     // e.g. "KICK (36)"
    let fullName: String        // e.g. "KICK DRUM"
    let comicBurst: String      // e.g. "BOOM!"
    let sampleName: String      // e.g. "kick"
    let color: Color
    let defaultPadIndex: Int    // 0-15 index on 4x4 matrix
    let keyEquivalent: Character // Keyboard shortcut fallback
    
    var id: UInt8 { canonicalNote }
    
    static let allVoices: [DrumVoiceConfig] = [
        DrumVoiceConfig(
            laneIndex: 0,
            canonicalNote: 12,
            gmNote: 36,
            padCode: "PAD A01",
            shortName: "KICK",
            matrixLabel: "KICK (36)",
            fullName: "KICK DRUM",
            comicBurst: "BOOM!",
            sampleName: "kick",
            color: MPCTheme.kick,
            defaultPadIndex: 0,
            keyEquivalent: "a"
        ),
        DrumVoiceConfig(
            laneIndex: 1,
            canonicalNote: 13,
            gmNote: 38,
            padCode: "PAD A02",
            shortName: "SNARE",
            matrixLabel: "SNARE (38)",
            fullName: "SNARE DRUM",
            comicBurst: "CRACK!",
            sampleName: "Snare",
            color: MPCTheme.snare,
            defaultPadIndex: 1,
            keyEquivalent: "s"
        ),
        DrumVoiceConfig(
            laneIndex: 2,
            canonicalNote: 14,
            gmNote: 42,
            padCode: "PAD A03",
            shortName: "CL-HAT",
            matrixLabel: "CL-HAT (42)",
            fullName: "CLOSED HAT",
            comicBurst: "CHK!",
            sampleName: "hihat_closed",
            color: MPCTheme.closedHat,
            defaultPadIndex: 2,
            keyEquivalent: "d"
        ),
        DrumVoiceConfig(
            laneIndex: 3,
            canonicalNote: 15,
            gmNote: 46,
            padCode: "PAD A04",
            shortName: "OP-HAT",
            matrixLabel: "OP-HAT (46)",
            fullName: "OPEN HAT",
            comicBurst: "TSSS!",
            sampleName: "hihat_open",
            color: MPCTheme.openHat,
            defaultPadIndex: 3,
            keyEquivalent: "f"
        )
    ]
    
    static func voice(forCanonicalNote note: UInt8) -> DrumVoiceConfig? {
        allVoices.first { $0.canonicalNote == note }
    }
}

/// SwiftData persistent record for completed or saved practice sessions
@Model
final class PracticeSessionRecord {
    var id: UUID
    var timestamp: Date
    var patternName: String
    var bpm: Double
    var score: Int
    var maxStreak: Int
    var perfectCount: Int
    var goodCount: Int
    var missCount: Int
    var accuracyPercentage: Double
    
    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        patternName: String,
        bpm: Double,
        score: Int,
        maxStreak: Int,
        perfectCount: Int,
        goodCount: Int,
        missCount: Int,
        accuracyPercentage: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.patternName = patternName
        self.bpm = bpm
        self.score = score
        self.maxStreak = maxStreak
        self.perfectCount = perfectCount
        self.goodCount = goodCount
        self.missCount = missCount
        self.accuracyPercentage = accuracyPercentage
    }
}

@MainActor
class DataManager: ObservableObject {
    static let shared = DataManager()
    
    nonisolated private struct RealtimeMappingSnapshot: Sendable {
        var customMIDIMapping: [UInt8: UInt8] = [12: 12, 13: 13, 14: 14, 15: 15]
        var isLearning: Bool = false
    }
    
    nonisolated private static let rtMappingLock = OSAllocatedUnfairLock(initialState: RealtimeMappingSnapshot())
    
    /// Custom MIDI note mappings: maps canonicalNote (12..15) -> physical MIDI note on controller
    @Published var customMIDIMapping: [UInt8: UInt8] = [
        12: 12,
        13: 13,
        14: 14,
        15: 15
    ] {
        didSet { syncRealtimeSnapshot() }
    }
    
    /// If non-nil, the next incoming MIDI Note On will be bound to this canonical voice note (12..15)
    @Published var learningCanonicalNote: UInt8? = nil {
        didSet { syncRealtimeSnapshot() }
    }
    
    /// Recent practice sessions loaded from SwiftData
    @Published private(set) var recentSessions: [PracticeSessionRecord] = []
    
    /// Best score per pattern name
    @Published private(set) var highScores: [String: Int] = [:]
    
    private var modelContainer: ModelContainer?
    private let mappingDefaultsKey = "FingerIN.customMIDIMapping"
    
    // Standard General MIDI fallback notes (C1=36 Kick, D1=38 Snare, F#1=42 Closed Hat, A#1=46 Open Hat)
    nonisolated private static let generalMIDIFallback: [UInt8: UInt8] = [
        36: 12,
        38: 13,
        42: 14,
        46: 15
    ]
    
    private init() {
        loadSavedMIDIMapping()
        syncRealtimeSnapshot()
        setupSwiftData()
        fetchSessions()
    }
    
    private func syncRealtimeSnapshot() {
        let map = customMIDIMapping
        let learning = (learningCanonicalNote != nil)
        Self.rtMappingLock.withLock { state in
            state.customMIDIMapping = map
            state.isLearning = learning
        }
    }
    
    /// Thread-safe lookup for the CoreMIDI real-time callback thread (returns nil if MIDI Learn is active)
    nonisolated static func resolveRealtimeMIDINote(_ physicalNote: UInt8) -> UInt8? {
        let snapshot = rtMappingLock.withLock { $0 }
        guard !snapshot.isLearning else { return nil }
        if let match = snapshot.customMIDIMapping.first(where: { $0.value == physicalNote }) {
            return match.key
        }
        return generalMIDIFallback[physicalNote]
    }
    
    private func setupSwiftData() {
        do {
            let schema = Schema([PracticeSessionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            if let fallback = try? ModelContainer(
                for: PracticeSessionRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) {
                modelContainer = fallback
            }
        }
    }
    
    // MARK: - MIDI Mapping & MIDI Learn
    
    func physicalNote(forCanonicalNote canonical: UInt8) -> UInt8 {
        customMIDIMapping[canonical] ?? canonical
    }
    
    /// Resolves an incoming physical MIDI note to a canonical voice note (12..15),
    /// handling MIDI Learn if active.
    func resolveIncomingMIDINote(_ physicalNote: UInt8) -> UInt8? {
        if let targetCanonical = learningCanonicalNote {
            assignMIDINote(physicalNote, toCanonicalNote: targetCanonical)
            learningCanonicalNote = nil
            return targetCanonical
        }
        
        if let match = customMIDIMapping.first(where: { $0.value == physicalNote }) {
            return match.key
        }
        
        if let gmCanonical = Self.generalMIDIFallback[physicalNote] {
            return gmCanonical
        }
        
        return nil
    }
    
    func assignMIDINote(_ physicalNote: UInt8, toCanonicalNote canonical: UInt8) {
        customMIDIMapping[canonical] = physicalNote
        saveMIDIMapping()
    }
    
    func toggleMIDILearn(forCanonicalNote canonical: UInt8) {
        if learningCanonicalNote == canonical {
            learningCanonicalNote = nil
        } else {
            learningCanonicalNote = canonical
        }
    }
    
    func resetMIDIMappingToDefault() {
        customMIDIMapping = [12: 12, 13: 13, 14: 14, 15: 15]
        learningCanonicalNote = nil
        saveMIDIMapping()
    }
    
    private func saveMIDIMapping() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: customMIDIMapping.map { (String($0.key), Int($0.value)) })
        UserDefaults.standard.set(stringKeyed, forKey: mappingDefaultsKey)
    }
    
    private func loadSavedMIDIMapping() {
        guard let saved = UserDefaults.standard.dictionary(forKey: mappingDefaultsKey) as? [String: Int] else {
            return
        }
        for (k, v) in saved {
            if let canonical = UInt8(k), (12...15).contains(canonical), (0...127).contains(v) {
                customMIDIMapping[canonical] = UInt8(v)
            }
        }
    }
    
    // MARK: - SwiftData Session History
    
    func recordSession(
        patternName: String,
        bpm: Double,
        score: Int,
        maxStreak: Int,
        perfectCount: Int,
        goodCount: Int,
        missCount: Int,
        accuracyPercentage: Double
    ) {
        guard (perfectCount + goodCount + missCount) > 0 else { return }
        guard let context = modelContainer?.mainContext else { return }
        
        let record = PracticeSessionRecord(
            patternName: patternName,
            bpm: bpm,
            score: score,
            maxStreak: maxStreak,
            perfectCount: perfectCount,
            goodCount: goodCount,
            missCount: missCount,
            accuracyPercentage: accuracyPercentage
        )
        context.insert(record)
        try? context.save()
        fetchSessions()
    }
    
    func fetchSessions() {
        guard let context = modelContainer?.mainContext else { return }
        let descriptor = FetchDescriptor<PracticeSessionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let results = try? context.fetch(descriptor) {
            self.recentSessions = Array(results.prefix(20))
            var best: [String: Int] = [:]
            for session in results {
                best[session.patternName] = max(best[session.patternName] ?? 0, session.score)
            }
            self.highScores = best
        }
    }
}

import Foundation
import SwiftData
import SwiftUI
import Combine

/// Canonical definition for each of the 4 finger-drumming voices/lanes
struct DrumVoiceConfig: Identifiable, Equatable {
    let laneIndex: Int          // 0 (bottom) to 3 (top)
    let canonicalNote: UInt8    // Internal canonical ID: 12, 13, 14, 15
    let shortName: String       // e.g. "KICK"
    let fullName: String        // e.g. "KICK"
    let sampleName: String      // e.g. "kick"
    let color: Color
    let defaultPadIndex: Int    // 0-15 index on 4x4 matrix
    let keyEquivalent: Character // Keyboard shortcut fallback
    
    var id: UInt8 { canonicalNote }
    
    static let allVoices: [DrumVoiceConfig] = [
        DrumVoiceConfig(
            laneIndex: 0,
            canonicalNote: 12,
            shortName: "KICK",
            fullName: "KICK DRUM",
            sampleName: "kick",
            color: .cyan,
            defaultPadIndex: 0,
            keyEquivalent: "a"
        ),
        DrumVoiceConfig(
            laneIndex: 1,
            canonicalNote: 13,
            shortName: "SNARE",
            fullName: "SNARE DRUM",
            sampleName: "Snare",
            color: .orange,
            defaultPadIndex: 1,
            keyEquivalent: "s"
        ),
        DrumVoiceConfig(
            laneIndex: 2,
            canonicalNote: 14,
            shortName: "HH C",
            fullName: "HI-HAT CLOSED",
            sampleName: "hihat_closed",
            color: .yellow,
            defaultPadIndex: 2,
            keyEquivalent: "d"
        ),
        DrumVoiceConfig(
            laneIndex: 3,
            canonicalNote: 15,
            shortName: "HH O",
            fullName: "HI-HAT OPEN",
            sampleName: "hihat_open",
            color: .mint,
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
    
    /// Custom MIDI note mappings: maps canonicalNote (12..15) -> physical MIDI note on controller
    @Published var customMIDIMapping: [UInt8: UInt8] = [
        12: 12,
        13: 13,
        14: 14,
        15: 15
    ]
    
    /// If non-nil, the next incoming MIDI Note On will be bound to this canonical voice note (12..15)
    @Published var learningCanonicalNote: UInt8? = nil
    
    /// Recent practice sessions loaded from SwiftData
    @Published private(set) var recentSessions: [PracticeSessionRecord] = []
    
    /// Best score per pattern name
    @Published private(set) var highScores: [String: Int] = [:]
    
    private var modelContainer: ModelContainer?
    private let mappingDefaultsKey = "FingerIN.customMIDIMapping"
    
    // Standard General MIDI fallback notes (C1=36 Kick, D1=38 Snare, F#1=42 Closed Hat, A#1=46 Open Hat)
    private let generalMIDIFallback: [UInt8: UInt8] = [
        36: 12,
        38: 13,
        42: 14,
        46: 15
    ]
    
    private init() {
        loadSavedMIDIMapping()
        setupSwiftData()
        fetchSessions()
    }
    
    private func setupSwiftData() {
        do {
            let schema = Schema([PracticeSessionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback to in-memory container if sandbox/disk path is restricted in tests
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
        
        // Check user's active mapping first
        if let match = customMIDIMapping.first(where: { $0.value == physicalNote }) {
            return match.key
        }
        
        // Also support General MIDI standard drum pad notes if not conflicting
        if let gmCanonical = generalMIDIFallback[physicalNote] {
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

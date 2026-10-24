//
//  FingerINTests.swift
//  FingerINTests
//
//  Created by Reiwa on 03.06.2026.
//

import XCTest
@testable import FingerIN

@MainActor
final class FingerINTests: XCTestCase {

    override func setUpWithError() throws {
        ScoreManager.shared.reset()
        CalibrationManager.shared.clearHistory()
        CalibrationManager.shared.saveOffset(0.0)
        DataManager.shared.resetMIDIMappingToDefault()
    }

    func testPatternBuilderFilteringVelocitiesAndSwing() throws {
        let activePads: Set<UInt8> = [12, 13] // Only Kick and Snare
        let result = PatternBuilder.build(
            bpm: 120,
            activePads: activePads,
            kick:  [3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            snare: [0, 0, 0, 0, 3, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0],
            hatC:  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            hatO:  [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1],
            swing: 0.24
        )

        // At 120 BPM, 1 beat = 0.5s, 1 single bar (16 steps) = 2.0s
        XCTAssertEqual(result.barDuration, 2.0, accuracy: 0.0001)
        XCTAssertEqual(result.totalSteps, 16)
        // Hats should be filtered out, leaving 2 kick notes + 2 snare notes = 4 notes
        XCTAssertEqual(result.notes.count, 4)
        XCTAssertTrue(result.notes.allSatisfy { activePads.contains($0.padIndex) })

        // Verify accent (3 -> 124) and ghost note (2 -> 52) velocities and odd-step swing
        let firstKick = result.notes.first { $0.padIndex == 12 && $0.stepIndex == 0 }
        let ghostSnare = result.notes.first { $0.padIndex == 13 && $0.stepIndex == 7 }
        XCTAssertEqual(firstKick?.velocity, 124)
        XCTAssertEqual(firstKick?.stepOffsetRatio ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(ghostSnare?.velocity, 52)
        XCTAssertEqual(ghostSnare?.stepOffsetRatio ?? -1, 0.24, accuracy: 0.0001)
    }

    func testTwoBarTemplatesAndKits() throws {
        for template in LevelProvider.allTemplates where !template.isCalibration {
            XCTAssertEqual(template.totalSteps, 32, "\(template.name) should be a 2-bar (32-step) pattern")
            XCTAssertFalse(template.backingEvents.isEmpty, "\(template.name) should include musical backing events")
        }
    }

    func testScoreManagerStreakMultipliersAndAccuracy() throws {
        let scoreManager = ScoreManager.shared
        scoreManager.reset()

        // 10 perfect hits: hits 1..9 at 1x (100pt), hit 10 reaches streak 10 -> 2x (200pt)
        for _ in 0..<10 {
            scoreManager.registerHit(accuracy: .perfect, timingOffsetMs: -4)
        }
        XCTAssertEqual(scoreManager.streak, 10)
        XCTAssertEqual(scoreManager.maxStreak, 10)
        XCTAssertEqual(scoreManager.multiplier, 2)
        XCTAssertEqual(scoreManager.score, 9 * 100 + 200)

        // Miss resets current streak but preserves maxStreak
        scoreManager.registerHit(accuracy: .miss, timingOffsetMs: nil)
        XCTAssertEqual(scoreManager.streak, 0)
        XCTAssertEqual(scoreManager.maxStreak, 10)
        XCTAssertEqual(scoreManager.perfectCount, 10)
        XCTAssertEqual(scoreManager.missCount, 1)
    }

    func testCalibrationRollingAverageAndOutlierRejection() throws {
        let calibration = CalibrationManager.shared
        calibration.clearHistory()
        calibration.saveOffset(0.0)

        calibration.recordCalibrationOffset(0.020)
        calibration.recordCalibrationOffset(0.030)
        XCTAssertEqual(calibration.sampleCount, 2)
        XCTAssertEqual(calibration.visualOffset, 0.025, accuracy: 0.0001)

        // Outlier > 250ms should be ignored
        calibration.recordCalibrationOffset(0.450)
        XCTAssertEqual(calibration.sampleCount, 2)
        XCTAssertEqual(calibration.visualOffset, 0.025, accuracy: 0.0001)
    }

    func testMIDIMappingAndLearnFlow() throws {
        let dataManager = DataManager.shared
        dataManager.resetMIDIMappingToDefault()

        // Default mapping resolves 12 -> 12 and General MIDI 36 -> 12
        XCTAssertEqual(dataManager.resolveIncomingMIDINote(12), 12)
        XCTAssertEqual(dataManager.resolveIncomingMIDINote(36), 12)

        // Activate MIDI Learn for Kick (canonical 12) and send note 60
        dataManager.toggleMIDILearn(forCanonicalNote: 12)
        XCTAssertEqual(dataManager.learningCanonicalNote, 12)
        let resolved = dataManager.resolveIncomingMIDINote(60)
        XCTAssertEqual(resolved, 12)
        XCTAssertNil(dataManager.learningCanonicalNote)
        XCTAssertEqual(dataManager.physicalNote(forCanonicalNote: 12), 60)
        XCTAssertEqual(dataManager.resolveIncomingMIDINote(60), 12)
    }
}

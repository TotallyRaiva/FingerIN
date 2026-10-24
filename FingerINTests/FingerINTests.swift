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

        XCTAssertEqual(result.barDuration, 2.0, accuracy: 0.0001)
        XCTAssertEqual(result.totalSteps, 16)
        XCTAssertEqual(result.notes.count, 4)
        XCTAssertTrue(result.notes.allSatisfy { activePads.contains($0.padIndex) })

        let firstKick = result.notes.first { $0.padIndex == 12 && $0.stepIndex == 0 }
        let ghostSnare = result.notes.first { $0.padIndex == 13 && $0.stepIndex == 7 }
        XCTAssertEqual(firstKick?.velocity, 124)
        XCTAssertEqual(firstKick?.stepOffsetRatio ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(ghostSnare?.velocity, 52)
        XCTAssertEqual(ghostSnare?.stepOffsetRatio ?? -1, 0.24, accuracy: 0.0001)
    }

    func testMusicStyleBeatVariationsAndLatencyModes() throws {
        for style in MusicStyle.allCases where style != .calibration {
            let variations = LevelProvider.variations(for: style)
            XCTAssertEqual(variations.count, 3, "\(style.rawValue) should provide 3 distinct beat variations")
            for variation in variations {
                XCTAssertEqual(variation.totalSteps, 32, "\(variation.name) should be a 2-bar (32-step) pattern")
                XCTAssertFalse(variation.backingEvents.isEmpty)
            }
        }
        XCTAssertGreaterThan(SampleLatencyMode.instant.trimMilliseconds, SampleLatencyMode.tight.trimMilliseconds)
        XCTAssertEqual(SampleLatencyMode.natural.trimMilliseconds, 0.0)
    }

    func testScoreManagerStreakMultipliersAndAccuracy() throws {
        let scoreManager = ScoreManager.shared
        scoreManager.reset()

        for _ in 0..<10 {
            scoreManager.registerHit(accuracy: .perfect, timingOffsetMs: -4)
        }
        XCTAssertEqual(scoreManager.streak, 10)
        XCTAssertEqual(scoreManager.maxStreak, 10)
        XCTAssertEqual(scoreManager.multiplier, 2)
        XCTAssertEqual(scoreManager.score, 9 * 100 + 200)

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

        calibration.recordCalibrationOffset(0.450)
        XCTAssertEqual(calibration.sampleCount, 2)
        XCTAssertEqual(calibration.visualOffset, 0.025, accuracy: 0.0001)
    }

    func testMIDIMappingAndLearnFlow() throws {
        let dataManager = DataManager.shared
        dataManager.resetMIDIMappingToDefault()

        XCTAssertEqual(dataManager.resolveIncomingMIDINote(12), 12)
        XCTAssertEqual(dataManager.resolveIncomingMIDINote(36), 12)

        dataManager.toggleMIDILearn(forCanonicalNote: 12)
        XCTAssertEqual(dataManager.learningCanonicalNote, 12)
        let resolved = dataManager.resolveIncomingMIDINote(60)
        XCTAssertEqual(resolved, 12)
        XCTAssertNil(dataManager.learningCanonicalNote)
        XCTAssertEqual(dataManager.physicalNote(forCanonicalNote: 12), 60)
        XCTAssertEqual(dataManager.resolveIncomingMIDINote(60), 12)
    }
}

//
//  ContentView.swift
//  FingerIN
//
//  Created by Reiwa on 03.06.2026.
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @ObservedObject var midiManager = MIDIManager.shared
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var scoreManager = ScoreManager.shared
    @ObservedObject var calibration = CalibrationManager.shared
    @ObservedObject var dataManager = DataManager.shared
    
    // Practice Engine State
    @State private var currentBPM: Double = LevelProvider.boomBap.bpm
    @State private var isLooping: Bool = true
    @State private var isMetronomeEnabled: Bool = false
    @State private var isBackingTrackEnabled: Bool = true
    @State private var isDemoMode: Bool = false
    @State private var isPlaying: Bool = false
    @State private var activePads: Set<UInt8> = [12, 13, 14, 15]
    @State private var selectedTemplate: LevelProvider.PatternTemplate = LevelProvider.boomBap
    
    // Scene instance
    @State private var scene: GameScene = {
        let scene = GameScene()
        scene.size = CGSize(width: 920, height: 320)
        scene.scaleMode = .resizeFill
        return scene
    }()
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topControlBar
                
                gameArea(totalSize: geometry.size)
                
                bottomControlBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onAppear {
                audioManager.currentKit = selectedTemplate.recommendedKit
                scene.size = CGSize(width: max(400, geometry.size.width - 180), height: 320)
                reloadLevel(resetSession: true)
            }
            .onChange(of: geometry.size) { _, newSize in
                scene.size = CGSize(width: max(400, newSize.width - 180), height: 320)
            }
        }
        .frame(minWidth: 1180, minHeight: 450)
        .onChange(of: currentBPM) { _, _ in applyLiveSettings() }
        .onChange(of: isLooping) { _, _ in applyLiveSettings() }
        .onChange(of: isMetronomeEnabled) { _, _ in applyLiveSettings() }
        .onChange(of: isBackingTrackEnabled) { _, _ in applyLiveSettings() }
        .onChange(of: isDemoMode) { _, _ in applyLiveSettings() }
        .onChange(of: activePads) { _, _ in applyLiveSettings() }
        .onChange(of: selectedTemplate) { oldTemplate, newTemplate in
            saveCurrentSessionIfNeeded(patternName: oldTemplate.name)
            currentBPM = newTemplate.bpm
            audioManager.currentKit = newTemplate.recommendedKit
            if newTemplate.isCalibration {
                calibration.clearHistory()
                isMetronomeEnabled = true
            }
            reloadLevel(resetSession: true)
        }
    }
    
    // MARK: - Subviews
    
    private var topControlBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("FingerIN").font(.headline).foregroundColor(.white)
                if let accuracy = scoreManager.lastAccuracy {
                    HStack(spacing: 4) {
                        Text(accuracy.rawValue)
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(accuracy.color)
                        if let offsetMs = scoreManager.lastTimingOffsetMs, accuracy != .miss {
                            Text(String(format: "%+dms", offsetMs))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                    .transition(.opacity)
                } else {
                    Text(selectedTemplate.subtitle)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .frame(width: 140, alignment: .leading)
            
            Divider().frame(height: 22)
            
            scoreStreakDisplay
            
            Divider().frame(height: 22)
            
            playbackControls
            
            Divider().frame(height: 22)
            
            bpmControl
            
            Divider().frame(height: 22)
            
            HStack(spacing: 6) {
                Toggle("LOOP", isOn: $isLooping).toggleStyle(.button)
                Toggle("MUSIC", isOn: $isBackingTrackEnabled)
                    .toggleStyle(.button)
                    .tint(.purple)
                    .help("Play musical bassline & electric piano chords along with the groove")
                Toggle("METRO", isOn: $isMetronomeEnabled).toggleStyle(.button)
                Toggle("DEMO", isOn: $isDemoMode).toggleStyle(.button)
            }
            
            Divider().frame(height: 22)
            
            calibrationControlSection
            
            Spacer(minLength: 4)
            
            if let note = midiManager.lastNote {
                let vel = midiManager.lastVelocity ?? 0
                Text("MIDI \(note) (v\(vel))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color.black)
        .controlSize(.small)
    }
    
    private var scoreStreakDisplay: some View {
        HStack(spacing: 12) {
            VStack(alignment: .center, spacing: 0) {
                Text("SCORE").font(.system(size: 8)).foregroundColor(.gray)
                Text("\(scoreManager.score)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            VStack(alignment: .center, spacing: 0) {
                HStack(spacing: 3) {
                    Text("STREAK").font(.system(size: 8)).foregroundColor(.gray)
                    if scoreManager.multiplier > 1 {
                        Text("\(scoreManager.multiplier)x")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
                Text("\(scoreManager.streak)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            VStack(alignment: .center, spacing: 0) {
                Text("ACC").font(.system(size: 8)).foregroundColor(.gray)
                Text(String(format: "%.0f%%", scoreManager.accuracyPercentage))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)
            }
            if let best = dataManager.highScores[selectedTemplate.name], best > 0 {
                VStack(alignment: .center, spacing: 0) {
                    Text("BEST").font(.system(size: 8)).foregroundColor(.gray)
                    Text("\(best)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow)
                }
            }
        }
    }
    
    private var playbackControls: some View {
        HStack(spacing: 8) {
            Button(action: {
                isPlaying.toggle()
                scene.setPaused(!isPlaying)
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.blue)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help("Play / Pause (Space)")
            
            Button(action: {
                isPlaying = false
                saveCurrentSessionIfNeeded(patternName: selectedTemplate.name)
                scene.stopAndClear(resetScore: true)
                reloadLevel(resetSession: true)
                scene.setPaused(true)
            }) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Stop and Reset Session")
        }
    }
    
    private var bpmControl: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text("BPM").font(.system(size: 8)).foregroundColor(.gray)
                if selectedTemplate.swing > 0 {
                    Text("SWING \(Int(50 + selectedTemplate.swing * 50))%")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.mint)
                }
            }
            Text("\(Int(currentBPM))")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 30, alignment: .trailing)
            Slider(value: $currentBPM, in: 60...200, step: 1)
                .frame(width: 75)
        }
    }
    
    private var calibrationControlSection: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedTemplate.isCalibration ? "AUTO (\(calibration.sampleCount)/10)" : "CALIB")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(selectedTemplate.isCalibration ? .cyan : .gray)
                Text(String(format: "%+.0fms", calibration.visualOffset * 1000))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Slider(
                value: Binding(
                    get: { calibration.visualOffset },
                    set: { calibration.saveOffset($0) }
                ),
                in: -0.2...0.2
            )
            .frame(width: 68)
            
            Button("0ms") {
                calibration.clearHistory()
                calibration.saveOffset(0.0)
            }
            .font(.system(size: 8, design: .monospaced))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Reset visual latency calibration to 0ms")
        }
    }
    
    private func gameArea(totalSize: CGSize) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            LeftContextPanel()
            
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .onReceive(midiManager.noteOnPublisher) { event in
                    scene.handleHit(for: event.canonicalNote, velocity: event.velocity)
                }
        }
        .frame(height: 320)
        .background(Color.black)
    }
    
    private var bottomControlBar: some View {
        HStack(spacing: 18) {
            instrumentToggles
            
            Divider().frame(height: 40)
            
            kitSelection
            
            Divider().frame(height: 40)
            
            levelSelection
            
            Spacer(minLength: 4)
            
            VStack(alignment: .trailing, spacing: 3) {
                Text("IN: \(midiManager.connectedDevices.first ?? "Keys [A,S,D,F]")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(midiManager.connectedDevices.isEmpty ? .gray : .green)
                if dataManager.customMIDIMapping != [12: 12, 13: 13, 14: 14, 15: 15] {
                    Button("Reset MIDI Map") {
                        dataManager.resetMIDIMappingToDefault()
                    }
                    .font(.system(size: 8))
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 80)
        .background(Color(white: 0.05))
    }
    
    private var instrumentToggles: some View {
        HStack(spacing: 8) {
            ForEach(DrumVoiceConfig.allVoices) { voice in
                InstrumentToggle(
                    name: voice.shortName,
                    note: voice.canonicalNote,
                    color: voice.color,
                    activePads: $activePads
                )
            }
        }
    }
    
    private var kitSelection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DRUM KIT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            HStack(spacing: 5) {
                ForEach(DrumKit.allCases) { kit in
                    Button(action: {
                        audioManager.currentKit = kit
                        // Audition snare softly when switching kits so user feels the kit change immediately
                        if !isPlaying {
                            audioManager.triggerSound(for: 13, velocity: 95)
                        }
                    }) {
                        Text(kit.displayName)
                            .font(.system(size: 9, weight: audioManager.currentKit == kit ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(audioManager.currentKit == kit ? Color.orange.opacity(0.28) : Color.white.opacity(0.07))
                            .foregroundColor(audioManager.currentKit == kit ? .orange : .gray)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var levelSelection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GROOVE / VARIATION (2 BARS)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            HStack(spacing: 6) {
                ForEach(LevelProvider.allTemplates) { template in
                    Button(action: { selectedTemplate = template }) {
                        Text(template.name)
                            .font(.system(size: 10, weight: selectedTemplate == template ? .bold : .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(selectedTemplate == template ? Color.cyan.opacity(0.25) : Color.white.opacity(0.08))
                            .foregroundColor(selectedTemplate == template ? .cyan : .white)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Engine Helpers
    
    private func buildCurrentPattern() -> (notes: [TrackNote], barDuration: TimeInterval, totalSteps: Int) {
        PatternBuilder.build(
            bpm: currentBPM,
            activePads: activePads,
            kick: selectedTemplate.kick,
            snare: selectedTemplate.snare,
            hatC: selectedTemplate.hatC,
            hatO: selectedTemplate.hatO,
            swing: selectedTemplate.swing
        )
    }
    
    private func reloadLevel(resetSession: Bool) {
        let result = buildCurrentPattern()
        scene.loadLevel(
            notes: result.notes,
            barDuration: result.barDuration,
            totalSteps: result.totalSteps,
            backingEvents: selectedTemplate.backingEvents,
            loop: isLooping,
            metronome: isMetronomeEnabled,
            backingTrack: isBackingTrackEnabled,
            isDemoMode: isDemoMode,
            isCalibrationMode: selectedTemplate.isCalibration,
            activePads: activePads
        )
        scene.setPaused(!isPlaying)
    }
    
    private func applyLiveSettings() {
        let result = buildCurrentPattern()
        scene.updateLiveConfiguration(
            notes: result.notes,
            barDuration: result.barDuration,
            totalSteps: result.totalSteps,
            backingEvents: selectedTemplate.backingEvents,
            loop: isLooping,
            metronome: isMetronomeEnabled,
            backingTrack: isBackingTrackEnabled,
            isDemoMode: isDemoMode,
            isCalibrationMode: selectedTemplate.isCalibration,
            activePads: activePads
        )
        scene.setPaused(!isPlaying)
    }
    
    private func saveCurrentSessionIfNeeded(patternName: String) {
        guard scoreManager.totalJudgedNotes > 0 else { return }
        dataManager.recordSession(
            patternName: patternName,
            bpm: currentBPM,
            score: scoreManager.score,
            maxStreak: scoreManager.maxStreak,
            perfectCount: scoreManager.perfectCount,
            goodCount: scoreManager.goodCount,
            missCount: scoreManager.missCount,
            accuracyPercentage: scoreManager.accuracyPercentage
        )
    }
}

struct InstrumentToggle: View {
    let name: String
    let note: UInt8
    let color: Color
    @Binding var activePads: Set<UInt8>
    @ObservedObject var padStatus = PadStatusManager.shared
    
    var isHighlighted: Bool {
        padStatus.isPadHighlighted[note] ?? false
    }
    
    var body: some View {
        Button(action: {
            if activePads.contains(note) {
                activePads.remove(note)
            } else {
                activePads.insert(note)
            }
        }) {
            VStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 8, weight: .black))
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(activePads.contains(note) ? color : Color.gray.opacity(0.2))
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(isHighlighted ? 0.85 : 0), lineWidth: 2)
                    )
                    .shadow(color: color.opacity(isHighlighted ? 0.65 : 0), radius: 10)
                    .scaleEffect(isHighlighted ? 1.06 : 1.0)
            }
            .foregroundColor(activePads.contains(note) ? .white : .gray)
            .animation(.spring(response: 0.1, dampingFraction: 0.5), value: isHighlighted)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}

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
    @State private var selectedStyle: MusicStyle = .boomBap
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
        .frame(minWidth: 1220, minHeight: 460)
        .onChange(of: currentBPM) { _, _ in applyLiveSettings() }
        .onChange(of: isLooping) { _, _ in applyLiveSettings() }
        .onChange(of: isMetronomeEnabled) { _, _ in applyLiveSettings() }
        .onChange(of: isBackingTrackEnabled) { _, _ in applyLiveSettings() }
        .onChange(of: isDemoMode) { _, _ in applyLiveSettings() }
        .onChange(of: activePads) { _, _ in applyLiveSettings() }
        .onChange(of: selectedTemplate) { oldTemplate, newTemplate in
            saveCurrentSessionIfNeeded(patternName: oldTemplate.name)
            selectedStyle = newTemplate.style
            currentBPM = newTemplate.bpm
            audioManager.currentKit = newTemplate.recommendedKit
            if newTemplate.isCalibration {
                calibration.clearHistory()
                isMetronomeEnabled = true
            }
            reloadLevel(resetSession: true)
        }
    }
    
    // MARK: - Top Control Bar
    
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
            .frame(width: 145, alignment: .leading)
            
            Divider().frame(height: 22)
            
            scoreStreakDisplay
            
            Divider().frame(height: 22)
            
            playbackControls
            
            Divider().frame(height: 22)
            
            bpmControl
            
            Divider().frame(height: 22)
            
            HStack(spacing: 8) {
                musicBandButton
                
                Toggle("LOOP", isOn: $isLooping).toggleStyle(.button)
                Toggle("METRO", isOn: $isMetronomeEnabled).toggleStyle(.button)
                Toggle("DEMO", isOn: $isDemoMode).toggleStyle(.button)
            }
            
            Divider().frame(height: 22)
            
            latencyAndCalibrationSection
            
            Spacer(minLength: 4)
            
            if let note = midiManager.lastNote {
                let vel = midiManager.lastVelocity ?? 0
                Text("MIDI \(note) (v\(vel))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Color.black)
        .controlSize(.small)
    }
    
    /// Visually appealing pill button for the backing Bass + Rhodes Chords accompaniment
    private var musicBandButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isBackingTrackEnabled.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isBackingTrackEnabled ? "waveform.circle.fill" : "waveform.slash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isBackingTrackEnabled ? .cyan : .gray)
                    .symbolEffect(.pulse, isActive: isBackingTrackEnabled && isPlaying)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("MUSIC")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(isBackingTrackEnabled ? .white : .gray)
                    Text(isBackingTrackEnabled ? "BASS + KEYS" : "MUTED")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(isBackingTrackEnabled ? .cyan.opacity(0.9) : .gray.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    if isBackingTrackEnabled {
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(0.65),
                                Color.indigo.opacity(0.65),
                                Color.cyan.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isBackingTrackEnabled
                            ? LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.05)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: isBackingTrackEnabled ? 1.5 : 1.0
                    )
            )
            .shadow(color: isBackingTrackEnabled ? Color.purple.opacity(0.55) : .clear, radius: 6, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .help("Toggle live Bassline & Fender Rhodes Chords accompaniment")
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
                .frame(width: 70)
        }
    }
    
    /// Sample Attack Latency Mode selector + Visual Offset Calibration
    private var latencyAndCalibrationSection: some View {
        HStack(spacing: 10) {
            // Sample Attack Trim (eliminates pre-peak sample onset delay)
            VStack(alignment: .leading, spacing: 2) {
                Text("SAMPLE LATENCY")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                HStack(spacing: 3) {
                    ForEach(SampleLatencyMode.allCases) { mode in
                        Button(action: {
                            audioManager.sampleLatencyMode = mode
                            if !isPlaying {
                                audioManager.triggerSound(for: 13, velocity: 105)
                            }
                        }) {
                            Text(mode.shortLabel)
                                .font(.system(size: 8, weight: audioManager.sampleLatencyMode == mode ? .black : .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(audioManager.sampleLatencyMode == mode ? Color.green.opacity(0.28) : Color.white.opacity(0.07))
                                .foregroundColor(audioManager.sampleLatencyMode == mode ? .green : .gray)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help("Sample transient trim: \(mode.rawValue)")
                    }
                }
            }
            
            // Visual Hit-Line Offset Calibration
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedTemplate.isCalibration ? "AUTO (\(calibration.sampleCount)/10)" : "SYNC")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(selectedTemplate.isCalibration ? .cyan : .gray)
                    Text(String(format: "%+.0fms", calibration.visualOffset * 1000))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange)
                }
                Slider(
                    value: Binding(
                        get: { calibration.visualOffset },
                        set: { calibration.saveOffset($0) }
                    ),
                    in: -0.2...0.2
                )
                .frame(width: 58)
                
                Button("0") {
                    calibration.clearHistory()
                    calibration.saveOffset(0.0)
                }
                .font(.system(size: 8, design: .monospaced))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Reset visual latency offset to 0ms")
            }
        }
    }
    
    // MARK: - Game Area
    
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
    
    // MARK: - Bottom Control Bar (Instruments, Drum Kits, Styles & Beat Variations)
    
    private var bottomControlBar: some View {
        HStack(spacing: 14) {
            instrumentToggles
            
            Divider().frame(height: 44)
            
            kitSelection
            
            Divider().frame(height: 44)
            
            styleAndVariationSelection
            
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
        .frame(height: 86)
        .background(Color(white: 0.05))
    }
    
    private var instrumentToggles: some View {
        HStack(spacing: 7) {
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
        VStack(alignment: .leading, spacing: 5) {
            Text("DRUM KIT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            HStack(spacing: 4) {
                ForEach(DrumKit.allCases) { kit in
                    Button(action: {
                        audioManager.currentKit = kit
                        if !isPlaying {
                            audioManager.triggerSound(for: 13, velocity: 95)
                        }
                    }) {
                        Text(kit.displayName)
                            .font(.system(size: 9, weight: audioManager.currentKit == kit ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(audioManager.currentKit == kit ? Color.orange.opacity(0.28) : Color.white.opacity(0.07))
                            .foregroundColor(audioManager.currentKit == kit ? .orange : .gray)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var styleAndVariationSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Music Style tabs
            HStack(spacing: 5) {
                Text("STYLE:")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 44, alignment: .leading)
                
                ForEach(MusicStyle.allCases) { style in
                    Button(action: {
                        selectedStyle = style
                        if let firstVar = LevelProvider.variations(for: style).first {
                            selectedTemplate = firstVar
                        }
                    }) {
                        Text(style.rawValue)
                            .font(.system(size: 9, weight: selectedStyle == style ? .bold : .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(selectedStyle == style ? Color.cyan.opacity(0.26) : Color.white.opacity(0.07))
                            .foregroundColor(selectedStyle == style ? .cyan : .white.opacity(0.8))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Row 2: Beat Variations within the selected Music Style
            HStack(spacing: 6) {
                Text("BEAT:")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 44, alignment: .leading)
                
                let variations = LevelProvider.variations(for: selectedStyle)
                ForEach(variations) { variation in
                    let isSelected = (selectedTemplate == variation)
                    Button(action: {
                        selectedTemplate = variation
                    }) {
                        HStack(spacing: 4) {
                            Text(variation.variationName)
                                .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .monospaced))
                            Text("\(Int(variation.bpm))")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundColor(isSelected ? .mint : .gray)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            isSelected
                                ? LinearGradient(colors: [Color.mint.opacity(0.32), Color.cyan.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(isSelected ? .mint : .gray)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.mint.opacity(0.6) : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(4)
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
                    .frame(width: 36, height: 36)
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

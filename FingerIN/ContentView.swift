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
    @ObservedObject var padStatus = PadStatusManager.shared
    
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
    @State private var inspectedBarIndex: Int = 0 // 0 = Bar 1 (steps 0..15), 1 = Bar 2 (steps 16..31)
    
    // Scene instance
    @State private var scene: GameScene = {
        let scene = GameScene()
        scene.size = CGSize(width: 960, height: 320)
        scene.scaleMode = .resizeFill
        return scene
    }()
    
    /// Which bar (0 or 1) is currently shown in the 16-step matrix preview
    private var displayedBarIndex: Int {
        if isPlaying, let liveStep = padStatus.activePatternStep {
            return (liveStep >= 16 && selectedTemplate.totalSteps > 16) ? 1 : 0
        }
        return inspectedBarIndex
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Warm Vintage MPC Cream/Beige Halftone Background
                MPCTheme.mpcCream
                    .ignoresSafeArea()
                
                HalftonePatternBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    topHardwareDeck
                    
                    gameStageCard(totalWidth: geometry.size.width)
                    
                    bottomGrooveExplorerCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                audioManager.currentKit = selectedTemplate.recommendedKit
                scene.size = CGSize(width: max(400, geometry.size.width - 244), height: 320)
                reloadLevel(resetSession: true)
            }
            .onChange(of: geometry.size) { _, newSize in
                scene.size = CGSize(width: max(400, newSize.width - 244), height: 320)
            }
        }
        .frame(minWidth: 1240, minHeight: 740)
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
            inspectedBarIndex = 0
            audioManager.currentKit = newTemplate.recommendedKit
            if newTemplate.isCalibration {
                calibration.clearHistory()
                isMetronomeEnabled = true
            }
            reloadLevel(resetSession: true)
        }
    }
    
    // MARK: - 1. Top Retro MPC Hardware Deck (Brand + Backlit Green LCD + Transport & Kit Controls)
    
    private var topHardwareDeck: some View {
        HStack(spacing: 12) {
            // Left: PAD A01 Brand Plate + Play/Stop Transport
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("PAD A01")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(MPCTheme.ink)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(MPCTheme.ink, lineWidth: 1.5))
                            .shadow(color: .red.opacity(0.8), radius: 4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MPCTheme.mpcCream)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(MPCTheme.ink, lineWidth: 2))
                    
                    Text("FingerIN")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(MPCTheme.ink)
                }
                
                playbackControls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MPCTheme.mpcBeige)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MPCTheme.ink, lineWidth: 2.5))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(MPCTheme.ink)
                    .offset(x: 4, y: 4)
            )
            
            // Center: Backlit Retro Green MPC LCD Screen
            mpcLCDScreen
            
            // Right: Tactile Hardware Controls (MUSIC, Modes, BPM, Kit, Sample Latency, Sync)
            HStack(spacing: 10) {
                musicBandButton
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        hardwareTogglePill("LOOP", isOn: $isLooping, activeColor: MPCTheme.closedHat)
                        hardwareTogglePill("METRO", isOn: $isMetronomeEnabled, activeColor: MPCTheme.snare)
                        hardwareTogglePill("DEMO", isOn: $isDemoMode, activeColor: MPCTheme.openHat)
                    }
                    bpmControl
                }
                
                Divider().frame(height: 44)
                
                kitAndLatencyColumn
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MPCTheme.mpcBeige)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MPCTheme.ink, lineWidth: 2.5))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(MPCTheme.ink)
                    .offset(x: 4, y: 4)
            )
        }
        .frame(height: 76)
    }
    
    private var mpcLCDScreen: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top LCD metadata strip
            HStack(spacing: 10) {
                Text("KIT: \(audioManager.currentKit.displayName)")
                Text("·")
                Text("BPM: \(Int(currentBPM)) (SWING \(Int(50 + selectedTemplate.swing * 50))%)")
                Spacer(minLength: 4)
                if let note = midiManager.lastNote {
                    let vel = midiManager.lastVelocity ?? 0
                    Text("MIDI N\(note) V\(vel)")
                        .foregroundColor(.white)
                } else {
                    Text(midiManager.connectedDevices.first ?? "KEYS [A,S,D,F]")
                }
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(MPCTheme.lcdGlow.opacity(0.85))
            
            Rectangle()
                .fill(MPCTheme.lcdDim)
                .frame(height: 1)
            
            // Main LCD groove & score readout
            HStack(spacing: 12) {
                Text("\(selectedStyle.rawValue) · \(selectedTemplate.variationName.uppercased())")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: MPCTheme.lcdGlow.opacity(0.6), radius: 4)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if let accuracy = scoreManager.lastAccuracy {
                    HStack(spacing: 4) {
                        Text(accuracy.rawValue)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                        if let offsetMs = scoreManager.lastTimingOffsetMs, accuracy != .miss {
                            Text(String(format: "%+dms", offsetMs))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(MPCTheme.lcdGlow.opacity(0.18))
                    .foregroundColor(accuracy == .miss ? MPCTheme.kick : MPCTheme.lcdGlow)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                HStack(spacing: 10) {
                    Text("SCORE \(scoreManager.score)")
                    Text("STRK \(scoreManager.streak)\(scoreManager.multiplier > 1 ? " (\(scoreManager.multiplier)x)" : "")")
                        .foregroundColor(MPCTheme.snare)
                    Text(String(format: "ACC %.0f%%", scoreManager.accuracyPercentage))
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(MPCTheme.lcdGlow)
            }
            
            // 16-Step LCD Playhead Bar
            HStack(spacing: 3) {
                let activeStepMod16 = (padStatus.activePatternStep ?? -1) % 16
                ForEach(0..<16, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            step == activeStepMod16
                                ? MPCTheme.lcdGlow
                                : (step % 4 == 0 ? MPCTheme.lcdDim : MPCTheme.lcdDim.opacity(0.45))
                        )
                        .frame(height: 5)
                        .shadow(color: step == activeStepMod16 ? MPCTheme.lcdGlow : .clear, radius: 3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(MPCTheme.lcdBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MPCTheme.ink, lineWidth: 2.5))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(MPCTheme.ink)
                .offset(x: 4, y: 4)
        )
    }
    
    private var playbackControls: some View {
        HStack(spacing: 6) {
            Button(action: {
                isPlaying.toggle()
                scene.setPaused(!isPlaying)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .black))
                    Text(isPlaying ? "PAUSE" : "PLAY")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .foregroundColor( isPlaying ? MPCTheme.ink : .white)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(isPlaying ? MPCTheme.closedHat : MPCTheme.kick)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(MPCTheme.ink, lineWidth: 2))
                .background(RoundedRectangle(cornerRadius: 9).fill(MPCTheme.ink).offset(x: 2.5, y: 2.5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help("Play / Pause Groove (Space)")
            
            Button(action: {
                isPlaying = false
                saveCurrentSessionIfNeeded(patternName: selectedTemplate.name)
                scene.stopAndClear(resetScore: true)
                reloadLevel(resetSession: true)
                scene.setPaused(true)
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(MPCTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(MPCTheme.ink, lineWidth: 2))
                    .background(RoundedRectangle(cornerRadius: 9).fill(MPCTheme.ink).offset(x: 2.5, y: 2.5))
            }
            .buttonStyle(.plain)
            .help("Stop and Reset Session")
        }
    }
    
    private func hardwareTogglePill(_ title: String, isOn: Binding<Bool>, activeColor: Color) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn.wrappedValue ? activeColor : Color.white)
                .foregroundColor(MPCTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MPCTheme.ink, lineWidth: 1.8))
                .background(RoundedRectangle(cornerRadius: 6).fill(MPCTheme.ink).offset(x: 2, y: 2))
        }
        .buttonStyle(.plain)
    }
    
    private var musicBandButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                isBackingTrackEnabled.toggle()
            }
        }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: isBackingTrackEnabled ? "pianokeys.inverse" : "speaker.slash.fill")
                        .font(.system(size: 11, weight: .black))
                    Text("MUSIC")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                Text(isBackingTrackEnabled ? "BASS + KEYS" : "DRUMS ONLY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .opacity(0.85)
            }
            .foregroundColor(MPCTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isBackingTrackEnabled ? Color(red: 0.78, green: 0.71, blue: 1.0) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MPCTheme.ink, lineWidth: 2))
            .background(RoundedRectangle(cornerRadius: 10).fill(MPCTheme.ink).offset(x: 2.5, y: 2.5))
        }
        .buttonStyle(.plain)
        .help("Toggle live Fender Rhodes & Bassline accompaniment")
    }
    
    private var bpmControl: some View {
        HStack(spacing: 6) {
            Text("BPM \(Int(currentBPM))")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(MPCTheme.ink)
                .frame(width: 52, alignment: .leading)
            Slider(value: $currentBPM, in: 60...200, step: 1)
                .frame(width: 82)
                .tint(MPCTheme.kick)
        }
    }
    
    private var kitAndLatencyColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: 5 Studio Drum Kits
            HStack(spacing: 4) {
                Text("KIT:")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(MPCTheme.ink)
                ForEach(DrumKit.allCases) { kit in
                    let isSelected = (audioManager.currentKit == kit)
                    Button(action: {
                        audioManager.currentKit = kit
                        if !isPlaying {
                            audioManager.triggerSound(for: 13, velocity: 98)
                        }
                    }) {
                        Text(kit.displayName)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isSelected ? MPCTheme.snare : Color.white)
                            .foregroundColor(MPCTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(MPCTheme.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Row 2: Sample Trim Latency Mode + Sync Offset
            HStack(spacing: 6) {
                Text("TRIM:")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(MPCTheme.ink)
                ForEach(SampleLatencyMode.allCases) { mode in
                    let isSelected = (audioManager.sampleLatencyMode == mode)
                    Button(action: {
                        audioManager.sampleLatencyMode = mode
                        if !isPlaying {
                            audioManager.triggerSound(for: 13, velocity: 105)
                        }
                    }) {
                        Text(mode.shortLabel)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(isSelected ? MPCTheme.closedHat : Color.white)
                            .foregroundColor(MPCTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MPCTheme.ink, lineWidth: 1.4))
                    }
                    .buttonStyle(.plain)
                }
                
                Text(String(format: "SYNC %+.0fms", calibration.visualOffset * 1000))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(MPCTheme.ink)
                
                Slider(
                    value: Binding(
                        get: { calibration.visualOffset },
                        set: { calibration.saveOffset($0) }
                    ),
                    in: -0.2...0.2
                )
                .frame(width: 48)
                .tint(MPCTheme.ink)
                
                if dataManager.customMIDIMapping != [12: 12, 13: 13, 14: 14, 15: 15] {
                    Button("RST MAP") {
                        dataManager.resetMIDIMappingToDefault()
                    }
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(MPCTheme.kick)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
    
    // MARK: - 2. Middle 120Hz Falling-Note Rhythm Stage
    
    private func gameStageCard(totalWidth: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            LeftContextPanel(activePads: $activePads)
            
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .onReceive(midiManager.noteOnPublisher) { event in
                    scene.handleHit(for: event.canonicalNote, velocity: event.velocity)
                }
        }
        .frame(height: 320)
        .background(MPCTheme.mpcPanel)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(MPCTheme.ink, lineWidth: 3.5)
        )
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(MPCTheme.ink)
                .offset(x: 6, y: 6)
        )
    }
    
    // MARK: - 3. Bottom Comix × Retro MPC Groove Explorer & 16-Step Matrix Card
    
    private var bottomGrooveExplorerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Chunky Music Style Tabs (Yellow active tab with hard black shadow)
            HStack(spacing: 8) {
                ForEach(MusicStyle.allCases) { style in
                    let isSelected = (selectedStyle == style)
                    let defaultBPM = Int(LevelProvider.variations(for: style).first?.bpm ?? 100)
                    Button(action: {
                        selectedStyle = style
                        if let firstVar = LevelProvider.variations(for: style).first {
                            selectedTemplate = firstVar
                        }
                    }) {
                        Text(style == .calibration ? "CALIBRATION" : "\(style.rawValue) (\(defaultBPM) BPM)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(isSelected ? MPCTheme.snare : MPCTheme.mpcSlate)
                            .foregroundColor(isSelected ? MPCTheme.ink : Color(white: 0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(MPCTheme.ink, lineWidth: 2.5)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected ? Color.black : Color.clear)
                                    .offset(x: 3, y: 3)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 4)
                
                // Bar 1 / Bar 2 Matrix Inspector Toggle
                if selectedTemplate.totalSteps > 16 {
                    HStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { barIdx in
                            let isBarActive = (displayedBarIndex == barIdx)
                            Button(action: {
                                inspectedBarIndex = barIdx
                            }) {
                                Text("BAR \(barIdx + 1)")
                                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(isBarActive ? MPCTheme.snare : MPCTheme.mpcPanel)
                                    .foregroundColor(isBarActive ? MPCTheme.ink : .gray)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(isBarActive ? MPCTheme.ink : Color.white.opacity(0.18), lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Row 2: Pill-Shaped Beat Variation Tabs (Orange-Red active pill with white rim)
            HStack(spacing: 8) {
                let variations = LevelProvider.variations(for: selectedStyle)
                ForEach(variations) { variation in
                    let isSelected = (selectedTemplate == variation)
                    Button(action: {
                        selectedTemplate = variation
                    }) {
                        Text("Beat \(variation.variationIndex): \(variation.variationName)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5)
                            .background(isSelected ? MPCTheme.kick : Color.clear)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.white : Color.white.opacity(0.25), lineWidth: 1.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 4)
                
                if let best = dataManager.highScores[selectedTemplate.name], best > 0 {
                    Text("HIGH SCORE: \(best)")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundColor(MPCTheme.snare)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(MPCTheme.mpcPanel)
                        .clipShape(Capsule())
                }
            }
            
            // Row 3: Groove Details Banner (#14161B card with bold yellow headline & spec pills)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedStyle.rawValue) — BEAT \(selectedTemplate.variationIndex): \(selectedTemplate.variationName.uppercased())")
                        .font(.system(size: 13.5, weight: .black, design: .rounded))
                        .foregroundColor(MPCTheme.snare)
                    Text(selectedTemplate.subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color(white: 0.74))
                }
                
                Spacer(minLength: 8)
                
                HStack(spacing: 8) {
                    specPill("\(Int(currentBPM)) BPM")
                    specPill(selectedTemplate.swing > 0 ? "\(Int(50 + selectedTemplate.swing * 50))% Swing" : "50% Straight")
                    specPill("\(selectedTemplate.totalSteps / 16) Bars · \(selectedTemplate.totalSteps) Steps")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(MPCTheme.mpcPanel)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
            )
            
            // Row 4: Live 4-Lane x 16-Step Matrix Grid (Kick, Snare, Cl-Hat, Op-Hat)
            stepMatrixGridView
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(MPCTheme.mpcChassis)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(MPCTheme.ink, lineWidth: 3.5)
        )
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(MPCTheme.ink)
                .offset(x: 6, y: 6)
        )
    }
    
    private func specPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(red: 0.145, green: 0.161, blue: 0.196))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
            )
    }
    
    private var stepMatrixGridView: some View {
        let barOffset = displayedBarIndex * 16
        let liveStep = padStatus.activePatternStep
        
        return VStack(spacing: 5) {
            ForEach(DrumVoiceConfig.allVoices) { voice in
                let isLaneActive = activePads.contains(voice.canonicalNote)
                let stepsArray = patternArray(for: voice.canonicalNote)
                
                HStack(spacing: 6) {
                    // Left Lane Label (Click to mute/unmute lane)
                    Button(action: {
                        if activePads.contains(voice.canonicalNote) {
                            activePads.remove(voice.canonicalNote)
                        } else {
                            activePads.insert(voice.canonicalNote)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isLaneActive ? voice.color : Color.gray.opacity(0.35))
                                .frame(width: 8, height: 8)
                            Text(voice.matrixLabel)
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(isLaneActive ? .white : .gray)
                                .strikethrough(!isLaneActive, color: .red)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 110, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Click to toggle \(voice.fullName) lane")
                    
                    // 16 Step Cells for the currently displayed bar
                    HStack(spacing: 5) {
                        ForEach(0..<16, id: \.self) { localStep in
                            let absStep = barOffset + localStep
                            let stepValue = (absStep < stepsArray.count) ? stepsArray[absStep] : 0
                            let isHit = isLaneActive && (stepValue > 0)
                            let isPlayhead = (liveStep == absStep)
                            let isDownbeat = (localStep % 4 == 0)
                            
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    isHit
                                        ? voice.color.opacity(stepValue == 2 ? 0.55 : 1.0)
                                        : MPCTheme.mpcPanel
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(
                                            isPlayhead
                                                ? Color.white
                                                : (isHit ? voice.color.opacity(0.9) : Color.white.opacity(isDownbeat ? 0.26 : 0.10)),
                                            lineWidth: isPlayhead ? 2.2 : 1.2
                                        )
                                )
                                .shadow(
                                    color: isHit ? voice.color.opacity(isPlayhead ? 0.85 : 0.42) : .clear,
                                    radius: isPlayhead ? 7 : 4
                                )
                        }
                    }
                }
            }
        }
    }
    
    private func patternArray(for canonicalNote: UInt8) -> [Int] {
        switch canonicalNote {
        case 12: return selectedTemplate.kick
        case 13: return selectedTemplate.snare
        case 14: return selectedTemplate.hatC
        case 15: return selectedTemplate.hatO
        default: return []
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

/// Subtle Ben-Day comic halftone dot pattern matching the web showcase background
struct HalftonePatternBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dotRadius: CGFloat = 1.15
            let dotColor = Color(red: 0.067, green: 0.071, blue: 0.086).opacity(0.10)
            
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : (spacing / 2)
                while x < size.width {
                    let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
}

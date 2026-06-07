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
    @ObservedObject var scoreManager = ScoreManager.shared
    
    // Practice Engine State
    @State private var currentBPM: Double = 120
    @State private var isLooping: Bool = true
    @State private var isMetronomeEnabled: Bool = false
    @State private var isDemoMode: Bool = false
    @State private var isPlaying: Bool = true
    @State private var activePads: Set<UInt8> = [12, 13, 14, 15]
    @State private var selectedTemplate: LevelProvider.PatternTemplate = LevelProvider.rock
    
    // Scene instance
    @State private var scene: GameScene = {
        let scene = GameScene()
        scene.size = CGSize(width: 800, height: 320)
        scene.scaleMode = .aspectFill
        return scene
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            topControlBar
            gameArea
            bottomControlBar
        }
        .frame(minWidth: 1000, minHeight: 450)
        .onChange(of: currentBPM) { _, _ in reloadLevel() }
        .onChange(of: isLooping) { _, _ in reloadLevel() }
        .onChange(of: isMetronomeEnabled) { _, _ in reloadLevel() }
        .onChange(of: isDemoMode) { _, _ in reloadLevel() }
        .onChange(of: activePads) { _, _ in reloadLevel() }
        .onChange(of: selectedTemplate) { _, newValue in 
            currentBPM = newValue.bpm
            reloadLevel() 
        }
        .onAppear { reloadLevel() }
    }
    
    // MARK: - Subviews
    
    private var topControlBar: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text("FingerIN").font(.headline).foregroundColor(.white)
                if let accuracy = scoreManager.lastAccuracy {
                    Text(accuracy.rawValue)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(accuracy.color)
                        .transition(.opacity)
                }
            }
            .frame(width: 100, alignment: .leading)
            
            Divider().frame(height: 20)
            
            scoreStreakDisplay
            
            Divider().frame(height: 20)
            
            playbackControls
            
            Divider().frame(height: 20)
            
            bpmControl
            
            Divider().frame(height: 20)
            
            Toggle("LOOP", isOn: $isLooping).toggleStyle(.button)
            Toggle("METRO", isOn: $isMetronomeEnabled).toggleStyle(.button)
            Toggle("DEMO", isOn: $isDemoMode).toggleStyle(.button)
            
            Spacer()
            
            if let note = midiManager.lastNote {
                Text("MIDI: \(note)").font(.caption).monospaced().foregroundColor(.cyan)
            }
        }
        .padding(.horizontal)
        .frame(height: 50)
        .background(Color.black)
        .controlSize(.small)
    }
    
    private var scoreStreakDisplay: some View {
        HStack(spacing: 15) {
            VStack(alignment: .center) {
                Text("SCORE").font(.system(size: 8)).foregroundColor(.gray)
                Text("\(scoreManager.score)").font(.system(size: 16, weight: .bold)).monospaced()
            }
            VStack(alignment: .center) {
                Text("STREAK").font(.system(size: 8)).foregroundColor(.gray)
                Text("\(scoreManager.streak)").font(.system(size: 16, weight: .bold)).monospaced().foregroundColor(.orange)
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
            
            Button(action: { 
                isPlaying = false
                scene.stopAndClear()
                reloadLevel()
                scene.setPaused(true)
            }) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var bpmControl: some View {
        HStack {
            Text("BPM:").font(.caption).foregroundColor(.gray)
            Text("\(Int(currentBPM))").font(.headline).monospaced().foregroundColor(.cyan)
            Slider(value: $currentBPM, in: 60...200, step: 1)
                .frame(width: 80)
        }
    }
    
    private var gameArea: some View {
        HStack(alignment: .bottom, spacing: 0) {
            LeftContextPanel()
            
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .onReceive(midiManager.$lastNote) { note in
                    if let noteValue = note {
                        scene.handleHit(for: UInt8(noteValue))
                    }
                }
        }
        .frame(height: 320)
        .background(Color.black)
    }
    
    private var bottomControlBar: some View {
        HStack(spacing: 30) {
            instrumentToggles
            
            Divider().frame(height: 40)
            
            levelSelection
            
            Spacer()
            
            Text("DEVICE: \(midiManager.connectedDevices.first ?? "None")")
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
        .padding()
        .frame(height: 80)
        .background(Color(white: 0.05))
    }
    
    private var instrumentToggles: some View {
        HStack(spacing: 10) {
            InstrumentToggle(name: "KICK", note: 12, color: .cyan, activePads: $activePads)
            InstrumentToggle(name: "SNARE", note: 13, color: .orange, activePads: $activePads)
            InstrumentToggle(name: "HH C", note: 14, color: .yellow, activePads: $activePads)
            InstrumentToggle(name: "HH O", note: 15, color: .yellow, activePads: $activePads)
        }
    }
    
    private var levelSelection: some View {
        HStack(spacing: 12) {
            Button("ROCK") { selectedTemplate = LevelProvider.rock }
            Button("HOUSE") { selectedTemplate = LevelProvider.house }
            Button("BOOM BAP") { selectedTemplate = LevelProvider.boomBap }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    private func reloadLevel() {
        let result = PatternBuilder.build(
            bpm: currentBPM,
            activePads: activePads,
            kick: selectedTemplate.kick,
            snare: selectedTemplate.snare,
            hatC: selectedTemplate.hatC,
            hatO: selectedTemplate.hatO
        )
        
        scene.loadLevel(
            notes: result.notes,
            barDuration: result.barDuration,
            loop: isLooping,
            metronome: isMetronomeEnabled,
            isDemoMode: isDemoMode
        )
    }
}

struct InstrumentToggle: View {
    let name: String
    let note: UInt8
    let color: Color
    @Binding var activePads: Set<UInt8>
    
    var body: some View {
        Button(action: {
            if activePads.contains(note) {
                activePads.remove(note)
            } else {
                activePads.insert(note)
            }
        }) {
            Text(name)
                .font(.caption2).bold()
                .frame(width: 50, height: 30)
                .background(activePads.contains(note) ? color.opacity(0.8) : Color.gray.opacity(0.2))
                .foregroundColor(activePads.contains(note) ? .black : .gray)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}

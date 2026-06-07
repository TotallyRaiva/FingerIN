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
    
    // Practice Engine State
    @State private var currentBPM: Double = 120
    @State private var isLooping: Bool = true
    @State private var isMetronomeEnabled: Bool = false
    @State private var isPlaying: Bool = true
    @State private var activePads: Set<UInt8> = [12, 13, 14, 15] // All pads active by default
    @State private var selectedTemplate: LevelProvider.PatternTemplate = LevelProvider.rock
    
    // Scene instance
    @State private var scene: GameScene = {
        let scene = GameScene()
        // Force size to match the 4-lane height (80 * 4)
        scene.size = CGSize(width: 800, height: 320)
        scene.scaleMode = .aspectFill // Ensure it fills the container without distortion
        return scene
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Top: Control Bar
            HStack(spacing: 20) {
                Text("FingerIN").font(.headline).foregroundColor(.white)
                
                Divider().frame(height: 20)
                
                // Playback Controls
                HStack(spacing: 8) {
                    // Play/Pause Button
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
                    
                    // Stop/Reset Button
                    Button(action: { 
                        isPlaying = false
                        scene.stopAndClear()
                        // Reload at the start of the bar but stay paused
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
                
                Divider().frame(height: 20)
                
                // BPM Control
                HStack {
                    Text("BPM:").font(.caption).foregroundColor(.gray)
                    Text("\(Int(currentBPM))").font(.headline).monospaced().foregroundColor(.cyan)
                    Slider(value: $currentBPM, in: 60...200, step: 1)
                        .frame(width: 100)
                }
                
                Divider().frame(height: 20)
                
                // Looping & Metro Toggles
                Toggle("LOOP", isOn: $isLooping).toggleStyle(.button)
                Toggle("METRO", isOn: $isMetronomeEnabled).toggleStyle(.button)
                
                Spacer()
                
                if let note = midiManager.lastNote {
                    Text("MIDI NOTE: \(note)").font(.caption).monospaced().foregroundColor(.cyan)
                }
            }
            .padding(.horizontal)
            .frame(height: 50)
            .background(Color.black)
            .controlSize(.small)
            
            // Middle: Game Area
            HStack(alignment: .bottom, spacing: 0) {
                // Left: Spatial Mapping Panel
                LeftContextPanel()
                
                // Right: Scrolling Timeline
                SpriteView(scene: scene)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320) // Exactly 4 lanes * 80px
                    .onReceive(midiManager.$lastNote) { note in
                        if let noteValue = note {
                            scene.flashLane(for: UInt8(noteValue))
                        }
                    }
            }
            .frame(height: 320)
            .background(Color.black)
            
            // Bottom: Instrument Toggles & Level Selection
            HStack(spacing: 30) {
                // Instrument Isolation (Complexity Mode)
                HStack(spacing: 10) {
                    InstrumentToggle(name: "KICK", note: 12, color: .cyan, activePads: $activePads)
                    InstrumentToggle(name: "SNARE", note: 13, color: .orange, activePads: $activePads)
                    InstrumentToggle(name: "HH C", note: 14, color: .yellow, activePads: $activePads)
                    InstrumentToggle(name: "HH O", note: 15, color: .yellow, activePads: $activePads)
                }
                
                Divider().frame(height: 40)
                
                // Level Selection
                HStack(spacing: 12) {
                    Button("ROCK") { selectedTemplate = LevelProvider.rock }
                    Button("HOUSE") { selectedTemplate = LevelProvider.house }
                    Button("BOOM BAP") { selectedTemplate = LevelProvider.boomBap }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                VStack(alignment: .leading) {
                    Text("MIDI: \(midiManager.connectedDevices.first ?? "None")").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
            .padding()
            .frame(height: 80)
            .background(Color(white: 0.05))
        }
        .frame(minWidth: 1000, minHeight: 450)
        .onChange(of: currentBPM) { _, _ in reloadLevel() }
        .onChange(of: isLooping) { _, _ in reloadLevel() }
        .onChange(of: isMetronomeEnabled) { _, _ in reloadLevel() }
        .onChange(of: activePads) { _, _ in reloadLevel() }
        .onChange(of: selectedTemplate) { _, newValue in 
            currentBPM = newValue.bpm
            reloadLevel() 
        }
        .onAppear { reloadLevel() }
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
            metronome: isMetronomeEnabled
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

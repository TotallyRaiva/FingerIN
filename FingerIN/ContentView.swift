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
    
    // Use a computed property or a persistent object to ensure the scene isn't lost
    // Better yet, use a dedicated ViewModel or simple container
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
            // Top: Control Bar (Future Overview)
            HStack {
                Text("FingerIN").font(.headline).foregroundColor(.white)
                Spacer()
                if let note = midiManager.lastNote {
                    Text("MIDI NOTE: \(note)").font(.caption).monospaced().foregroundColor(.cyan)
                }
            }
            .padding(.horizontal)
            .frame(height: 40)
            .background(Color.black)
            
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
            
            // Bottom: Device Info & Test Controls
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("MIDI Devices:").font(.caption).bold()
                    ForEach(midiManager.connectedDevices, id: \.self) { device in
                        Text("• \(device)").font(.system(size: 9))
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                
                Spacer()
                
                // Level Controls
                HStack(spacing: 12) {
                    Button("ROCK") { scene.loadLevel(notes: LevelProvider.rockPattern) }
                    Button("HOUSE") { scene.loadLevel(notes: LevelProvider.housePattern) }
                    Button("BOOM BAP") { scene.loadLevel(notes: LevelProvider.boomBapPattern) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Spacer()
                
                HStack {
                    Button("KICK") { scene.spawnNote(for: 12) }
                    Button("SNARE") { scene.spawnNote(for: 13, travelTime: 3.0) }
                    Button("HH C") { scene.spawnNote(for: 14, travelTime: 1.5) }
                    Button("HH O") { scene.spawnNote(for: 15, travelTime: 4.0) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.05))
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}

#Preview {
    ContentView()
}

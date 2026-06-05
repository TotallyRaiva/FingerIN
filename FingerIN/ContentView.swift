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
    @State private var scene: GameScene = {
        let scene = GameScene()
        scene.size = CGSize(width: 400, height: 600)
        scene.scaleMode = .fill
        return scene
    }()
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Side: Game Timeline
            SpriteView(scene: scene)
                .frame(width: 400, height: 600)
                .onReceive(midiManager.$lastNote) { note in
                    if let noteValue = note {
                        print("ContentView: Received Note \(noteValue), flashing lane...")
                        scene.flashLane(for: UInt8(noteValue))
                    }
                }
            
            // Right Side: Controls & Info
            VStack(spacing: 20) {
                Text("FingerIN")
                    .font(.largeTitle)
                    .bold()
                
                VStack(alignment: .leading) {
                    Text("MIDI Devices:")
                        .font(.headline)
                    ForEach(midiManager.connectedDevices, id: \.self) { device in
                        Text("• \(device)").font(.caption)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Divider()
                
                // Test Controls
                VStack {
                    Text("Spawn Test Notes")
                        .font(.headline)
                    HStack {
                        Button("Kick (12)") { scene.spawnNote(for: 12) }
                        Button("Snare (13)") { scene.spawnNote(for: 13) }
                    }
                    HStack {
                        Button("HH C (14)") { scene.spawnNote(for: 14) }
                        Button("HH O (15)") { scene.spawnNote(for: 15) }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                if let note = midiManager.lastNote {
                    VStack {
                        Text("Last Pad Hit: \(note)")
                            .font(.headline)
                            .foregroundColor(.cyan)
                    }
                }
            }
            .padding()
            .frame(width: 300)
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  FingerIN
//
//  Created by Reiwa on 03.06.2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var midiManager = MIDIManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "pianokeys")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            Text("FingerIN MIDI Sniffer")
                .font(.title)
            
            VStack(alignment: .leading) {
                Text("Connected Devices:")
                    .font(.headline)
                if midiManager.connectedDevices.isEmpty {
                    Text("No MIDI devices detected.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(midiManager.connectedDevices, id: \.self) { device in
                        Text("• \(device)")
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            Divider()
            
            if let note = midiManager.lastNote, let velocity = midiManager.lastVelocity {
                VStack {
                    Text("Last Pad Hit:")
                        .font(.headline)
                    Text("Note: \(note)")
                        .font(.title2)
                    Text("Velocity: \(velocity)")
                        .font(.title2)
                }
                .transition(.scale)
                .id(note) // Force view refresh on new note
            } else {
                Text("Press a pad on your controller...")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
    }
}

#Preview {
    ContentView()
}

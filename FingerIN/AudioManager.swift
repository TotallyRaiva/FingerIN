import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    
    // Pool of player nodes to handle polyphony
    private var playerNodes: [AVAudioPlayerNode] = []
    private let poolSize = 16
    private var currentPlayerIndex = 0
    
    // Cache for pre-loaded audio buffers
    private var sampleBuffers: [UInt8: AVAudioPCMBuffer] = [:]
    
    // Mapping of MIDI Note Numbers to Sample File Names
    // Updated to match user controller layout (12, 13, 14, 15)
    private let noteToSampleMap: [UInt8: String] = [
        12: "kick",
        13: "Snare",
        14: "hihat_closed",
        15: "hihat_open"
    ]
    
    private init() {
        setupEngine()
        loadSamples()
    }
    
    private func setupEngine() {
        print("AudioManager: Setting up AVAudioEngine...")
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: engine.mainMixerNode.outputFormat(forBus: 0))
        
        // Initialize player node pool
        for _ in 0..<poolSize {
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            // Connect with a generic format or mixer's input format
            engine.connect(playerNode, to: mixer, format: nil)
            playerNodes.append(playerNode)
        }
        
        startEngine()
    }
    
    private func startEngine() {
        do {
            if !engine.isRunning {
                try engine.start()
                print("AudioManager: AVAudioEngine started successfully.")
            }
        } catch {
            print("AudioManager: Could not start AVAudioEngine: \(error)")
        }
    }
    
    private func loadSamples() {
        print("AudioManager: Loading samples...")
        for (note, sampleName) in noteToSampleMap {
            guard let url = Bundle.main.url(forResource: sampleName, withExtension: "wav") else {
                print("AudioManager: [ERROR] Could not find file \(sampleName).wav in Bundle.main")
                continue
            }
            
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let frameCount = UInt32(file.length)
                
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    print("AudioManager: [ERROR] Could not create buffer for \(sampleName)")
                    continue
                }
                
                try file.read(into: buffer)
                sampleBuffers[note] = buffer
                print("AudioManager: [SUCCESS] Loaded \(sampleName).wav for MIDI Note \(note)")
            } catch {
                print("AudioManager: [ERROR] Loading \(sampleName): \(error)")
            }
        }
        
        if sampleBuffers.isEmpty {
            print("AudioManager: [WARNING] No samples were loaded. Check file names and bundle inclusion.")
        }
    }
    
    func triggerSound(for noteNumber: UInt8) {
        print("AudioManager: Triggering sound for MIDI Note: \(noteNumber)")
        
        // Ensure engine is running (it can stop if audio hardware changes)
        if !engine.isRunning {
            print("AudioManager: Engine not running, attempting to restart...")
            startEngine()
        }

        guard let buffer = sampleBuffers[noteNumber] else {
            print("AudioManager: [IDLE] No sample mapped for note \(noteNumber). Current map: \(noteToSampleMap)")
            return
        }
        
        // Get the next available player node from the pool
        let playerNode = playerNodes[currentPlayerIndex]
        currentPlayerIndex = (currentPlayerIndex + 1) % poolSize
        
        // Schedule and play with zero latency
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
        print("AudioManager: [PLAY] Scheduled buffer for note \(noteNumber)")
    }
}

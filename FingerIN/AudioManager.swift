import Foundation
import AVFoundation
import SwiftUI
import Combine

@MainActor
class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    
    // Pool of player nodes to handle polyphony
    private var playerNodes: [AVAudioPlayerNode] = []
    private let poolSize = 16
    private var currentPlayerIndex = 0
    
    // Dedicated metronome player node and synthesized buffers
    private let metronomeNode = AVAudioPlayerNode()
    private var metronomeAccentBuffer: AVAudioPCMBuffer?
    private var metronomeRegularBuffer: AVAudioPCMBuffer?
    
    // Track active Open Hi-Hat node for realistic Hi-Hat choke when Closed Hi-Hat is struck
    private weak var activeOpenHatNode: AVAudioPlayerNode?
    
    // Cache for pre-loaded audio buffers
    private var sampleBuffers: [UInt8: AVAudioPCMBuffer] = [:]
    
    // Mapping of canonical MIDI Note Numbers to Sample File Names
    private let noteToSampleMap: [UInt8: String] = [
        12: "kick",
        13: "Snare",
        14: "hihat_closed",
        15: "hihat_open"
    ]
    
    private init() {
        setupEngine()
        loadSamples()
        buildMetronomeBuffers()
    }
    
    private func setupEngine() {
        engine.attach(mixer)
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(mixer, to: engine.outputNode, format: outputFormat)
        
        // Initialize drum player node pool
        for _ in 0..<poolSize {
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.connect(playerNode, to: mixer, format: nil)
            playerNodes.append(playerNode)
        }
        
        // Attach dedicated metronome node
        if let metroFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) {
            engine.attach(metronomeNode)
            engine.connect(metronomeNode, to: mixer, format: metroFormat)
        }
        
        startEngine()
    }
    
    private func startEngine() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            print("AudioManager: Could not start AVAudioEngine: \(error)")
        }
    }
    
    private func loadSamples() {
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
                    continue
                }
                
                try file.read(into: buffer)
                sampleBuffers[note] = buffer
            } catch {
                print("AudioManager: [ERROR] Loading \(sampleName): \(error)")
            }
        }
    }
    
    /// Synthesizes crisp woodblock/click buffers for accented (Beat 1) and regular beats
    private func buildMetronomeBuffers() {
        metronomeAccentBuffer = Self.makeClickBuffer(frequency: 1320.0, duration: 0.032, gain: 0.55)
        metronomeRegularBuffer = Self.makeClickBuffer(frequency: 880.0, duration: 0.026, gain: 0.38)
    }
    
    private static func makeClickBuffer(frequency: Double, duration: Double, gain: Float) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount
        
        let left = channelData[0]
        let right = channelData[1]
        
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            // Fast exponential decay with a brief pitch drop for a natural woodblock transient
            let envelope = Float(exp(-t * 140.0))
            let phase = 2.0 * Double.pi * frequency * t
            let sample = sin(Float(phase)) * envelope * gain
            left[frame] = sample
            right[frame] = sample
        }
        return buffer
    }
    
    func triggerSound(for noteNumber: UInt8, velocity: UInt8 = 100) {
        if !engine.isRunning {
            startEngine()
        }
        
        guard let buffer = sampleBuffers[noteNumber] else {
            return
        }
        
        // Hi-Hat Choke Group: Closed Hi-Hat (14) chokes ringing Open Hi-Hat (15)
        if noteNumber == 14, let openHat = activeOpenHatNode, openHat.isPlaying {
            openHat.stop()
            activeOpenHatNode = nil
        }
        
        let playerNode = playerNodes[currentPlayerIndex]
        currentPlayerIndex = (currentPlayerIndex + 1) % poolSize
        
        if playerNode.isPlaying {
            playerNode.stop()
        }
        
        let clampedVelocity = max(1, min(127, Int(velocity)))
        playerNode.volume = max(0.15, Float(clampedVelocity) / 127.0)
        
        if noteNumber == 15 {
            activeOpenHatNode = playerNode
        }
        
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        playerNode.play()
    }
    
    func playMetronomeClick(isDownbeat: Bool = false) {
        if !engine.isRunning {
            startEngine()
        }
        
        if let buffer = isDownbeat ? metronomeAccentBuffer : metronomeRegularBuffer {
            if metronomeNode.isPlaying {
                metronomeNode.stop()
            }
            metronomeNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            metronomeNode.play()
        } else {
            // Fallback if buffer creation failed
            triggerSound(for: 14, velocity: isDownbeat ? 110 : 70)
        }
    }
}

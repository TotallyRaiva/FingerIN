import Foundation
import AVFoundation
import SwiftUI
import Combine

@MainActor
class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    @Published var currentKit: DrumKit = .mpcLoFi
    
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    
    // Pool of player nodes to handle drum polyphony
    private var playerNodes: [AVAudioPlayerNode] = []
    private let poolSize = 16
    private var currentPlayerIndex = 0
    
    // Dedicated player nodes for metronome and musical accompaniment (Bass + Rhodes/Synth Chords)
    private let metronomeNode = AVAudioPlayerNode()
    private let bassNode = AVAudioPlayerNode()
    private let chordNode = AVAudioPlayerNode()
    
    private var metronomeAccentBuffer: AVAudioPCMBuffer?
    private var metronomeRegularBuffer: AVAudioPCMBuffer?
    
    // Track active Open Hi-Hat node for realistic Hi-Hat choke when Closed Hi-Hat is struck
    private weak var activeOpenHatNode: AVAudioPlayerNode?
    
    private enum VelocityTier: Int, CaseIterable {
        case ghost = 0
        case normal = 1
        case accent = 2
        
        static func from(velocity: UInt8) -> VelocityTier {
            if velocity < 70 { return .ghost }
            if velocity > 110 { return .accent }
            return .normal
        }
    }
    
    private struct KitSampleKey: Hashable {
        let kit: DrumKit
        let note: UInt8
        let tier: VelocityTier
    }
    
    // Raw loaded acoustic buffers and multi-kit sculpted/synthesized buffers
    private var rawBuffers: [UInt8: AVAudioPCMBuffer] = [:]
    private var kitBuffers: [KitSampleKey: AVAudioPCMBuffer] = [:]
    
    // Cache for synthesized bass and chord accompaniment buffers
    private struct BassCacheKey: Hashable {
        let midiNote: UInt8
        let durationMs: Int
        let kit: DrumKit
    }
    private struct ChordCacheKey: Hashable {
        let midiNotes: [UInt8]
        let durationMs: Int
        let kit: DrumKit
    }
    private var bassBufferCache: [BassCacheKey: AVAudioPCMBuffer] = [:]
    private var chordBufferCache: [ChordCacheKey: AVAudioPCMBuffer] = [:]
    
    private let sampleRate: Double = 44_100.0
    private var stereoFormat: AVAudioFormat!
    
    private let noteToSampleMap: [UInt8: String] = [
        12: "kick",
        13: "Snare",
        14: "hihat_closed",
        15: "hihat_open"
    ]
    
    private init() {
        stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        setupEngine()
        loadRawSamples()
        buildAllKitVoicings()
        buildMetronomeBuffers()
    }
    
    private func setupEngine() {
        engine.attach(mixer)
        engine.attach(reverb)
        
        // Studio room ambience so drum kits feel like a real room rather than dry test clicks
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 12.0
        
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(mixer, to: reverb, format: stereoFormat)
        engine.connect(reverb, to: engine.mainMixerNode, format: outputFormat)
        
        for _ in 0..<poolSize {
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.connect(playerNode, to: mixer, format: stereoFormat)
            playerNodes.append(playerNode)
        }
        
        for node in [metronomeNode, bassNode, chordNode] {
            engine.attach(node)
            engine.connect(node, to: mixer, format: stereoFormat)
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
    
    private func loadRawSamples() {
        for (note, sampleName) in noteToSampleMap {
            guard let url = Bundle.main.url(forResource: sampleName, withExtension: "wav") else {
                continue
            }
            do {
                let file = try AVAudioFile(forReading: url)
                let frameCount = UInt32(file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
                    continue
                }
                try file.read(into: buffer)
                rawBuffers[note] = buffer
            } catch {
                print("AudioManager: Error loading \(sampleName): \(error)")
            }
        }
    }
    
    // MARK: - Multi-Kit Studio Voicing & Hybrid Drum Synthesis
    
    private func buildAllKitVoicings() {
        for kit in DrumKit.allCases {
            for tier in VelocityTier.allCases {
                kitBuffers[KitSampleKey(kit: kit, note: 12, tier: tier)] = makeKickBuffer(kit: kit, tier: tier)
                kitBuffers[KitSampleKey(kit: kit, note: 13, tier: tier)] = makeSnareBuffer(kit: kit, tier: tier)
                kitBuffers[KitSampleKey(kit: kit, note: 14, tier: tier)] = makeClosedHatBuffer(kit: kit, tier: tier)
                kitBuffers[KitSampleKey(kit: kit, note: 15, tier: tier)] = makeOpenHatBuffer(kit: kit, tier: tier)
            }
        }
    }
    
    private func rawSampleValue(note: UInt8, channel: Int, sampleIndex: Double) -> Float {
        guard let buf = rawBuffers[note],
              let data = buf.floatChannelData else { return 0.0 }
        let ch = min(channel, Int(buf.format.channelCount) - 1)
        let idx = Int(sampleIndex)
        guard idx >= 0, idx + 1 < Int(buf.frameLength) else { return 0.0 }
        let frac = Float(sampleIndex - Double(idx))
        return data[ch][idx] * (1.0 - frac) + data[ch][idx + 1] * frac
    }
    
    private func makeKickBuffer(kit: DrumKit, tier: VelocityTier) -> AVAudioPCMBuffer? {
        let duration: Double
        switch kit {
        case .trap808: duration = 0.52
        case .club909: duration = 0.34
        case .mpcLoFi: duration = 0.32
        case .funkBreak: duration = 0.24
        case .studioAcoustic: duration = 0.32
        }
        
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let tierGain: Float = (tier == .ghost) ? 0.55 : (tier == .accent ? 1.0 : 0.82)
        let clickLevel: Float = (tier == .accent) ? 0.45 : (tier == .normal ? 0.28 : 0.12)
        
        var phase: Double = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let synthSample: Float
            let rawRate: Double
            let rawMix: Float
            
            switch kit {
            case .trap808:
                let freq = 42.0 + 115.0 * exp(-t * 48.0)
                phase += 2.0 * .pi * freq / sampleRate
                let subEnv = Float(exp(-t * 5.2))
                let click = Float(exp(-t * 220.0)) * sin(Float(t * 2600.0)) * clickLevel
                synthSample = tanh((sin(Float(phase)) * subEnv * 1.35) + click)
                rawRate = 0.85
                rawMix = 0.18
                
            case .club909:
                let freq = 49.0 + 140.0 * exp(-t * 55.0)
                phase += 2.0 * .pi * freq / sampleRate
                let env = Float(exp(-t * 10.5))
                let click = Float(exp(-t * 260.0)) * sin(Float(t * 3200.0)) * (clickLevel * 1.2)
                synthSample = tanh((sin(Float(phase)) * env * 1.4) + click)
                rawRate = 1.0
                rawMix = 0.25
                
            case .mpcLoFi:
                let freq = 51.0 + 90.0 * exp(-t * 42.0)
                phase += 2.0 * .pi * freq / sampleRate
                let env = Float(exp(-t * 11.5))
                synthSample = tanh(sin(Float(phase)) * env * 1.25)
                rawRate = 0.90
                rawMix = 0.65
                
            case .funkBreak:
                let freq = 62.0 + 110.0 * exp(-t * 65.0)
                phase += 2.0 * .pi * freq / sampleRate
                let env = Float(exp(-t * 16.0))
                synthSample = sin(Float(phase)) * env * 0.95
                rawRate = 1.08
                rawMix = 0.75
                
            case .studioAcoustic:
                let freq = 52.0 + 95.0 * exp(-t * 50.0)
                phase += 2.0 * .pi * freq / sampleRate
                let env = Float(exp(-t * 12.0))
                synthSample = sin(Float(phase)) * env * 0.75
                rawRate = 1.0
                rawMix = 0.82
            }
            
            let sampleIdx = Double(i) * rawRate
            let envTail = Float(exp(-t * (kit == .trap808 ? 4.5 : 10.0)))
            let rawL = rawSampleValue(note: 12, channel: 0, sampleIndex: sampleIdx) * envTail
            let rawR = rawSampleValue(note: 12, channel: 1, sampleIndex: sampleIdx) * envTail
            
            outData[0][i] = tanh((rawL * rawMix + synthSample) * tierGain)
            outData[1][i] = tanh((rawR * rawMix + synthSample) * tierGain)
        }
        return out
    }
    
    private func makeSnareBuffer(kit: DrumKit, tier: VelocityTier) -> AVAudioPCMBuffer? {
        let duration: Double = (tier == .ghost) ? 0.16 : 0.34
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let tierGain: Float = (tier == .ghost) ? 0.38 : (tier == .accent ? 1.0 : 0.80)
        var lpStateL: Float = 0.0
        var lpStateR: Float = 0.0
        // Ghost notes get a warmer low-pass rolloff so they sound like real soft stick taps
        let filterAlpha: Float = (tier == .ghost) ? 0.28 : (tier == .accent ? 0.92 : 0.68)
        
        var rngState: UInt64 = 0x1234_5678_9ABC_DEF0
        func nextNoise() -> Float {
            rngState = rngState &* 6364136223846793005 &+ 1
            let v = Int32(truncatingIfNeeded: rngState >> 32)
            return Float(v) / Float(Int32.max)
        }
        
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let noiseL = nextNoise()
            let noiseR = nextNoise()
            
            let rawRate: Double
            let rawMix: Float
            let synthL: Float
            let synthR: Float
            
            switch kit {
            case .trap808:
                let body = sin(Float(2.0 * .pi * 215.0 * t)) * Float(exp(-t * 38.0)) * 0.65
                // Layered clap/snap burst on accents
                let clapEnv = (t < 0.022 && Int(t * 450) % 2 == 0) ? Float(0.7) : Float(exp(-t * 26.0))
                let snap = clapEnv * ((tier == .accent) ? 0.75 : 0.45)
                synthL = body + noiseL * snap
                synthR = body + noiseR * snap
                rawRate = 1.15
                rawMix = 0.45
                
            case .club909:
                let body = (sin(Float(2.0 * .pi * 185.0 * t)) + 0.6 * sin(Float(2.0 * .pi * 330.0 * t))) * Float(exp(-t * 30.0)) * 0.5
                let wireEnv = Float(exp(-t * (tier == .ghost ? 28.0 : 14.0)))
                synthL = body + noiseL * wireEnv * 0.55
                synthR = body + noiseR * wireEnv * 0.55
                rawRate = 1.04
                rawMix = 0.55
                
            case .mpcLoFi:
                let body = sin(Float(2.0 * .pi * 195.0 * t)) * Float(exp(-t * 34.0)) * 0.55
                let wireEnv = Float(exp(-t * (tier == .ghost ? 30.0 : 17.0)))
                synthL = body + noiseL * wireEnv * 0.35
                synthR = body + noiseR * wireEnv * 0.35
                rawRate = 0.96
                rawMix = 0.85
                
            case .funkBreak:
                let rimCrack = (tier == .accent) ? sin(Float(2.0 * .pi * 490.0 * t)) * Float(exp(-t * 95.0)) * 0.55 : 0.0
                let wireEnv = Float(exp(-t * (tier == .ghost ? 34.0 : 19.0)))
                synthL = rimCrack + noiseL * wireEnv * 0.28
                synthR = rimCrack + noiseR * wireEnv * 0.28
                rawRate = 1.14
                rawMix = 0.88
                
            case .studioAcoustic:
                let rimCrack = (tier == .accent) ? sin(Float(2.0 * .pi * 420.0 * t)) * Float(exp(-t * 85.0)) * 0.35 : 0.0
                let wireEnv = Float(exp(-t * (tier == .ghost ? 28.0 : 15.0)))
                synthL = rimCrack + noiseL * wireEnv * 0.22
                synthR = rimCrack + noiseR * wireEnv * 0.22
                rawRate = 1.0
                rawMix = 0.92
            }
            
            let sampleIdx = Double(i) * rawRate
            let envGate = Float(exp(-t * (tier == .ghost ? 20.0 : 8.5)))
            let rawL = rawSampleValue(note: 13, channel: 0, sampleIndex: sampleIdx) * envGate
            let rawR = rawSampleValue(note: 13, channel: 1, sampleIndex: sampleIdx) * envGate
            
            let combinedL = rawL * rawMix + synthL
            let combinedR = rawR * rawMix + synthR
            lpStateL += filterAlpha * (combinedL - lpStateL)
            lpStateR += filterAlpha * (combinedR - lpStateR)
            
            outData[0][i] = tanh(lpStateL * tierGain * 1.15)
            outData[1][i] = tanh(lpStateR * tierGain * 1.15)
        }
        return out
    }
    
    /// Fixes the raw 700ms `hihat_closed.wav` into a tight, musical closed hi-hat (55ms–95ms)
    private func makeClosedHatBuffer(kit: DrumKit, tier: VelocityTier) -> AVAudioPCMBuffer? {
        let duration: Double = (tier == .ghost) ? 0.065 : 0.115
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let tierGain: Float = (tier == .ghost) ? 0.36 : (tier == .accent ? 0.92 : 0.66)
        let decayRate: Double
        let rawRate: Double
        let metallicMix: Float
        
        switch kit {
        case .trap808:
            decayRate = 58.0
            rawRate = 1.32
            metallicMix = 0.45
        case .club909:
            decayRate = 42.0
            rawRate = 1.15
            metallicMix = 0.35
        case .mpcLoFi:
            decayRate = 52.0
            rawRate = 0.94
            metallicMix = 0.15
        case .funkBreak:
            decayRate = 48.0
            rawRate = 1.08
            metallicMix = 0.18
        case .studioAcoustic:
            decayRate = 40.0
            rawRate = 1.04
            metallicMix = 0.12
        }
        
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let env = Float(exp(-t * decayRate))
            // High-frequency metallic shimmer partials
            let m1 = sin(Float(2.0 * .pi * 6340.0 * t))
            let m2 = sin(Float(2.0 * .pi * 8920.0 * t))
            let m3 = sin(Float(2.0 * .pi * 11450.0 * t))
            let metallic = (m1 + m2 + m3) * 0.25 * metallicMix * env
            
            let sampleIdx = Double(i) * rawRate
            let rawL = rawSampleValue(note: 14, channel: 0, sampleIndex: sampleIdx) * env
            let rawR = rawSampleValue(note: 14, channel: 1, sampleIndex: sampleIdx) * env
            
            outData[0][i] = (rawL * 0.85 + metallic) * tierGain
            outData[1][i] = (rawR * 0.85 - metallic) * tierGain
        }
        return out
    }
    
    /// Extends and voices the Open Hi-Hat (360ms–480ms) so it rings lushly until choked by Closed Hi-Hat
    private func makeOpenHatBuffer(kit: DrumKit, tier: VelocityTier) -> AVAudioPCMBuffer? {
        let duration: Double = 0.46
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let tierGain: Float = (tier == .ghost) ? 0.50 : (tier == .accent ? 0.95 : 0.78)
        let decayRate: Double = (kit == .funkBreak) ? 9.5 : (kit == .club909 ? 6.0 : 7.5)
        let rawRate: Double = (kit == .trap808) ? 1.22 : (kit == .mpcLoFi ? 0.95 : 1.02)
        
        var rng: UInt64 = 0xCAFE_BABE_1337_0001
        var hpPrevL: Float = 0
        var hpPrevR: Float = 0
        
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let env = Float(exp(-t * decayRate))
            
            rng = rng &* 6364136223846793005 &+ 1
            let nL = Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max)
            rng = rng &* 6364136223846793005 &+ 1
            let nR = Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max)
            
            // High-passed cymbal sizzle + metallic partials
            let hpL = nL - hpPrevL
            let hpR = nR - hpPrevR
            hpPrevL = nL * 0.82
            hpPrevR = nR * 0.82
            
            let shimmer = (sin(Float(2.0 * .pi * 5820.0 * t)) + sin(Float(2.0 * .pi * 8310.0 * t))) * 0.16
            let cymbalTailL = (hpL * 0.26 + shimmer) * env
            let cymbalTailR = (hpR * 0.26 - shimmer) * env
            
            let sampleIdx = Double(i) * rawRate
            let rawL = rawSampleValue(note: 15, channel: 0, sampleIndex: sampleIdx) * env
            let rawR = rawSampleValue(note: 15, channel: 1, sampleIndex: sampleIdx) * env
            
            outData[0][i] = tanh((rawL * 0.85 + cymbalTailL) * tierGain)
            outData[1][i] = tanh((rawR * 0.85 + cymbalTailR) * tierGain)
        }
        return out
    }
    
    // MARK: - Drum Triggering
    
    func triggerSound(for noteNumber: UInt8, velocity: UInt8 = 100) {
        if !engine.isRunning {
            startEngine()
        }
        
        let tier = VelocityTier.from(velocity: velocity)
        let key = KitSampleKey(kit: currentKit, note: noteNumber, tier: tier)
        guard let buffer = kitBuffers[key] ?? rawBuffers[noteNumber] else {
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
        
        // Subtle humanized micro-variation so 16th-note patterns never sound robotic
        let humanVariation = Float.random(in: 0.96...1.04)
        let clampedVelocity = max(1, min(127, Int(velocity)))
        let velocityScale = 0.35 + 0.65 * (Float(clampedVelocity) / 127.0)
        playerNode.volume = min(1.0, velocityScale * humanVariation)
        
        if noteNumber == 15 {
            activeOpenHatNode = playerNode
        }
        
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        playerNode.play()
    }
    
    // MARK: - Musical Backing Track Synth (Warm Bassline + Rhodes / Synth Chords)
    
    func playBackingEvent(_ event: BackingStepEvent, stepDuration: TimeInterval) {
        if !engine.isRunning {
            startEngine()
        }
        
        // 1. Trigger Bass Note if present on this step
        if let bassMIDI = event.bassMIDINote, event.bassDurationSteps > 0 {
            let durationSec = max(0.12, min(2.5, event.bassDurationSteps * stepDuration))
            let durationMs = Int((durationSec * 1000.0).rounded())
            let cacheKey = BassCacheKey(midiNote: bassMIDI, durationMs: durationMs, kit: currentKit)
            
            let buffer: AVAudioPCMBuffer?
            if let cached = bassBufferCache[cacheKey] {
                buffer = cached
            } else if let generated = makeBassBuffer(midiNote: bassMIDI, duration: durationSec) {
                bassBufferCache[cacheKey] = generated
                buffer = generated
            } else {
                buffer = nil
            }
            
            if let buffer = buffer {
                if bassNode.isPlaying { bassNode.stop() }
                bassNode.volume = 0.68
                bassNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
                bassNode.play()
            }
        }
        
        // 2. Trigger Rhodes / Synth Chord if present on this step
        if !event.chordMIDINotes.isEmpty && event.chordDurationSteps > 0 {
            let durationSec = max(0.18, min(3.5, event.chordDurationSteps * stepDuration))
            let durationMs = Int((durationSec * 1000.0).rounded())
            let cacheKey = ChordCacheKey(midiNotes: event.chordMIDINotes, durationMs: durationMs, kit: currentKit)
            
            let buffer: AVAudioPCMBuffer?
            if let cached = chordBufferCache[cacheKey] {
                buffer = cached
            } else if let generated = makeChordBuffer(midiNotes: event.chordMIDINotes, duration: durationSec) {
                chordBufferCache[cacheKey] = generated
                buffer = generated
            } else {
                buffer = nil
            }
            
            if let buffer = buffer {
                if chordNode.isPlaying { chordNode.stop() }
                chordNode.volume = 0.52
                chordNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
                chordNode.play()
            }
        }
    }
    
    func stopBackingAudio() {
        if bassNode.isPlaying { bassNode.stop() }
        if chordNode.isPlaying { chordNode.stop() }
        if let openHat = activeOpenHatNode, openHat.isPlaying {
            openHat.stop()
            activeOpenHatNode = nil
        }
    }
    
    private static func midiFrequency(_ note: UInt8) -> Double {
        440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
    }
    
    /// Synthesizes a warm fingered/sub bass note with filter pluck envelope
    private func makeBassBuffer(midiNote: UInt8, duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let freq = Self.midiFrequency(midiNote)
        let releaseStart = max(0.04, duration - 0.04)
        
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let attack = Float(min(1.0, t / 0.008))
            let release = t > releaseStart ? Float(max(0.0, 1.0 - (t - releaseStart) / 0.04)) : 1.0
            let sustainDecay = Float(exp(-t * 2.2))
            let env = attack * sustainDecay * release
            
            // Warm fundamental + plucked 2nd & 3rd harmonics that mellow out quickly
            let pluckEnv = Float(exp(-t * 18.0))
            let f1 = sin(Float(2.0 * .pi * freq * t))
            let f2 = sin(Float(2.0 * .pi * (freq * 2.0) * t)) * (0.38 * pluckEnv + 0.12)
            let f3 = sin(Float(2.0 * .pi * (freq * 3.0) * t)) * (0.18 * pluckEnv)
            
            let sample = tanh((f1 + f2 + f3) * env * 0.55)
            outData[0][i] = sample
            outData[1][i] = sample
        }
        return out
    }
    
    /// Synthesizes a warm stereo Fender Rhodes / Electric Piano chord voicing with gentle chorus
    private func makeChordBuffer(midiNotes: [UInt8], duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let freqs = midiNotes.map { Self.midiFrequency($0) }
        let voiceScale = 1.0 / Float(max(1, freqs.count))
        let releaseStart = max(0.05, duration - 0.06)
        
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let attack = Float(min(1.0, t / 0.012))
            let release = t > releaseStart ? Float(max(0.0, 1.0 - (t - releaseStart) / 0.06)) : 1.0
            let bodyEnv = Float(exp(-t * 1.6)) * attack * release
            let tineEnv = Float(exp(-t * 16.0)) * attack
            
            // Subtle stereo tremolo / chorus movement
            let lfo = 0.08 * sin(Float(2.0 * .pi * 4.2 * t))
            var sumL: Float = 0.0
            var sumR: Float = 0.0
            
            for (idx, f) in freqs.enumerated() {
                let detuneL = f * (1.0 - 0.0012)
                let detuneR = f * (1.0 + 0.0012)
                let tine = sin(Float(2.0 * .pi * (f * 4.0) * t)) * 0.18 * tineEnv
                let mod = sin(Float(2.0 * .pi * (f * 2.0) * t)) * 0.25 * Float(exp(-t * 5.0))
                
                let voiceL = sin(Float(2.0 * .pi * detuneL * t) + mod) * bodyEnv + tine
                let voiceR = sin(Float(2.0 * .pi * detuneR * t) + mod) * bodyEnv + tine
                
                let pan = Float(idx) / Float(max(1, freqs.count - 1)) // 0..1 stereo spread
                sumL += voiceL * (0.75 - 0.3 * pan)
                sumR += voiceR * (0.45 + 0.3 * pan)
            }
            
            outData[0][i] = tanh(sumL * voiceScale * (1.0 + lfo) * 0.85)
            outData[1][i] = tanh(sumR * voiceScale * (1.0 - lfo) * 0.85)
        }
        return out
    }
    
    // MARK: - Metronome
    
    private func buildMetronomeBuffers() {
        metronomeAccentBuffer = Self.makeClickBuffer(frequency: 1320.0, duration: 0.032, gain: 0.50, format: stereoFormat)
        metronomeRegularBuffer = Self.makeClickBuffer(frequency: 880.0, duration: 0.026, gain: 0.34, format: stereoFormat)
    }
    
    private static func makeClickBuffer(frequency: Double, duration: Double, gain: Float, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
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
            let envelope = Float(exp(-t * 140.0))
            let phase = 2.0 * Double.pi * frequency * t
            let sample = sin(Float(phase)) * envelope * gain
            left[frame] = sample
            right[frame] = sample
        }
        return buffer
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
        }
    }
}

import Foundation
import AVFoundation
import SwiftUI
import Combine
import os

@MainActor
class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    @Published var currentKit: DrumKit = .mpcLoFi {
        didSet {
            syncRealtimeState()
        }
    }
    
    @Published var sampleLatencyMode: SampleLatencyMode = .tight {
        didSet {
            UserDefaults.standard.set(sampleLatencyMode.rawValue, forKey: latencyDefaultsKey)
            syncRealtimeState()
        }
    }
    
    private let latencyDefaultsKey = "FingerIN.sampleLatencyMode"
    
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    
    // Pool of player nodes to handle drum polyphony
    private var playerNodes: [AVAudioPlayerNode] = []
    private let poolSize = 16
    
    // Dedicated player nodes for metronome and musical accompaniment (Bass + Rhodes/Synth Chords)
    private let metronomeNode = AVAudioPlayerNode()
    private let bassNode = AVAudioPlayerNode()
    private let chordNode = AVAudioPlayerNode()
    
    private var metronomeAccentBuffer: AVAudioPCMBuffer?
    private var metronomeRegularBuffer: AVAudioPCMBuffer?
    
    nonisolated private enum VelocityTier: Int, CaseIterable, Sendable {
        case ghost = 0
        case normal = 1
        case accent = 2
        
        static func from(velocity: UInt8) -> VelocityTier {
            if velocity < 70 { return .ghost }
            if velocity > 110 { return .accent }
            return .normal
        }
    }
    
    nonisolated private struct KitSampleKey: Hashable, Sendable {
        let kit: DrumKit
        let latencyMode: SampleLatencyMode
        let note: UInt8
        let tier: VelocityTier
    }
    
    // Thread-safe real-time audio trigger state so CoreMIDI can schedule buffers with zero MainActor hop latency
    nonisolated private struct RealtimeAudioState: @unchecked Sendable {
        var currentKit: DrumKit = .mpcLoFi
        var latencyMode: SampleLatencyMode = .tight
        var currentPlayerIndex: Int = 0
        var activeOpenHatNode: AVAudioPlayerNode? = nil
        var kitBuffers: [KitSampleKey: AVAudioPCMBuffer] = [:]
        var rawBuffers: [UInt8: AVAudioPCMBuffer] = [:]
        var playerNodes: [AVAudioPlayerNode] = []
    }
    
    nonisolated private let rtLock = OSAllocatedUnfairLock(initialState: RealtimeAudioState())
    
    // Raw loaded acoustic buffers and multi-kit sculpted/synthesized buffers
    private var rawBuffers: [UInt8: AVAudioPCMBuffer] = [:]
    private var kitBuffers: [KitSampleKey: AVAudioPCMBuffer] = [:]
    
    // Cache for synthesized bass and chord accompaniment buffers
    private struct BassCacheKey: Hashable {
        let midiNote: UInt8
        let durationMs: Int
    }
    private struct ChordCacheKey: Hashable {
        let midiNotes: [UInt8]
        let durationMs: Int
    }
    private var bassBufferCache: [BassCacheKey: AVAudioPCMBuffer] = [:]
    private var chordBufferCache: [ChordCacheKey: AVAudioPCMBuffer] = [:]
    
    // Fast 4096-entry sine lookup table for sub-millisecond chord/bass buffer generation
    private static let sinLUTSize = 4096
    private static let sinLUTMask = 4095
    private static let sinLUT: [Float] = {
        (0..<4096).map { i in
            sin(Float(Double(i) * 2.0 * .pi / 4096.0))
        }
    }()
    
    @inline(__always)
    private static func fastSinUnit(_ normalizedPhase: Double) -> Float {
        let idx = Int(normalizedPhase * Double(sinLUTSize)) & sinLUTMask
        return sinLUT[idx]
    }
    
    private let sampleRate: Double = 44_100.0
    private var stereoFormat: AVAudioFormat!
    
    private let noteToSampleMap: [UInt8: String] = [
        12: "kick",
        13: "Snare",
        14: "hihat_closed",
        15: "hihat_open"
    ]
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: latencyDefaultsKey),
           let mode = SampleLatencyMode(rawValue: saved) {
            self.sampleLatencyMode = mode
        }
        stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        setupEngine()
        loadRawSamples()
        buildAllKitVoicings()
        buildMetronomeBuffers()
        syncRealtimeState()
    }
    
    private func syncRealtimeState() {
        let kit = self.currentKit
        let mode = self.sampleLatencyMode
        let kBuffers = self.kitBuffers
        let rBuffers = self.rawBuffers
        let nodes = self.playerNodes
        rtLock.withLock { state in
            state.currentKit = kit
            state.latencyMode = mode
            if state.kitBuffers.isEmpty {
                state.kitBuffers = kBuffers
                state.rawBuffers = rBuffers
                state.playerNodes = nodes
            }
        }
    }
    
    private func setupEngine() {
        engine.attach(mixer)
        engine.attach(reverb)
        
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 10.0
        
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
            // Pre-start all player nodes so scheduling buffers with .interrupts has zero start-up latency
            for node in playerNodes where !node.isPlaying {
                node.play()
            }
            for node in [metronomeNode, bassNode, chordNode] where !node.isPlaying {
                node.play()
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
    
    // MARK: - Multi-Kit Studio Voicing & Sample Latency Trim
    
    private func buildAllKitVoicings() {
        for mode in SampleLatencyMode.allCases {
            let trimFrames = mode.trimMilliseconds * 0.001 * sampleRate
            for kit in DrumKit.allCases {
                for tier in VelocityTier.allCases {
                    kitBuffers[KitSampleKey(kit: kit, latencyMode: mode, note: 12, tier: tier)] =
                        makeKickBuffer(kit: kit, tier: tier, trimOffsetFrames: trimFrames * 0.5)
                    kitBuffers[KitSampleKey(kit: kit, latencyMode: mode, note: 13, tier: tier)] =
                        makeSnareBuffer(kit: kit, tier: tier, trimOffsetFrames: trimFrames)
                    kitBuffers[KitSampleKey(kit: kit, latencyMode: mode, note: 14, tier: tier)] =
                        makeClosedHatBuffer(kit: kit, tier: tier, trimOffsetFrames: trimFrames)
                    kitBuffers[KitSampleKey(kit: kit, latencyMode: mode, note: 15, tier: tier)] =
                        makeOpenHatBuffer(kit: kit, tier: tier, trimOffsetFrames: trimFrames * 1.3)
                }
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
    
    private func makeKickBuffer(kit: DrumKit, tier: VelocityTier, trimOffsetFrames: Double) -> AVAudioPCMBuffer? {
        let duration: Double
        switch kit {
        case .trap808: duration = 0.50
        case .club909: duration = 0.32
        case .mpcLoFi: duration = 0.30
        case .funkBreak: duration = 0.23
        case .studioAcoustic: duration = 0.30
        }
        
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let tierGain: Float = (tier == .ghost) ? 0.55 : (tier == .accent ? 1.0 : 0.82)
        let clickLevel: Float = (tier == .accent) ? 0.48 : (tier == .normal ? 0.30 : 0.14)
        
        var phase: Double = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let microFade = Float(min(1.0, Double(i) / 16.0))
            let synthSample: Float
            let rawRate: Double
            let rawMix: Float
            
            switch kit {
            case .trap808:
                let freq = 42.0 + 115.0 * exp(-t * 48.0)
                phase += freq / sampleRate
                let subEnv = Float(exp(-t * 5.2))
                let click = Float(exp(-t * 220.0)) * Self.fastSinUnit(t * 415.0) * clickLevel
                synthSample = tanh((Self.fastSinUnit(phase) * subEnv * 1.35) + click)
                rawRate = 0.85
                rawMix = 0.18
                
            case .club909:
                let freq = 49.0 + 140.0 * exp(-t * 55.0)
                phase += freq / sampleRate
                let env = Float(exp(-t * 10.5))
                let click = Float(exp(-t * 260.0)) * Self.fastSinUnit(t * 510.0) * (clickLevel * 1.2)
                synthSample = tanh((Self.fastSinUnit(phase) * env * 1.4) + click)
                rawRate = 1.0
                rawMix = 0.25
                
            case .mpcLoFi:
                let freq = 51.0 + 90.0 * exp(-t * 42.0)
                phase += freq / sampleRate
                let env = Float(exp(-t * 11.5))
                synthSample = tanh(Self.fastSinUnit(phase) * env * 1.25)
                rawRate = 0.90
                rawMix = 0.65
                
            case .funkBreak:
                let freq = 62.0 + 110.0 * exp(-t * 65.0)
                phase += freq / sampleRate
                let env = Float(exp(-t * 16.0))
                synthSample = Self.fastSinUnit(phase) * env * 0.95
                rawRate = 1.08
                rawMix = 0.75
                
            case .studioAcoustic:
                let freq = 52.0 + 95.0 * exp(-t * 50.0)
                phase += freq / sampleRate
                let env = Float(exp(-t * 12.0))
                synthSample = Self.fastSinUnit(phase) * env * 0.75
                rawRate = 1.0
                rawMix = 0.82
            }
            
            let sampleIdx = trimOffsetFrames + Double(i) * rawRate
            let envTail = Float(exp(-t * (kit == .trap808 ? 4.5 : 10.0)))
            let rawL = rawSampleValue(note: 12, channel: 0, sampleIndex: sampleIdx) * envTail * microFade
            let rawR = rawSampleValue(note: 12, channel: 1, sampleIndex: sampleIdx) * envTail * microFade
            
            outData[0][i] = tanh((rawL * rawMix + synthSample) * tierGain)
            outData[1][i] = tanh((rawR * rawMix + synthSample) * tierGain)
        }
        return out
    }
    
    private func makeSnareBuffer(kit: DrumKit, tier: VelocityTier, trimOffsetFrames: Double) -> AVAudioPCMBuffer? {
        let duration: Double = (tier == .ghost) ? 0.15 : 0.32
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let tierGain: Float = (tier == .ghost) ? 0.38 : (tier == .accent ? 1.0 : 0.80)
        var lpStateL: Float = 0.0
        var lpStateR: Float = 0.0
        let filterAlpha: Float = (tier == .ghost) ? 0.30 : (tier == .accent ? 0.92 : 0.70)
        
        var rngState: UInt64 = 0x1234_5678_9ABC_DEF0
        func nextNoise() -> Float {
            rngState = rngState &* 6364136223846793005 &+ 1
            let v = Int32(truncatingIfNeeded: rngState >> 32)
            return Float(v) / Float(Int32.max)
        }
        
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let microFade = Float(min(1.0, Double(i) / 14.0))
            let noiseL = nextNoise()
            let noiseR = nextNoise()
            
            let rawRate: Double
            let rawMix: Float
            let synthL: Float
            let synthR: Float
            
            switch kit {
            case .trap808:
                let body = Self.fastSinUnit(215.0 * t) * Float(exp(-t * 38.0)) * 0.65
                let clapEnv = (t < 0.022 && Int(t * 450) % 2 == 0) ? Float(0.7) : Float(exp(-t * 26.0))
                let snap = clapEnv * ((tier == .accent) ? 0.75 : 0.45)
                synthL = body + noiseL * snap
                synthR = body + noiseR * snap
                rawRate = 1.15
                rawMix = 0.45
                
            case .club909:
                let body = (Self.fastSinUnit(185.0 * t) + 0.6 * Self.fastSinUnit(330.0 * t)) * Float(exp(-t * 30.0)) * 0.5
                let wireEnv = Float(exp(-t * (tier == .ghost ? 28.0 : 14.0)))
                synthL = body + noiseL * wireEnv * 0.55
                synthR = body + noiseR * wireEnv * 0.55
                rawRate = 1.04
                rawMix = 0.55
                
            case .mpcLoFi:
                let body = Self.fastSinUnit(195.0 * t) * Float(exp(-t * 34.0)) * 0.55
                let wireEnv = Float(exp(-t * (tier == .ghost ? 30.0 : 17.0)))
                synthL = body + noiseL * wireEnv * 0.35
                synthR = body + noiseR * wireEnv * 0.35
                rawRate = 0.96
                rawMix = 0.85
                
            case .funkBreak:
                let rimCrack = (tier == .accent) ? Self.fastSinUnit(490.0 * t) * Float(exp(-t * 95.0)) * 0.55 : 0.0
                let wireEnv = Float(exp(-t * (tier == .ghost ? 34.0 : 19.0)))
                synthL = rimCrack + noiseL * wireEnv * 0.28
                synthR = rimCrack + noiseR * wireEnv * 0.28
                rawRate = 1.14
                rawMix = 0.88
                
            case .studioAcoustic:
                let rimCrack = (tier == .accent) ? Self.fastSinUnit(420.0 * t) * Float(exp(-t * 85.0)) * 0.35 : 0.0
                let wireEnv = Float(exp(-t * (tier == .ghost ? 28.0 : 15.0)))
                synthL = rimCrack + noiseL * wireEnv * 0.22
                synthR = rimCrack + noiseR * wireEnv * 0.22
                rawRate = 1.0
                rawMix = 0.92
            }
            
            let sampleIdx = trimOffsetFrames + Double(i) * rawRate
            let envGate = Float(exp(-t * (tier == .ghost ? 20.0 : 8.5)))
            let rawL = rawSampleValue(note: 13, channel: 0, sampleIndex: sampleIdx) * envGate * microFade
            let rawR = rawSampleValue(note: 13, channel: 1, sampleIndex: sampleIdx) * envGate * microFade
            
            let combinedL = rawL * rawMix + synthL
            let combinedR = rawR * rawMix + synthR
            lpStateL += filterAlpha * (combinedL - lpStateL)
            lpStateR += filterAlpha * (combinedR - lpStateR)
            
            outData[0][i] = tanh(lpStateL * tierGain * 1.15)
            outData[1][i] = tanh(lpStateR * tierGain * 1.15)
        }
        return out
    }
    
    private func makeClosedHatBuffer(kit: DrumKit, tier: VelocityTier, trimOffsetFrames: Double) -> AVAudioPCMBuffer? {
        let duration: Double = (tier == .ghost) ? 0.062 : 0.110
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
            let microFade = Float(min(1.0, Double(i) / 10.0))
            let env = Float(exp(-t * decayRate))
            let m1 = Self.fastSinUnit(6340.0 * t)
            let m2 = Self.fastSinUnit(8920.0 * t)
            let m3 = Self.fastSinUnit(11450.0 * t)
            let metallic = (m1 + m2 + m3) * 0.25 * metallicMix * env
            
            let sampleIdx = trimOffsetFrames + Double(i) * rawRate
            let rawL = rawSampleValue(note: 14, channel: 0, sampleIndex: sampleIdx) * env * microFade
            let rawR = rawSampleValue(note: 14, channel: 1, sampleIndex: sampleIdx) * env * microFade
            
            outData[0][i] = (rawL * 0.85 + metallic) * tierGain
            outData[1][i] = (rawR * 0.85 - metallic) * tierGain
        }
        return out
    }
    
    private func makeOpenHatBuffer(kit: DrumKit, tier: VelocityTier, trimOffsetFrames: Double) -> AVAudioPCMBuffer? {
        let duration: Double = 0.45
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
            let microFade = Float(min(1.0, Double(i) / 12.0))
            let env = Float(exp(-t * decayRate))
            
            rng = rng &* 6364136223846793005 &+ 1
            let nL = Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max)
            rng = rng &* 6364136223846793005 &+ 1
            let nR = Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max)
            
            let hpL = nL - hpPrevL
            let hpR = nR - hpPrevR
            hpPrevL = nL * 0.82
            hpPrevR = nR * 0.82
            
            let shimmer = (Self.fastSinUnit(5820.0 * t) + Self.fastSinUnit(8310.0 * t)) * 0.16
            let cymbalTailL = (hpL * 0.26 + shimmer) * env
            let cymbalTailR = (hpR * 0.26 - shimmer) * env
            
            let sampleIdx = trimOffsetFrames + Double(i) * rawRate
            let rawL = rawSampleValue(note: 15, channel: 0, sampleIndex: sampleIdx) * env * microFade
            let rawR = rawSampleValue(note: 15, channel: 1, sampleIndex: sampleIdx) * env * microFade
            
            outData[0][i] = tanh((rawL * 0.85 + cymbalTailL) * tierGain)
            outData[1][i] = tanh((rawR * 0.85 + cymbalTailR) * tierGain)
        }
        return out
    }
    
    // MARK: - Zero-Latency Drum Triggering (Callable from both CoreMIDI RT Thread & MainActor)
    
    /// Thread-safe immediate trigger usable directly on the CoreMIDI real-time thread
    nonisolated func triggerSoundRealtime(for noteNumber: UInt8, velocity: UInt8 = 100) {
        let tier = VelocityTier.from(velocity: velocity)
        let clampedVelocity = max(1, min(127, Int(velocity)))
        let velocityScale = 0.35 + 0.65 * (Float(clampedVelocity) / 127.0)
        
        let (targetNode, targetBuffer, openHatToChoke) = rtLock.withLock { state -> (AVAudioPlayerNode?, AVAudioPCMBuffer?, AVAudioPlayerNode?) in
            guard !state.playerNodes.isEmpty else { return (nil, nil, nil) }
            let key = KitSampleKey(
                kit: state.currentKit,
                latencyMode: state.latencyMode,
                note: noteNumber,
                tier: tier
            )
            guard let buf = state.kitBuffers[key] ?? state.rawBuffers[noteNumber] else { return (nil, nil, nil) }
            
            var choke: AVAudioPlayerNode? = nil
            if noteNumber == 14, let openHat = state.activeOpenHatNode {
                choke = openHat
                state.activeOpenHatNode = nil
            }
            
            let node = state.playerNodes[state.currentPlayerIndex]
            state.currentPlayerIndex = (state.currentPlayerIndex + 1) % state.playerNodes.count
            if noteNumber == 15 {
                state.activeOpenHatNode = node
            }
            return (node, buf, choke)
        }
        
        // Choke Open Hi-Hat if Closed Hi-Hat was struck
        if let chokeNode = openHatToChoke {
            // Schedule silence/interrupt rather than full stop() so node stays primed
            chokeNode.stop()
            chokeNode.play()
        }
        
        if let playerNode = targetNode, let buffer = targetBuffer {
            playerNode.volume = min(1.0, velocityScale)
            if !playerNode.isPlaying {
                playerNode.play()
            }
            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        }
    }
    
    func triggerSound(for noteNumber: UInt8, velocity: UInt8 = 100) {
        if !engine.isRunning {
            startEngine()
        }
        triggerSoundRealtime(for: noteNumber, velocity: velocity)
    }
    
    // MARK: - Musical Backing Track Synth (Pre-Warmed & LUT-Accelerated)
    
    /// Pre-generates all Bass and Rhodes Chord buffers for a pattern so zero synthesis occurs during gameplay
    func prewarmBacking(events: [BackingStepEvent], stepDuration: TimeInterval) {
        for event in events {
            if let bassMIDI = event.bassMIDINote, event.bassDurationSteps > 0 {
                let durationSec = max(0.12, min(2.5, event.bassDurationSteps * stepDuration))
                let durationMs = Int((durationSec * 1000.0).rounded())
                let key = BassCacheKey(midiNote: bassMIDI, durationMs: durationMs)
                if bassBufferCache[key] == nil,
                   let generated = makeBassBuffer(midiNote: bassMIDI, duration: durationSec) {
                    bassBufferCache[key] = generated
                }
            }
            if !event.chordMIDINotes.isEmpty && event.chordDurationSteps > 0 {
                let durationSec = max(0.18, min(3.5, event.chordDurationSteps * stepDuration))
                let durationMs = Int((durationSec * 1000.0).rounded())
                let key = ChordCacheKey(midiNotes: event.chordMIDINotes, durationMs: durationMs)
                if chordBufferCache[key] == nil,
                   let generated = makeChordBuffer(midiNotes: event.chordMIDINotes, duration: durationSec) {
                    chordBufferCache[key] = generated
                }
            }
        }
    }
    
    func playBackingEvent(_ event: BackingStepEvent, stepDuration: TimeInterval) {
        if !engine.isRunning {
            startEngine()
        }
        
        // 1. Trigger Bass Note
        if let bassMIDI = event.bassMIDINote, event.bassDurationSteps > 0 {
            let durationSec = max(0.12, min(2.5, event.bassDurationSteps * stepDuration))
            let durationMs = Int((durationSec * 1000.0).rounded())
            let cacheKey = BassCacheKey(midiNote: bassMIDI, durationMs: durationMs)
            
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
                bassNode.volume = 0.68
                if !bassNode.isPlaying { bassNode.play() }
                bassNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            }
        }
        
        // 2. Trigger Rhodes / Synth Chord
        if !event.chordMIDINotes.isEmpty && event.chordDurationSteps > 0 {
            let durationSec = max(0.18, min(3.5, event.chordDurationSteps * stepDuration))
            let durationMs = Int((durationSec * 1000.0).rounded())
            let cacheKey = ChordCacheKey(midiNotes: event.chordMIDINotes, durationMs: durationMs)
            
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
                chordNode.volume = 0.52
                if !chordNode.isPlaying { chordNode.play() }
                chordNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            }
        }
    }
    
    func stopBackingAudio() {
        if bassNode.isPlaying {
            bassNode.stop()
            bassNode.play()
        }
        if chordNode.isPlaying {
            chordNode.stop()
            chordNode.play()
        }
    }
    
    private static func midiFrequency(_ note: UInt8) -> Double {
        440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
    }
    
    private func makeBassBuffer(midiNote: UInt8, duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = frames
        
        let freq = Self.midiFrequency(midiNote)
        let releaseStart = max(0.04, duration - 0.04)
        
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let attack = Float(min(1.0, t / 0.006))
            let release = t > releaseStart ? Float(max(0.0, 1.0 - (t - releaseStart) / 0.04)) : 1.0
            let sustainDecay = Float(exp(-t * 2.2))
            let env = attack * sustainDecay * release
            
            let pluckEnv = Float(exp(-t * 18.0))
            let f1 = Self.fastSinUnit(freq * t)
            let f2 = Self.fastSinUnit(freq * 2.0 * t) * (0.38 * pluckEnv + 0.12)
            let f3 = Self.fastSinUnit(freq * 3.0 * t) * (0.18 * pluckEnv)
            
            let sample = tanh((f1 + f2 + f3) * env * 0.55)
            outData[0][i] = sample
            outData[1][i] = sample
        }
        return out
    }
    
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
            let attack = Float(min(1.0, t / 0.010))
            let release = t > releaseStart ? Float(max(0.0, 1.0 - (t - releaseStart) / 0.06)) : 1.0
            let bodyEnv = Float(exp(-t * 1.6)) * attack * release
            let tineEnv = Float(exp(-t * 16.0)) * attack
            
            let lfo = 0.08 * Self.fastSinUnit(4.2 * t)
            var sumL: Float = 0.0
            var sumR: Float = 0.0
            
            for (idx, f) in freqs.enumerated() {
                let detuneL = f * (1.0 - 0.0012)
                let detuneR = f * (1.0 + 0.0012)
                let tine = Self.fastSinUnit(f * 4.0 * t) * 0.18 * tineEnv
                let mod = Double(Self.fastSinUnit(f * 2.0 * t) * 0.04 * Float(exp(-t * 5.0)))
                
                let voiceL = Self.fastSinUnit(detuneL * t + mod) * bodyEnv + tine
                let voiceR = Self.fastSinUnit(detuneR * t + mod) * bodyEnv + tine
                
                let pan = Float(idx) / Float(max(1, freqs.count - 1))
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
            let sample = fastSinUnit(frequency * t) * envelope * gain
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
            if !metronomeNode.isPlaying {
                metronomeNode.play()
            }
            metronomeNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        }
    }
}

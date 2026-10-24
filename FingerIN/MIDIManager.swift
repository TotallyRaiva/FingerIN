import Foundation
import CoreMIDI
import Combine
import QuartzCore

/// Represents a discrete MIDI pad hit event with velocity and hardware arrival timestamp
struct MIDINoteEvent: Equatable {
    let canonicalNote: UInt8
    let rawNote: UInt8
    let velocity: UInt8
    let timestamp: TimeInterval
}

@MainActor
class MIDIManager: ObservableObject {
    static let shared = MIDIManager()
    
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSourceRefs = Set<MIDIEndpointRef>()
    
    @Published var lastNote: Int?
    @Published var lastVelocity: Int?
    @Published var connectedDevices: [String] = []
    
    /// Discrete event stream for Note On hits (used by GameScene to avoid @Published state side-effects)
    let noteOnPublisher = PassthroughSubject<MIDINoteEvent, Never>()
    
    private init() {
        setupMIDI()
    }
    
    private func setupMIDI() {
        // 1. Create MIDI Client and handle hot-plug notifications
        var status = MIDIClientCreateWithBlock("FingerINMIDIClient" as CFString, &client) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.connectToSources()
                self?.updateConnectedDevices()
            }
        }
        
        if status != noErr {
            print("MIDIManager: Error creating MIDI Client: \(status)")
            return
        }
        
        // 2. Create Input Port
        status = MIDIInputPortCreateWithBlock(client, "FingerINInputPort" as CFString, &inputPort) { [weak self] packetList, _ in
            let events = Self.parseMIDIPackets(packetList)
            guard !events.isEmpty else { return }
            let receiveTime = CACurrentMediaTime()
            Task { @MainActor [weak self] in
                self?.processParsedEvents(events, timestamp: receiveTime)
            }
        }
        
        if status != noErr {
            print("MIDIManager: Error creating MIDI Input Port: \(status)")
            return
        }
        
        // 3. Connect to all currently available sources
        connectToSources()
        updateConnectedDevices()
    }
    
    private func connectToSources() {
        let sourceCount = MIDIGetNumberOfSources()
        var currentSources = Set<MIDIEndpointRef>()
        
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            currentSources.insert(source)
            if !connectedSourceRefs.contains(source) {
                let status = MIDIPortConnectSource(inputPort, source, nil)
                if status == noErr {
                    connectedSourceRefs.insert(source)
                }
            }
        }
        // Clean up disconnected sources
        connectedSourceRefs.formIntersection(currentSources)
    }
    
    private func updateConnectedDevices() {
        var devices: [String] = []
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            var nameRef: Unmanaged<CFString>? = nil
            let status = MIDIObjectGetStringProperty(source, kMIDIPropertyName, &nameRef)
            if status == noErr, let cfStr = nameRef?.takeRetainedValue() {
                devices.append(cfStr as String)
            }
        }
        self.connectedDevices = devices
    }
    
    // MARK: - Safe Multi-Message MIDI Packet Parser
    
    private enum ParsedMIDIAction {
        case noteOn(note: UInt8, velocity: UInt8)
        case noteOff(note: UInt8)
    }
    
    /// Safely parses all packets and multi-message byte streams (including chords & running status)
    nonisolated private static func parseMIDIPackets(_ packetList: UnsafePointer<MIDIPacketList>) -> [ParsedMIDIAction] {
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) else {
            return []
        }
        
        let numPackets = Int(packetList.pointee.numPackets)
        var packetPtr = UnsafeMutableRawPointer(mutating: packetList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)
        
        var actions: [ParsedMIDIAction] = []
        
        for _ in 0..<numPackets {
            let length = Int(packetPtr.pointee.length)
            let bytes: [UInt8] = withUnsafeBytes(of: packetPtr.pointee.data) { rawBuffer in
                Array(rawBuffer.prefix(length))
            }
            
            var index = 0
            var runningStatus: UInt8 = 0
            
            while index < bytes.count {
                let byte = bytes[index]
                
                if byte >= 0x80 {
                    // System Real-Time messages (0xF8..0xFF) are single-byte and don't affect running status
                    if byte >= 0xF8 {
                        index += 1
                        continue
                    }
                    // System Common / SysEx (0xF0..0xF7)
                    if byte >= 0xF0 {
                        runningStatus = 0
                        index += 1
                        continue
                    }
                    runningStatus = byte
                    index += 1
                }
                
                let command = runningStatus & 0xF0
                switch command {
                case 0x80: // Note Off (2 data bytes)
                    guard index + 1 < bytes.count else { index = bytes.count; break }
                    let note = bytes[index]
                    actions.append(.noteOff(note: note))
                    index += 2
                    
                case 0x90: // Note On (2 data bytes)
                    guard index + 1 < bytes.count else { index = bytes.count; break }
                    let note = bytes[index]
                    let velocity = bytes[index + 1]
                    if velocity > 0 {
                        actions.append(.noteOn(note: note, velocity: velocity))
                    } else {
                        actions.append(.noteOff(note: note))
                    }
                    index += 2
                    
                case 0xA0, 0xB0, 0xE0: // Other 2-data-byte channel messages
                    index += 2
                    
                case 0xC0, 0xD0: // 1-data-byte channel messages
                    index += 1
                    
                default:
                    // Unrecognized or data byte without running status
                    index += 1
                }
            }
            
            packetPtr = MIDIPacketNext(packetPtr)
        }
        
        return actions
    }
    
    private func processParsedEvents(_ actions: [ParsedMIDIAction], timestamp: TimeInterval) {
        for action in actions {
            switch action {
            case .noteOn(let rawNote, let velocity):
                self.lastNote = Int(rawNote)
                self.lastVelocity = Int(velocity)
                
                if let canonicalNote = DataManager.shared.resolveIncomingMIDINote(rawNote) {
                    AudioManager.shared.triggerSound(for: canonicalNote, velocity: velocity)
                    PadStatusManager.shared.highlightPad(canonicalNote)
                    noteOnPublisher.send(
                        MIDINoteEvent(
                            canonicalNote: canonicalNote,
                            rawNote: rawNote,
                            velocity: velocity,
                            timestamp: timestamp
                        )
                    )
                }
                
            case .noteOff(let rawNote):
                if let match = DataManager.shared.customMIDIMapping.first(where: { $0.value == rawNote }) {
                    PadStatusManager.shared.removeHighlight(match.key)
                } else {
                    PadStatusManager.shared.removeHighlight(rawNote)
                }
            }
        }
    }
    
    /// Simulates a pad hit from keyboard shortcuts or UI buttons
    func simulatePadHit(canonicalNote: UInt8, velocity: UInt8 = 100) {
        self.lastNote = Int(canonicalNote)
        self.lastVelocity = Int(velocity)
        AudioManager.shared.triggerSound(for: canonicalNote, velocity: velocity)
        PadStatusManager.shared.pulseHighlight(canonicalNote, duration: 0.12)
        noteOnPublisher.send(
            MIDINoteEvent(
                canonicalNote: canonicalNote,
                rawNote: canonicalNote,
                velocity: velocity,
                timestamp: CACurrentMediaTime()
            )
        )
    }
}

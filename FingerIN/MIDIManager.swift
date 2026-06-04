import Foundation
import CoreMIDI
import Combine

class MIDIManager: ObservableObject {
    static let shared = MIDIManager()
    
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    
    @Published var lastNote: Int?
    @Published var lastVelocity: Int?
    @Published var connectedDevices: [String] = []

    private init() {
        setupMIDI()
    }
    
    private func setupMIDI() {
        // 1. Create MIDI Client
        var status = MIDIClientCreateWithBlock("FingerINMIDIClient" as CFString, &client) { notificationPtr in
            // Handle notifications (device added/removed)
            self.updateConnectedDevices()
        }
        
        if status != noErr {
            print("Error creating MIDI Client: \(status)")
            return
        }
        
        // 2. Create Input Port
        status = MIDIInputPortCreateWithBlock(client, "FingerINInputPort" as CFString, &inputPort) { packetList, srcConnRefCon in
            self.handleMIDIInput(packetList: packetList)
        }
        
        if status != noErr {
            print("Error creating MIDI Input Port: \(status)")
            return
        }
        
        // 3. Connect to all available sources
        connectToSources()
        updateConnectedDevices()
    }
    
    private func connectToSources() {
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, source, nil)
        }
    }
    
    private func updateConnectedDevices() {
        var devices: [String] = []
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            var nameRef: Unmanaged<CFString>? = nil
            let status = MIDIObjectGetStringProperty(source, kMIDIPropertyName, &nameRef)
            if status == noErr, let cfStr = nameRef?.takeRetainedValue() {
                let name = cfStr as String
                devices.append(name)
            }
        }
        DispatchQueue.main.async {
            self.connectedDevices = devices
        }
    }
    
    private func handleMIDIInput(packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        let packetCount = Int(packetList.pointee.numPackets)
        
        for _ in 0..<packetCount {
            let data = withUnsafeBytes(of: packet.data) { Array($0) }
            let length = Int(packet.length)
            
            if length >= 3 {
                let status = data[0]
                let note = Int(data[1])
                let velocity = Int(data[2])
                
                // Note ON is 0x90 to 0x9F (depending on channel)
                if (status & 0xF0) == 0x90 && velocity > 0 {
                    print("Sniffer: Note ON - Note Number: [\(note)], Velocity: [\(velocity)]")
                    
                    // Trigger sound instantly for zero-latency feedback
                    AudioManager.shared.triggerSound(for: UInt8(note))
                    
                    DispatchQueue.main.async {
                        self.lastNote = note
                        self.lastVelocity = velocity
                    }
                } else if (status & 0xF0) == 0x80 || ((status & 0xF0) == 0x90 && velocity == 0) {
                    // Note OFF
                    // print("Sniffer: Note OFF - Note Number: [\(note)]")
                }
            }
            
            packet = MIDIPacketNext(&packet).pointee
        }
    }
}

import SwiftUI

struct PadMatrixView: View {
    let activeIndex: Int // 0-15 representing the pad in a 4x4 matrix
    let color: Color
    let isGlowing: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<4) { row in
                HStack(spacing: 2) {
                    ForEach(0..<4) { col in
                        let index = (3 - row) * 4 + col // Bottom-to-top, left-to-right indexing
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index == activeIndex ? color : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1)
                                    .stroke(color.opacity(isGlowing && index == activeIndex ? 1 : 0), lineWidth: 1)
                                    .blur(radius: 1)
                            )
                    }
                }
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.4))
        .cornerRadius(4)
    }
}

struct LaneIndicatorView: View {
    let name: String
    let padIndex: Int
    let color: Color
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            PadMatrixView(activeIndex: padIndex, color: color, isGlowing: isActive)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? .white : .gray)
                
                Text("PAD \(padIndex + 1)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isActive ? color : .gray.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 80) // Match GameScene lane height
        .background(isActive ? Color.white.opacity(0.05) : Color.clear)
    }
}

struct LeftContextPanel: View {
    @ObservedObject var midiManager = MIDIManager.shared
    
    // Mapping MIDI notes to pad indices (0-15)
    // Note: Assuming notes 12-15 map to indices 0-3 for now.
    // Adjust as per actual controller physical layout.
    private let laneConfigs: [(note: UInt8, name: String, color: Color, padIndex: Int)] = [
        (15, "HI-HAT OPEN", .yellow, 3),
        (14, "HI-HAT CLOSED", .yellow, 2),
        (13, "SNARE", .orange, 1),
        (12, "KICK", .cyan, 0)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(laneConfigs, id: \.note) { config in
                LaneIndicatorView(
                    name: config.name,
                    padIndex: config.padIndex,
                    color: config.color,
                    isActive: midiManager.lastNote == Int(config.note)
                )
            }
        }
        .frame(width: 180)
        .background(Color(white: 0.1))
    }
}

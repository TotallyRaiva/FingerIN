import SwiftUI

struct PadMatrixView: View {
    let activeIndex: Int // 0-15 representing the pad in a 4x4 matrix
    let color: Color
    let isGlowing: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { col in
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
    let voice: DrumVoiceConfig
    let mappedNote: UInt8
    let isHighlighted: Bool
    let isLearning: Bool
    let onTrigger: () -> Void
    let onToggleLearn: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTrigger) {
                PadMatrixView(
                    activeIndex: voice.defaultPadIndex,
                    color: voice.color,
                    isGlowing: isHighlighted
                )
            }
            .buttonStyle(.plain)
            .help("Click to audition \(voice.fullName) (Key: \(String(voice.keyEquivalent).uppercased()))")
            
            VStack(alignment: .leading, spacing: 3) {
                Text(voice.fullName)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isHighlighted ? .white : .gray)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text("MIDI \(mappedNote) · [\(String(voice.keyEquivalent).uppercased())]")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(isHighlighted ? voice.color : .gray.opacity(0.75))
                    
                    Button(action: onToggleLearn) {
                        Text(isLearning ? "HIT PAD..." : "MAP")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isLearning ? Color.orange : Color.white.opacity(0.1))
                            .foregroundColor(isLearning ? .black : .gray)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("Click then hit any physical MIDI pad to map it to \(voice.shortName)")
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 80) // Match GameScene lane height
        .background(isHighlighted ? voice.color.opacity(0.14) : Color.clear)
        .animation(.easeOut(duration: 0.08), value: isHighlighted)
    }
}

struct LeftContextPanel: View {
    @ObservedObject var padStatus = PadStatusManager.shared
    @ObservedObject var dataManager = DataManager.shared
    
    // Top-to-bottom visual order matching GameScene's bottom-to-top lane coordinates (15 down to 12)
    private var topDownVoices: [DrumVoiceConfig] {
        DrumVoiceConfig.allVoices.sorted { $0.laneIndex > $1.laneIndex }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(topDownVoices) { voice in
                LaneIndicatorView(
                    voice: voice,
                    mappedNote: dataManager.physicalNote(forCanonicalNote: voice.canonicalNote),
                    isHighlighted: padStatus.isPadHighlighted[voice.canonicalNote] ?? false,
                    isLearning: dataManager.learningCanonicalNote == voice.canonicalNote,
                    onTrigger: {
                        MIDIManager.shared.simulatePadHit(canonicalNote: voice.canonicalNote)
                    },
                    onToggleLearn: {
                        dataManager.toggleMIDILearn(forCanonicalNote: voice.canonicalNote)
                    }
                )
            }
        }
        .frame(width: 180)
        .background(Color(white: 0.1))
    }
}

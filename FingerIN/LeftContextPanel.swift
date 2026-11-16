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
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index == activeIndex ? color : Color.white.opacity(0.16))
                            .frame(width: 6, height: 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .stroke(index == activeIndex ? MPCTheme.ink : Color.clear, lineWidth: 0.8)
                            )
                    }
                }
            }
        }
        .padding(5)
        .background(MPCTheme.mpcPanel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isGlowing ? color : MPCTheme.ink, lineWidth: 2)
        )
        .shadow(color: isGlowing ? color.opacity(0.65) : MPCTheme.ink, radius: isGlowing ? 6 : 0, x: isGlowing ? 0 : 2, y: isGlowing ? 0 : 2)
    }
}

struct LaneIndicatorView: View {
    let voice: DrumVoiceConfig
    let mappedNote: UInt8
    let isHighlighted: Bool
    let isLearning: Bool
    let isMuted: Bool
    let onTrigger: () -> Void
    let onToggleMute: () -> Void
    let onToggleLearn: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTrigger) {
                PadMatrixView(
                    activeIndex: voice.defaultPadIndex,
                    color: isMuted ? .gray : voice.color,
                    isGlowing: isHighlighted
                )
            }
            .buttonStyle(.plain)
            .help("Click to audition \(voice.fullName) (Key: \(String(voice.keyEquivalent).uppercased()))")
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isMuted ? Color.gray.opacity(0.4) : voice.color)
                        .frame(width: 8, height: 8)
                        .shadow(color: isMuted ? .clear : voice.color.opacity(0.8), radius: 4)
                    
                    Button(action: onToggleMute) {
                        Text(voice.matrixLabel)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(isMuted ? .gray : (isHighlighted ? .white : Color(white: 0.94)))
                            .strikethrough(isMuted, color: .red)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Click to toggle \(voice.shortName) lane active/muted")
                    
                    Spacer(minLength: 2)
                    
                    if isHighlighted {
                        Text(voice.comicBurst)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(MPCTheme.snare)
                            .foregroundColor(MPCTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(MPCTheme.ink, lineWidth: 1.5)
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                HStack(spacing: 5) {
                    Text("[\(String(voice.keyEquivalent).uppercased())]")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(MPCTheme.mpcCream)
                        .foregroundColor(MPCTheme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(MPCTheme.ink, lineWidth: 1.2)
                        )
                    
                    Text("N\(mappedNote)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.65))
                    
                    Spacer(minLength: 2)
                    
                    Button(action: onToggleLearn) {
                        Text(isLearning ? "HIT PAD" : "MAP")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isLearning ? MPCTheme.kick : MPCTheme.mpcSlate)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isLearning ? Color.white : MPCTheme.ink, lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Click then hit any physical MIDI pad to map it to \(voice.shortName)")
                }
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(isMuted ? Color.gray.opacity(0.25) : voice.color)
                    .frame(height: 3.5)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 80) // Match GameScene lane height (4 * 80 = 320)
        .background(
            ZStack {
                MPCTheme.mpcChassis
                if isHighlighted {
                    voice.color.opacity(0.20)
                }
            }
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.08)),
            alignment: .bottom
        )
        .animation(.easeOut(duration: 0.08), value: isHighlighted)
    }
}

struct LeftContextPanel: View {
    @Binding var activePads: Set<UInt8>
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
                    isMuted: !activePads.contains(voice.canonicalNote),
                    onTrigger: {
                        MIDIManager.shared.simulatePadHit(canonicalNote: voice.canonicalNote)
                    },
                    onToggleMute: {
                        if activePads.contains(voice.canonicalNote) {
                            activePads.remove(voice.canonicalNote)
                        } else {
                            activePads.insert(voice.canonicalNote)
                        }
                    },
                    onToggleLearn: {
                        dataManager.toggleMIDILearn(forCanonicalNote: voice.canonicalNote)
                    }
                )
            }
        }
        .frame(width: 206, height: 320)
        .background(MPCTheme.mpcChassis)
        .overlay(
            Rectangle()
                .frame(width: 3)
                .foregroundColor(MPCTheme.ink),
            alignment: .trailing
        )
    }
}

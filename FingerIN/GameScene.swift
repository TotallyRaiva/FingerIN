import SpriteKit
import SwiftUI
import QuartzCore

/// Strongly-typed SpriteKit node representing a falling/scrolling drum note
final class NoteNode: SKShapeNode {
    let padIndex: UInt8
    let velocity: UInt8
    let targetHitSongTime: TimeInterval
    let travelDuration: TimeInterval
    var isJudged: Bool = false
    var hasPlayedDemoAudio: Bool = false
    
    init(
        padIndex: UInt8,
        velocity: UInt8,
        targetHitSongTime: TimeInterval,
        travelDuration: TimeInterval,
        size: CGSize,
        color: NSColor
    ) {
        self.padIndex = padIndex
        self.velocity = velocity
        self.targetHitSongTime = targetHitSongTime
        self.travelDuration = travelDuration
        super.init()
        
        let cornerRadius: CGFloat = velocity < 70 ? 8 : 6
        let rect = CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2), size: size)
        self.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        // Visual distinction between Ghost notes (<70), Normal notes (70..110), and Accents (>110)
        let alpha: CGFloat = velocity < 70 ? 0.50 : (velocity > 110 ? 0.98 : 0.84)
        self.fillColor = color.withAlphaComponent(alpha)
        self.strokeColor = velocity > 110 ? .white : color.withAlphaComponent(0.9)
        self.lineWidth = velocity > 110 ? 2.2 : 1.0
        self.glowWidth = velocity > 110 ? 4.5 : (velocity < 70 ? 0.0 : 1.5)
        self.zPosition = 5
        self.name = "note"
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Vertical beat / bar grid line scrolling in sync with notes
final class GridLineNode: SKShapeNode {
    let targetHitSongTime: TimeInterval
    let travelDuration: TimeInterval
    let isBarLine: Bool
    
    init(
        targetHitSongTime: TimeInterval,
        travelDuration: TimeInterval,
        totalHeight: CGFloat,
        isBarLine: Bool,
        barNumber: Int? = nil
    ) {
        self.targetHitSongTime = targetHitSongTime
        self.travelDuration = travelDuration
        self.isBarLine = isBarLine
        super.init()
        
        let width: CGFloat = isBarLine ? 2.0 : 1.0
        let rect = CGRect(x: -width / 2, y: 0, width: width, height: totalHeight)
        self.path = CGPath(rect: rect, transform: nil)
        self.fillColor = NSColor.white.withAlphaComponent(isBarLine ? 0.24 : 0.07)
        self.strokeColor = .clear
        self.zPosition = 0
        self.name = "gridLine"
        
        if let barNum = barNumber, isBarLine {
            let tag = SKLabelNode(text: "BAR \(barNum)")
            tag.fontName = "Menlo-Bold"
            tag.fontSize = 9
            tag.fontColor = NSColor.white.withAlphaComponent(0.35)
            tag.horizontalAlignmentMode = .left
            tag.position = CGPoint(x: 6, y: totalHeight - 14)
            addChild(tag)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class GameScene: SKScene {
    
    // Layout Constants
    private let hitLineX: CGFloat = 80
    private let laneHeight: CGFloat = 80
    private let totalLanes = 4
    
    // Canonical Note mapping (bottom-to-top lanes: 12, 13, 14, 15)
    private let midiNotes: [UInt8] = [12, 13, 14, 15]
    
    // Timing Windows (seconds)
    private let perfectWindow: TimeInterval = 0.048
    private let goodWindow: TimeInterval = 0.140
    private let maxEarlyCandidateWindow: TimeInterval = 0.25
    
    // Playback & Scheduler State
    private var isEnginePlaying: Bool = false
    private var lastUpdateRealTime: TimeInterval?
    private(set) var songTime: TimeInterval = 0
    
    private var patternNotes: [TrackNote] = []
    private var backingEvents: [BackingStepEvent] = []
    private var totalPatternSteps: Int = 32
    private var barDuration: TimeInterval = 2.0
    private var isLooping: Bool = true
    private var isMetronomeEnabled: Bool = false
    private var isBackingTrackEnabled: Bool = true
    private var isDemoMode: Bool = false
    private var isCalibrationMode: Bool = false
    private var activePads: Set<UInt8> = [12, 13, 14, 15]
    
    private var lastSpawnedStepIndex: Int = -1
    private var lastHitStepIndex: Int = -1
    private var lastMetronomeBeatIndex: Int = -1
    
    // Tracked Scene Nodes
    private var hitLine: SKShapeNode?
    private var playhead: SKShapeNode?
    private var lanes: [SKShapeNode] = []
    private var activeNoteNodes: [NoteNode] = []
    private var activeGridLines: [GridLineNode] = []
    private var worldNode = SKNode()
    
    override func didMove(to view: SKView) {
        self.anchorPoint = .zero
        self.backgroundColor = .black
        
        worldNode.removeFromParent()
        addChild(worldNode)
        
        rebuildStaticGeometry()
        self.isPaused = !isEnginePlaying
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard oldSize != size, size.width > 0 else { return }
        rebuildStaticGeometry()
    }
    
    private func rebuildStaticGeometry() {
        lanes.forEach { $0.removeFromParent() }
        lanes.removeAll()
        hitLine?.removeFromParent()
        playhead?.removeFromParent()
        
        setupLanes()
        setupHitLine()
    }
    
    private func setupLanes() {
        let laneWidth = max(size.width * 2, 1200)
        for i in 0..<totalLanes {
            let laneY = (CGFloat(i) * laneHeight) + (laneHeight / 2)
            let lane = SKShapeNode(rectOf: CGSize(width: laneWidth, height: laneHeight - 1))
            lane.position = CGPoint(x: laneWidth / 2, y: laneY)
            lane.strokeColor = SKColor.white.withAlphaComponent(0.06)
            lane.fillColor = (i % 2 == 0) ? SKColor.white.withAlphaComponent(0.015) : .clear
            lane.zPosition = -2
            worldNode.addChild(lane)
            lanes.append(lane)
        }
    }
    
    private func setupHitLine() {
        let totalHeight = laneHeight * CGFloat(totalLanes)
        let line = SKShapeNode(rectOf: CGSize(width: 2, height: totalHeight))
        line.fillColor = .cyan
        line.strokeColor = .cyan
        line.position = CGPoint(x: hitLineX, y: totalHeight / 2)
        line.glowWidth = 3
        line.zPosition = 3
        worldNode.addChild(line)
        self.hitLine = line
        
        let trianglePath = CGMutablePath()
        trianglePath.move(to: CGPoint(x: -10, y: 10))
        trianglePath.addLine(to: CGPoint(x: 10, y: 10))
        trianglePath.addLine(to: CGPoint(x: 0, y: 0))
        trianglePath.closeSubpath()
        
        let head = SKShapeNode(path: trianglePath)
        head.fillColor = .cyan
        head.strokeColor = .white
        head.position = CGPoint(x: hitLineX, y: totalHeight)
        head.zPosition = 4
        worldNode.addChild(head)
        self.playhead = head
    }
    
    // MARK: - Frame-Accurate Update Loop & Scheduler
    
    private var spawnX: CGFloat {
        max(size.width + 40, hitLineX + 400)
    }
    
    /// Visual travel duration equals 1 bar (4 beats = 16 steps) so the metronome count-in and bar lines are 100% phase-aligned at every BPM
    private var currentTravelDuration: TimeInterval {
        max(0.8, barDuration)
    }
    
    override func update(_ currentTime: TimeInterval) {
        guard isEnginePlaying, !self.isPaused else {
            lastUpdateRealTime = nil
            return
        }
        
        let dt: TimeInterval
        if let prev = lastUpdateRealTime {
            dt = min(0.1, max(0.0, currentTime - prev))
        } else {
            dt = 0.0
        }
        lastUpdateRealTime = currentTime
        songTime += dt
        
        let stepDuration = barDuration / 16.0
        let beatDuration = barDuration / 4.0
        guard stepDuration > 0, beatDuration > 0 else { return }
        
        // 1. Trigger phase-aligned Metronome clicks on exact beat boundaries
        let currentBeatIndex = Int(floor(songTime / beatDuration))
        if currentBeatIndex > lastMetronomeBeatIndex {
            lastMetronomeBeatIndex = currentBeatIndex
            if isMetronomeEnabled {
                let isDownbeat = (currentBeatIndex % 4) == 0
                AudioManager.shared.playMetronomeClick(isDownbeat: isDownbeat)
            }
        }
        
        // 2. Spawn notes and beat grid lines per 16th-note step (16 steps = 1 bar ahead of hit line)
        let currentStepIndex = Int(floor(songTime / stepDuration))
        if currentStepIndex > lastSpawnedStepIndex {
            for step in (lastSpawnedStepIndex + 1)...currentStepIndex {
                if !isLooping && step >= totalPatternSteps {
                    break
                }
                spawnStepContent(globalStep: step, stepDuration: stepDuration)
            }
            lastSpawnedStepIndex = currentStepIndex
        }
        
        // 3. Trigger musical accompaniment (Bass + Rhodes Chords) as steps cross hitLineX (after 16-step travel)
        let currentHitStep = currentStepIndex - 16
        if currentHitStep >= 0 && currentHitStep > lastHitStepIndex {
            for hitStep in max(0, lastHitStepIndex + 1)...currentHitStep {
                if !isLooping && hitStep >= totalPatternSteps {
                    break
                }
                if isBackingTrackEnabled && !isCalibrationMode {
                    let localStep = hitStep % max(16, totalPatternSteps)
                    for event in backingEvents where event.stepIndex == localStep {
                        AudioManager.shared.playBackingEvent(event, stepDuration: stepDuration)
                    }
                }
            }
            lastHitStepIndex = currentHitStep
        }
        
        // 4. Update positions of all active grid lines
        let distanceToHitLine = spawnX - hitLineX
        for i in stride(from: activeGridLines.count - 1, through: 0, by: -1) {
            let gridNode = activeGridLines[i]
            let timeRemaining = gridNode.targetHitSongTime - songTime
            let progress = timeRemaining / gridNode.travelDuration
            gridNode.position.x = hitLineX + CGFloat(progress) * distanceToHitLine
            
            if gridNode.position.x < -20 {
                gridNode.removeFromParent()
                activeGridLines.remove(at: i)
            }
        }
        
        // 5. Update positions and handle Demo triggers / Miss expirations for active notes
        let visualOffset = CalibrationManager.shared.visualOffset
        for i in stride(from: activeNoteNodes.count - 1, through: 0, by: -1) {
            let noteNode = activeNoteNodes[i]
            let timeRemaining = noteNode.targetHitSongTime - songTime
            let progress = timeRemaining / noteNode.travelDuration
            noteNode.position.x = hitLineX + CGFloat(progress) * distanceToHitLine
            
            // Demo Mode: automatically trigger sound & pad highlight at exact swung timestamp
            if isDemoMode && !noteNode.hasPlayedDemoAudio && timeRemaining <= 0 {
                noteNode.hasPlayedDemoAudio = true
                noteNode.isJudged = true
                AudioManager.shared.triggerSound(for: noteNode.padIndex, velocity: noteNode.velocity)
                PadStatusManager.shared.pulseHighlight(noteNode.padIndex, duration: 0.1)
                flashLane(for: noteNode.padIndex)
                createParticles(at: CGPoint(x: hitLineX, y: noteNode.position.y), color: voiceColor(for: noteNode.padIndex))
                noteNode.removeFromParent()
                activeNoteNodes.remove(at: i)
                continue
            }
            
            // Play Mode: immediately expire as MISS once note passes beyond the Good timing window
            let lateness = (songTime - noteNode.targetHitSongTime) - visualOffset
            if !isDemoMode && !noteNode.isJudged && lateness > goodWindow {
                noteNode.isJudged = true
                noteNode.fillColor = NSColor.systemRed.withAlphaComponent(0.35)
                noteNode.strokeColor = .systemRed
                registerMiss(at: CGPoint(x: hitLineX, y: noteNode.position.y))
            }
            
            // Remove once off-screen left
            if noteNode.position.x < -50 {
                noteNode.removeFromParent()
                activeNoteNodes.remove(at: i)
            }
        }
        
        // Stop automatically if non-looping pattern has finished and all notes have cleared
        if !isLooping && currentStepIndex >= totalPatternSteps && activeNoteNodes.isEmpty {
            setPaused(true)
        }
    }
    
    private func spawnStepContent(globalStep: Int, stepDuration: TimeInterval) {
        let travel = currentTravelDuration
        let totalHeight = laneHeight * CGFloat(totalLanes)
        let patternSteps = max(16, totalPatternSteps)
        let localStep = globalStep % patternSteps
        
        // Spawn vertical beat/bar grid line every 4 sixteenth-notes (1 beat)
        if globalStep % 4 == 0 {
            let isBarLine = (globalStep % 16) == 0
            let barNum = isBarLine ? ((localStep / 16) + 1) : nil
            let gridTargetTime = (Double(globalStep) * stepDuration) + travel
            let gridLine = GridLineNode(
                targetHitSongTime: gridTargetTime,
                travelDuration: travel,
                totalHeight: totalHeight,
                isBarLine: isBarLine,
                barNumber: barNum
            )
            gridLine.position = CGPoint(x: spawnX, y: 0)
            worldNode.addChild(gridLine)
            activeGridLines.append(gridLine)
        }
        
        // Spawn any active pattern notes matching this step (including swing offset)
        for trackNote in patternNotes where trackNote.stepIndex == localStep && activePads.contains(trackNote.padIndex) {
            let swungSpawnSongTime = (Double(globalStep) + trackNote.stepOffsetRatio) * stepDuration
            let targetHitSongTime = swungSpawnSongTime + travel
            spawnNoteNode(
                padIndex: trackNote.padIndex,
                velocity: trackNote.velocity,
                targetHitSongTime: targetHitSongTime,
                travelDuration: travel
            )
        }
    }
    
    private func spawnNoteNode(
        padIndex: UInt8,
        velocity: UInt8,
        targetHitSongTime: TimeInterval,
        travelDuration: TimeInterval
    ) {
        guard let laneIndex = midiNotes.firstIndex(of: padIndex) else { return }
        let laneY = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        
        let noteWidth: CGFloat = velocity < 70 ? 28 : 38
        let noteHeight: CGFloat = velocity < 70 ? (laneHeight - 36) : (velocity > 110 ? (laneHeight - 14) : (laneHeight - 20))
        let nsColor = NSColor(voiceColor(for: padIndex))
        let noteNode = NoteNode(
            padIndex: padIndex,
            velocity: velocity,
            targetHitSongTime: targetHitSongTime,
            travelDuration: travelDuration,
            size: CGSize(width: noteWidth, height: noteHeight),
            color: nsColor
        )
        noteNode.position = CGPoint(x: spawnX, y: laneY)
        worldNode.addChild(noteNode)
        activeNoteNodes.append(noteNode)
    }
    
    private func voiceColor(for noteNumber: UInt8) -> Color {
        DrumVoiceConfig.voice(forCanonicalNote: noteNumber)?.color ?? .white
    }
    
    // MARK: - Physical Pad & Keyboard Hit Handling
    
    func handleHit(for noteNumber: UInt8, velocity: UInt8 = 100) {
        flashLane(for: noteNumber)
        guard isEnginePlaying, !isDemoMode else { return }
        
        let visualOffset = CalibrationManager.shared.visualOffset
        
        // Filter unjudged notes in the matching lane
        let candidates = activeNoteNodes.filter { !$0.isJudged && $0.padIndex == noteNumber }
        
        // Find the candidate closest to the calibrated hit time
        guard let closestNote = candidates.min(by: { a, b in
            let deltaA = abs((songTime - a.targetHitSongTime) - visualOffset)
            let deltaB = abs((songTime - b.targetHitSongTime) - visualOffset)
            return deltaA < deltaB
        }) else {
            return
        }
        
        // Raw signed time offset: negative = EARLY, positive = LATE
        let rawSignedOffset = songTime - closestNote.targetHitSongTime
        let calibratedSignedOffset = rawSignedOffset - visualOffset
        let absTimeDiff = abs(calibratedSignedOffset)
        
        // Ignore hits that occur way before the note approaches the hit zone
        guard absTimeDiff <= maxEarlyCandidateWindow else {
            return
        }
        
        // If practicing with the Calibration pattern, feed the raw offset into CalibrationManager
        if isCalibrationMode {
            CalibrationManager.shared.recordCalibrationOffset(rawSignedOffset)
        }
        
        let accuracy: HitAccuracy
        if absTimeDiff <= perfectWindow {
            accuracy = .perfect
        } else if absTimeDiff <= goodWindow {
            accuracy = .good
        } else {
            accuracy = .miss
        }
        
        closestNote.isJudged = true
        let offsetMs = Int((calibratedSignedOffset * 1000.0).rounded())
        
        if accuracy != .miss {
            showFeedback(accuracy: accuracy, offsetMs: offsetMs, at: closestNote.position)
            triggerHitEffects(accuracy: accuracy, position: closestNote.position, padIndex: noteNumber)
            if let idx = activeNoteNodes.firstIndex(where: { $0 === closestNote }) {
                activeNoteNodes.remove(at: idx)
            }
            closestNote.removeFromParent()
            ScoreManager.shared.registerHit(accuracy: accuracy, timingOffsetMs: offsetMs)
        } else {
            closestNote.fillColor = NSColor.systemRed.withAlphaComponent(0.35)
            showFeedback(accuracy: .miss, offsetMs: offsetMs, at: closestNote.position)
            ScoreManager.shared.registerHit(accuracy: .miss, timingOffsetMs: offsetMs)
        }
    }
    
    // MARK: - Keyboard Input Fallback (macOS)
    
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat, let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return
        }
        for char in chars {
            switch char {
            case "a", "1":
                MIDIManager.shared.simulatePadHit(canonicalNote: 12)
            case "s", "2":
                MIDIManager.shared.simulatePadHit(canonicalNote: 13)
            case "d", "3":
                MIDIManager.shared.simulatePadHit(canonicalNote: 14)
            case "f", "4":
                MIDIManager.shared.simulatePadHit(canonicalNote: 15)
            default:
                break
            }
        }
    }
    
    // MARK: - Visual Feedback & Effects
    
    private func triggerHitEffects(accuracy: HitAccuracy, position: CGPoint, padIndex: UInt8) {
        let amplitude: CGFloat = accuracy == .perfect ? 6 : 2.5
        worldNode.run(SKAction.screenShake(duration: 0.08, amplitude: amplitude))
        if accuracy == .perfect {
            createParticles(at: position, color: voiceColor(for: padIndex))
        }
    }
    
    private func createParticles(at position: CGPoint, color: Color) {
        for _ in 0...12 {
            let p = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3.5))
            p.fillColor = NSColor(color)
            p.strokeColor = .clear
            p.position = position
            p.zPosition = 15
            worldNode.addChild(p)
            let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let dist = CGFloat.random(in: 35...90)
            let move = SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.35)
            move.timingMode = .easeOut
            p.run(SKAction.sequence([SKAction.group([move, .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
    }
    
    private func registerMiss(at position: CGPoint) {
        guard !isDemoMode else { return }
        ScoreManager.shared.registerHit(accuracy: .miss, timingOffsetMs: nil)
        showFeedback(accuracy: .miss, offsetMs: nil, at: position)
    }
    
    private func showFeedback(accuracy: HitAccuracy, offsetMs: Int?, at position: CGPoint) {
        let container = SKNode()
        container.position = position
        container.zPosition = 12
        
        let label = SKLabelNode(text: accuracy.rawValue)
        label.fontName = "AvenirNext-HeavyItalic"
        label.fontSize = accuracy == .perfect ? 28 : 22
        label.fontColor = NSColor(accuracy.color)
        container.addChild(label)
        
        if let offsetMs = offsetMs, accuracy != .miss {
            let direction = offsetMs < -3 ? "EARLY" : (offsetMs > 3 ? "LATE" : "ON TIME")
            let subLabel = SKLabelNode(text: String(format: "%+dms %@", offsetMs, direction))
            subLabel.fontName = "Menlo-Bold"
            subLabel.fontSize = 10
            subLabel.fontColor = NSColor.white.withAlphaComponent(0.85)
            subLabel.position = CGPoint(x: 0, y: -14)
            container.addChild(subLabel)
        }
        
        worldNode.addChild(container)
        let moveUp = SKAction.moveBy(x: 0, y: 42, duration: 0.48)
        moveUp.timingMode = .easeOut
        container.run(SKAction.sequence([
            SKAction.group([moveUp, .fadeOut(withDuration: 0.48)]),
            .removeFromParent()
        ]))
    }
    
    func flashLane(for noteNumber: UInt8) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        let laneY = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        let laneColor = NSColor(voiceColor(for: noteNumber))
        
        let hitGlow = SKShapeNode(rectOf: CGSize(width: 40, height: laneHeight - 4), cornerRadius: 4)
        hitGlow.position = CGPoint(x: hitLineX, y: laneY)
        hitGlow.fillColor = laneColor.withAlphaComponent(0.45)
        hitGlow.strokeColor = .white
        hitGlow.lineWidth = 1.5
        hitGlow.glowWidth = 8
        hitGlow.zPosition = 4
        worldNode.addChild(hitGlow)
        
        let fade = SKAction.fadeOut(withDuration: 0.12)
        hitGlow.run(SKAction.sequence([fade, .removeFromParent()]))
    }
    
    // MARK: - Level Loading & Live Settings Configuration
    
    func loadLevel(
        notes: [TrackNote],
        barDuration: TimeInterval,
        totalSteps: Int = 32,
        backingEvents: [BackingStepEvent] = [],
        loop: Bool = true,
        metronome: Bool = false,
        backingTrack: Bool = true,
        isDemoMode: Bool = false,
        isCalibrationMode: Bool = false,
        activePads: Set<UInt8> = [12, 13, 14, 15]
    ) {
        stopAndClear(resetScore: true)
        self.patternNotes = notes
        self.barDuration = max(0.5, barDuration)
        self.totalPatternSteps = max(16, totalSteps)
        self.backingEvents = backingEvents
        self.isLooping = loop
        self.isMetronomeEnabled = metronome
        self.isBackingTrackEnabled = backingTrack
        self.isDemoMode = isDemoMode
        self.isCalibrationMode = isCalibrationMode
        self.activePads = activePads
        
        if backingTrack && !isCalibrationMode {
            AudioManager.shared.prewarmBacking(events: backingEvents, stepDuration: self.barDuration / 16.0)
        }
    }
    
    /// Updates playback flags and pattern parameters live without wiping notes or resetting score
    func updateLiveConfiguration(
        notes: [TrackNote],
        barDuration: TimeInterval,
        totalSteps: Int = 32,
        backingEvents: [BackingStepEvent] = [],
        loop: Bool,
        metronome: Bool,
        backingTrack: Bool,
        isDemoMode: Bool,
        isCalibrationMode: Bool,
        activePads: Set<UInt8>
    ) {
        let oldBarDuration = self.barDuration
        self.patternNotes = notes
        self.barDuration = max(0.5, barDuration)
        self.totalPatternSteps = max(16, totalSteps)
        self.backingEvents = backingEvents
        self.isLooping = loop
        self.isMetronomeEnabled = metronome
        self.isBackingTrackEnabled = backingTrack
        self.isDemoMode = isDemoMode
        self.isCalibrationMode = isCalibrationMode
        self.activePads = activePads
        
        if !backingTrack {
            AudioManager.shared.stopBackingAudio()
        } else if !isCalibrationMode {
            AudioManager.shared.prewarmBacking(events: backingEvents, stepDuration: self.barDuration / 16.0)
        }
        
        if abs(oldBarDuration - self.barDuration) > 0.0001 && oldBarDuration > 0 {
            let ratio = self.barDuration / oldBarDuration
            songTime *= ratio
        }
    }
    
    func setPaused(_ paused: Bool) {
        self.isEnginePlaying = !paused
        self.isPaused = paused
        if paused {
            lastUpdateRealTime = nil
            AudioManager.shared.stopBackingAudio()
        }
    }
    
    func stopAndClear(resetScore: Bool = true) {
        self.removeAllActions()
        worldNode.removeAllActions()
        worldNode.position = .zero
        AudioManager.shared.stopBackingAudio()
        
        activeNoteNodes.forEach { $0.removeFromParent() }
        activeNoteNodes.removeAll()
        
        activeGridLines.forEach { $0.removeFromParent() }
        activeGridLines.removeAll()
        
        songTime = 0
        lastUpdateRealTime = nil
        lastSpawnedStepIndex = -1
        lastHitStepIndex = -1
        lastMetronomeBeatIndex = -1
        
        if resetScore {
            ScoreManager.shared.reset()
        }
    }
}

extension SKAction {
    static func screenShake(duration: TimeInterval, amplitude: CGFloat) -> SKAction {
        let numberOfShakes = max(1, Int(duration / 0.02))
        var actions: [SKAction] = []
        for _ in 0..<numberOfShakes {
            let diffX = CGFloat.random(in: -amplitude...amplitude)
            let diffY = CGFloat.random(in: -amplitude...amplitude)
            let move = SKAction.moveBy(x: diffX, y: diffY, duration: 0.01)
            actions.append(SKAction.sequence([move, move.reversed()]))
        }
        actions.append(SKAction.move(to: .zero, duration: 0.01))
        return SKAction.sequence(actions)
    }
}

import SpriteKit
import SwiftUI

class GameScene: SKScene {
    
    // Layout Constants
    private let hitLineX: CGFloat = 80 // Reserved space on the left
    private let laneHeight: CGFloat = 80
    private let totalLanes = 4
    
    // Note mapping (matching MIDI notes 12-15)
    private let midiNotes: [UInt8] = [12, 13, 14, 15]
    
    // Scoring State
    private var levelStartTime: TimeInterval = 0
    private let perfectWindow: TimeInterval = 0.05
    private let goodWindow: TimeInterval = 0.15
    private var isDemoMode: Bool = false
    
    // UI Elements
    private var hitLine: SKShapeNode!
    private var lanes: [SKShapeNode] = []
    private var worldNode = SKNode() // Node to hold everything for screen shake
    
    override func didMove(to view: SKView) {
        // Set anchor point to bottom-left for easier horizontal math
        self.anchorPoint = .zero
        
        // Ensure worldNode is clean and add it
        worldNode.removeFromParent()
        addChild(worldNode)
        
        setupBackground()
        setupLanes()
        setupHitLine()
    }
    
    private func setupBackground() {
        self.backgroundColor = .black
    }
    
    private func setupLanes() {
        for i in 0..<totalLanes {
            let laneY = (CGFloat(i) * laneHeight) + (laneHeight / 2)
            
            let lane = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: laneHeight - 1))
            lane.position = CGPoint(x: size.width / 2, y: laneY)
            lane.strokeColor = SKColor.white.withAlphaComponent(0.05)
            lane.fillColor = SKColor.clear
            lane.zPosition = -1
            worldNode.addChild(lane)
            lanes.append(lane)
        }
    }
    
    private func setupHitLine() {
        let totalHeight = laneHeight * CGFloat(totalLanes)
        hitLine = SKShapeNode(rectOf: CGSize(width: 2, height: totalHeight))
        hitLine.fillColor = .cyan
        hitLine.strokeColor = .cyan
        hitLine.position = CGPoint(x: hitLineX, y: totalHeight / 2)
        hitLine.glowWidth = 3
        hitLine.zPosition = 1
        worldNode.addChild(hitLine)
        
        // Add a triangular playhead at the top
        let trianglePath = CGMutablePath()
        trianglePath.move(to: CGPoint(x: -10, y: 10))
        trianglePath.addLine(to: CGPoint(x: 10, y: 10))
        trianglePath.addLine(to: CGPoint(x: 0, y: 0))
        trianglePath.closeSubpath()
        
        let playhead = SKShapeNode(path: trianglePath)
        playhead.fillColor = .cyan
        playhead.strokeColor = .white
        playhead.position = CGPoint(x: hitLineX, y: totalHeight)
        worldNode.addChild(playhead)
    }
    
    func spawnNote(for noteNumber: UInt8, targetHitTime: TimeInterval, travelTime: TimeInterval = 2.0) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        let laneY = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        
        let note = SKShapeNode(rectOf: CGSize(width: 40, height: laneHeight - 20), cornerRadius: 4)
        note.fillColor = .white
        note.strokeColor = .white
        note.position = CGPoint(x: size.width + 100, y: laneY)
        note.name = "note"
        
        let distanceToHit = (size.width + 100) - hitLineX
        let speed = distanceToHit / CGFloat(travelTime)
        
        note.userData = ["targetHitTime": targetHitTime, "lane": noteNumber, "speed": speed]
        worldNode.addChild(note)
        
        let totalDistance = (size.width + 100) + 40
        let totalDuration = totalDistance / speed
        
        let moveAction = SKAction.moveTo(x: -40, duration: Double(totalDuration))
        let removeAction = SKAction.run { [weak self, weak note] in
            if let note = note, note.parent != nil { self?.registerMiss() }
            note?.removeFromParent()
        }
        note.run(SKAction.sequence([moveAction, removeAction]))
    }
    
    func handleHit(for noteNumber: UInt8) {
        if isDemoMode { flashLane(for: noteNumber); return }
        let currentTime = CACurrentMediaTime() - levelStartTime
        
        let activeNotes = worldNode.children.compactMap { $0 as? SKShapeNode }
            .filter { $0.name == "note" && ($0.userData?["lane"] as? UInt8) == noteNumber }
        
        guard let closestNote = activeNotes.min(by: {
            abs($0.position.x - hitLineX) < abs($1.position.x - hitLineX)
        }) else {
            flashLane(for: noteNumber)
            return
        }
        
        let speed = closestNote.userData?["speed"] as? CGFloat ?? 400
        let distance = closestNote.position.x - hitLineX
        let timeDiff = abs(Double(distance / speed))
        
        var accuracy: HitAccuracy = .miss
        if timeDiff <= perfectWindow { accuracy = .perfect }
        else if timeDiff <= goodWindow { accuracy = .good }
        
        if accuracy != .miss {
            showFeedback(accuracy: accuracy, at: closestNote.position)
            triggerHitEffects(accuracy: accuracy, position: closestNote.position)
            closestNote.removeFromParent()
            ScoreManager.shared.registerHit(accuracy: accuracy)
        }
        flashLane(for: noteNumber)
    }
    
    private func triggerHitEffects(accuracy: HitAccuracy, position: CGPoint) {
        let amplitude: CGFloat = accuracy == .perfect ? 8 : 3
        worldNode.run(SKAction.screenShake(duration: 0.1, amplitude: amplitude))
        if accuracy == .perfect { createParticles(at: position, color: accuracy.color) }
    }
    
    private func createParticles(at position: CGPoint, color: Color) {
        for _ in 0...12 {
            let p = SKShapeNode(circleOfRadius: CGFloat.random(in: 1...3))
            p.fillColor = NSColor(color)
            p.strokeColor = .clear
            p.position = position
            p.zPosition = 15
            worldNode.addChild(p)
            let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let dist = CGFloat.random(in: 40...100)
            let move = SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.4)
            move.timingMode = .easeOut
            p.run(SKAction.sequence([SKAction.group([move, .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
        }
    }
    
    private func registerMiss() {
        if isDemoMode { return }
        ScoreManager.shared.registerHit(accuracy: .miss)
        showFeedback(accuracy: .miss, at: CGPoint(x: hitLineX, y: size.height / 2))
    }
    
    private func showFeedback(accuracy: HitAccuracy, at position: CGPoint) {
        let label = SKLabelNode(text: accuracy.rawValue)
        label.fontName = "AvenirNext-HeavyItalic"
        label.fontSize = accuracy == .perfect ? 35 : 24
        label.fontColor = NSColor(accuracy.color)
        label.position = position
        label.zPosition = 10
        worldNode.addChild(label)
        let moveUp = SKAction.moveBy(x: 0, y: 50, duration: 0.5)
        label.run(SKAction.sequence([SKAction.group([moveUp, .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
    }
    
    func flashLane(for noteNumber: UInt8) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        let laneY = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        let hitGlow = SKShapeNode(rectOf: CGSize(width: 40, height: laneHeight - 2))
        hitGlow.position = CGPoint(x: hitLineX, y: laneY)
        hitGlow.fillColor = .white.withAlphaComponent(0.4)
        hitGlow.strokeColor = .white
        hitGlow.lineWidth = 1
        hitGlow.glowWidth = 8
        hitGlow.zPosition = 2
        worldNode.addChild(hitGlow)
        let fade = SKAction.fadeOut(withDuration: 0.1)
        hitGlow.run(SKAction.sequence([fade, .removeFromParent()]))
    }
    
    func loadLevel(notes: [TrackNote], barDuration: TimeInterval, loop: Bool = true, metronome: Bool = false, isDemoMode: Bool = false, noteTravelTime: TimeInterval = 2.0) {
        stopAndClear()
        self.isDemoMode = isDemoMode
        levelStartTime = CACurrentMediaTime()
        for (index, note) in notes.enumerated() {
            let spawnDelay = note.timeSeconds
            let spawn = SKAction.run { [weak self] in self?.spawnNote(for: note.padIndex, targetHitTime: note.timeSeconds, travelTime: noteTravelTime) }
            let playSound = SKAction.run { [weak self] in
                if self?.isDemoMode == true {
                    AudioManager.shared.triggerSound(for: note.padIndex)
                    PadStatusManager.shared.highlightPad(note.padIndex)
                    self?.run(SKAction.sequence([SKAction.wait(forDuration: 0.1), SKAction.run { PadStatusManager.shared.removeHighlight(note.padIndex) }]))
                }
            }
            let audioDelay = spawnDelay + noteTravelTime
            if loop {
                let visualWait = SKAction.wait(forDuration: spawnDelay)
                self.run(SKAction.sequence([visualWait, SKAction.repeatForever(SKAction.sequence([spawn, SKAction.wait(forDuration: barDuration)]))]), withKey: "note_loop_visual_\(index)")
                if isDemoMode {
                    let audioWait = SKAction.wait(forDuration: audioDelay)
                    self.run(SKAction.sequence([audioWait, SKAction.repeatForever(SKAction.sequence([playSound, SKAction.wait(forDuration: barDuration)]))]), withKey: "note_loop_audio_\(index)")
                }
            } else {
                self.run(SKAction.sequence([SKAction.wait(forDuration: spawnDelay), spawn]))
                if isDemoMode { self.run(SKAction.sequence([SKAction.wait(forDuration: audioDelay), playSound])) }
            }
        }
        if metronome {
            let click = SKAction.run { AudioManager.shared.playMetronomeClick() }
            let wait = SKAction.wait(forDuration: barDuration / 4.0)
            let seq = SKAction.sequence([click, wait])
            self.run(loop ? SKAction.repeatForever(seq) : SKAction.repeat(seq, count: 4), withKey: "metronome_loop")
        }
    }
    
    func setPaused(_ paused: Bool) { self.isPaused = paused }
    
    func stopAndClear() {
        self.removeAllActions()
        worldNode.removeAllActions()
        worldNode.position = .zero
        worldNode.enumerateChildNodes(withName: "note") { node, _ in node.removeFromParent() }
        ScoreManager.shared.reset()
    }
}

extension SKAction {
    static func screenShake(duration: TimeInterval, amplitude: CGFloat) -> SKAction {
        let numberOfShakes = Int(duration / 0.02)
        var actions: [SKAction] = []
        for _ in 0..<numberOfShakes {
            let diffX = CGFloat.random(in: -amplitude...amplitude)
            let diffY = CGFloat.random(in: -amplitude...amplitude)
            let move = SKAction.moveBy(x: diffX, y: diffY, duration: 0.01)
            actions.append(SKAction.sequence([move, move.reversed()]))
        }
        return SKAction.sequence(actions)
    }
}

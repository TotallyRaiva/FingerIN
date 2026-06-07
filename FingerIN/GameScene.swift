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
    
    // UI Elements
    private var hitLine: SKShapeNode!
    private var lanes: [SKShapeNode] = []
    
    override func didMove(to view: SKView) {
        // Set anchor point to bottom-left for easier horizontal math
        self.anchorPoint = .zero
        setupBackground()
        setupLanes()
        setupHitLine()
    }
    
    private func setupBackground() {
        self.backgroundColor = .black
    }
    
    private func setupLanes() {
        // We stack lanes precisely from the bottom (y=0) up to totalHeight
        for i in 0..<totalLanes {
            let laneY = (CGFloat(i) * laneHeight) + (laneHeight / 2)
            
            // Create a lane visual (Horizontal)
            let lane = SKShapeNode(rectOf: CGSize(width: size.width, height: laneHeight - 1)) // 1px gap for separation
            lane.position = CGPoint(x: size.width / 2, y: laneY)
            lane.strokeColor = SKColor.white.withAlphaComponent(0.1)
            lane.fillColor = SKColor.clear
            lane.zPosition = -1
            addChild(lane)
            lanes.append(lane)
        }
    }
    
    private func setupHitLine() {
        let totalHeight = laneHeight * CGFloat(totalLanes)
        // Vertical hit line on the left side, precisely sized to the lane stack
        hitLine = SKShapeNode(rectOf: CGSize(width: 2, height: totalHeight))
        hitLine.fillColor = .cyan
        hitLine.strokeColor = .cyan
        hitLine.position = CGPoint(x: hitLineX, y: totalHeight / 2)
        hitLine.glowWidth = 3
        hitLine.zPosition = 1
        addChild(hitLine)
    }
    
    // Spawn a note moving Right-to-Left
    func spawnNote(for noteNumber: UInt8, targetHitTime: TimeInterval, travelTime: TimeInterval = 2.0) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        
        let laneY = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        
        // Horizontal note (rectangle) - rounded like Melodics
        let note = SKShapeNode(rectOf: CGSize(width: 40, height: laneHeight - 20), cornerRadius: 4)
        note.fillColor = .white
        note.strokeColor = .white
        note.position = CGPoint(x: size.width + 20, y: laneY)
        note.name = "note"
        
        // Calculate speed
        let distanceToHit = (size.width + 20) - hitLineX
        let speed = distanceToHit / CGFloat(travelTime)
        
        // Store metadata for hit detection
        note.userData = [
            "targetHitTime": targetHitTime,
            "lane": noteNumber,
            "speed": speed
        ]
        
        addChild(note)
        
        // Total distance to fully pass the left edge (x = -40)
        let totalDistance = (size.width + 20) + 40
        let totalDuration = totalDistance / speed
        
        let moveAction = SKAction.moveTo(x: -40, duration: Double(totalDuration))
        let removeAction = SKAction.run { [weak self, weak note] in
            // If the note was removed by passing the screen and wasn't hit, it's a miss
            if let note = note, note.parent != nil {
                self?.registerMiss()
            }
            note?.removeFromParent()
        }
        
        note.run(SKAction.sequence([moveAction, removeAction]))
    }
    
    // Handle a physical pad hit
    func handleHit(for noteNumber: UInt8) {
        // Find notes in this lane that are close to the hit line
        let activeNotes = children.compactMap { $0 as? SKShapeNode }
            .filter { $0.name == "note" && ($0.userData?["lane"] as? UInt8) == noteNumber }
        
        // Find the one closest to the hit line spatially
        guard let closestNote = activeNotes.min(by: {
            abs($0.position.x - hitLineX) < abs($1.position.x - hitLineX)
        }) else {
            flashLane(for: noteNumber)
            return // No note to hit in this lane
        }
        
        let speed = closestNote.userData?["speed"] as? CGFloat ?? 400
        let distance = closestNote.position.x - hitLineX
        let timeDiff = abs(Double(distance / speed))
        
        var accuracy: HitAccuracy = .miss
        if timeDiff <= perfectWindow {
            accuracy = .perfect
        } else if timeDiff <= goodWindow {
            accuracy = .good
        }
        
        if accuracy != .miss {
            showFeedback(accuracy: accuracy, at: closestNote.position)
            closestNote.removeFromParent() // Note was hit
            ScoreManager.shared.registerHit(accuracy: accuracy)
        } else {
            // Hit was too early or too late, but we don't count it as a miss yet
            // to allow the note to reach the hit line or be hit later.
            print("GameScene: Hit detected but outside windows (diff: \(timeDiff)s)")
        }
        
        flashLane(for: noteNumber)
    }
    
    private func registerMiss() {
        ScoreManager.shared.registerHit(accuracy: .miss)
        // Show "MISS" feedback at the hit line
        showFeedback(accuracy: .miss, at: CGPoint(x: hitLineX, y: size.height / 2))
    }
    
    private func showFeedback(accuracy: HitAccuracy, at position: CGPoint) {
        let label = SKLabelNode(text: accuracy.rawValue)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 24
        label.fontColor = NSColor(accuracy.color)
        label.position = position
        label.zPosition = 10
        addChild(label)
        
        let moveUp = SKAction.moveBy(x: 0, y: 50, duration: 0.5)
        let fade = SKAction.fadeOut(withDuration: 0.5)
        let group = SKAction.group([moveUp, fade])
        let remove = SKAction.removeFromParent()
        label.run(SKAction.sequence([group, remove]))
    }
    
    // Flash a lane when a hit is detected (at the Hit Line)
    func flashLane(for noteNumber: UInt8) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        
        let laneY = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        
        // Subtle local glow at the hit line intersection
        let hitGlow = SKShapeNode(rectOf: CGSize(width: 40, height: laneHeight - 2))
        hitGlow.position = CGPoint(x: hitLineX, y: laneY)
        hitGlow.fillColor = .white.withAlphaComponent(0.4)
        hitGlow.strokeColor = .white
        hitGlow.lineWidth = 1
        hitGlow.glowWidth = 8
        hitGlow.zPosition = 2
        addChild(hitGlow)
        
        // Brief horizontal line 'pulse'
        let pulse = SKShapeNode(rectOf: CGSize(width: size.width, height: 2))
        pulse.position = CGPoint(x: size.width / 2, y: laneY)
        pulse.fillColor = .white.withAlphaComponent(0.1)
        pulse.strokeColor = .clear
        pulse.zPosition = 0
        addChild(pulse)
        
        let fade = SKAction.fadeOut(withDuration: 0.1)
        let remove = SKAction.removeFromParent()
        hitGlow.run(SKAction.sequence([fade, remove]))
        pulse.run(SKAction.sequence([fade, remove]))
    }
    
    // Load a sequence of notes (a Level) into the timeline with looping and metronome
    func loadLevel(
        notes: [TrackNote],
        barDuration: TimeInterval,
        loop: Bool = true,
        metronome: Bool = false,
        noteTravelTime: TimeInterval = 2.0
    ) {
        stopAndClear()
        levelStartTime = CACurrentMediaTime()
        
        print("GameScene: Loading level with \(notes.count) notes, Loop: \(loop), Metro: \(metronome)")
        
        // 1. Schedule Notes
        for (index, note) in notes.enumerated() {
            let spawnDelay = note.timeSeconds
            
            let waitBefore = SKAction.wait(forDuration: spawnDelay)
            let spawn = SKAction.run { [weak self] in
                self?.spawnNote(for: note.padIndex, targetHitTime: note.timeSeconds, travelTime: noteTravelTime)
            }
            
            if loop {
                let waitAfter = SKAction.wait(forDuration: barDuration - spawnDelay)
                let sequence = SKAction.sequence([waitBefore, spawn, waitAfter])
                self.run(SKAction.repeatForever(sequence), withKey: "note_loop_\(index)")
            } else {
                self.run(SKAction.sequence([waitBefore, spawn]))
            }
        }
        
        // 2. Schedule Metronome (4 clicks per bar)
        if metronome {
            let clickInterval = barDuration / 4.0
            let click = SKAction.run {
                AudioManager.shared.playMetronomeClick()
            }
            let wait = SKAction.wait(forDuration: clickInterval)
            let sequence = SKAction.sequence([click, wait])
            let action = loop ? SKAction.repeatForever(sequence) : SKAction.repeat(sequence, count: 4)
            self.run(action, withKey: "metronome_loop")
        }
    }
    
    func setPaused(_ paused: Bool) {
        self.isPaused = paused
        print("GameScene: \(paused ? "Paused" : "Resumed")")
    }
    
    func stopAndClear() {
        self.removeAllActions()
        self.enumerateChildNodes(withName: "note") { node, _ in
            node.removeFromParent()
        }
        ScoreManager.shared.reset()
        print("GameScene: Actions and notes cleared.")
    }
}

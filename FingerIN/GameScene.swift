import SpriteKit
import SwiftUI

class GameScene: SKScene {
    
    // Constants for the timeline
    private let hitLineY: CGFloat = 100
    private let noteSpeed: CGFloat = 400 // Points per second
    private let laneWidth: CGFloat = 80
    private let totalLanes = 4
    
    // Note mapping (matching MIDI notes 12-15)
    private let midiNotes: [UInt8] = [12, 13, 14, 15]
    
    // UI Elements
    private var hitLine: SKShapeNode!
    private var lanes: [SKShapeNode] = []
    
    override func didMove(to view: SKView) {
        setupBackground()
        setupLanes()
        setupHitLine()
    }
    
    private func setupBackground() {
        self.backgroundColor = .black
    }
    
    private func setupLanes() {
        let totalWidth = laneWidth * CGFloat(totalLanes)
        let startX = (size.width - totalWidth) / 2
        
        for i in 0..<totalLanes {
            let laneX = startX + (CGFloat(i) * laneWidth) + (laneWidth / 2)
            
            // Create a lane visual
            let lane = SKShapeNode(rectOf: CGSize(width: laneWidth - 4, height: size.height))
            lane.position = CGPoint(x: laneX, y: size.height / 2)
            lane.strokeColor = SKColor.darkGray.withAlphaComponent(0.3)
            lane.fillColor = SKColor.gray.withAlphaComponent(0.1)
            addChild(lane)
            lanes.append(lane)
            
            // Add label for MIDI note
            let label = SKLabelNode(text: "\(midiNotes[i])")
            label.fontSize = 12
            label.fontColor = .white
            label.position = CGPoint(x: laneX, y: 20)
            addChild(label)
        }
    }
    
    private func setupHitLine() {
        hitLine = SKShapeNode(rectOf: CGSize(width: laneWidth * CGFloat(totalLanes), height: 4))
        hitLine.fillColor = .cyan
        hitLine.strokeColor = .cyan
        hitLine.position = CGPoint(x: size.width / 2, y: hitLineY)
        hitLine.glowWidth = 5
        addChild(hitLine)
    }
    
    // Spawn a note falling in a specific lane
    func spawnNote(for noteNumber: UInt8) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        
        let totalWidth = laneWidth * CGFloat(totalLanes)
        let startX = (size.width - totalWidth) / 2
        let laneX = startX + (CGFloat(laneIndex) * laneWidth) + (laneWidth / 2)
        
        let note = SKShapeNode(rectOf: CGSize(width: laneWidth - 10, height: 20), cornerRadius: 5)
        note.fillColor = .white
        note.strokeColor = .white
        note.position = CGPoint(x: laneX, y: size.height)
        note.name = "note"
        addChild(note)
        
        // Action to move the note down
        let duration = Double(size.height - hitLineY) / Double(noteSpeed)
        let moveAction = SKAction.moveTo(y: -50, duration: duration + 0.5) // Move slightly past bottom
        let removeAction = SKAction.removeFromParent()
        
        note.run(SKAction.sequence([moveAction, removeAction]))
    }
    
    // Flash a lane when a hit is detected
    func flashLane(for noteNumber: UInt8) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        
        let flash = SKShapeNode(rectOf: CGSize(width: laneWidth - 4, height: 60))
        flash.position = CGPoint(x: lanes[laneIndex].position.x, y: hitLineY)
        flash.fillColor = .cyan.withAlphaComponent(0.5)
        flash.strokeColor = .clear
        addChild(flash)
        
        let fade = SKAction.fadeOut(withDuration: 0.1)
        let remove = SKAction.removeFromParent()
        flash.run(SKAction.sequence([fade, remove]))
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Handle logic for checking note positions vs hit line here later
    }
}

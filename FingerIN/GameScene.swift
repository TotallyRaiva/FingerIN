import SpriteKit
import SwiftUI

class GameScene: SKScene {
    
    // Layout Constants
    private let hitLineX: CGFloat = 80 // Reserved space on the left
    private let laneHeight: CGFloat = 80
    private let totalLanes = 4
    
    // Note mapping (matching MIDI notes 12-15)
    private let midiNotes: [UInt8] = [12, 13, 14, 15]
    
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
    func spawnNote(for noteNumber: UInt8, travelTime: Double = 2.0) {
        guard let laneIndex = midiNotes.firstIndex(of: noteNumber) else { return }
        
        let laneY = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        
        // Horizontal note (rectangle) - rounded like Melodics
        let note = SKShapeNode(rectOf: CGSize(width: 40, height: laneHeight - 20), cornerRadius: 4)
        note.fillColor = .white
        note.strokeColor = .white
        note.position = CGPoint(x: size.width + 20, y: laneY)
        note.name = "note"
        addChild(note)
        
        // Action: The horizontal center of the note must intersect the Hit Line at travelTime
        // Distance to hit line = currentX - hitLineX
        let distanceToHit = (size.width + 20) - hitLineX
        let speed = distanceToHit / CGFloat(travelTime)
        
        // Total distance to fully pass the left edge (x = -40)
        let totalDistance = (size.width + 20) + 40
        let totalDuration = totalDistance / speed
        
        let moveAction = SKAction.moveTo(x: -40, duration: Double(totalDuration))
        let removeAction = SKAction.removeFromParent()
        
        note.run(SKAction.sequence([moveAction, removeAction]))
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
}

import Foundation
import Combine

@MainActor
class PadStatusManager: ObservableObject {
    static let shared = PadStatusManager()
    
    @Published var isPadHighlighted: [UInt8: Bool] = [
        12: false,
        13: false,
        14: false,
        15: false
    ]
    
    private var autoReleaseTasks: [UInt8: DispatchWorkItem] = [:]
    
    private init() {}
    
    func highlightPad(_ pad: UInt8) {
        autoReleaseTasks[pad]?.cancel()
        autoReleaseTasks[pad] = nil
        isPadHighlighted[pad] = true
    }
    
    func removeHighlight(_ pad: UInt8) {
        autoReleaseTasks[pad]?.cancel()
        autoReleaseTasks[pad] = nil
        isPadHighlighted[pad] = false
    }
    
    /// Highlights a pad and automatically clears it after `duration` (used for Demo Mode & keyboard hits)
    func pulseHighlight(_ pad: UInt8, duration: TimeInterval = 0.1) {
        highlightPad(pad)
        let workItem = DispatchWorkItem { [weak self] in
            self?.isPadHighlighted[pad] = false
            self?.autoReleaseTasks[pad] = nil
        }
        autoReleaseTasks[pad] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}

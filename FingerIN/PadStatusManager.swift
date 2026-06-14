import Foundation
import Combine

class PadStatusManager: ObservableObject {
    static let shared = PadStatusManager()
    
    @Published var isPadHighlighted: [UInt8: Bool] = [
        12: false,
        13: false,
        14: false,
        15: false
    ]
    
    private init() {}
    
    func highlightPad(_ pad: UInt8) {
        DispatchQueue.main.async {
            self.isPadHighlighted[pad] = true
        }
    }
    
    func removeHighlight(_ pad: UInt8) {
        DispatchQueue.main.async {
            self.isPadHighlighted[pad] = false
        }
    }
}

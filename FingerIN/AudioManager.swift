import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    private init() {}
    
    func playSample(named: String) {
        // TODO: Implement zero-latency triggering
    }
}

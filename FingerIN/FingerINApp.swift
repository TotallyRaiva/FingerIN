//
//  FingerINApp.swift
//  FingerIN
//
//  Created by Reiwa on 03.06.2026.
//

import SwiftUI
import AppKit

@main
struct FingerINApp: App {
    init() {
        Self.applyApplicationDockIcon()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    Self.applyApplicationDockIcon()
                }
        }
    }

    private static func applyApplicationDockIcon() {
        if let assetIcon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = assetIcon
            NSApplication.shared.dockTile.display()
        } else if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let icnsImage = NSImage(contentsOf: icnsURL) {
            NSApplication.shared.applicationIconImage = icnsImage
            NSApplication.shared.dockTile.display()
        }
    }
}


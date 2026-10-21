//
//  AntigravityRemoteApp.swift
//  AntigravityRemote
//

import SwiftUI

@main
struct AntigravityRemoteApp: App {
    init() {
        let args = ProcessInfo.processInfo.arguments
        if !args.contains("-AGYMarketingScene") && !args.contains("-AGYDemoMode") {
            TailnetManager.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainRemoteView()
        }
    }
}

//
//  timerApp.swift
//  timer
//
//  Created by 조경민 on 2/5/26.
//

import SwiftUI

#if !APP_EXTENSION
@main
struct timerApp: App {
    @StateObject private var heartRateManager = HeartRateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(heartRateManager)
        }
    }
}
#endif

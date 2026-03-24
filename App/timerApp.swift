//
//  timerApp.swift
//  timer
//
//  Created by 조경민 on 2/5/26.
//

import SwiftUI
import notify

#if !APP_EXTENSION
@main
struct timerApp: App {
    @StateObject private var heartRateManager: HeartRateManager

    init() {
        Self.externalStopObserver.start()
        Self.performEarlyColdLaunchCleanup()
        let manager = HeartRateManager()
        _heartRateManager = StateObject(wrappedValue: manager)
        Self.invalidateStaleSharedTimerStateOnColdLaunch(using: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(heartRateManager)
        }
    }

    private static func performEarlyColdLaunchCleanup() {
        Task(priority: .userInitiated) { @MainActor in
            TimerSessionTermination.clearTimerNotifications()
            await TimerSessionTermination.endAllLiveActivitiesImmediately()
        }
    }

    private static func invalidateStaleSharedTimerStateOnColdLaunch(using manager: HeartRateManager) {
        manager.sendTimerState(
            mode: "",
            phase: TimerSyncPhase.idle,
            displaySeconds: 0,
            headline: "",
            exercise: ""
        )
    }

    private static let externalStopObserver = ExternalStopSignalObserver()
}

private final class ExternalStopSignalObserver {
    private var token: Int32 = 0
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let status = notify_register_dispatch(
            TimerExternalControl.darwinNotificationName,
            &token,
            .main
        ) { _ in
            NotificationCenter.default.post(name: TimerExternalControl.notificationName, object: nil)
        }

        if status != 0 {
            token = 0
            isStarted = false
        }
    }

    deinit {
        if token != 0 {
            notify_cancel(token)
        }
    }
}
#endif

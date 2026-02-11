import SwiftUI

struct WatchForTimeView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @Binding var isTabLocked: Bool

    @State private var totalMinutes: Int = 30
    @State private var countdown: Int? = nil
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
    @State private var exerciseInput: String = ""
    @State private var showComplete: Bool = false

    private var exercises: [String] {
        WatchTimerUtilities.parseExercises(exerciseInput)
    }

    private var phoneState: PhoneTimerState? {
        guard let state = workoutManager.phoneTimerState,
              state.mode == WatchWorkoutMode.forTime.rawValue else { return nil }
        return state
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("FOR TIME")
                    .font(.headline)
                if let state = phoneState {
                    PhoneTimerStatusView(state: state, bpm: workoutManager.currentBpm, averageBpm: workoutManager.averageBpm)
                } else if countdown == nil, !showComplete {
                    inputView
                } else if let cd = countdown, cd > 0 {
                    countdownView(cd)
                } else if isRunning {
                    runningView
                } else {
                    completeView
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollDisabled(false)
    }

    private var inputView: some View {
        VStack(spacing: 8) {
            WatchCounterRow(title: "총 시간", unit: "분", range: 1...60, value: $totalMinutes)
            TextField("운동(쉼표로 구분)", text: $exerciseInput)
            Button("시작") {
                startCountdown()
            }
            .buttonStyle(.bordered)
        }
    }

    private func countdownView(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 48, weight: .bold))
    }

    private var runningView: some View {
        VStack(spacing: 8) {
            Text("경과 시간")
                .font(.subheadline)
            Text(WatchTimerUtilities.formatTime(elapsedSeconds))
                .font(.title2.bold())
            if let bpm = workoutManager.currentBpm {
                WatchHeartRateView(title: "현재 심박", bpm: bpm)
            }
            if exercises.isEmpty {
                Text("운동 목록 없음")
                    .font(.subheadline)
            } else {
                ForEach(Array(exercises.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Button("중지") {
                stopTimer()
            }
            .buttonStyle(.bordered)
        }
    }

    private var completeView: some View {
        VStack(spacing: 8) {
            Text("완료!")
                .font(.headline)
            Text("소요 시간 \(WatchTimerUtilities.formatTime(elapsedSeconds))")
                .font(.subheadline)
            if let average = workoutManager.averageBpm {
                WatchHeartRateView(title: "평균 심박", bpm: average)
            }
            Button("다시 시작") {
                resetAll()
            }
            .buttonStyle(.bordered)
        }
    }

    private func startCountdown() {
        workoutManager.phoneTimerState = nil
        isTabLocked = true
        showComplete = false
        startCountdownTimer {
            startForTimeTimer(total: totalMinutes)
        }
    }

    private func startCountdownTimer(then startAction: @escaping () -> Void) {
        countdown = 5
        isRunning = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let cd = countdown, cd > 1 {
                countdown = cd - 1
            } else {
                timer?.invalidate()
                startAction()
            }
        }
    }

    private func startForTimeTimer(total: Int) {
        elapsedSeconds = 0
        isRunning = true
        countdown = 0
        workoutManager.startWorkout()
        WatchTimerUtilities.playBeep()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let totalSeconds = total * 60
            if elapsedSeconds + 1 >= totalSeconds {
                elapsedSeconds = totalSeconds
                timer?.invalidate()
                isRunning = false
                workoutManager.stopWorkout()
                WatchTimerUtilities.playBeep()
                showComplete = true
                isTabLocked = false
            } else {
                elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = 0
        showComplete = true
        workoutManager.stopWorkout()
        isTabLocked = false
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        elapsedSeconds = 0
        showComplete = false
        workoutManager.stopWorkout()
        isTabLocked = false
    }
}

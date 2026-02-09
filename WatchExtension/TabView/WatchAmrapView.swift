import SwiftUI

struct WatchAmrapView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @Binding var isTabLocked: Bool

    @State private var totalMinutes: Int = 20
    @State private var countdown: Int? = nil
    @State private var remainingSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
    @State private var exerciseInput: String = ""
    @State private var rounds: Int = 0
    @State private var endAlertEnabled: Bool = true

    private var exercises: [String] {
        WatchTimerUtilities.parseExercises(exerciseInput)
    }

    private var phoneState: PhoneTimerState? {
        guard let state = workoutManager.phoneTimerState,
              state.mode == WatchWorkoutMode.amrap.rawValue else { return nil }
        return state
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("AMRAP")
                    .font(.headline)
                if let state = phoneState {
                    PhoneTimerStatusView(state: state, bpm: workoutManager.currentBpm, averageBpm: workoutManager.averageBpm)
                } else if countdown == nil {
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
        .scrollDisabled(isRunning)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if isRunning {
                    rounds += 1
                }
            },
            including: .all
        )
    }

    private var inputView: some View {
        VStack(spacing: 8) {
            WatchCounterRow(title: "총 시간", unit: "분", range: 1...60, value: $totalMinutes)
            Toggle("끝 알람", isOn: $endAlertEnabled)
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
            Text("라운드 \(rounds)")
                .font(.title2.bold())
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
            Text(WatchTimerUtilities.formatTime(remainingSeconds))
                .font(.title2)
            if let bpm = workoutManager.currentBpm {
                WatchHeartRateView(title: "현재 심박", bpm: bpm)
            }
            Text("더블탭: 라운드 +1")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            Text("완료 라운드 \(rounds)")
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
        startCountdownTimer {
            startAmrapTimer(total: totalMinutes)
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

    private func startAmrapTimer(total: Int) {
        remainingSeconds = total * 60
        isRunning = true
        countdown = 0
        rounds = 0
        workoutManager.startWorkout()
        WatchTimerUtilities.playBeep()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                timer?.invalidate()
                isRunning = false
                workoutManager.stopWorkout()
                if endAlertEnabled {
                    WatchTimerUtilities.playBeep()
                }
                isTabLocked = false
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = nil
        workoutManager.stopWorkout()
        isTabLocked = false
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        remainingSeconds = 0
        rounds = 0
        workoutManager.stopWorkout()
        isTabLocked = false
    }
}

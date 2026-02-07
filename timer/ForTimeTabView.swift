import SwiftUI

struct ForTimeTabView: View {
    @Binding var isModePickerVisible: Bool
    @EnvironmentObject private var heartRateManager: HeartRateManager

    @State private var totalMinutes: Int = 5
    @State private var countdown: Int? = nil
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
    @State private var exerciseInput: String = ""

    private let minuteOptions = Array(1...60)

    private var exercises: [String] {
        TimerUtilities.parseExercises(exerciseInput)
    }

    private var exerciseSummary: String {
        exercises.isEmpty ? "운동 목록 없음" : exercises.joined(separator: " / ")
    }

    var body: some View {
        VStack(spacing: 24) {
            if countdown == nil {
                inputView
            } else if let cd = countdown, cd > 0 {
                countdownView(cd)
            } else if isRunning {
                runningView
            } else {
                completeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: updateModePickerVisibility)
        .onChange(of: isRunning, initial: false) { _, _ in updateModePickerVisibility() }
        .onChange(of: countdown, initial: false) { _, _ in updateModePickerVisibility() }
    }

    private var inputView: some View {
        VStack(spacing: 12) {
            Text("FOR TIME 타이머 설정")
                .font(.title2)
                .foregroundStyle(TimerTheme.primaryText)
            HStack(spacing: 12) {
                Text("총 시간(분):")
                    .foregroundStyle(TimerTheme.secondaryText)
                Picker("총 시간(분)", selection: $totalMinutes) {
                    ForEach(minuteOptions, id: \.self) { min in
                        Text("\(min)분").tag(min)
                    }
                }
                .pickerStyle(.menu)
            }
            VStack(alignment: .center, spacing: 6) {
                Text("운동 목록")
                    .font(.subheadline)
                    .foregroundStyle(TimerTheme.secondaryText)
                TextEditor(text: $exerciseInput)
                    .scrollContentBackground(.hidden)
                    .frame(height: 90)
                    .padding(8)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .foregroundStyle(TimerTheme.primaryText)
                    .tint(TimerTheme.actionTint)
                    .padding(.horizontal, 12)
            }
            Button("시작") {
                startCountdown()
            }
            .buttonStyle(.borderedProminent)
            .tint(TimerTheme.actionTint)
        }
    }

    private func countdownView(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 64, weight: .bold))
            .foregroundStyle(TimerTheme.primaryText)
            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    private var runningView: some View {
        VStack(spacing: 20) {
            Text("경과 시간")
                .font(.headline)
                .foregroundStyle(TimerTheme.secondaryText)
            Text(TimerUtilities.formatTime(elapsedSeconds))
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(TimerTheme.primaryText)
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            if let bpm = heartRateManager.currentBpm {
                HeartRateMetricView(title: "현재 심박", bpm: bpm)
            }
            if exercises.isEmpty {
                Text("운동 목록 없음")
                    .font(.headline)
                    .foregroundStyle(TimerTheme.secondaryText)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.headline)
                            .foregroundStyle(TimerTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            Button("중지") {
                stopTimer()
            }
            .buttonStyle(.bordered)
            .tint(TimerTheme.stopTint)
        }
    }

    private var completeView: some View {
        VStack(spacing: 12) {
            Text("완료!")
                .font(.title)
                .foregroundStyle(TimerTheme.primaryText)
            Text("소요 시간 \(TimerUtilities.formatTime(elapsedSeconds))")
                .font(.headline)
                .foregroundStyle(TimerTheme.secondaryText)
            if let average = heartRateManager.averageBpm {
                HeartRateMetricView(title: "평균 심박", bpm: average)
            }
            Button("다시 시작") {
                resetAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(TimerTheme.actionTint)
        }
    }

    private func updateModePickerVisibility() {
        isModePickerVisible = !isRunning && countdown == nil
    }

    private func startCountdown() {
        startCountdownTimer {
            startForTimeTimer(total: totalMinutes)
        }
    }

    private func startCountdownTimer(then startAction: @escaping () -> Void) {
        countdown = 5
        isRunning = false
        sendCountdownState()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let cd = countdown, cd > 1 {
                countdown = cd - 1
                sendCountdownState()
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
        heartRateManager.start()
        TimerUtilities.playBeep()
        sendRunningState()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let totalSeconds = total * 60
            if elapsedSeconds + 1 >= totalSeconds {
                elapsedSeconds = totalSeconds
                timer?.invalidate()
                isRunning = false
                heartRateManager.stop()
                TimerUtilities.playBeep()
                sendCompleteState()
            } else {
                elapsedSeconds += 1
                sendRunningState()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = 0
        heartRateManager.stop()
        sendIdleState()
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        elapsedSeconds = 0
        heartRateManager.reset()
        sendIdleState()
    }

    private func sendCountdownState() {
        guard let cd = countdown else { return }
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.forTime,
            phase: TimerSyncPhase.countdown,
            displaySeconds: cd,
            headline: "카운트다운",
            exercise: nil
        )
    }

    private func sendRunningState() {
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.forTime,
            phase: TimerSyncPhase.running,
            displaySeconds: elapsedSeconds,
            headline: "경과 시간",
            exercise: exerciseSummary
        )
    }

    private func sendCompleteState() {
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.forTime,
            phase: TimerSyncPhase.complete,
            displaySeconds: elapsedSeconds,
            headline: "소요 시간",
            exercise: nil
        )
    }

    private func sendIdleState() {
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.forTime,
            phase: TimerSyncPhase.idle,
            displaySeconds: 0,
            headline: "",
            exercise: nil
        )
    }
}

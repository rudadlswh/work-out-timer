import SwiftUI
import WatchKit

enum WatchWorkoutMode: String, CaseIterable, Identifiable {
    case emom = "EMOM"
    case amrap = "AMRAP"
    case forTime = "FOR TIME"

    var id: String { rawValue }
}

struct WatchContentView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @State private var workoutMode: WatchWorkoutMode = .emom

    var body: some View {
        TabView(selection: $workoutMode) {
            WatchEmomView()
                .tag(WatchWorkoutMode.emom)
            WatchAmrapView()
                .tag(WatchWorkoutMode.amrap)
            WatchForTimeView()
                .tag(WatchWorkoutMode.forTime)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: workoutManager.phoneTimerState) { newValue in
            guard let modeString = newValue?.mode,
                  let mode = WatchWorkoutMode(rawValue: modeString) else { return }
            workoutMode = mode
        }
    }
}

struct WatchEmomView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    @State private var intervalMinutes: Int = 1
    @State private var totalMinutes: Int = 5
    @State private var countdown: Int? = nil
    @State private var remainingSeconds: Int = 0
    @State private var nextBeep: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
    @State private var exerciseInput: String = ""

    private var exercises: [String] {
        WatchTimerUtilities.parseExercises(exerciseInput)
    }

    private var phoneState: PhoneTimerState? {
        guard let state = workoutManager.phoneTimerState,
              state.mode == WatchWorkoutMode.emom.rawValue else { return nil }
        return state
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("EMOM")
                    .font(.headline)
                if let state = phoneState {
                    PhoneTimerStatusView(state: state)
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
    }

    private var inputView: some View {
        VStack(spacing: 8) {
            WatchCounterRow(title: "인터벌", unit: "분", range: 1...60, value: $intervalMinutes)
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
        let rounds = max(1, ((totalMinutes * 60 - remainingSeconds) / (intervalMinutes * 60)) + 1)
        let roundLabel = intervalMinutes == 1 ? "\(rounds)분" : "\(rounds)라운드"
        let currentExercise = exercises.isEmpty
            ? "운동 없음"
            : exercises[(rounds - 1) % exercises.count]

        return VStack(spacing: 8) {
            Text(roundLabel)
                .font(.title2.bold())
            Text(currentExercise)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let bpm = workoutManager.currentBpm {
                WatchHeartRateView(title: "현재 심박", bpm: bpm)
            }
            Text(WatchTimerUtilities.formatTime(nextBeep))
                .font(.title3)
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
        startCountdownTimer {
            startEmomTimer(interval: intervalMinutes, total: totalMinutes)
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

    private func startEmomTimer(interval: Int, total: Int) {
        remainingSeconds = total * 60
        nextBeep = interval * 60
        isRunning = true
        countdown = 0
        workoutManager.startWorkout()
        WatchTimerUtilities.playBeep()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                nextBeep -= 1
                if nextBeep == 0 {
                    WatchTimerUtilities.playBeep()
                    nextBeep = interval * 60
                }
            } else {
                timer?.invalidate()
                isRunning = false
                workoutManager.stopWorkout()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = nil
        workoutManager.stopWorkout()
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        remainingSeconds = 0
        nextBeep = 0
        workoutManager.stopWorkout()
    }
}

struct WatchAmrapView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    @State private var totalMinutes: Int = 5
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
                    PhoneTimerStatusView(state: state)
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
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if isRunning {
                    rounds += 1
                }
            }
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
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = nil
        workoutManager.stopWorkout()
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        remainingSeconds = 0
        rounds = 0
        workoutManager.stopWorkout()
    }
}

struct WatchForTimeView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    @State private var totalMinutes: Int = 5
    @State private var countdown: Int? = nil
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
    @State private var exerciseInput: String = ""

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
                    PhoneTimerStatusView(state: state)
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
            } else {
                elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = nil
        workoutManager.stopWorkout()
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        elapsedSeconds = 0
        workoutManager.stopWorkout()
    }
}

struct PhoneTimerStatusView: View {
    let state: PhoneTimerState

    var body: some View {
        VStack(spacing: 4) {
            Text("폰 연동")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(state.mode)
                .font(.caption2.weight(.semibold))
            Text(state.headline)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(WatchTimerUtilities.formatTime(state.displaySeconds))
                .font(.title3.monospacedDigit())
            if !state.exercise.isEmpty {
                Text(state.exercise)
                    .font(.caption2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum WatchTimerUtilities {
    static func playBeep() {
        WKInterfaceDevice.current().play(.click)
    }

    static func formatTime(_ sec: Int) -> String {
        let minutes = sec / 60
        let seconds = sec % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func parseExercises(_ input: String) -> [String] {
        input
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct WatchHeartRateView: View {
    let title: String
    let bpm: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(bpm) bpm")
                .font(.subheadline.weight(.semibold))
        }
    }
}

struct WatchCounterRow: View {
    let title: String
    let unit: String
    let range: ClosedRange<Int>
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(action: decrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Text("\(value)\(unit)")
                    .font(.headline.monospacedDigit())
                    .frame(maxWidth: .infinity)

                Button(action: increment) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func increment() {
        if value < range.upperBound {
            value += 1
        }
    }

    private func decrement() {
        if value > range.lowerBound {
            value -= 1
        }
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchWorkoutManager())
}

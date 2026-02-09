import SwiftUI
import WatchKit

struct PhoneTimerStatusView: View {
    let state: PhoneTimerState
    let bpm: Int?
    let averageBpm: Int?

    var body: some View {
        let isComplete = state.phase == "complete"
        let isForTime = state.mode == WatchWorkoutMode.forTime.rawValue

        TimelineView(.periodic(from: .now, by: 1)) { context in
            let displaySeconds = adjustedSeconds(at: context.date)
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
                if !isComplete || isForTime {
                    Text(WatchTimerUtilities.formatTime(displaySeconds))
                        .font(.title3.monospacedDigit())
                }
                if isComplete {
                    if let averageBpm {
                        WatchHeartRateView(title: "평균 심박", bpm: averageBpm)
                    } else {
                        Text("평균 심박 없음")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let bpm {
                    WatchHeartRateView(title: "현재 심박", bpm: bpm)
                }
                if !(isComplete && state.mode == WatchWorkoutMode.amrap.rawValue) && !state.exercise.isEmpty {
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

    private func adjustedSeconds(at date: Date) -> Int {
        let delta = Int(date.timeIntervalSince(state.updatedAt))
        if delta <= 0 || state.phase == "complete" {
            return state.displaySeconds
        }

        let isCountdown = state.phase == "countdown"
            || (state.mode != WatchWorkoutMode.forTime.rawValue && state.phase == "running")
        if isCountdown {
            return max(0, state.displaySeconds - delta)
        }
        return state.displaySeconds + delta
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

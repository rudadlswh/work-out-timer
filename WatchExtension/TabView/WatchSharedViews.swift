import SwiftUI
import WatchKit

struct PhoneTimerStatusView: View {
    let state: PhoneTimerState
    let bpm: Int?
    let averageBpm: Int?

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
            if state.phase == "complete" {
                if let averageBpm {
                    WatchHeartRateView(title: "평균 심박", bpm: averageBpm)
                }
            } else if let bpm {
                WatchHeartRateView(title: "현재 심박", bpm: bpm)
            }
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

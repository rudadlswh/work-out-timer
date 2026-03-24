import SwiftUI

struct EmomRunningView: View {
    let roundLabel: String
    let exercise: String
    let currentBpm: Int?
    let displayTime: String
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text(roundLabel)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(TimerTheme.primaryText)
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            VStack(spacing: 8) {
                Text("이번 동작")
                    .font(.headline)
                    .foregroundStyle(TimerTheme.secondaryText)
                Text(exercise)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(TimerTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let currentBpm {
                HeartRateMetricView(title: "현재 심박", bpm: currentBpm)
            }
            Text(displayTime)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(TimerTheme.secondaryText)
            Button("중지", action: onStop)
                .buttonStyle(.bordered)
                .tint(TimerTheme.stopTint)
        }
    }
}

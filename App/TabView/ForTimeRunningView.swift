import SwiftUI

struct ForTimeRunningView: View {
    let elapsedTimeText: String
    let exercises: [String]
    let currentBpm: Int?
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("경과 시간")
                .font(.headline)
                .foregroundStyle(TimerTheme.secondaryText)
            Text(elapsedTimeText)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(TimerTheme.primaryText)
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            if let currentBpm {
                HeartRateMetricView(title: "현재 심박", bpm: currentBpm)
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
            Button("중지", action: onStop)
                .buttonStyle(.bordered)
                .tint(TimerTheme.stopTint)
        }
    }
}

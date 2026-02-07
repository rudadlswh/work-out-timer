import SwiftUI

struct HeartRateMetricView: View {
    let title: String
    let bpm: Int

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(TimerTheme.secondaryText)
            Text("\(bpm) bpm")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(TimerTheme.primaryText)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

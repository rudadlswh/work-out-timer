import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var heartRateManager: HeartRateManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("shouldShowOnboarding") private var shouldShowOnboarding: Bool = false

    var body: some View {
        ZStack {
            TimerBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    if heartRateManager.isHeartRateFeatureTemporarilyDisabled {
                        integrationUnavailableCard
                    }
                    onboardingCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("닫기") {
                    dismiss()
                }
                .foregroundStyle(TimerTheme.actionTint)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("설정")
                .font(.title3.bold())
                .foregroundStyle(TimerTheme.primaryText)
            Text("앱 사용에 필요한 기본 기능을 확인할 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(TimerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var integrationUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("일시 제한")
                .font(.headline)
                .foregroundStyle(TimerTheme.primaryText)
            Text("일부 연동 기능은 현재 표시되지 않습니다.")
            Text("기본 타이머 기능은 그대로 사용할 수 있습니다.")
            // TODO: Re-enable HealthKit after App Review fix.
        }
        .font(.subheadline)
        .foregroundStyle(TimerTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("기능 안내")
                .font(.headline)
                .foregroundStyle(TimerTheme.primaryText)
            Text("처음 보여지는 기능 안내를 다시 볼 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(TimerTheme.secondaryText)
            Button("기능 안내 다시 보기") {
                shouldShowOnboarding = true
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(TimerTheme.actionTint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(HeartRateManager())
}

import SwiftUI

struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            TimerBackgroundView()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    featureCard
                    timerCard
                    tipsCard
                    startButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("HIIT 타이머 기능 안내")
                .font(.title2.bold())
                .foregroundStyle(TimerTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("주요 기능")
                .font(.headline)
                .foregroundStyle(TimerTheme.primaryText)
            featureRow(
                icon: "timer",
                title: "EMOM / AMRAP / FOR TIME",
                detail: "세 가지 HIIT 타이머를 제공합니다."
            )
            featureRow(
                icon: "list.bullet.rectangle",
                title: "운동 목록",
                detail: "쉼표 또는 줄바꿈으로 입력하면 순서대로 표시됩니다."
            )
            featureRow(
                icon: "applewatch",
                title: "Apple Watch 연동",
                detail: "워치 앱 실행 중 실시간 타이머/심박을 확인할 수 있습니다."
            )
            featureRow(
                icon: "dynamic.island",
                title: "Live Activity",
                detail: "홈 화면에서도 타이머 진행 상태를 확인합니다."
            )
        }
        .padding(16)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("짧은 팁")
                .font(.headline)
                .foregroundStyle(TimerTheme.primaryText)
            Text("- AMRAP은 실행 화면 더블탭으로 라운드를 추가합니다.")
            Text("- 워치 연동은 iPhone/Watch 모두 앱 실행 중일 때 가장 안정적입니다.")
            Text("- 설정에서 핑 테스트/심박 상태를 확인할 수 있습니다.")
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

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("타이머별 기능")
                .font(.headline)
                .foregroundStyle(TimerTheme.primaryText)
            timerRow(
                title: "EMOM",
                detail: "EMOM(Every Minute On the Minute)의 약자로, 1분마다 정해진 횟수의 운동을 수행하고 남은 시간은 휴식하는 고강도 인터벌 트레이닝(HIIT) 방식입니다."
            )
            timerRow(
                title: "AMRAP",
                detail: "AMRAP는 (As Many Rounds/Reps As Possible)의 약자로, 크로스핏 및 고강도 인터벌 트레이닝(HIIT)에서 정해진 시간 동안 최대한 많은 라운드나 횟수를 수행하는 운동 방식입니다."
            )
            timerRow(
                title: "FOR TIME",
                detail: "'For Time'은 주어진 운동 세트(WOD)를 최대한 빠르게 완료하는 방식입니다."
            )
        }
        .padding(16)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var startButton: some View {
        Button("시작하기") {
            onDismiss()
        }
        .buttonStyle(.borderedProminent)
        .tint(TimerTheme.actionTint)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(TimerTheme.actionTint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TimerTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(TimerTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timerRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TimerTheme.primaryText)
            Text(detail)
                .font(.caption)
                .foregroundStyle(TimerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingView {}
}

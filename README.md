# work-out-timer

SwiftUI로 만든 HIIT 타이머 앱입니다. EMOM/AMRAP/FOR TIME을 지원하며 iPhone ↔ Apple Watch 연동과 Live Activity를 제공합니다.

## 빠른 시작
1. Xcode에서 `timer.xcodeproj` 열기
2. `timer` 스킴 선택 후 실행
3. 워치 앱 확인 시 `timerWatch` 스킴 선택

CLI 빌드:
```
xcodebuild -project timer.xcodeproj -scheme timer -sdk iphonesimulator -configuration Debug build
```

## 타이머 모드
- EMOM: EMOM(Every Minute On the Minute)의 약자로, 1분마다 정해진 횟수의 운동을 수행하고 남은 시간은 휴식하는 고강도 인터벌 트레이닝(HIIT) 방식입니다.
- AMRAP: AMRAP는 (As Many Rounds/Reps As Possible)의 약자로, 크로스핏 및 고강도 인터벌 트레이닝(HIIT)에서 정해진 시간 동안 최대한 많은 라운드나 횟수를 수행하는 운동 방식입니다.
- FOR TIME: 'For Time'은 주어진 운동 세트(WOD)를 최대한 빠르게 완료하는 방식입니다.

기본 총 시간:
- EMOM: 15분
- AMRAP: 20분
- FOR TIME: 30분

## 주요 기능
- 시작 흐름: 시작 버튼 → 5초 카운트다운 → 타이머 시작.
- EMOM: 인터벌마다 라운드 증가, 현재 라운드 운동 표시, 매 인터벌 끝에 알림.
- AMRAP: 전체 카운트다운, 운동 목록 표시, 실행 중 더블탭으로 라운드 +1, 끝 알람 토글.
- FOR TIME: 경과 시간 증가, 완료/중지 시 소요 시간 표시.
- 완료 화면: 완료 표시 + 다시 시작 버튼, 평균 심박 표시.
- Live Activity 지원(홈 화면/다이나믹 아일랜드에서 진행 시간 표시).
- Apple Watch 앱 제공(EMOM/AMRAP/FOR TIME 화면 + 심박 측정).
- iPhone ↔ Apple Watch 연동 상태/핑 테스트 표시.
- iPhone 타이머 시작 시 워치에 동일한 시간/운동 정보 표시.

## 온보딩
- 처음 실행 시 기능 안내 페이지가 1회 노출됩니다.
- 설정 화면 하단의 "기능 안내 다시 보기" 버튼으로 재확인할 수 있습니다.

## 심박수/연동
- HealthKit 권한이 필요합니다.
- 실시간 심박은 워치 앱이 전면 실행 중일 때 가장 안정적으로 들어옵니다.
- 시뮬레이터에서는 더미 심박수 모드를 사용할 수 있습니다(설정에서 토글).

## Live Activity / Dynamic Island
- 타이머가 실행 중일 때 홈 화면에서도 진행 시간을 확인할 수 있습니다.
- 시스템 타이머 표시를 활용해 초 단위 업데이트가 자연스럽게 보이도록 구성했습니다.

## 프로젝트 구조
- `App/ContentView.swift`: 앱 쉘 + 탭 전환
- `App/OnboardingView.swift`: 첫 실행 기능 안내 화면
- `App/TabView/EmomTabView.swift`: EMOM UI + 타이머 로직
- `App/TabView/AmrapTabView.swift`: AMRAP UI + 타이머 로직
- `App/TabView/ForTimeTabView.swift`: FOR TIME UI + 타이머 로직
- `App/Setting/SettingsView.swift`: 워치 연동/핑/심박 설정 화면
- `App/HeartRate/HeartRateManager.swift`: 워치 연결 + 심박/타이머 동기화 처리
- `Shared/HIITActivity.swift`: Live Activity 속성
- `WidgetExtension/`: WidgetKit 확장
- `WatchApp/`: 워치 앱 리소스(아이콘/Info.plist)
- `WatchExtension/`: 워치 앱(타이머 UI + 심박 수집)

## 권한/알림
- 알림 허용이 필요합니다(끝 알람).
- 심박수 기능 사용 시 HealthKit 권한을 요청합니다.

## 참고/제한 사항
- AMRAP 라운드는 실행 화면 더블탭으로 수동 체크합니다.
- 워치 연동은 iPhone/Watch 모두 앱이 실행 중일 때 실시간 표시가 됩니다.
- 유료 개발자 계정이 없어 실기기(특히 Apple Watch) 설치/테스트에 제한이 있습니다. 현재는 시뮬레이터 중심으로 검증했습니다.

## 로드맵
- 연동/설치
  - iPhone→Watch 설치 경로 안내 정리(무료/유료 계정 구분)
  - 워치 앱 자동 설치 실패 시 대응 플로우(문구/가이드) 추가
  - WCSession 상태 진단 로그/상태 화면 개선
- 실시간 동기화
  - 워치 표시 지연 보정 로직 정밀화(모드별 카운트업/카운트다운 분리)
  - 운동 목록 전송 최적화 및 대용량 목록 처리 안정화
  - Ping/응답 기반 실시간 연결 표시 개선
- 심박수/헬스킷
  - 실기기 심박수/워크아웃 미러링 테스트 확대
  - 권한 거부/제한 상황 UX 보완(가이드/재요청)
  - 평균 심박 계산 정확도/표시 타이밍 개선
- 타이머 UX
  - 완료/중지 화면 분리 및 재시작 플로우 개선
  - 알림 세분화(인터벌 종료/운동 종료 개별 설정)
  - AMRAP 라운드 입력 방식 추가(버튼/크라운)
- Live Activity/다이나믹 아일랜드
  - 모드별 표시 레이아웃 개선(EMOM 운동명/인터벌 분리)
  - 잠금화면 위젯 레이아웃 개선 및 색상 커스터마이즈
  - 업데이트 예산 최적화 및 저전력 모드 대응

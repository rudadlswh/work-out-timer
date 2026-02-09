#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

struct HIITAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var displaySeconds: Int     // 표시할 초
        var label: String           // 표시 라벨
        var isRunning: Bool         // 실행 상태
        var isCountdown: Bool       // 카운트다운 여부
        var sentAt: Date            // 마지막 업데이트 시각
    }
    var mode: String               // 타이머 모드
    var totalMinutes: Int          // 총 분
    var intervalMinutes: Int       // 인터벌 분
}
#else
import Foundation

struct HIITAttributes {
    public struct ContentState: Codable, Hashable {
        var displaySeconds: Int     // 표시할 초
        var label: String           // 표시 라벨
        var isRunning: Bool         // 실행 상태
        var isCountdown: Bool       // 카운트다운 여부
        var sentAt: Date            // 마지막 업데이트 시각
    }
    var mode: String               // 타이머 모드
    var totalMinutes: Int          // 총 분
    var intervalMinutes: Int       // 인터벌 분
}
#endif
